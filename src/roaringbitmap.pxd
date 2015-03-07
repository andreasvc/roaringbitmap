from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t
from libc.string cimport memset, memcpy, memcmp
from posix.stdlib cimport posix_memalign
from libc.stdlib cimport free

cimport cython
from cpython cimport array


cdef extern from "macros.h":
	int BITSIZE
	int BITSLOT(int b)
	int BITNSLOTS(int nb)
	void SETBIT(uint64_t a[], int b)
	void CLEARBIT(uint64_t a[], int b)
	uint64_t TESTBIT(uint64_t a[], int b)
	uint64_t BITMASK(int b)


cdef extern from "bitcount.h":
	unsigned int bit_clz(uint64_t)
	unsigned int bit_ctz(uint64_t)
	unsigned int bit_popcount(uint64_t)

cdef class RoaringBitmap(object):
	cdef list data

	cdef int _getindex(self, uint16_t elem)
	cdef int _binarysearch(self, int begin, int end, uint16_t elem)
