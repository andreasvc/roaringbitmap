from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t
from libc.string cimport memcpy

cdef extern from "macros.h":
	int BITSIZE
	int BITSLOT(int b)
	uint64_t BITMASK(int b)
	uint64_t TESTBIT(uint64_t a[], int b)
	void CLEARBIT(uint64_t a[], int b)


cdef extern from "bitcount.h":
	unsigned int bit_clz(uint64_t)
	unsigned int bit_ctz(uint64_t)
	unsigned int bit_popcount(uint64_t)


# cdef inline functions defined here:
# ===================================
# cdef inline int abitcount(uint64_t *vec, int slots)
# cdef inline int anextset(uint64_t *vec, uint32_t pos, int slots)
# cdef inline int anextunset(uint64_t *vec, uint32_t pos, int slots)
# cdef inline bint subset(uint64_t *vec1, uint64_t *vec2, int slots)
# cdef inline void bitsetunioninplace(uint64_t *dest,
#		uint64_t *src, int slots)
# cdef inline void bitsetintersectinplace(uint64_t *dest,
#		uint64_t *src, int slots)
# cdef inline void bitsetunion(uint64_t *dest, uint64_t *src1,
#		uint64_t *src2, int slots)
# cdef inline void bitsetintersect(uint64_t *dest, uint64_t *src1,
#		uint64_t *src2, int slots)

cdef inline int abitcount(uint64_t *vec, int slots):
	""" Return number of set bits in variable length bitvector """
	cdef int a
	cdef int result = 0
	for a in range(slots):
		result += bit_popcount(vec[a])
	return result


cdef inline int abitlength(uint64_t *vec, int slots):
	"""Return number of bits needed to represent vector.

	(equivalently: index of most significant set bit, plus one)."""
	cdef int a = slots - 1
	while a and not vec[a]:
		a -= 1
	return (a + 1) * sizeof(uint64_t) * 8 - bit_clz(vec[a])


cdef inline int anextset(uint64_t *vec, uint32_t pos, int slots):
	""" Return next set bit starting from pos, -1 if there is none. """
	cdef int a = BITSLOT(pos)
	cdef uint64_t x
	if a >= slots:
		return -1
	x = vec[a] & (~0UL << (pos % BITSIZE))
	while x == 0UL:
		a += 1
		if a == slots:
			return -1
		x = vec[a]
	return a * BITSIZE + bit_ctz(x)


cdef inline int anextunset(uint64_t *vec, uint32_t pos, int slots):
	""" Return next unset bit starting from pos. """
	cdef int a = BITSLOT(pos)
	cdef uint64_t x
	if a >= slots:
		return a * BITSIZE
	x = vec[a] | (BITMASK(pos) - 1)
	while x == ~0UL:
		a += 1
		if a == slots:
			return a * BITSIZE
		x = vec[a]
	return a * BITSIZE + bit_ctz(~x)


cdef inline int iteratesetbits(uint64_t *vec, int slots,
		uint64_t *cur, int *idx):
	"""Iterate over set bits in an array of unsigned long.

	:param slots: number of elements in unsigned long array ``vec``.
	:param cur and idx: pointers to variables to maintain state,
		``idx`` should be initialized to 0,
		and ``cur`` to the first element of
		the bit array ``vec``, i.e., ``cur = vec[idx]``.
	:returns: the index of a set bit, or -1 if there are no more set
		bits. The result of calling a stopped iterator is undefined.

	e.g.::

		uint64_t vec[4] = {0, 0, 0, 0b10001}, cur = vec[0]
		int idx = 0
		iteratesetbits(vec, 4, &cur, &idx) # returns 0
		iteratesetbits(vec, 4, &cur, &idx) # returns 4
		iteratesetbits(vec, 4, &cur, &idx) # returns -1
	"""
	cdef int tmp
	while not cur[0]:
		idx[0] += 1
		if idx[0] >= slots:
			return -1
		cur[0] = vec[idx[0]]
	tmp = bit_ctz(cur[0])  # index of bit in current slot
	CLEARBIT(cur, tmp)
	return idx[0] * BITSIZE + tmp


cdef inline int iterateunsetbits(uint64_t *vec, int slots,
		uint64_t *cur, int *idx):
	"""Like ``iteratesetbits``, but return indices of zero bits."""
	cdef int tmp
	while not ~cur[0]:
		idx[0] += 1
		if idx[0] >= slots:
			return -1
		cur[0] = vec[idx[0]]
	tmp = bit_ctz(~cur[0])  # index of bit in current slot
	CLEARBIT(cur, tmp)
	return idx[0] * BITSIZE + tmp


cdef inline int bitsetintersectinplace(uint64_t *dest, uint64_t *src, int slots):
	"""dest gets the intersection of dest and src.

	both operands must have at least `slots' slots."""
	cdef int a
	cdef size_t result = 0
	for a in range(slots):
		dest[a] &= src[a]
		result += bit_popcount(dest[a])
	return result

cdef inline int bitsetunioninplace(uint64_t *dest, uint64_t *src, int slots):
	"""dest gets the union of dest and src.

	Both operands must have at least ``slots`` slots."""
	cdef int a
	cdef size_t result = 0
	for a in range(slots):
		dest[a] |= src[a]
		result += bit_popcount(dest[a])
	return result


cdef inline void bitsetintersect(uint64_t *dest, uint64_t *src1, uint64_t *src2,
		int slots):
	"""dest gets the intersection of src1 and src2.

	operands must have at least ``slots`` slots."""
	cdef int a
	for a in range(slots):
		dest[a] = src1[a] & src2[a]


cdef inline void bitsetunion(uint64_t *dest, uint64_t *src1, uint64_t *src2,
		int slots):
	"""dest gets the union of src1 and src2.

	operands must have at least ``slots`` slots."""
	cdef int a
	for a in range(slots):
		dest[a] = src1[a] | src2[a]


cdef inline bint subset(uint64_t *vec1, uint64_t *vec2, int slots):
	"""Test whether vec1 is a subset of vec2.

	i.e., all set bits of vec1 should be set in vec2."""
	cdef int a
	for a in range(slots):
		if (vec1[a] & vec2[a]) != vec1[a]:
			return False
	return True
