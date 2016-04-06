from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t
from libc.string cimport memset, memcpy, memcmp, memmove
from libc.stdlib cimport free, malloc, realloc
from posix.stdlib cimport posix_memalign
from cpython cimport array
cimport cython


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
	uint8_t state  # either DENSE, INVERTED, or POSITIVE
	uint16_t key  # the high bits of elements in this block
	uint32_t cardinality  # the number of elements
	uint32_t capacity  # allocated elements
	Buffer buf  # data: sparse array or fixed-size bitvector


cdef class RoaringBitmap(object):
	cdef Block *data
	cdef uint32_t size  # the number of blocks
	cdef uint32_t capacity  # the allocated capacity for blocks

	cdef int _getindex(self, uint16_t elem)
	cdef int _binarysearch(self, int begin, int end, uint16_t elem)
	cdef _extendarray(self, int k)
	cdef _resize(self, int k)
	cdef _removeatidx(self, int i)
	cdef _insert(self, int i, Block *elem)
