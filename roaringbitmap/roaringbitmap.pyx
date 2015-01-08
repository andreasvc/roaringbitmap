"""Roaring bitmap in Cython.

A Roaring bitmap stores a set of 32 bit integers compactly while allowing for
efficient set operations. The space of integers is partitioned into blocks
of 2 ** 16 integers. Depending on the number of elements each block contains,
it is stored as either:

	- an array of up to 2 ** 12 shorts that are part of the set
	- an array of up to 2 ** 12 shorts that are not part of the set
	- a bitmap of 2 ** 16 bits with a 1-bit for each element in the set.
"""
# TODOs
# [x] intersection, union
# [x] tests
# [x] benchmarks
# [x] serialization
# [x] galloping search for large vs. small intersection
# [ ] aggregate intersection of more than 2 roaringbitmaps
# [ ] other set operations: xor, diff, subset, complement, rank, select,
#		shifts, get / set slices
# [ ] store maximum capacity? needed for complement
# [ ] error checking
# [ ] serialization compatible with original Roaring bitmap

import sys
import array
from itertools import chain
cimport cython

DEF BLOCKSIZE = 1 << 16
DEF MAXARRAYLENGTH = 1 << 12

cdef array.array ulongarray = array.array(
		'L' if sys.version[0] >= '3' else b'L', ())
cdef array.array ushortarray = array.array(
		'H' if sys.version[0] >= '3' else b'H', ())

cdef class RoaringBitmap(object):
	"""A compact, mutable set of 32-bit integers."""
	def __init__(self, iterable=None):
		cdef uint32_t elem
		cdef uint16_t *elem_parts
		cdef int i
		cdef Block block
		self.data = []
		if iterable is not None:
			for elem in sorted(iterable):
				elem_parts = <uint16_t *>(&elem)
				i = self._getindex(elem_parts[1])
				if i >= 0:
					block = self.data[i]
				else:
					block = Block.__new__(Block,
							elem_parts[1], False, False, 0, None)
					self.data.append(block)
				block.add(elem_parts[0])

	def add(self, uint32_t elem):
		cdef uint16_t *elem_parts = <uint16_t *>(&elem)
		cdef int i = self._getindex(elem_parts[1])
		cdef Block block
		if i >= 0:
			block = self.data[i]
		else:
			block = Block.__new__(Block, elem_parts[1], False, False, 0, None)
			self.data.append(block)
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
		cdef uint16_t *elem_parts = <uint16_t *>(&elem)
		cdef int i = self._getindex(elem_parts[1])
		cdef Block block
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
		if op == 2:
			if not isinstance(self, RoaringBitmap):
				return self == set(other)
			elif not isinstance(other, RoaringBitmap):
				return set(self) == other
			ob1, ob2 = self, other
			for b1, b2 in zip(ob1.data, ob2.data):
				if (b1.key != b2.key
						or b1.cardinality != b2.cardinality
						or b1.dense != b2.dense
						or b1.inverted != b2.inverted
						or b1.buffer != b2.buffer):
					return False
			return True
		return NotImplemented

	def __iand__(self, other):
		cdef RoaringBitmap ob1, ob2
		cdef int length1, length2
		cdef int pos1 = 0, pos2 = 0
		cdef uint16_t key1, key2
		cdef Block block1, block2
		if not isinstance(self, RoaringBitmap):
			ob1, ob2 = RoaringBitmap(self), other
		elif not isinstance(other, RoaringBitmap):
			ob1, ob2 = self, RoaringBitmap(other)
		else:
			ob1, ob2 = self, other
		if len(ob1) > len(ob2):
			ob1, ob2 = ob2, ob1
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
		cdef int length1, length2
		cdef int pos1 = 0, pos2 = 0
		cdef uint16_t key1, key2
		cdef Block block1, block2
		if not isinstance(self, RoaringBitmap):
			ob1, ob2 = RoaringBitmap(self), other
		elif not isinstance(other, RoaringBitmap):
			ob1, ob2 = self, RoaringBitmap(other)
		else:
			ob1, ob2 = self, other
		if len(ob1) < len(ob2):
			ob1, ob2 = ob2, ob1
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
					ob1.data.append(block2.copy())
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

	def __len__(self):
		cdef Block block
		cdef int result = 0
		for block in self.data:
			result += block.cardinality
		return result

	def __iter__(self):
		cdef Block block
		cdef list tmp = []
		for block in self.data:
			tmp.append(block.iterblock())
		return chain(*tmp)

	def __bool__(self):
		return len(self) > 0

	def __repr__(self):
		return 'RoaringBitmap(%r)' % set(self)

	def __reduce__(self):
		return (RoaringBitmap, None, self.data)

	def __setstate__(self, data):
		self.data = data

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
		cdef int low = begin, high = end - 1
		cdef int middleidx, middleval
		cdef Block block
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


@cython.freelist(4)
cdef class Block(object):
	# Whether this block contains a bitvector; otherwise sparse array
	cdef bint dense
	# If dense==False, whether array elements represent 0-bits or 1-bits
	cdef bint inverted
	cdef uint16_t key  # the high bits of elements in this block
	cdef uint16_t cardinality  # the number of elements
	cdef array.array buffer  # bitvector, positive sparse, or inverted sparse

	def __cinit__(self,
			uint16_t key,
			bint dense,
			bint inverted,
			uint16_t cardinality,
			array.array buffer):
		self.key = key
		self.dense = dense
		self.inverted = inverted
		self.cardinality = cardinality
		self.buffer = buffer
		if buffer is None:
			self.buffer = array.clone(ushortarray, 0, False)

	def __init__(self):
		pass  # should only be used by pickle

	cdef contains(self, uint16_t elem):
		if self.dense:
			return TESTBIT(self.buffer.data.as_ulongs, elem)
		else:
			if self.inverted:
				found = binarysearch(self.buffer.data.as_ushorts,
						0, BLOCKSIZE - self.cardinality, elem) >= 0
				return not found
			found = binarysearch(self.buffer.data.as_ushorts,
					0, self.cardinality, elem) >= 0
			return found

	cdef add(self, uint16_t elem):
		if self.dense:
			if not TESTBIT(self.buffer.data.as_ulongs, elem):
				SETBIT(self.buffer.data.as_ulongs, elem)
				self.cardinality += 1
		else:
			found = binarysearch(self.buffer.data.as_ushorts,
					0, self.cardinality, elem)
			if self.inverted and found >= 0:
				del self.buffer[found]
				self.cardinality += 1
			elif found < 0:
				self.buffer.insert(-found - 1, elem)
				self.cardinality += 1
				self.resize()

	cdef discard(self, uint16_t elem):
		if self.dense:
			if TESTBIT(self.buffer.data.as_ulongs, elem):
				CLEARBIT(self.buffer.data.as_ulongs, elem)
				self.cardinality -= 1
				self.resize()
		else:
			if self.inverted:
				found = binarysearch(self.buffer.data.as_ushorts,
						0, BLOCKSIZE - self.cardinality, elem)
				if found < 0:
					self.buffer.insert(-found - 1, elem)
					self.cardinality -= 1
					self.resize()
			else:
				found = binarysearch(self.buffer.data.as_ushorts,
						0, self.cardinality, elem)
				if found >= 0:
					del self.buffer[found]
					self.cardinality -= 1

	cdef Block _and(self, Block other):
		cdef Block answer = self.copy()
		answer.iand(other)
		return other

	cdef Block _or(self, Block other):
		cdef Block answer = self.copy()
		answer.ior(other)
		return other

	cdef iand(self, Block other):
		cdef array.array tmp
		cdef int length
		if self.dense and other.dense:
			self.cardinality = setintersectinplace(
					self.buffer.data.as_ulongs,
					other.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
		elif not self.dense and not other.dense:
			if not self.inverted and not other.inverted:
				tmp = array.clone(ushortarray,
						min(self.cardinality, other.cardinality), False)
				self.cardinality = intersect2by2(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						self.cardinality, other.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, self.cardinality)
				self.buffer = tmp
			elif self.inverted and other.inverted:
				tmp = array.clone(ushortarray,
						BLOCKSIZE - (self.cardinality + other.cardinality),
						False)
				length = union2by2(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						BLOCKSIZE - other.cardinality,
						tmp.data.as_ushorts)
				self.cardinality = BLOCKSIZE - length
				array.resize(tmp, length)
				self.buffer = tmp
			elif self.inverted and not other.inverted:
				tmp = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE),
						False)
				memset(tmp.data.as_uchars, 255, BLOCKSIZE // 8)
				for n in range(BLOCKSIZE - self.cardinality):
					CLEARBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
				self.dense = True
				self.inverted = False
				self.buffer = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE),
						True)
				for n in range(other.cardinality):
					SETBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n])
				setintersectinplace(
						self.buffer.data.as_ulongs,
						tmp.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE))
				self.cardinality = abitcount(self.buffer.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE))
			elif not self.inverted and other.inverted:
				tmp = array.clone(ushortarray,
						min(self.cardinality, BLOCKSIZE - other.cardinality),
						False)
				length = difference(self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						self.cardinality, BLOCKSIZE - other.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, length)
				self.cardinality -= length
				self.buffer = tmp
		elif self.dense and not other.dense:
			if other.inverted:
				for n in range(BLOCKSIZE - other.cardinality):
					CLEARBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n])
				self.cardinality = abitcount(self.buffer.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE))
			else:
				tmp = array.clone(ushortarray, 0, False)
				self.cardinality = 0
				for n in range(other.cardinality):
					if TESTBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n]):
						tmp.data.as_ushorts[self.cardinality
								] = other.buffer.data.as_ushorts[n]
						self.cardinality += 1
				array.resize(tmp, self.cardinality)
				self.buffer = tmp
				self.dense = False
				self.inverted = False
		elif not self.dense and other.dense:
			if self.inverted:
				tmp = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE), False)
				memset(tmp.data.as_uchars, 255, BLOCKSIZE // 8)
				for n in range(BLOCKSIZE - self.cardinality):
					CLEARBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
			else:
				tmp = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE), True)
				for n in range(self.cardinality):
					SETBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
			self.cardinality = setintersectinplace(
					tmp.data.as_ulongs,
					other.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
			self.buffer = tmp
			self.dense = True
			self.inverted = False
		self.resize()

	cdef ior(self, Block other):
		cdef array.array tmp
		cdef int length
		if self.dense and other.dense:
			self.cardinality = setunioninplace(
					self.buffer.data.as_ulongs,
					other.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
		elif not self.dense and not other.dense:
			if not self.inverted and not other.inverted:
				tmp = array.clone(ushortarray,
						max(self.cardinality + other.cardinality, BLOCKSIZE),
						False)
				length = union2by2(self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						self.cardinality, other.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, length)
				self.buffer = tmp
				self.cardinality = length
			elif self.inverted and other.inverted:
				tmp = array.clone(ushortarray,
						BLOCKSIZE - (self.cardinality + other.cardinality),
						False)
				length = xor2by2(self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						BLOCKSIZE - other.cardinality,
						tmp.data.as_ushorts)
				self.buffer = tmp
				array.resize(self.buffer, length)
				self.cardinality = length
				self.flip()  # FIXME: implement without negation
			elif self.inverted and not other.inverted:
				for n in range(other.cardinality):  # FIXME slow
					self.discard(other.buffer.data.as_ushorts[n])
			elif not self.inverted and other.inverted:
				tmp = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE), True)
				for n in range(self.cardinality):
					SETBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
				self.buffer = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE),
						False)
				memset(self.buffer.data.as_uchars, 255, BLOCKSIZE // 8)
				for n in range(BLOCKSIZE - other.cardinality):
					CLEARBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n])
				setunioninplace(
						self.buffer.data.as_ulongs,
						tmp.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE))
				self.cardinality = abitcount(self.buffer.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE))
		elif self.dense and not other.dense:
			if other.inverted:
				for n in range(BLOCKSIZE - other.cardinality):  # FIXME slow
					self.add(other.buffer.data.as_ushorts[n])
			else:
				for n in range(other.cardinality):  # FIXME slow
					self.add(other.buffer.data.as_ushorts[n])
		elif not self.dense and other.dense:
			if self.inverted:
				tmp = array.copy(other.buffer)
				for n in range(BLOCKSIZE - self.cardinality):  # FIXME slow
					SETBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
				self.buffer = tmp
				self.dense = True
				self.inverted = False
			else:
				tmp = array.clone(ushortarray,
						max(self.cardinality + other.cardinality, BLOCKSIZE),
						False)
				for n in range(self.cardinality):  # FIXME slow
					if not TESTBIT(other.buffer.data.as_ulongs,
							self.buffer.data.as_ushorts[n]):
						tmp.append(self.buffer.data.as_ushorts[n])
				self.buffer = tmp
				self.dense = True
				self.inverted = True
		self.resize()

	cdef flip(self):
		if self.dense:
			for n in range(BITNSLOTS(BLOCKSIZE)):
				self.buffer.data.as_ulongs[n] = ~self.buffer.data.as_ulongs[n]
		else:
			self.inverted = not self.inverted
		# FIXME: need notion of maximium element
		self.cardinality = BLOCKSIZE - self.cardinality

	cdef resize(self):
		"""Convert between dense, sparse, inverted sparse as needed."""
		cdef array.array tmp
		cdef int n = 0, elem
		if self.dense:
			if self.cardinality < MAXARRAYLENGTH:
				# To positive sparse array
				tmp = array.clone(ushortarray, self.cardinality, False)
				for elem in yieldbits(self.buffer):
					tmp.data.as_ushorts[n] = elem
					n += 1
				self.buffer = tmp
				self.dense = self.inverted = False
			elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
				# To inverted sparse array
				tmp = array.clone(ushortarray, BLOCKSIZE - self.cardinality,
						False)
				for elem in yieldunsetbits(self.buffer):
					tmp.data.as_ushorts[n] = elem
					n += 1
				self.buffer = tmp
				self.dense = False
				self.inverted = True
		elif self.inverted:  # not dense
			if self.cardinality < MAXARRAYLENGTH:
				# To positive sparse array
				tmp = array.clone(ushortarray, self.cardinality, False)
				if self.cardinality > 0:
					tmp.extend(range(0, self.buffer.data.as_ushorts[0]))
					if self.cardinality > 1:
						for n in range(self.cardinality - 1):
							if (self.buffer.data.as_ushorts[n + 1]
									- self.buffer.data.as_ushorts[n]) > 1:
								tmp.extend(range(
										self.buffer.data.as_ushorts[n],
										self.buffer.data.as_ushorts[n + 1]))
						tmp.extend(range(
								self.buffer.data.as_ushorts[
									self.cardinality - 1],
								BLOCKSIZE))
				self.buffer = tmp
				self.dense = False
				self.inverted = False
			elif (MAXARRAYLENGTH < self.cardinality
					< BLOCKSIZE - MAXARRAYLENGTH):
				# To dense bitvector
				tmp = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE), False)
				memset(tmp.data.as_uchars, 255, BLOCKSIZE // 8)
				for n in range(self.cardinality):
					CLEARBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
				self.buffer = tmp
				self.dense = True
				self.inverted = False
		# not dense, not self.inverted
		elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
			# To inverted sparse array
			tmp = array.clone(ushortarray, BLOCKSIZE - self.cardinality,
					False)
			if self.cardinality > 0:
				tmp.extend(range(0, self.buffer.data.as_ushorts[0]))
				if self.cardinality > 1:
					for n in range(self.cardinality - 1):
						if (self.buffer.data.as_ushorts[n + 1]
								- self.buffer.data.as_ushorts[n]) > 1:
							tmp.extend(range(
									self.buffer.data.as_ushorts[n],
									self.buffer.data.as_ushorts[n + 1]))
					tmp.extend(range(
							self.buffer.data.as_ushorts[self.cardinality - 1],
							BLOCKSIZE))
			self.buffer = tmp
			self.dense = False
			self.inverted = True
		elif MAXARRAYLENGTH < self.cardinality < BLOCKSIZE - MAXARRAYLENGTH:
			# To dense bitvector
			tmp = array.clone(ulongarray, BITNSLOTS(BLOCKSIZE), True)
			for n in range(self.cardinality):
				SETBIT(tmp.data.as_ulongs, self.buffer.data.as_ushorts[n])
			self.buffer = tmp
			self.dense = True
			self.inverted = False

	def copy(self):
		cdef Block answer = Block.__new__(Block,
				self.key, self.dense, self.inverted,
				self.cardinality, self.buffer)
		return answer

	def iterblock(self):
		cdef uint32_t high = self.key << 16
		cdef uint32_t low = 0, n
		if self.dense:
			for low in yieldbits(self.buffer):
				yield high | low
		elif self.inverted:
			start = -1
			if self.cardinality > 0:
				for low in range(0, self.buffer[0]):
					yield high | low
			if self.cardinality > 1:
				for n in self.buffer:
					if start < n:
						for low in range(start, n):
							yield high | low
					start = n + 1
				for low in range(0, self.buffer[self.cardinality - 1]):
					yield high | low
		else:
			for low in self.buffer:
				yield high | low

	def __repr__(self):
		if self.dense:
			return 'bitmap(%r)' % self.buffer
		else:
			if self.inverted:
				return 'invertedarray(%r)' % self.buffer
			else:
				return 'array(%r)' % self.buffer

	def __reduce__(self):
		return (Block, None,
				(self.key, self.dense, self.inverted, self.buffer))

	def __setstate__(self, key, dense, inverted, buffer):
		self.key = key
		self.dense = dense
		self.inverted = inverted
		self.buffer = buffer


cdef int binarysearch(uint16_t *data, int begin, int end, uint16_t elem):
	"""Binary search for short `elem` in array `data`."""
	cdef int low = begin
	cdef int high = end - 1
	cdef int middleidx, middleval
	# accelerate the possibly common case of a just appended value
	if end > 0 and data[end - 1] < elem:
		return -end - 1
	while low <= high:
		middleidx = (low + high) >> 1
		middleval = data[middleidx]
		if middleval < elem:
			low = middleidx + 1
		elif middleval > elem:
			high = middleidx - 1
		else:
			return middleidx
	return -(low + 1)


cdef int intersect2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	if length1 * 64 < length2:
		return intersectgalloping(data1, data2, length1, length2, dest)
	elif length2 * 64 < length1:
		return intersectgalloping(data2, data1, length2, length1, dest)
	return intersectlocal2by2(data1, data2, length1, length2, dest)


cdef int intersectlocal2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length1 == 0 or length2 == 0:
		return 0
	while True:
		if data2[k2] < data1[k1]:
			while True:
				k2 += 1
				if k2 == length2:
					return pos
				elif data2[k2] >= data1[k1]:
					break
		elif data1[k1] < data2[k2]:
			while True:
				k1 += 1
				if k1 == length1:
					return pos
				elif data1[k1] >= data2[k2]:
					break
		else:  # data1[k1] == data2[k2]
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 == length1:
				return pos
			k2 += 1
			if k2 == length2:
				return pos


cdef int intersectgalloping(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length1 == 0:
		return 0
	while True:
		if data2[k1] < data1[k2]:
			k1 = advance(data2, k1, length2, data1[k2])
			if k1 == length2:
				return pos
		if data1[k2] < data2[k1]:
			k2 += 1
			if k2 == length2:
				return pos
		else:  # data2[k2] == data1[k1]
			dest[pos] = data1[k2]
			pos += 1
			k2 += 1
			if k2 == length1:
				return pos
			k2 += 1
			k1 = advance(data2, k1, length2, data1[k2])
			if k1 == length2:
				return pos


cdef int advance(uint16_t *data, int pos, int length, uint16_t minitem):
	cdef int lower = pos + 1
	cdef int spansize = 1
	cdef int upper, mid
	if lower >= length or data[lower] >= minitem:
		return lower
	while lower + spansize < length and data[lower + spansize] < minitem:
		spansize *= 2
	upper = lower + spansize if lower + spansize < length else length - 1
	if data[upper] == minitem:
		return upper
	if data[upper] < minitem:
		return length
	lower += spansize // 2
	while lower + 1 != upper:
		mid = (lower + upper) // 2
		if data[mid] == minitem:
			return mid
		elif data[mid] < minitem:
			lower = mid
		else:
			upper = mid
	return upper



cdef int union2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		memcpy(<void *>dest, <void *>data2, length2 * sizeof(uint16_t))
		return length2
	while True:
		if data1[k1] < data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
		elif data1[k1] == data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			k2 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos
		else:  # data1[k1] > data2[k2]
			dest[pos] = data2[k2]
			pos += 1
			k2 += 1
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos


cdef int xor2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		memcpy(<void *>dest, <void *>data2, length2 * sizeof(uint16_t))
		return length2
	while True:
		if data1[k1] < data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
		elif data1[k1] == data2[k2]:
			k1 += 1
			k2 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos
		else:  # data1[k1] > data2[k2]
			dest[pos] = data2[k2]
			pos += 1
			k2 += 1
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos


cdef int difference(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		return 0
	while True:
		if data1[k1] < data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				break
		elif data1[k1] == data2[k2]:
			k1 += 1
			k2 += 1
			if k1 >= length1:
				break
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos
		else:  # data1[k1] > data2[k2]
			k2 += 1
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos


def yieldbits(array.array buffer):
	"""Python iterator over set bits in a dense bitvector."""
	cdef uint64_t cur = buffer.data.as_ulongs[0]
	cdef int n, idx = 0
	n = iteratesetbits(buffer.data.as_ulongs, BITNSLOTS(BLOCKSIZE),
			&cur, &idx)
	while n != -1:
		yield n
		n = iteratesetbits(buffer.data.as_ulongs, BITNSLOTS(BLOCKSIZE),
				&cur, &idx)


def yieldunsetbits(array.array buffer):
	"""Python iterator over unset bits in a dense bitvector."""
	cdef uint64_t cur = buffer.data.as_ulongs[0]
	cdef int n, idx = 0
	n = iterateunsetbits(buffer.data.as_ulongs, BITNSLOTS(BLOCKSIZE),
			&cur, &idx)
	while n != -1:
		yield n
		n = iterateunsetbits(buffer.data.as_ulongs, BITNSLOTS(BLOCKSIZE),
				&cur, &idx)
