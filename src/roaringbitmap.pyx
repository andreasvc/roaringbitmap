"""Roaring bitmap in Cython.

A Roaring bitmap stores a set of 32 bit integers compactly while allowing for
efficient set operations. The space of integers is partitioned into blocks
of ``2 ** 16`` integers. The representation for a block depends on the number
of elements it contains:

<= 4096 elements:
	an array of up to ``1 << 12`` 16-bit integers that are part of the set.

>= 61140 elements:
	an array of up to ``1 << 12`` 16-bit integers that are not part of the set.

otherwise:
	a fixed bitmap of ``1 << 16`` (65536) bits with a 1-bit for each element.

A ``RoaringBitmap`` can be used as a replacement for a mutable
Python ``set`` containing unsigned 32-bit integers:

>>> from roaringbitmap import RoaringBitmap
>>> RoaringBitmap(range(10)) & RoaringBitmap(range(5, 15))
RoaringBitmap({5, 6, 7, 8, 9})
"""
# TODOs
# [ ] use SSE/AVX2 intrinsics
# [ ] separate cardinality & binary ops for bitops
# [ ] check growth strategy of arrays
# [ ] more operations:
#     [ ] effcient shifts
#     [ ] operate on slices without instantiating range as temp object
# [ ] subclass Set ABC?
# [ ] error checking, robustness

import io
import sys
import heapq
import array
cimport cython

from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t, int32_t
from libc.stdio cimport printf
from libc.stdlib cimport free, malloc, calloc, realloc, abort
from libc.string cimport memset, memcpy, memcmp, memmove
from posix.stdlib cimport posix_memalign
from cpython cimport array
cimport cython

cdef extern from *:
	cdef bint PY2


cdef extern from "macros.h":
	int BITSIZE
	int BITSLOT(int b) nogil
	int BITNSLOTS(int nb) nogil
	void SETBIT(uint64_t a[], int b) nogil
	void CLEARBIT(uint64_t a[], int b) nogil
	uint64_t TESTBIT(uint64_t a[], int b) nogil
	uint64_t BITMASK(int b) nogil


cdef extern from "bitcount.h":
	unsigned int bit_clz(uint64_t) nogil
	unsigned int bit_ctz(uint64_t) nogil
	unsigned int bit_popcount(uint64_t) nogil


cdef extern from "_arrayops.h":
	int32_t intersect_uint16(uint16_t *A, size_t lenA,
			uint16_t *B, size_t lenB, uint16_t *out) nogil
	int32_t intersect_general16(uint16_t *A, size_t lenA,
			uint16_t *B, size_t lenB, uint16_t *out) nogil


cdef union Buffer:
	uint16_t *sparse
	uint64_t *dense
	void *ptr


cdef struct Block:
	# A set of 2**16 integers, stored as bitmap or array.
	#
	# Whether this block contains a bitvector (DENSE); otherwise sparse array;
	# The array can contain elements corresponding to 0-bits (INVERTED)
	# or 1-bits (POSITIVE).
	Buffer buf  # data: sparse array or fixed-size bitvector
	uint32_t cardinality  # the number of elements
	uint16_t capacity  # number of allocated uint16_t elements
	uint8_t state  # either DENSE, INVERTED, or POSITIVE


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
include "immutablerb.pxi"
include "multirb.pxi"

rangegen = xrange if PY2 else range
chararray = array.array(b'B' if PY2 else 'B')


cdef class RoaringBitmap(object):
	"""A compact, mutable set of 32-bit integers."""
	cdef Block *data  # pointer and size of array/bitmap with elements
	cdef uint16_t *keys  # the high bits of elements in each block
	cdef uint32_t size  # the number of blocks
	cdef uint32_t capacity  # the allocated capacity for blocks

	def __cinit__(self, *args, **kwargs):
		self.keys = <uint16_t *>malloc(INITCAPACITY * sizeof(uint16_t))
		self.data = <Block *>malloc(INITCAPACITY * sizeof(Block))
		self.capacity = INITCAPACITY
		self.size = 0

	def __init__(self, iterable=None):
		"""Return a new RoaringBitmap with elements from ``iterable``.

		The elements ``x`` of a RoaringBitmap must be ``0 <= x < 2 ** 32``.
		If ``iterable`` is not specified, a new empty RoaringBitmap is
		returned. Note that a sorted iterable will significantly speed up the
		construction.
		``iterable`` may be a generator, in which case the generator is
		consumed incrementally.
		``iterable`` may be a ``range`` (Python 3) or ``xrange`` (Python 2)
		object, which will be constructed efficiently."""
		cdef int n
		cdef RoaringBitmap ob
		if isinstance(iterable, rangegen):
			_,  (start, stop, step) = iterable.__reduce__()
			if step == 1:
				self._initrange(start, stop)
				return
		if isinstance(iterable, (list, tuple, set, dict)):
			self._init2pass(iterable)
		if isinstance(iterable, RoaringBitmap):
			ob = iterable
			self._extendarray(ob.size)
			for n in range(ob.size):
				self._insertcopy(self.size, ob.keys[n], &(ob.data[n]))
		elif iterable is not None:
			self._inititerator(iterable)

	def __dealloc__(self):
		if self.data is not NULL:
			for n in range(self.size):
				free(self.data[n].buf.ptr)
			free(<void *>self.keys)
			free(<void *>self.data)
			self.keys = self.data = NULL
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

	def __iand__(self, x):
		cdef RoaringBitmap ob1 = self
		cdef RoaringBitmap ob2 = ensurerb(x)
		cdef int pos1 = 0, pos2 = 0, res = 0
		cdef uint16_t *keys = NULL
		cdef Block *data = NULL
		if pos1 < ob1.size and pos2 < ob2.size:
			ob1.capacity = min(ob1.size, ob2.size)
			ob1._tmpalloc(self.capacity, &keys, &data)
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					free(ob1.data[pos1].buf.ptr)
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_iand(&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						keys[res] = ob1.keys[pos1]
						data[res] = ob1.data[pos1]
						res += 1
					else:
						free(ob1.data[pos1].buf.ptr)
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
			ob1._replacearrays(keys, data, res)
		return ob1

	def __isub__(self, x):
		cdef RoaringBitmap ob1 = self
		cdef RoaringBitmap ob2 = ensurerb(x)
		cdef int pos1 = 0, pos2 = 0, res = 0
		cdef uint16_t *keys = NULL
		cdef Block *data = NULL
		if pos1 < ob1.size and pos2 < ob2.size:
			ob1.capacity = ob1.size
			ob1._tmpalloc(ob1.capacity, &keys, &data)
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
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
						keys[res] = ob1.keys[pos1]
						data[res] = ob1.data[pos1]
						res += 1
					else:
						free(ob1.data[pos1].buf.ptr)
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
			if pos2 == ob2.size:
				for pos1 in range(pos1, ob1.size):
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
			ob1._replacearrays(keys, data, res)
		return ob1

	def __ior__(self, x):
		cdef RoaringBitmap ob1 = self
		cdef RoaringBitmap ob2 = ensurerb(x)
		cdef int pos1 = 0, pos2 = 0, res = 0
		cdef uint16_t *keys = NULL
		cdef Block *data = NULL
		if ob2.size == 0:
			return ob1
		ob1.capacity = ob1.size + ob2.size
		ob1._tmpalloc(ob1.capacity, &keys, &data)
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					keys[res] = ob2.keys[pos2]
					block_copy(&(data[res]), &(ob2.data[pos2]))
					res += 1
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_ior(&(ob1.data[pos1]), &(ob2.data[pos2]))
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size:
			for pos2 in range(pos2, ob2.size):
				keys[res] = ob2.keys[pos2]
				block_copy(&(data[res]), &(ob2.data[pos2]))
				res += 1
		elif pos2 == ob2.size:
			for pos1 in range(pos1, ob1.size):
				keys[res] = ob1.keys[pos1]
				data[res] = ob1.data[pos1]
				res += 1
		ob1._replacearrays(keys, data, res)
		return ob1

	def __ixor__(self, x):
		cdef RoaringBitmap ob1 = self
		cdef RoaringBitmap ob2 = ensurerb(x)
		cdef int pos1 = 0, pos2 = 0, res = 0
		cdef uint16_t *keys = NULL
		cdef Block *data = NULL
		ob1.capacity = ob1.size + ob2.size
		ob1._tmpalloc(ob1.capacity, &keys, &data)
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					keys[res] = ob2.keys[pos2]
					block_copy(&(data[res]), &(ob2.data[pos2]))
					res += 1
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_ixor(&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						keys[res] = ob1.keys[pos1]
						data[res] = ob1.data[pos1]
						res += 1
					else:
						free(ob1.data[pos1].buf.ptr)
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size:
			for pos2 in range(pos2, ob2.size):
				keys[res] = ob2.keys[pos2]
				block_copy(&(data[res]), &(ob2.data[pos2]))
				res += 1
		elif pos2 == ob2.size:
			for pos1 in range(pos1, ob1.size):
				keys[res] = ob1.keys[pos1]
				data[res] = ob1.data[pos1]
				res += 1
		ob1._replacearrays(keys, data, res)
		return ob1

	def __and__(x, y):
		cdef RoaringBitmap ob1 = ensurerb(x)
		cdef RoaringBitmap ob2 = ensurerb(y)
		cdef RoaringBitmap result = RoaringBitmap()
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			result._extendarray(min(ob1.size, ob2.size))
			# initialize to zero so that unallocated blocks can be detected
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
					block_and(&(result.data[result.size]),
							&(ob1.data[pos1]), &(ob2.data[pos2]))
					if result.data[result.size].cardinality:
						result.keys[result.size] = ob1.keys[pos1]
						result.size += 1
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
			free(result.data[result.size].buf.ptr)
			result._resize(result.size)
		return result

	def __sub__(x, y):
		cdef RoaringBitmap ob1 = ensurerb(x)
		cdef RoaringBitmap ob2 = ensurerb(y)
		cdef RoaringBitmap result = RoaringBitmap()
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			result._extendarray(ob1.size)
			memset(result.data, 0, result.capacity * sizeof(Block))
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					result._insertcopy(
							result.size, ob1.keys[pos1], &(ob1.data[pos1]))
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:  # ob1.keys[pos1] == ob2.keys[pos2]:
					block_sub(&(result.data[result.size]),
							&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						result.keys[result.size] = ob1.keys[pos1]
						result.size += 1
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
			if pos2 == ob2.size:
				for pos1 in range(pos1, ob1.size):
					result._insertcopy(
							result.size, ob1.keys[pos1], &(ob1.data[pos1]))
		result._resize(result.size)
		return result

	def __or__(x, y):
		cdef RoaringBitmap ob1 = ensurerb(x)
		cdef RoaringBitmap ob2 = ensurerb(y)
		cdef RoaringBitmap result = RoaringBitmap()
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			result._extendarray(ob1.size + ob2.size)
			memset(result.data, 0, result.capacity * sizeof(Block))
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					result._insertcopy(
							result.size, ob1.keys[pos1], &(ob1.data[pos1]))
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					result._insertcopy(
							result.size, ob2.keys[pos2], &(ob2.data[pos2]))
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_or(&(result.data[result.size]),
							&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						result.keys[result.size] = ob1.keys[pos1]
						result.size += 1
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size:
			result._extendarray(ob2.size - pos2)
			for pos2 in range(pos2, ob2.size):
				result._insertcopy(result.size,
						ob2.keys[pos2], &(ob2.data[pos2]))
		elif pos2 == ob2.size:
			result._extendarray(ob1.size - pos1)
			for pos1 in range(pos1, ob1.size):
				result._insertcopy(
						result.size, ob1.keys[pos1], &(ob1.data[pos1]))
		result._resize(result.size)
		return result

	def __xor__(x, y):
		cdef RoaringBitmap ob1 = ensurerb(x)
		cdef RoaringBitmap ob2 = ensurerb(y)
		cdef RoaringBitmap result = RoaringBitmap()
		cdef int pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			result._extendarray(ob1.size + ob2.size)
			memset(result.data, 0, result.capacity * sizeof(Block))
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					result._insertcopy(
							result.size, ob1.keys[pos1], &(ob1.data[pos1]))
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					result._insertcopy(
							result.size, ob2.keys[pos2], &(ob2.data[pos2]))
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					block_xor(&(result.data[result.size]),
							&(ob1.data[pos1]), &(ob2.data[pos2]))
					if ob1.data[pos1].cardinality > 0:
						result.keys[result.size] = ob1.keys[pos1]
						result.size += 1
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size:
			result._extendarray(ob2.size - pos2)
			for pos2 in range(pos2, ob2.size):
				result._insertcopy(
						result.size, ob2.keys[pos2], &(ob2.data[pos2]))
		elif pos2 == ob2.size:
			result._extendarray(ob1.size - pos1)
			for pos1 in range(pos1, ob1.size):
				result._insertcopy(
						result.size, ob1.keys[pos1], &(ob1.data[pos1]))
		result._resize(result.size)
		return result

	def __lshift__(self, other):
		return self.__rshift__(-other)

	def __rshift__(self, other):
		# FIXME: replace with optimized implementation
		return RoaringBitmap(elem + other for elem in self
				if 0 <= elem + other < 1 << 32)

	# def __ilshift__(self, other):
	# 	raise NotImplementedError

	# def __irshift__(self, other):
	# 	raise NotImplementedError

	def __invert__(self):
		"""Return copy with smallest to largest elements inverted."""
		return self.symmetric_difference(
				rangegen(self.min(), self.max() + 1))

	def min(self):
		"""Return smallest element in this RoaringBitmap.

		NB: faster than min(self) which iterates over all elements."""
		return self.select(0)

	def max(self):
		"""Return largest element in this RoaringBitmap.

		NB: faster than max(self) which iterates over all elements."""
		return next(reversed(self))

	def __len__(self):
		cdef int result = 0, n
		for n in range(self.size):
			result += self.data[n].cardinality
		return result

	def __richcmp__(x, y, int op):
		return richcmp(x, y, op)

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
		return <bint>self.size

	def __str__(self):
		return '{%s}' % ', '.join(str(a) for a in self)

	def __repr__(self):
		return 'RoaringBitmap(%s)' % str(self)

	def debuginfo(self):
		"""Return a string with the internal representation of this bitmap."""
		return 'size=%d, cap=%d, data={%s}' % (
				self.size, self.capacity,
				', '.join([block_repr(self.keys[n], &(self.data[n]))
				for n in range(self.size)]))

	def __getstate__(self):
		cdef array.array state
		cdef Block *ob
		cdef uint32_t extra, alignment = 32
		cdef size_t n, size
		cdef size_t alloc  # total allocated bytes for pickle
		cdef size_t offset1 = sizeof(uint32_t)  # keys, data
		cdef size_t offset2  # buffers
		# compute total size to allocate
		# add padding to ensure bitmaps are 32-byte aligned
		alloc = offset1 + self.size * (sizeof(uint16_t) + sizeof(Block))
		alloc += alignment - alloc % alignment
		for n in range(self.size):
			alloc += _getsize(&(self.data[n])) * sizeof(uint16_t)
			alloc += alignment - alloc % alignment
		state = array.clone(chararray, alloc, False)
		(<uint32_t *>state.data.as_chars)[0] = self.size
		size = self.size * sizeof(uint16_t)
		memcpy(&(state.data.as_chars[offset1]), self.keys, size)
		offset1 += size
		offset2 = offset1 + self.size * sizeof(Block)
		# add zero padding bytes
		extra = alignment - offset2 % alignment
		memset(&(state.data.as_chars[offset2]), 0, extra)
		offset2 += extra
		for n in range(self.size):
			# copy block
			ob = (<Block *>&(state.data.as_chars[offset1]))
			ob[0] = self.data[n]
			ob.capacity = _getsize(&(self.data[n]))
			ob.buf.ptr = <void *>offset2
			offset1 += sizeof(Block)
			# copy buffer of block
			size = ob.capacity * sizeof(uint16_t)
			memcpy(&(state.data.as_chars[offset2]), self.data[n].buf.ptr, size)
			offset2 += size
			# add zero padding bytes
			extra = alignment - offset2 % alignment
			memset(&(state.data.as_chars[offset2]), 0, extra)
			offset2 += extra
		return state

	def __setstate__(self, array.array state):
		cdef char *buf = state.data.as_chars
		cdef Block *data
		cdef size_t size, offset = sizeof(uint32_t)
		cdef int n
		self.clear()
		self.size = (<uint32_t *>buf)[0]
		self.keys = <uint16_t *>realloc(self.keys, self.size * sizeof(uint16_t))
		self.data = <Block *>realloc(self.data, self.size * sizeof(Block))
		if self.keys is NULL or self.data is NULL:
			raise MemoryError(self.size)
		self.capacity = self.size = self.size
		memcpy(self.keys, &(buf[offset]), self.size * sizeof(uint16_t))
		offset += self.size * sizeof(uint16_t)
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
		"""Return memory usage in bytes (incl. overallocation)."""
		cdef uint32_t result = 0
		for n in range(self.size):
			result += (sizeof(uint16_t) + sizeof(Block)
					+ self.data[n].capacity * sizeof(uint16_t))
		return result

	def numelem(self):
		"""Return total number of uint16_t elements stored."""
		cdef uint32_t result = 0
		for n in range(self.size):
			result += 1 + _getsize(&(self.data[n]))
		return result

	def clear(self):
		"""Remove all elements from this RoaringBitmap."""
		cdef int n
		for n in range(self.size):
			free(self.data[n].buf.ptr)
		self.size = 0
		self.keys = <uint16_t *>realloc(
				self.keys, INITCAPACITY * sizeof(uint16_t))
		self.data = <Block *>realloc(self.data, INITCAPACITY * sizeof(Block))
		if self.keys is NULL or self.data is NULL:
			raise MemoryError(INITCAPACITY)
		self.capacity = INITCAPACITY

	def copy(self):
		"""Return a copy of this RoaringBitmap."""
		cdef RoaringBitmap result = RoaringBitmap()
		cdef int n
		result._extendarray(self.size)
		for n in range(self.size):
			result._insertcopy(result.size, self.keys[n], &(self.data[n]))
		return result

	def freeze(self):
		"""Return an immutable copy of this RoaringBitmap."""
		cdef ImmutableRoaringBitmap result = ImmutableRoaringBitmap.__new__(
				ImmutableRoaringBitmap)
		result.__setstate__(self.__getstate__())
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
		if len(other) == 1:
			return self & other[0]
		other = list(other)
		other.append(self)
		other.sort(key=RoaringBitmap.numelem)
		result = other[0] & other[1]
		for ob in other[2:]:
			result &= ob
		return result

	def union(self, *other):
		"""Return the union of two or more sets as a new set.

		(i.e. all elements that are in at least one of the sets.)"""
		if len(other) == 1:
			return self | other[0]
		queue = [(ob1.numelem(), ob1) for ob1 in other]
		queue.append((self.numelem(), self))
		heapq.heapify(queue)
		while len(queue) > 1:
			_, ob1 = heapq.heappop(queue)
			_, ob2 = heapq.heappop(queue)
			result = ob1 | ob2
			heapq.heappush(queue, (result.numelem(), result))
		_, result = heapq.heappop(queue)
		return result

	def difference(self, *other):
		"""Return the difference of two or more sets as a new RoaringBitmap.

		(i.e, self - other[0] - other[1] - ...)"""
		cdef RoaringBitmap bitmap
		cdef RoaringBitmap ob
		other = sorted(other, key=RoaringBitmap.numelem, reverse=True)
		ob = self - other[0]
		for bitmap in other[1:]:
			ob -= bitmap
		return ob

	def symmetric_difference(self, other):
		"""Return the symmetric difference of two sets as a new RoaringBitmap.

		(i.e. all elements that are in exactly one of the sets.)"""
		return self ^ other

	def update(self, *bitmaps):
		"""In-place union update of this RoaringBitmap.

		With one argument, add items from the iterable to this bitmap;
		with more arguments: add the union of given ``RoaringBitmap`` objects.

		NB: since range objects are recognized by the constructor, this
		provides an efficient way to set a range of bits:

		>>> rb = RoaringBitmap(range(5))
		>>> rb.update(range(3, 7))
		>>> rb
		RoaringBitmap({0, 1, 2, 3, 4, 5, 6})
		"""
		cdef RoaringBitmap bitmap1, bitmap2
		if len(bitmaps) == 0:
			return
		if len(bitmaps) == 1:
			self |= bitmaps[0]
			return
		queue = [(bitmap1.numelem(), bitmap1) for bitmap1 in bitmaps]
		heapq.heapify(queue)
		while len(queue) > 1:
			_, bitmap1 = heapq.heappop(queue)
			_, bitmap2 = heapq.heappop(queue)
			result = bitmap1 | bitmap2
			heapq.heappush(queue, (result.numelem(), result))
		_, result = heapq.heappop(queue)
		self |= result

	def intersection_update(self, *bitmaps):
		"""Intersect this bitmap in-place with one or more ``RoaringBitmap``
		objects.

		NB: since range objects are recognized by the constructor, this
		provides an efficient way to restrict the set to a range of elements:

		>>> rb = RoaringBitmap(range(5))
		>>> rb.intersection_update(range(3, 7))
		>>> rb
		RoaringBitmap({3, 4})
		"""
		cdef RoaringBitmap bitmap
		if len(bitmaps) == 0:
			return
		elif len(bitmaps) == 1:
			self &= bitmaps[0]
			return
		bitmaps = sorted(bitmaps, key=RoaringBitmap.numelem)
		for bitmap in bitmaps:
			self &= bitmap

	def difference_update(self, *other):
		"""Remove all elements of other RoaringBitmaps from this one."""
		for bitmap in other:
			self -= bitmap

	def symmetric_difference_update(self, other):
		"""Update bitmap to symmetric difference of itself and another."""
		self ^= other

	def flip_range(self, uint32_t start, uint32_t stop):
		"""In-place negation for range(start, stop)."""
		self.symmetric_difference_update(rangegen(start, stop))

	def intersection_len(self, other):
		"""Return the cardinality of the intersection.

		Optimized version of ``len(self & other)``."""
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef uint32_t result = 0
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
				else:
					result += block_andlen(&(ob1.data[pos1]), &(ob2.data[pos2]))
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		return result

	def union_len(self, other):
		"""Return the cardinality of the union.

		Optimized version of ``len(self | other)``."""
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef uint32_t result = 0
		cdef int pos1 = 0, pos2 = 0
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

		Optimized version of ``1 - len(self & other) / len(self | other)``.
		Counts of union and intersection are performed simultaneously."""
		cdef RoaringBitmap ob1 = ensurerb(self)
		cdef RoaringBitmap ob2 = ensurerb(other)
		cdef uint32_t union_result = 0, intersection_result = 0, tmp1, tmp2
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

		:param i: a 0-based index."""
		cdef int leftover = i, n
		cdef uint32_t keycontrib, lowcontrib
		if i < 0:
			raise IndexError('select: index %d out of range 0..%d.' % (
					i, len(self)))
		for n in range(self.size):
			if self.data[n].cardinality > leftover:
				keycontrib = self.keys[n] << 16
				lowcontrib = block_select(&(self.data[n]), leftover)
				return keycontrib | lowcontrib
			leftover -= self.data[n].cardinality
		raise IndexError('select: index %d out of range 0..%d.' % (
				i, len(self)))

	def index(self, uint32_t x):
		"""Return the 0-based index of `x` in sorted elements of bitmap."""
		if x in self:
			return self.rank(x) - 1
		raise IndexError

	def _ridx(self, i):
		if i < 0:
			return len(self) - i
		return i

	def _slice(self, i):
		# handle negative indices, step
		start = 0 if i.start is None else self._ridx(i.start)
		stop = len(self) if i.stop is None else self._ridx(i.stop)
		return rangegen(
				self.select(start), self.select(stop - 1) + 1,
				1 if i.step is None else i.step)

	def __getitem__(self, i):
		"""Get element with rank `i`, or a slice.

		In the case of a slice, a new roaringbitmap is returned."""
		if isinstance(i, slice):
			return self.intersection(self._slice(i))
		elif isinstance(i, int):
			return self._ridx(i)
		else:
			raise TypeError('Expected integer index or slice object.')

	def __delitem__(self, i):
		"""Discard element with rank `i`, or a slice."""
		if isinstance(i, slice):
			self.difference_update(self._slice(i))
		elif isinstance(i, int):
			self.discard(self.select(self._ridx(i)))
		else:
			raise TypeError('Expected integer index or slice object.')

	def __setitem__(self, i, x):
		"""Set element with rank `i` to ``False``.

		Alternatively, set all elements within a range of ranks to
		``True`` or ``False``."""
		if isinstance(i, slice):
			self.update(self._slice(i))
		elif isinstance(i, int):
			if bool(x):
				raise NotImplementedError('use RoaringBitmap.add(x) to add an '
						'element; The ith element is by definition '
						'already in the set.')
			self.__delitem__(self._ridx(i))
		else:
			raise TypeError('Expected integer index or slice object.')

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
					block.cardinality = block.capacity = 0
				prev = key
			block.cardinality += 1
		# allocate blocks
		for i in range(self.size):
			block = &(self.data[i])
			if block.cardinality < MAXARRAYLENGTH:
				block.capacity = block.cardinality
				block.buf.sparse = allocsparse(block.capacity)
				block.state = POSITIVE
			else:  # if necessary, will convert to inverted later
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
		for elem in iterable:
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
			raise MemoryError(newcapacity)
		self.capacity = newcapacity

	cdef _resize(self, int k):
		"""Set size and if necessary reduce array allocation to k elements."""
		cdef int n
		if k > INITCAPACITY and k * 2 < self.capacity:
			for n in range(k, self.size):
				free(self.data[n].buf.ptr)
			self.keys = <uint16_t *>realloc(self.keys, k * sizeof(uint16_t))
			self.data = <Block *>realloc(self.data, k * sizeof(Block))
			if self.keys is NULL or self.data is NULL:
				raise MemoryError((k, self.size, self.capacity))
			self.capacity = k
		self.size = k

	cdef _tmpalloc(self, int size, uint16_t **keys, Block **data):
		keys[0] = <uint16_t *>malloc(size * sizeof(uint16_t))
		data[0] = <Block *>calloc(size, sizeof(Block))
		if keys[0] is NULL or data[0] is NULL:
			raise MemoryError(size)

	cdef _replacearrays(self, uint16_t *keys, Block *data, int size):
		free(self.keys)
		free(self.data)
		self.keys = keys
		self.data = data
		self.size = size
		self._resize(self.size)  # truncate

	cdef _removeatidx(self, int i):
		"""Remove the i'th element."""
		free(self.data[i].buf.ptr)
		memmove(&(self.keys[i]), &(self.keys[i + 1]),
				(self.size - i - 1) * sizeof(uint16_t))
		memmove(&(self.data[i]), &(self.data[i + 1]),
				(self.size - i - 1) * sizeof(Block))
		self.size -= 1

	cdef Block *_insertempty(self, int i, uint16_t key, bint moveblocks):
		"""Insert a new, uninitialized block.

		:param moveblocks: if False, assume self.data array is uninitialized
			and data does not have to be moved."""
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
		size = _getsize(block)
		self.keys[i] = key
		self.data[i] = block[0]
		if self.data[i].state == DENSE:
			self.data[i].buf.dense = allocdense()
		elif self.data[i].state in (POSITIVE, INVERTED):
			self.data[i].buf.sparse = allocsparse(size)
			self.data[i].capacity = size
		memcpy(self.data[i].buf.ptr, block.buf.ptr, size * sizeof(uint16_t))
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


cdef inline richcmp(x, y, int op):
	cdef RoaringBitmap ob1, ob2
	cdef int n
	if op == 2:  # ==
		if not isinstance(x, RoaringBitmap):
			# FIXME: what is best approach here?
			# cost of constructing RoaringBitmap vs loss of sort with set()
			# if non-RoaringBitmap is small, constructing new one is better
			return RoaringBitmap(x) == y if len(x) < 1024 else x == set(y)
		elif not isinstance(y, RoaringBitmap):
			return x == RoaringBitmap(y) if len(y) < 1024 else set(x) == y
		ob1, ob2 = x, y
		if ob1.size != ob2.size:
			return False
		if memcmp(ob1.keys, ob2.keys, ob1.size * sizeof(uint16_t)) != 0:
			return False
		for n in range(ob1.size):
			if ob1.data[n].cardinality != ob2.data[n].cardinality:
				return False
		for n in range(ob1.size):
			if memcmp(ob1.data[n].buf.sparse, ob2.data[n].buf.sparse,
					_getsize(&(ob1.data[n])) * sizeof(uint16_t)) != 0:
				return False
		return True
	elif op == 3:  # !=
		return not (x == y)
	elif op == 1:  # <=
		return ensurerb(x).issubset(y)
	elif op == 5:  # >=
		return ensurerb(x).issuperset(y)
	elif op == 0:  # <
		return len(x) < len(y) and ensurerb(x).issubset(y)
	elif op == 4:  # >
		return len(x) > len(y) and ensurerb(x).issuperset(y)
	return NotImplemented


cdef inline RoaringBitmap ensurerb(obj):
	"""Convert set-like ``obj`` to RoaringBitmap if necessary."""
	if isinstance(obj, RoaringBitmap):
		return obj
	return RoaringBitmap(obj)


cdef inline uint16_t highbits(uint32_t x) nogil:
	return x >> 16


cdef inline uint16_t lowbits(uint32_t x) nogil:
	return x & 0xFFFF


cdef inline uint32_t min(uint32_t a, uint32_t b) nogil:
	return a if a <= b else b


cdef inline uint32_t max(uint32_t a, uint32_t b) nogil:
	return a if a >= b else b


__all__ = ['RoaringBitmap']
