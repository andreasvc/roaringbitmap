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
# [ ] in-place vs. new bitmap
# [ ] subclass Set ABC?
# [ ] sequence API? (bitarray vs. bitset)
# [ ] additional operations: complement, shifts, get / set slices
# [ ] check growth strategy of arrays
# [ ] constructor for range (set slice)
#     - init with range: RoaringBitmap(range(2, 4))
#     - set slice: a[2:4] = True
#     - intersect/union/... inplace with range: a &= range(2, 4)
# [ ] error checking
# [ ] serialization compatible with original Roaring bitmap


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

# The different ways a block may store its elements:
DEF POSITIVE = 0
DEF DENSE = 1
DEF INVERTED = 2

cdef array.array ushortarray = array.array(
		'H' if sys.version[0] >= '3' else b'H', ())

include "bitops.pxi"
include "arrayops.pxi"
include "block.pxi"


cdef class RoaringBitmap(object):
	"""A compact, mutable set of 32-bit integers."""
	def __init__(self, iterable=None):
		"""Return a new RoaringBitmap whose elements are taken from
		``iterable``. The elements ``x`` of a RoaringBitmap must be
		``0 <= x < 2 ** 32``.  If ``iterable`` is not specified, a new empty
		RoaringBitmap is returned."""
		cdef Block block = None
		cdef uint32_t elem
		cdef uint16_t key
		cdef int i, prev = -1
		self.data = []
		if iterable is not None:
			for elem in sorted(iterable):
				key = highbits(elem)
				if key != prev:
					i = self._getindex(key)
					if i >= 0:
						block = self.data[i]
					else:
						block = new_Block(key)
						block.allocarray()
						self.data.append(block)
					prev = key
				block.add(lowbits(elem))

	def __contains__(self, uint32_t elem):
		cdef int i = self._getindex(highbits(elem))
		cdef Block block
		if i >= 0:
			block = self.data[i]
			return block.contains(lowbits(elem))
		return False

	def __richcmp__(self, other, op):
		cdef RoaringBitmap ob1, ob2
		cdef Block b1, b2
		if op == 2:  # ==
			if not isinstance(self, RoaringBitmap):
				return set(other) == self
			elif not isinstance(other, RoaringBitmap):
				return set(self) == other
			ob1, ob2 = self, other
			for b1, b2 in zip(ob1.data, ob2.data):
				if (b1.key != b2.key
						or b1.cardinality != b2.cardinality
						or b1.state != b2.state):
					return False
			for b1, b2 in zip(ob1.data, ob2.data):
				if b1.buf != b2.buf:
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

	def __iand__(self, other):
		cdef RoaringBitmap ob1, ob2
		cdef Block block1, block2
		cdef int length1, length2
		cdef int pos1 = 0, pos2 = 0
		cdef uint16_t key1, key2
		if not isinstance(self, RoaringBitmap):
			ob1, ob2 = RoaringBitmap(self), other
		elif not isinstance(other, RoaringBitmap):
			ob1, ob2 = self, RoaringBitmap(other)
		else:
			ob1, ob2 = self, other
		length1, length2 = len(ob1.data), len(ob2.data)
		if pos1 < length1 and pos2 < length2:
			block1, block2 = ob1.data[pos1], ob2.data[pos2]
			key1, key2 = block1.key, block2.key
			while True:
				if key1 < key2:
					del ob1.data[pos1]
					length1 -= 1
					if pos1 == length1:
						break
					block1 = ob1.data[pos1]
					key1 = block1.key
				elif key1 > key2:
					pos2 += 1
					if pos2 == length2:
						break
					block2 = ob2.data[pos2]
					key2 = block2.key
				else:
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					block1.iand(block2)
					if block1.cardinality > 0:
						pos1 += 1
					else:
						del ob1.data[pos1]
						length1 -= 1
					pos2 += 1
					if pos1 == length1 or pos2 == length2:
						break
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					key1, key2 = block1.key, block2.key
		del ob1.data[pos1:]
		return ob1

	def __ior__(self, other):
		cdef RoaringBitmap ob1, ob2
		cdef Block block1, block2
		cdef int length1, length2
		cdef int pos1 = 0, pos2 = 0
		cdef uint16_t key1, key2
		if not isinstance(self, RoaringBitmap):
			ob1, ob2 = RoaringBitmap(self), other
		elif not isinstance(other, RoaringBitmap):
			ob1, ob2 = self, RoaringBitmap(other)
		else:
			ob1, ob2 = self, other
		length1, length2 = len(ob1.data), len(ob2.data)
		if pos1 < length1 and pos2 < length2:
			block1, block2 = ob1.data[pos1], ob2.data[pos2]
			key1, key2 = block1.key, block2.key
			while True:
				if key1 < key2:
					pos1 += 1
					if pos1 == length1:
						break
					block1 = ob1.data[pos1]
					key1 = block1.key
				elif key1 > key2:
					ob1.data.insert(pos1, block2.copy())
					length1 += 1
					pos1 += 1
					pos2 += 1
					if pos2 == length2:
						break
					block2 = ob2.data[pos2]
					key2 = block2.key
				else:
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					block1.ior(block2)
					pos1 += 1
					pos2 += 1
					if pos1 == length1 or pos2 == length2:
						break
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					key1, key2 = block1.key, block2.key
		if pos1 == length1:
			for block2 in ob2.data[pos2:]:
				ob1.data.append(block2.copy())
		return ob1

	def __isub__(self, other):
		cdef RoaringBitmap ob1, ob2
		cdef Block block1, block2
		cdef int length1, length2
		cdef int pos1 = 0, pos2 = 0
		cdef uint16_t key1, key2
		if not isinstance(self, RoaringBitmap):
			ob1, ob2 = RoaringBitmap(self), other
		elif not isinstance(other, RoaringBitmap):
			ob1, ob2 = self, RoaringBitmap(other)
		else:
			ob1, ob2 = self, other
		length1, length2 = len(ob1.data), len(ob2.data)
		if pos1 < length1 and pos2 < length2:
			block1, block2 = ob1.data[pos1], ob2.data[pos2]
			key1, key2 = block1.key, block2.key
			while True:
				if key1 < key2:
					pos1 += 1
					if pos1 == length1:
						break
					block1 = ob1.data[pos1]
					key1 = block1.key
				elif key1 > key2:
					pos2 += 1
					if pos2 == length2:
						break
					block2 = ob2.data[pos2]
					key2 = block2.key
				else:
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					block1.isub(block2)
					if block1.cardinality > 0:
						pos1 += 1
					else:
						del ob1.data[pos1]
						length1 -= 1
					pos2 += 1
					if pos1 == length1 or pos2 == length2:
						break
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					key1, key2 = block1.key, block2.key
		return ob1

	def __ixor__(self, other):
		cdef RoaringBitmap ob1, ob2
		cdef Block block1, block2
		cdef int length1, length2
		cdef int pos1 = 0, pos2 = 0
		cdef uint16_t key1, key2
		if not isinstance(self, RoaringBitmap):
			ob1, ob2 = RoaringBitmap(self), other
		elif not isinstance(other, RoaringBitmap):
			ob1, ob2 = self, RoaringBitmap(other)
		else:
			ob1, ob2 = self, other
		length1, length2 = len(ob1.data), len(ob2.data)
		if pos1 < length1 and pos2 < length2:
			block1, block2 = ob1.data[pos1], ob2.data[pos2]
			key1, key2 = block1.key, block2.key
			while True:
				if key1 < key2:
					pos1 += 1
					if pos1 == length1:
						break
					block1 = ob1.data[pos1]
					key1 = block1.key
				elif key1 > key2:
					self.data.insert(pos1, block2.copy())
					length1 += 1
					pos1 += 1
					pos2 += 1
					if pos2 == length2:
						break
					block2 = ob2.data[pos2]
					key2 = block2.key
				else:
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					block1.ixor(block2)
					if block1.cardinality > 0:
						pos1 += 1
					else:
						del ob1.data[pos1]
						length1 -= 1
					pos2 += 1
					if pos1 == length1 or pos2 == length2:
						break
					block1, block2 = ob1.data[pos1], ob2.data[pos2]
					key1, key2 = block1.key, block2.key
		if pos1 == length1:
			for block2 in ob2.data[pos2:]:
				ob1.data.append(block2.copy())
		return ob1

	def __and__(self, other):
		cdef RoaringBitmap answer
		if isinstance(self, RoaringBitmap):
			answer = self.copy()
			answer &= other
		elif isinstance(other, RoaringBitmap):
			answer = other.copy()
			answer &= self
		else:
			raise ValueError
		return answer

	def __or__(self, other):
		cdef RoaringBitmap answer
		if isinstance(self, RoaringBitmap):
			answer = self.copy()
			answer |= other
		elif isinstance(other, RoaringBitmap):
			answer = other.copy()
			answer |= self
		else:
			raise ValueError
		return answer

	def __xor__(self, other):
		cdef RoaringBitmap answer
		if isinstance(self, RoaringBitmap):
			answer = self.copy()
			answer ^= other
		elif isinstance(other, RoaringBitmap):
			answer = other.copy()
			answer ^= self
		else:
			raise ValueError
		return answer

	def __sub__(self, other):
		cdef RoaringBitmap answer
		if isinstance(self, RoaringBitmap):
			answer = self.copy()
		elif isinstance(other, RoaringBitmap):
			answer = RoaringBitmap(self)
		else:
			raise ValueError
		answer -= other
		return answer

	def __len__(self):
		cdef Block block
		cdef int result = 0
		for block in self.data:
			result += block.cardinality
		return result

	def __iter__(self):
		cdef Block block
		for block in self.data:
			for elem in block:
				yield elem

	def __reversed__(self):
		cdef Block block
		for block in reversed(self.data):
			for elem in reversed(block):
				yield elem

	def __bool__(self):
		cdef Block block
		for block in self.data:
			if block.cardinality > 0:
				return True
		return False

	def __repr__(self):
		return 'RoaringBitmap({%s})' % repr(list(self)).strip('[]')

	def __reduce__(self):
		return (RoaringBitmap, (), dict(data=self.data))

	def __setstate__(self, state):
		self.data = state['data']

	def __sizeof__(self):
		"""Return memory usage in bytes."""
		return sys.getsizeof(self.data) + sum(map(Block.__sizeof__, self.data))

	def clear(self):
		"""Remove all elements from this RoaringBitmap."""
		self.data.clear()

	def copy(self):
		"""Return a copy of this RoaringBitmap."""
		cdef RoaringBitmap answer = RoaringBitmap()
		cdef Block block
		for block in self.data:
			answer.data.append(block.copy())
		return answer

	def add(self, uint32_t elem):
		"""Add an element to the bitmap.

		This has no effect if the element is already present."""
		cdef Block block
		cdef uint16_t key = highbits(elem)
		cdef int i = self._getindex(key)
		if i >= 0:
			block = self.data[i]
		else:
			block = new_Block(key)
			block.allocarray()
			self.data.insert(-i - 1, block)
		block.add(lowbits(elem))

	def discard(self, uint32_t elem):
		"""Remove an element from the bitmap if it is a member.

		If the element is not a member, do nothing."""
		cdef int i = self._getindex(highbits(elem))
		cdef Block block
		if i >= 0:
			block = self.data[i]
			block.discard(lowbits(elem))
			if block.cardinality == 0:
				del self.data[i]

	def remove(self, uint32_t elem):
		"""Remove an element from the bitmap; it must be a member.

		If the element is not a member, raise a KeyError."""
		cdef Block block
		cdef int i = self._getindex(highbits(elem))
		if i >= 0:
			block = self.data[i]
			block.discard(lowbits(elem))
			if block.cardinality == 0:
				del self.data[i]
		else:
			raise KeyError(elem)

	def pop(self):
		"""Remove and return the largest element."""
		cdef Block block
		if len(self.data) == 0:
			raise ValueError
		block = self.data[len(self.data) - 1]
		return block.pop()

	def isdisjoint(self, other):
		"""Return True if two RoaringBitmaps have a null intersection."""
		cdef RoaringBitmap ob
		cdef Block block
		cdef int i = 0
		if not isinstance(other, RoaringBitmap):
			ob = RoaringBitmap(other)
		else:
			ob = other
		if len(self.data) == 0 or len(ob.data) == 0:
			return True
		for block in self.data:
			i = ob._binarysearch(i, len(ob.data), block.key)
			if i < 0:
				i = -i -1
				if i >= len(ob.data):
					break
			elif not block.isdisjoint(ob.data[i]):
				return False
		return True

	def issubset(self, other):
		"""Report whether another set contains this RoaringBitmap."""
		cdef RoaringBitmap ob
		cdef Block block
		cdef int i = 0
		if not isinstance(other, RoaringBitmap):
			ob = RoaringBitmap(other)
		else:
			ob = other
		if len(self.data) == 0:
			return True
		elif len(ob.data) == 0:
			return False
		for block in self.data:
			i = ob._binarysearch(i, len(ob.data), block.key)
			if i < 0:
				return False
		i = 0
		for block in self.data:
			i = ob._binarysearch(i, len(ob.data), block.key)
			if not block.issubset(ob.data[i]):
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

	def rank(self, uint32_t x):
		"""Return the number of elements ``<= x`` that are in this bitmap."""
		cdef int size = 0
		cdef uint16_t key
		cdef Block block
		cdef uint16_t xhigh = highbits(x)
		for block in self.data:
			key = block.key
			if key < xhigh:
				size += block.cardinality
			elif key > xhigh:
				return size
			else:
				return size + block.rank(lowbits(x))
		return size

	def select(self, int i):
		"""Return the ith element that is in this bitmap.

		:param i: a 1-based index."""
		cdef int leftover = i
		cdef uint32_t keycontrib, lowcontrib
		cdef Block block
		for block in self.data:
			if block.cardinality > leftover:
				keycontrib = block.key << 16
				lowcontrib = block.select(leftover)
				return keycontrib | lowcontrib
			leftover -= block.cardinality
		raise ValueError('select %d when cardinality is %d' % (i, len(self)))

	cdef int _getindex(self, uint16_t key):
		cdef Block block
		if len(self.data) == 0:
			return -1
		# Common case of appending in last block:
		block = self.data[len(self.data) - 1]
		if block.key == key:
			return len(self.data) - 1
		return self._binarysearch(0, len(self.data), key)

	cdef int _binarysearch(self, int begin, int end, uint16_t key):
		cdef Block block
		cdef int low = begin, high = end - 1
		cdef int middleidx, middleval
		while low <= high:
			middleidx = (low + high) >> 1
			block = self.data[middleidx]
			middleval = block.key
			if middleval < key:
				low = middleidx + 1
			elif middleval > key:
				high = middleidx - 1
			else:
				return middleidx
		return -(low + 1)


cdef inline uint16_t highbits(uint32_t x):
	return x >> 16


cdef inline uint16_t lowbits(uint32_t x):
	return x & 0xFFFF


__all__ = ['RoaringBitmap']
