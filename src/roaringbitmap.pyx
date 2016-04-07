"""Roaring bitmap in Cython.

A Roaring bitmap stores a set of 32 bit integers compactly while allowing for
efficient set operations. The space of integers is partitioned into blocks
of 2 ** 16 integers. Depending on the number of elements each block contains,
it is stored as either:

<= 4096 elements:
	an array of up to 1 << 12 shorts part of the set.

>= 61140 elements:
	an array of up to 1 << 12 shorts not part of the set.

otherwise:
	a fixed bitmap of 1 << 16 (65536) bits with a 1-bit for each element.

A ``RoaringBitmap`` can be used as a replacement for a mutable
Python ``set`` containing unsigned 32-bit integers:

>>> from roaringbitmap import RoaringBitmap
>>> RoaringBitmap(range(10)) & RoaringBitmap(range(5, 15))
RoaringBitmap({5, 6, 7, 8, 9})
"""
# TODOs
# [ ] efficient serialization; compatible with original Roaring bitmap?
# [ ] in-place vs. new bitmap; ImmutableRoaringBitmap
# [ ] sequence API? (bitarray vs. bitset)
# [ ] subclass Set ABC?
# [ ] more operations: complement, shifts, get / set slices
# [ ] check growth strategy of arrays
# [ ] constructor for range (set slice)
#     [x] init with range: RoaringBitmap(range(2, 4))
#     [x] intersect/union/... inplace with range: a &= range(2, 4)
#         => works because RoaringBitmap constructor will be called
#     [x] set slice: a[2:4] = True; use a |= range(2, 4)
# [ ] error checking, robustness
# [ ] use SSE/AVX2 intrinsics
# [ ] immutable variant; enables serialization w/mmap

import io
import sys
import heapq
import array
cimport cython

# The maximum number of elements in a block
DEF BLOCKSIZE = 1 << 16

# The number of bytes to store a bitmap of 2**16 bits:
DEF BITMAPSIZE = BLOCKSIZE // 8

# Maximum length of positive/inverted sparse arrays:
DEF MAXARRAYLENGTH = 1 << 12

# Capacity to allocate for an empty array
DEF INITCAPACITY = 4

# The different ways a block may store its elements:
DEF DENSE = 0
DEF POSITIVE = 1
DEF INVERTED = 2

include "bitops.pxi"
include "arrayops.pxi"
include "block.pxi"


cdef class RoaringBitmap(object):
	"""A compact, mutable set of 32-bit integers."""
	def __cinit__(self, *args, **kwargs):
		self.keys = <uint16_t *>malloc(INITCAPACITY * sizeof(uint16_t))
		self.data = <Block *>malloc(INITCAPACITY * sizeof(Block))
		self.capacity = INITCAPACITY
		self.size = 0

	def __init__(self, iterable=None):
		"""Return a new RoaringBitmap whose elements are taken from
		``iterable``. The elements ``x`` of a RoaringBitmap must be
		``0 <= x < 2 ** 32``.  If ``iterable`` is not specified, a new empty
		RoaringBitmap is returned. Note that a sorted iterable will
		significantly speed up the construction. ``iterable`` may be a
		``range`` or ``xrange`` object."""
		if isinstance(iterable, xrange if sys.version_info[0] < 3 else range):
			_,  (start, stop, step) = iterable.__reduce__()
			if step == 1:
				self._initrange(start, stop)
				return
		if isinstance(iterable, (list, tuple, set)):
			self._init2pass(iterable)
		elif iterable is not None:
			self._inititerator(iterable)

	def __dealloc__(self):
		if self.data is not NULL:
			for n in range(self.size):
				if self.data[n].buf.ptr is not NULL:
					free(self.data[n].buf.ptr)
					self.data[n].buf.ptr = NULL
					self.data[n].cardinality = self.data[n].capacity = 0
			free(<void *>self.data)
			free(<void *>self.keys)
			self.data = self.keys = NULL
			self.size = 0

	def __contains__(self, uint32_t elem):
		cdef int i = self._getindex(highbits(elem))
		if i >= 0:
			return block_contains(&(self.data[i]), lowbits(elem))
		return False

	def add(self, uint32_t elem):
		"""Add an element to the bitmap.

		This has no effect if the element is already present."""
		cdef Block *block
		cdef uint16_t key = highbits(elem)
		cdef int i = self._getindex(key)
		if i >= 0:
			block = &(self.data[i])
		else:
			block = self._insertempty(-i - 1, key, True)
			block.state = POSITIVE
			block.cardinality = 0
			block.buf.sparse = allocsparse(INITCAPACITY)
			block.capacity = INITCAPACITY
		block_add(block, lowbits(elem))
		block_convert(block)

	def discard(self, uint32_t elem):
		"""Remove an element from the bitmap if it is a member.

		If the element is not a member, do nothing."""
		cdef int i = self._getindex(highbits(elem))
		if i >= 0:
			block_discard(&(self.data[i]), lowbits(elem))
			if self.data[i].cardinality == 0:
				self._removeatidx(i)

	def remove(self, uint32_t elem):
		"""Remove an element from the bitmap; it must be a member.

		If the element is not a member, raise a KeyError."""
		cdef int i = self._getindex(highbits(elem))
		cdef uint32_t x
		if i >= 0:
			x = self.data[i].cardinality
			block_discard(&(self.data[i]), lowbits(elem))
			if x == self.data[i].cardinality:
				raise KeyError(elem)
			if self.data[i].cardinality == 0:
				self._removeatidx(i)
		else:
			raise KeyError(elem)

	def pop(self):
		"""Remove and return the largest element."""
		cdef uint32_t high, low
		if self.size == 0:
			raise ValueError('pop from empty roaringbitmap')
		high = self.keys[self.size - 1]
		low = block_pop(&(self.data[self.size - 1]))
		return high << 16 | low

	def __iand__(self, other):
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					self._removeatidx(pos1)
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_iand(&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						pos1 += 1
					else:
						self._removeatidx(pos1)
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		self._resize(pos1)  # drop everything after pos1 - 1
		return ob1

	def __ior__(self, other):
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					ob1._insertcopy(pos1, ob2.keys[pos2], &(ob2.data[pos2]))
					pos1 += 1
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_ior(&(ob1.data[pos1]), &(ob2.data[pos2]))
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size and pos2 < ob2.size:
			ob1._extendarray(ob2.size - pos2)
			for pos2 in range(pos2, ob2.size):
				ob1._insertcopy(ob1.size, ob2.keys[pos2], &(ob2.data[pos2]))
		return ob1

	def __isub__(self, other):
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:  # ob1.keys[pos1] == ob2.keys[pos2]:
					block_isub(&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						pos1 += 1
					else:
						self._removeatidx(pos1)
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		return ob1

	def __ixor__(self, other):
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					ob1._insertcopy(pos1, ob2.keys[pos2], &(ob2.data[pos2]))
					pos1 += 1
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_ixor(&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						pos1 += 1
					else:
						self._removeatidx(pos1)
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size:
			ob1._extendarray(ob2.size - pos2)
			for pos2 in range(pos2, ob2.size):
				ob1._insertcopy(ob1.size, ob2.keys[pos2], &(ob2.data[pos2]))
		return ob1

	def __and__(x, y):
		cdef RoaringBitmap ob1 = ensurerb(x)
		cdef RoaringBitmap ob2 = ensurerb(y)
		cdef RoaringBitmap result = RoaringBitmap()
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			result._extendarray(min(ob1.size, ob2.size))
			memset(result.data, 0, result.capacity * sizeof(Block))
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					if result.data[result.size].buf.ptr is NULL:
						result.data[result.size].buf.sparse = allocsparse(
								INITCAPACITY)
						result.data[result.size].capacity = INITCAPACITY
						result.data[result.size].state = POSITIVE
					result.keys[result.size] = ob1.keys[pos1]
					block_and(&(result.data[result.size]),
							&(ob1.data[pos1]), &(ob2.data[pos2]))
					if result.data[result.size].cardinality:
						result.size += 1
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
			result._resize(result.size)
		return result

	def __or__(self, other):
		cdef RoaringBitmap result
		if isinstance(self, RoaringBitmap):
			result = self.copy()
			result |= other
		elif isinstance(other, RoaringBitmap):
			result = other.copy()
			result |= self
		else:
			raise ValueError
		return result

	def __xor__(self, other):
		cdef RoaringBitmap result
		if isinstance(self, RoaringBitmap):
			result = self.copy()
			result ^= other
		elif isinstance(other, RoaringBitmap):
			result = other.copy()
			result ^= self
		else:
			raise ValueError
		return result

	def __sub__(self, other):
		cdef RoaringBitmap result
		if isinstance(self, RoaringBitmap):
			result = self.copy()
		elif isinstance(other, RoaringBitmap):
			result = RoaringBitmap(self)
		else:
			raise ValueError
		result -= other
		return result

	def __len__(self):
		cdef int result = 0, n
		for n in range(self.size):
			result += self.data[n].cardinality
		return result

	def __richcmp__(self, other, op):
		cdef RoaringBitmap ob1, ob2
		cdef int n
		if op == 2:  # ==
			if len(self) != len(other):
				return False
			if not isinstance(self, RoaringBitmap):
				# FIXME: what is best approach here?
				# cost of constructing RoaringBitmap vs loss of sort with set()
				# if other is small, constructing RoaringBitmap is better.
				if len(self) < 1024:
					return RoaringBitmap(self) == other
				else:
					return self == set(other)
			elif not isinstance(other, RoaringBitmap):
				if len(other) < 1024:
					return self == RoaringBitmap(other)
				else:
					return set(self) == other
			ob1, ob2 = self, other
			if ob1.size != ob2.size:
				return False
			for n in range(ob1.size):
				if (ob1.keys[n] != ob2.keys[n]
						or ob1.data[n].cardinality != ob2.data[n].cardinality):
					return False
			for n in range(ob1.size):
				if memcmp(ob1.data[n].buf.sparse, ob2.data[n].buf.sparse,
						_getsize(&(ob1.data[n])) * sizeof(uint16_t)) != 0:
					return False
			return True
		elif op == 3:  # !=
			return not (self == other)
		elif op == 1:  # <=
			return self.issubset(other)
		elif op == 5:  # >=
			return self.issuperset(other)
		elif op == 0:  # <
			return len(self) < len(other) and self.issubset(other)
		elif op == 4:  # >
			return len(self) > len(other) and self.issuperset(other)
		return NotImplemented

	def __iter__(self):
		cdef RoaringBitmap ob = ensurerb(self)
		cdef Block *block
		cdef uint32_t high
		cdef uint64_t cur
		cdef int i, n, idx, low
		for i in range(ob.size):
			block = &(ob.data[i])
			high = (<uint32_t>(ob.keys[i])) << 16
			if block.cardinality == BLOCKSIZE:
				for low in range(BLOCKSIZE):
					yield high | low
			elif block.state == DENSE:
				idx = 0
				cur = block.buf.dense[idx]
				n = iteratesetbits(block.buf.dense, &cur, &idx)
				while n != -1:
					yield high | n
					n = iteratesetbits(block.buf.dense, &cur, &idx)
			elif block.state == POSITIVE:
				for n in range(block.cardinality):
					low = block.buf.sparse[n]
					yield high | low
			elif block.state == INVERTED:
				for low in range(block.buf.sparse[0]):
					yield high | low
				if block.cardinality < BLOCKSIZE - 1:
					for n in range(BLOCKSIZE - block.cardinality - 1):
						for low in range(
								block.buf.sparse[n] + 1,
								block.buf.sparse[n + 1]):
							yield high | low
					for low in range(block.buf.sparse[
							BLOCKSIZE - block.cardinality - 1] + 1, BLOCKSIZE):
						yield high | low

	def __reversed__(self):
		cdef RoaringBitmap ob = ensurerb(self)
		cdef Block *block
		cdef uint32_t high
		cdef uint64_t cur
		cdef int i, n, idx, low
		for i in range(ob.size - 1, -1, -1):
			block = &(ob.data[i])
			high = (<uint32_t>(ob.keys[i])) << 16
			if block.cardinality == BLOCKSIZE:
				for low in reversed(range(BLOCKSIZE)):
					yield high | low
			elif block.state == POSITIVE:
				for n in reversed(range(block.cardinality)):
					low = block.buf.sparse[n]
					yield high | low
			elif block.state == DENSE:
				idx = BITNSLOTS(BLOCKSIZE) - 1
				cur = block.buf.dense[idx]
				n = reviteratesetbits(block.buf.dense, &cur, &idx)
				while n != -1:
					low = n
					yield high | low
					n = reviteratesetbits(block.buf.dense, &cur, &idx)
			elif block.state == INVERTED:
				for low in reversed(range(block.buf.sparse[
							BLOCKSIZE - block.cardinality - 1] + 1, BLOCKSIZE)):
					yield high | low
				if block.cardinality < BLOCKSIZE - 1:
					for n in reversed(range(BLOCKSIZE - block.cardinality - 1)):
						for low in reversed(range(
								block.buf.sparse[n] + 1,
								block.buf.sparse[n + 1])):
							yield high | low
				for low in reversed(range(block.buf.sparse[0])):
					yield high | low

	def __bool__(self):
		cdef int n
		for n in range(self.size):
			if self.data[n].cardinality > 0:
				return True
		return False

	def __repr__(self):
		return 'RoaringBitmap({%s})' % ', '.join(str(a) for a in self)

	def debuginfo(self):
		"""Return a string with the internal representation of this bitmap."""
		return 'RoaringBitmap(<%s>)' % ', '.join([
				block_repr(self.keys[n], &(self.data[n]))
				for n in range(self.size)])

	def __getstate__(self):
		cdef array.array state
		cdef Block ob
		cdef uint32_t indexlen = self.size
		cdef size_t size, offset = sizeof(uint32_t), alloc
		cdef int n
		state = array.array('B' if sys.version_info[0] >= 3 else b'B')
		array.resize(state, sizeof(uint32_t)
				+ self.size * sizeof(uint16_t) + self.size * sizeof(Block))
		(<uint32_t *>state.data.as_chars)[0] = indexlen
		memcpy(&(state.data.as_chars[offset]), self.keys,
				self.size * sizeof(uint16_t))
		offset += indexlen * sizeof(uint16_t)
		alloc = offset + indexlen * sizeof(Block)
		for n in range(self.size):
			ob = self.data[n]
			ob.capacity = _getsize(&ob)
			ob.buf.ptr = <void *>alloc
			alloc += ob.capacity * sizeof(uint16_t)
			(<Block *>&(state.data.as_chars[offset]))[0] = ob
			offset += sizeof(Block)
		array.resize(state, offset + alloc)
		for n in range(self.size):
			size = _getsize(&(self.data[n])) * sizeof(uint16_t)
			memcpy(&(state.data.as_chars[offset]), self.data[n].buf.ptr, size)
			offset += size
		return state

	def __setstate__(self, array.array state):
		cdef char *buf = state.data.as_chars
		cdef Block *data
		cdef size_t size, offset = sizeof(uint32_t)
		cdef uint32_t indexlen = (<uint32_t *>buf)[0]
		cdef int n
		self.clear()
		self.keys = <uint16_t *>realloc(self.keys, indexlen * sizeof(uint16_t))
		self.data = <Block *>realloc(self.data, indexlen * sizeof(Block))
		if self.keys is NULL or self.data is NULL:
			raise MemoryError
		self.capacity = self.size = indexlen
		memcpy(self.keys, &(buf[offset]), indexlen * sizeof(uint16_t))
		offset += indexlen * sizeof(uint16_t)
		data = <Block *>&(buf[offset])
		for n in range(self.size):
			self.data[n] = data[n]
			offset = <size_t>data[n].buf.ptr
			if data[n].state == DENSE:
				self.data[n].buf.dense = allocdense()
				size = BITMAPSIZE
			else:
				self.data[n].buf.sparse = allocsparse(data[n].capacity)
				size = data[n].capacity * sizeof(uint16_t)
			memcpy(self.data[n].buf.ptr, &(buf[offset]), size)

	def __sizeof__(self):
		"""Return memory usage in bytes."""
		return sum([sizeof(uint16_t) + sizeof(Block)
				+ self.data[n].capacity * sizeof(uint16_t)
				for n in range(self.size)])

	def clear(self):
		"""Remove all elements from this RoaringBitmap."""
		cdef int n
		for n in range(self.size):
			if self.data[n].buf.ptr is not NULL:
				free(self.data[n].buf.ptr)
				self.data[n].buf.ptr = NULL
				self.data[n].cardinality = self.data[n].capacity = 0
		self.size = 0
		self.keys = <uint16_t *>realloc(
				self.keys, INITCAPACITY * sizeof(uint16_t))
		self.data = <Block *>realloc(self.data, INITCAPACITY * sizeof(Block))
		if self.keys is NULL or self.data is NULL:
			raise MemoryError
		self.capacity = INITCAPACITY

	def copy(self):
		"""Return a copy of this RoaringBitmap."""
		cdef RoaringBitmap result = RoaringBitmap()
		cdef int n
		result._extendarray(self.size)
		for n in range(self.size):
			result._insertcopy(result.size, self.keys[n], &(self.data[n]))
		return result

	def isdisjoint(self, other):
		"""Return True if two RoaringBitmaps have a null intersection."""
		cdef RoaringBitmap ob = ensurerb(other)
		cdef int i = 0, n
		if self.size == 0 or ob.size == 0:
			return True
		for n in range(self.size):
			i = ob._binarysearch(i, ob.size, self.keys[n])
			if i < 0:
				if -i - 1 >= ob.size:
					return True
			elif not block_isdisjoint(&(self.data[n]), &(ob.data[i])):
				return False
		return True

	def issubset(self, other):
		"""Report whether another set contains this RoaringBitmap."""
		cdef RoaringBitmap ob = ensurerb(other)
		cdef int i = 0, n
		if self.size == 0:
			return True
		elif ob.size == 0:
			return False
		for n in range(self.size):
			i = ob._binarysearch(i, ob.size, self.keys[n])
			if i < 0:
				return False
		i = 0
		for n in range(self.size):
			i = ob._binarysearch(i, ob.size, self.keys[n])
			if not block_issubset(&(self.data[n]), &(ob.data[i])):
				return False
		return True

	def issuperset(self, other):
		"""Report whether this RoaringBitmap contains another set."""
		return other.issubset(self)

	def intersection(self, *other):
		"""Return the intersection of two or more sets as a new RoaringBitmap.

		(i.e. elements that are common to all of the sets.)"""
		cdef RoaringBitmap ob
		if len(other) == 1:
			return self & other[0]
		ob = self.copy()
		ob.intersection_update(other)
		return ob

	def union(self, *other):
		"""Return the union of two or more sets as a new set.

		(i.e. all elements that are in at least one of the sets.)"""
		cdef RoaringBitmap ob
		if len(other) == 1:
			return self | other[0]
		ob = self.copy()
		ob.update(other)
		return ob

	def difference(self, *other):
		"""Return the difference of two or more sets as a new RoaringBitmap.

		(i.e, self - other[0] - other[1] - ...)"""
		cdef RoaringBitmap bitmap
		cdef RoaringBitmap ob = self.copy()
		for bitmap in other:
			ob -= bitmap
		return ob

	def symmetric_difference(self, other):
		"""Return the symmetric difference of two sets as a new RoaringBitmap.

		(i.e. all elements that are in exactly one of the sets.)"""
		return self ^ other

	def update(self, *bitmaps):
		"""In-place union update of this RoaringBitmap.

		With one argument, add items from any iterable to this bitmap;
		with more arguments: add the union of given ``RoaringBitmap`` objects.
		"""
		cdef RoaringBitmap bitmap1, bitmap2
		if len(bitmaps) == 0:
			return
		if len(bitmaps) == 1:
			self |= bitmaps[0]
			return
		queue = [(bitmap1.__sizeof__(), bitmap1) for bitmap1 in bitmaps]
		heapq.heapify(queue)
		while len(queue) > 1:
			_, bitmap1 = heapq.heappop(queue)
			_, bitmap2 = heapq.heappop(queue)
			result = bitmap1 | bitmap2
			heapq.heappush(queue, (result.__sizeof__(), result))
		_, result = heapq.heappop(queue)
		self |= result

	def intersection_update(self, *bitmaps):
		"""Intersect this bitmap in-place with one or more ``RoaringBitmap``
		objects."""
		cdef RoaringBitmap bitmap
		if len(bitmaps) == 0:
			return
		elif len(bitmaps) == 1:
			self &= bitmaps[0]
			return
		bitmaps = sorted(bitmaps, key=RoaringBitmap.__sizeof__)
		for bitmap in bitmaps:
			self &= bitmap

	def difference_update(self, *other):
		"""Remove all elements of other RoaringBitmaps from this one."""
		for bitmap in other:
			self -= bitmap

	def symmetric_difference_update(self, other):
		"""Update bitmap to symmetric difference of itself and another."""
		self ^= other

	def intersection_len(self, other):
		"""Return the cardinality of the intersection.

		Optimized version of ``len(self & other)``."""
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef int result = 0, pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					result += block_andlen(&(ob1.data[pos1]), &(ob2.data[pos2]))
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		return result

	def union_len(self, other):
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef int result = 0, pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					result += ob1.data[pos1].cardinality
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					result += ob2.data[pos2].cardinality
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					result += block_orlen(&(ob1.data[pos1]), &(ob2.data[pos2]))
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size and pos2 < ob2.size:
			for pos2 in range(pos2, ob2.size):
				result += ob2.data[pos2].cardinality
		elif pos2 == ob2.size and pos1 < ob1.size:
			for pos1 in range(pos1, ob1.size):
				result += ob1.data[pos1].cardinality
		return result

	def jaccard_dist(self, other):
		"""Return the Jaccard distance.

		Counts of union and intersection are performed simulteously.
		Optimized version of ``1 - len(self & other) / len(self | other)``."""
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef int union_result = 0, intersection_result = 0, tmp1, tmp2
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					union_result += ob1.data[pos1].cardinality
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					union_result += ob2.data[pos2].cardinality
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					tmp1, tmp2 = 0, 0
					block_andorlen(&(ob1.data[pos1]), &(ob2.data[pos2]),
							&tmp1, &tmp2)
					intersection_result += tmp1
					union_result += tmp2
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size and pos2 < ob2.size:
			for pos2 in range(pos2, ob2.size):
				union_result += ob2.data[pos2].cardinality
		elif pos2 == ob2.size and pos1 < ob1.size:
			for pos1 in range(pos1, ob1.size):
				union_result += ob1.data[pos1].cardinality
		return 1 - (intersection_result / <double>union_result)

	def rank(self, uint32_t x):
		"""Return the number of elements ``<= x`` that are in this bitmap."""
		cdef int size = 0, n
		cdef uint16_t xhigh = highbits(x)
		for n in range(self.size):
			if self.keys[n] < xhigh:
				size += self.data[n].cardinality
			elif self.keys[n] > xhigh:
				return size
			else:
				return size + block_rank(&(self.data[n]), lowbits(x))
		return size

	def select(self, int i):
		"""Return the ith element that is in this bitmap.

		:param i: a 1-based index."""
		cdef int leftover = i, n
		cdef uint32_t keycontrib, lowcontrib
		for n in range(self.size):
			if self.data[n].cardinality > leftover:
				keycontrib = self.keys[n] << 16
				lowcontrib = block_select(&(self.data[n]), leftover)
				return keycontrib | lowcontrib
			leftover -= self.data[n].cardinality
		raise IndexError('select: index %d out of range 0..%d.' % (
				i, len(self)))

	def _initrange(self, uint32_t start, uint32_t stop):
		cdef Block *block = NULL
		cdef uint16_t key
		# first block
		block = self._insertempty(self.size, highbits(start), False)
		block_initrange(block, lowbits(start),
				lowbits(stop) if highbits(start) == highbits(stop)
				else BLOCKSIZE)
		# middle blocks
		for key in range(highbits(start) + 1, highbits(stop) - 1):
			block = self._insertempty(self.size, key, False)
			block_initrange(block, 0, BLOCKSIZE)
		# last block
		if self.keys[self.size - 1] != highbits(stop):
			block = self._insertempty(self.size, highbits(stop), False)
			block_initrange(block, 0, lowbits(stop))

	def _init2pass(self, iterable):
		cdef Block *block = NULL
		cdef uint32_t elem
		cdef uint16_t key
		cdef int i, prev = -1
		# gather keys and count elements for each block
		for elem in iterable:
			key = highbits(elem)
			if key != prev:
				i = self._getindex(key)
				if i >= 0:
					block = &(self.data[i])
				else:
					block = self._insertempty(-i - 1, key, False)
					block.cardinality = 0
					block.capacity = 0
				prev = key
			block.cardinality += 1
		# allocate blocks
		for i in range(self.size):
			block = &(self.data[i])
			if block.cardinality < MAXARRAYLENGTH:
				block.capacity = block.cardinality
				block.buf.sparse = allocsparse(block.capacity)
				block.state = POSITIVE
			else:
				block.capacity = BITMAPSIZE // sizeof(uint16_t)
				block.buf.dense = allocdense()
				memset(block.buf.dense, 0, BITMAPSIZE)
				block.state = DENSE
			block.cardinality = 0
		# second pass, add elements for each block
		prev = -1
		for elem in iterable:
			key = highbits(elem)
			if key != prev:
				i = self._getindex(key)
				if prev != -1:
					block_convert(block)
				block = &(self.data[i])
				prev = key
			block_add(block, lowbits(elem))
		if prev != -1:
			block_convert(block)

	def _inititerator(self, iterable):
		cdef Block *block = NULL
		cdef uint32_t elem
		cdef uint16_t key
		cdef int i, prev = -1
		for elem in iterable:  # if alreadysorted else sorted(iterable):
			key = highbits(elem)
			if key != prev:
				i = self._getindex(key)
				if i >= 0:
					block = &(self.data[i])
				else:
					block = self._insertempty(-i - 1, key, True)
					block.state = POSITIVE
					block.cardinality = 0
					block.buf.sparse = allocsparse(INITCAPACITY)
					block.capacity = INITCAPACITY
				prev = key
			block_add(block, lowbits(elem))
			block_convert(block)

	cdef _extendarray(self, int k):
		"""Extend allocation with k extra elements + amortization."""
		cdef int desired = self.size + k
		cdef int newcapacity
		if desired < self.capacity:
			return
		newcapacity = 2 * desired if self.size < 1024 else 5 * desired // 4
		self.keys = <uint16_t *>realloc(self.keys,
				newcapacity * sizeof(uint16_t))
		self.data = <Block *>realloc(self.data, newcapacity * sizeof(Block))
		if self.keys is NULL or self.data is NULL:
			raise MemoryError
		self.capacity = newcapacity

	cdef _resize(self, int k):
		"""Set size and if necessary reduce array allocation to k elements."""
		cdef int n
		if k > INITCAPACITY and k * 2 < self.capacity:
			for n in range(k, self.size):
				if self.data[n].buf.ptr is not NULL:
					free(self.data[n].buf.ptr)
					self.data[n].buf.ptr = NULL
			self.keys = <uint16_t *>realloc(self.keys, k * sizeof(uint16_t))
			self.data = <Block *>realloc(self.data, k * sizeof(Block))
			if self.keys is NULL or self.data is NULL:
				raise MemoryError((k, self.size, self.capacity))
			self.capacity = k
		self.size = k

	cdef _removeatidx(self, int i):
		"""Remove the i'th element."""
		if self.data[i].buf.ptr is not NULL:
			free(self.data[i].buf.ptr)
			self.data[i].buf.ptr = NULL
		memmove(&(self.keys[i]), &(self.keys[i + 1]),
				(self.size - i - 1) * sizeof(uint16_t))
		memmove(&(self.data[i]), &(self.data[i + 1]),
				(self.size - i - 1) * sizeof(Block))
		self.size -= 1

	cdef Block *_insertempty(self, int i, uint16_t key, bint moveblocks):
		"""Insert a new, uninitialized block."""
		self._extendarray(1)
		if i < self.size:
			memmove(&(self.keys[i + 1]), &(self.keys[i]),
					(self.size - i) * sizeof(uint16_t))
			if moveblocks:
				memmove(&(self.data[i + 1]), &(self.data[i]),
						(self.size - i) * sizeof(Block))
		self.size += 1
		self.keys[i] = key
		return &(self.data[i])

	cdef _insertcopy(self, int i, uint16_t key, Block *block):
		"""Insert a copy of given block."""
		cdef size_t size
		self._extendarray(1)
		if i < self.size:
			memmove(&(self.keys[i + 1]), &(self.keys[i]),
					(self.size - i) * sizeof(uint16_t))
			memmove(&(self.data[i + 1]), &(self.data[i]),
					(self.size - i) * sizeof(Block))
		if block is not NULL:
			size = _getsize(block)
			self.keys[i] = key
			self.data[i] = block[0]
			if self.data[i].state == DENSE:
				self.data[i].buf.dense = allocdense()
			elif self.data[i].state in (POSITIVE, INVERTED):
				self.data[i].buf.sparse = allocsparse(size)
				self.data[i].capacity = size
			else:
				raise ValueError
			memcpy(self.data[i].buf.ptr, block.buf.ptr,
					size * sizeof(uint16_t))
		self.size += 1

	cdef int _getindex(self, uint16_t key):
		if self.size == 0:
			return -1
		# Common case of appending in last block:
		if self.keys[self.size - 1] == key:
			return self.size - 1
		return self._binarysearch(0, self.size, key)

	cdef int _binarysearch(self, int begin, int end, uint16_t key):
		"""Binary search for key.

		:returns: positive index ``i`` if ``key`` is found;
			negative value ``i`` if ``elem`` is not found,
			but would fit at ``-i - 1``."""
		cdef int low = begin, high = end - 1
		cdef int middleidx, middleval
		while low <= high:
			middleidx = (low + high) >> 1
			middleval = self.keys[middleidx]
			if middleval < key:
				low = middleidx + 1
			elif middleval > key:
				high = middleidx - 1
			else:
				return middleidx
		return -(low + 1)

	def _checkconsistency(self):
		"""Verify that arrays are sorted and free of duplicates."""
		cdef int n, m
		for n in range(self.size):
			assert self.data[n].state in (DENSE, POSITIVE, INVERTED)
			assert _getsize(&(self.data[n])) <= self.data[n].capacity
			if n + 1 < self.size:
				assert self.keys[n] < self.keys[n + 1]
			if self.data[n].state != DENSE:
				for m in range(_getsize(&(self.data[n])) - 1):
					assert self.data[n].buf.sparse[m] < self.data[
							n].buf.sparse[m + 1]


cdef RoaringBitmap ensurerb(obj):
	"""Coerce ``obj`` to RoaringBitmap if necessary."""
	if isinstance(obj, RoaringBitmap):
		return obj
	return RoaringBitmap(obj)


cdef inline uint16_t highbits(uint32_t x):
	return x >> 16


cdef inline uint16_t lowbits(uint32_t x):
	return x & 0xFFFF


cdef inline int min(int a, int b):
	return a if a <= b else b


cdef inline int max(int a, int b):
	return a if a >= b else b


__all__ = ['RoaringBitmap']
