from libc.stdint cimport uint16_t, uint32_t, uint64_t
from libc.string cimport memset, memcpy

cimport cython
from cpython cimport array
from roaringbitmap.bit cimport iteratesetbits, iterateunsetbits, \
		bitsetintersect, bitsetunion, bitsetsubtract, bitsetxor, \
		bitsetintersectinplace, bitsetunioninplace, \
		bitsetsubtractinplace, bitsetxorinplace, \
		anextset, anextunset, abitcount, abitlength

cdef extern from "macros.h":
	int BITSIZE
	int BITSLOT(int b)
	int BITNSLOTS(int nb)
	void SETBIT(uint64_t a[], int b)
	void CLEARBIT(uint64_t a[], int b)
	uint64_t TESTBIT(uint64_t a[], int b)
	uint64_t BITMASK(int b)


cdef class RoaringBitmap(object):
	cdef list data

	cdef int _getindex(self, uint16_t elem)
	cdef int _binarysearch(self, int begin, int end, uint16_t elem)
