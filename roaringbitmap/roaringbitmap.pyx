"""Roaring bitmap in Cython.

A Roaring bitmap stores a set of 32 bit integers compactly while allowing for
efficient set operations. The space of integers is partitioned into blocks
of 2 ** 16 integers. Depending on the number of elements each block contains,
it is stored as either:

	- <= 4096 elements: an array of up to 1 << 12 shorts part of the set.
	- >= 61140 elements: an array of up to 1 << 12 shorts not part of the set.
	- otherwise: a fixed bitmap of 1 << 16 (65536) bits with a 1-bit for each
      element.
"""
# TODOs
# [ ] in-place vs. new bitmap
# [ ] additional operations: complement, shifts, get / set slices
# [ ] check growth strategy of arrays
# [ ] constructor for range
# [ ] error checking
# [ ] serialization compatible with original Roaring bitmap

import sys
import heapq
import array
cimport cython

# The maximum number of elements in a block
DEF BLOCKSIZE = 1 << 16

# The number of shorts to store a bitmap of 2**16 bits:
DEF BITMAPSIZE = BLOCKSIZE // 16

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
						self.data.append(block)
					prev = key
				block.add(lowbits(elem))

	def copy(self):
		cdef RoaringBitmap answer = RoaringBitmap()
		cdef Block block
		for block in self.data:
			answer.data.append(block.copy())
		return answer

	def add(self, uint32_t elem):
		cdef Block block
		cdef uint16_t key = highbits(elem)
		cdef int i = self._getindex(key)
		if i >= 0:
			block = self.data[i]
		else:
			block = new_Block(key)
			self.data.insert(-i - 1, block)
		block.add(lowbits(elem))

	def discard(self, uint32_t elem):
		cdef int i = self._getindex(highbits(elem))
		cdef Block block
		if i >= 0:
			block = self.data[i]
			block.discard(lowbits(elem))
			if block.cardinality == 0:
				del self.data[i]

	def remove(self, uint32_t elem):
		cdef Block block
		cdef int i = self._getindex(highbits(elem))
		if i >= 0:
			block = self.data[i]
			block.discard(lowbits(elem))
			if block.cardinality == 0:
				del self.data[i]
		else:
			raise KeyError(elem)

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
		return (RoaringBitmap, None, self.data)

	def __setstate__(self, data):
		self.data = data

	def intersection(self, other):
		return self & other

	def union(self, other):
		return self | other

	def clear(self):
		self.data.clear()

	def pop(self):
		"""Remove and return the largest element."""
		cdef Block block
		if len(self.data) == 0:
			raise ValueError
		block = self.data[len(self.data) - 1]
		return block.pop()

	def isdisjoint(self, other):
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
		return other.issubset(self)

	def difference(self, other):
		return self - other

	def symmetric_difference(self, other):
		return self ^ other

	def intersection_update(self, *bitmaps):
		"""Intersect this bitmap in-place with one or more ``RoaringBitmap``
		objects."""
		cdef RoaringBitmap bitmap
		if len(bitmaps) == 0:
			return self
		elif len(bitmaps) == 1:
			self &= bitmaps[0]
			return self
		bitmaps = sorted(bitmaps, key=RoaringBitmap.size)
		for bitmap in bitmaps:
			self &= bitmap
		return self

	def update(self, *bitmaps):
		"""In-place union update of this bitmap.

		With one argument, add items from any iterable to this bitmap;
		with more arguments: add the union of given ``RoaringBitmap`` objects.
		"""
		cdef RoaringBitmap bitmap1, bitmap2
		if len(bitmaps) == 0:
			return self
		if len(bitmaps) == 1:
			self |= bitmaps[0]
			return self
		queue = [(bitmap1.size(), bitmap1) for bitmap1 in bitmaps]
		heapq.heapify(queue)
		while len(queue) > 1:
			_, bitmap1 = heapq.heappop(queue)
			_, bitmap2 = heapq.heappop(queue)
			result = bitmap1 | bitmap2
			heapq.heappush(queue, (result.size(), result))
		_, result = heapq.heappop(queue)
		self |= result
		return self

	def difference_update(self, other):
		self -= other

	def symmetric_difference_update(self, other):
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

	def size(self):
		"""Return memory used in bytes."""
		return sum(map(Block.size, self.data))

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
