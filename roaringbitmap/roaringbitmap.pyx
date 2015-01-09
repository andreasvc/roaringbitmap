"""Roaring bitmap in Cython.

A Roaring bitmap stores a set of 32 bit integers compactly while allowing for
efficient set operations. The space of integers is partitioned into blocks
of 2 ** 16 integers. Depending on the number of elements each block contains,
it is stored as either:

	- an array of up to 1 << 12 shorts that are part of the set
	- an array of up to 1 << 12 shorts that are not part of the set
	- a bitmap of 2 << 16 bits with a 1-bit for each element in the set.
"""
# TODOs
# [ ] subet operation
# [ ] additional operations: rank, select, complement, shifts, get / set slices
# [ ] aggregate intersection of more than 2 roaringbitmaps
# [ ] store maximum capacity? needed for complement
# [ ] error checking
# [ ] serialization compatible with original Roaring bitmap

import sys
import array
cimport cython

DEF BLOCKSIZE = 1 << 16
DEF MAXARRAYLENGTH = 1 << 12

cdef array.array ulongarray = array.array(
		'L' if sys.version[0] >= '3' else b'L', ())
cdef array.array ushortarray = array.array(
		'H' if sys.version[0] >= '3' else b'H', ())

include "arrayops.pxi"
include "block.pxi"


cdef class RoaringBitmap(object):
	"""A compact, mutable set of 32-bit integers."""
	def __init__(self, iterable=None):
		cdef Block block = None
		cdef uint32_t elem
		cdef uint16_t *elem_parts
		cdef int i, prev = -1
		self.data = []
		if iterable is not None:
			for elem in sorted(iterable):
				elem_parts = <uint16_t *>(&elem)
				if elem_parts[1] != prev:
					i = self._getindex(elem_parts[1])
					if i >= 0:
						block = self.data[i]
					else:
						block = Block.__new__(Block)
						block.key = elem_parts[1]
						block.dense = block.inverted = False
						block.cardinality = 0
						block.buffer = array.clone(ushortarray, 0, False)
						self.data.append(block)
					prev = elem_parts[1]
				block.add(elem_parts[0])

	def add(self, uint32_t elem):
		cdef Block block
		cdef uint16_t *elem_parts = <uint16_t *>(&elem)
		cdef int i = self._getindex(elem_parts[1])
		if i >= 0:
			block = self.data[i]
		else:
			block = Block.__new__(Block)
			block.key = elem_parts[1]
			block.dense = block.inverted = False
			block.cardinality = 0
			block.buffer = array.clone(ushortarray, 0, False)
			self.data.insert(-i - 1, block)
		block.add(elem_parts[0])

	def discard(self, uint32_t elem):
		cdef uint16_t *elem_parts = <uint16_t *>(&elem)
		cdef int i = self._getindex(elem_parts[1])
		cdef Block block
		if i >= 0:
			block = self.data[i]
			block.discard(elem_parts[0])
			if block.cardinality == 0:
				del self.data[i]

	def remove(self, uint32_t elem):
		cdef Block block
		cdef uint16_t *elem_parts = <uint16_t *>(&elem)
		cdef int i = self._getindex(elem_parts[1])
		if i >= 0:
			block = self.data[i]
			block.discard(elem_parts[0])
			if block.cardinality == 0:
				del self.data[i]
		else:
			raise KeyError(elem)

	def copy(self):
		cdef RoaringBitmap answer = RoaringBitmap()
		cdef Block block
		for block in self.data:
			answer.data.append(block.copy())
		return answer

	def __contains__(self, uint32_t elem):
		cdef uint16_t *elem_parts = <uint16_t *>(&elem)
		cdef int i = self._getindex(elem_parts[1])
		cdef Block block
		if i >= 0:
			block = self.data[i]
			return block.contains(elem_parts[0])
		return False

	def __richcmp__(self, other, op):
		cdef RoaringBitmap ob1, ob2
		cdef Block b1, b2
		if op == 2:  # ==
			if not isinstance(self, RoaringBitmap):
				return self == set(other)
			elif not isinstance(other, RoaringBitmap):
				return set(self) == other
			ob1, ob2 = self, other
			for b1, b2 in zip(ob1.data, ob2.data):
				if (b1.key != b2.key
						or b1.cardinality != b2.cardinality
						or b1.dense != b2.dense
						or b1.inverted != b2.inverted):
					return False
			for b1, b2 in zip(ob1.data, ob2.data):
				if b1.buffer != b2.buffer:
					return False
			return True
		elif op == 1:  # <=
			return self & other == self  # FIXME slow
		elif op == 5:  # >=
			return self & other == other  # FIXME slow
		elif op == 0:  # <
			return len(self) < len(other) and self <= other
		elif op == 4:  # >
			return len(self) > len(other) and self >= other
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
			for elem in block.iterblock():
				yield elem

	def __reversed__(self):
		cdef Block block
		for block in reversed(self.data):
			for elem in reversed(list(block.iterblock())):  # FIXME
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

	def intersection_update(self, other):
		self &= other

	def union_update(self, other):
		self |= other

	def update(self, other):
		self |= other

	def clear(self):
		self.data.clear()

	def pop(self):
		"""Remove and return the smallest element."""
		cdef Block block
		if len(self.data) == 0:
			raise ValueError
		block = self.data[0]
		return block.pop()

	def isdisjoint(self, other):
		return len(self & other) == 0  # FIXME slow

	def issubset(self, other):
		return self <= other

	def issuperset(self, other):
		return self >= other

	def difference(self, other):
		return self - other

	def difference_update(self, other):
		self -= other

	def symmetric_difference(self, other):
		return self ^ other

	def symmetric_difference_update(self, other):
		self ^= other

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
