# cdef inline functions defined here:
# ===================================
# cdef inline int iteratesetbits(uint64_t *vec,
#		uint64_t *cur, int *idx) nogil
# cdef inline int iterateunsetbits(uint64_t *vec,
#		uint64_t *cur, int *idx) nogil
# cdef inline int reviteratesetbits(uint64_t *vec,
#		uint64_t *cur, int *idx) nogil
# cdef inline uint32_t bitsetintersectinplace(uint64_t *dest,
#		uint64_t *src) nogil
# cdef inline uint32_t bitsetunioninplace(uint64_t *dest, uint64_t *src) nogil
# cdef inline uint32_t bitsetxorinplace(uint64_t *dest, uint64_t *src) nogil
# cdef inline uint32_t bitsetsubtractinplace(uint64_t *dest,
#		uint64_t *src) nogil
# cdef inline uint32_t bitsetintersect(uint64_t *dest, uint64_t *src1,
# 		uint64_t *src2) nogil
# cdef inline uint32_t bitsetunion(uint64_t *dest, uint64_t *src1,
# 		uint64_t *src2) nogil
# cdef inline uint32_t bitsetxor(uint64_t *dest,
#		uint64_t *src1, uint64_t *src2) nogil
# cdef inline uint32_t bitsetsubtract(uint64_t *dest, uint64_t *src1,
# 		uint64_t *src2) nogil
# cdef inline uint32_t bitsetunioncount(uint64_t *src1, uint64_t *src2) nogil
# cdef inline uint32_t bitsetintersectcount(uint64_t *src1,
#		uint64_t *src2) nogil
# cdef inline void bitsetintersectunioncount(uint64_t *src1, uint64_t *src2,
#		uint32_t *intersection_count, uint32_t *union_count) nogil
# cdef inline bint bitsubset(uint64_t *vec1, uint64_t *vec2) nogil
# cdef inline int select64(uint64_t w, int i) except -1
# cdef inline int select32(uint32_t w, int i) except -1
# cdef inline int select16(uint16_t w, int i) except -1
"""
All bitvector operands are assumed to have ``BLOCKSIZE`` elements (bits).
"""

cdef inline int iteratesetbits(uint64_t *vec,
		uint64_t *cur, int *idx) nogil:
	"""Iterate over set bits in an array of unsigned long.

	:param cur and idx: pointers to variables to maintain state,
		``idx`` should be initialized to 0,
		and ``cur`` to the first element of
		the bit array ``vec``, i.e., ``cur = vec[idx]``.
	:returns: the index of a set bit, or -1 if there are no more set
		bits. The result of calling a stopped iterator is undefined.

	e.g.::

		int idx = 0
		uint64_t vec[4] = {0, 0, 0, 0b10001}, cur = vec[idx]
		iteratesetbits(vec, 4, &cur, &idx) # returns 0
		iteratesetbits(vec, 4, &cur, &idx) # returns 4
		iteratesetbits(vec, 4, &cur, &idx) # returns -1
	"""
	cdef int tmp
	while not cur[0]:
		idx[0] += 1
		if idx[0] >= <int>(BLOCKSIZE // BITSIZE):
			return -1
		cur[0] = vec[idx[0]]
	tmp = bit_ctz(cur[0])  # index of right-most 1-bit in current slot
	cur[0] ^= 1ULL << tmp  # TOGGLEBIT(cur, tmp)
	return idx[0] * BITSIZE + tmp


cdef inline int iterateunsetbits(uint64_t *vec,
		uint64_t *cur, int *idx) nogil:
	"""Like ``iteratesetbits``, but return indices of zero bits.

	:param cur: should be initialized as: ``cur = ~vec[idx]``."""
	cdef int tmp
	while not cur[0]:
		idx[0] += 1
		if idx[0] >= <int>(BLOCKSIZE // BITSIZE):
			return -1
		cur[0] = ~vec[idx[0]]
	tmp = bit_ctz(cur[0])  # index of right-most 0-bit in current slot
	cur[0] ^= 1ULL << tmp  # TOGGLEBIT(cur, tmp)
	return idx[0] * BITSIZE + tmp


cdef inline int reviteratesetbits(uint64_t *vec, uint64_t *cur,
		int *idx) nogil:
	"""Iterate in reverse over set bits in an array of unsigned long.

	:param cur and idx: pointers to variables to maintain state,
		``idx`` should be initialized to ``slots - 1``, where slots is the
		number of elements in unsigned long array ``vec``.
		``cur`` should be initialized to the last element of
		the bit array ``vec``, i.e., ``cur = vec[idx]``.
	:returns: the index of a set bit, or -1 if there are no more set
		bits. The result of calling a stopped iterator is undefined.

	e.g.::

		int idx = 3
		uint64_t vec[4] = {0, 0, 0, 0b10001}, cur = vec[idx]
		reviteratesetbits(vec, 4, &cur, &idx) # returns 4
		reviteratesetbits(vec, 4, &cur, &idx) # returns 0
		reviteratesetbits(vec, 4, &cur, &idx) # returns -1
	"""
	cdef int tmp
	while not cur[0]:
		idx[0] -= 1
		if idx[0] < 0:
			return -1
		cur[0] = vec[idx[0]]
	tmp = BITSIZE - bit_clz(cur[0]) - 1  # index of left-most 1-bit in cur
	cur[0] &= ~(1ULL << tmp)  # CLEARBIT(cur, tmp)
	return idx[0] * BITSIZE + tmp


# Inplace ops
cdef inline uint32_t bitsetintersectinplace(uint64_t *dest, uint64_t *src) nogil:
	"""dest gets the intersection of dest and src.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = dest[n] & src[n]
		res2 = dest[n + 1] & src[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


cdef inline uint32_t bitsetunioninplace(uint64_t *dest, uint64_t *src) nogil:
	"""dest gets the union of dest and src.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = dest[n] | src[n]
		res2 = dest[n + 1] | src[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


cdef inline uint32_t bitsetxorinplace(uint64_t *dest, uint64_t *src) nogil:
	"""dest gets the xor of dest and src.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = dest[n] ^ src[n]
		res2 = dest[n + 1] ^ src[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


cdef inline uint32_t bitsetsubtractinplace(uint64_t *dest, uint64_t *src) nogil:
	"""dest gets dest - src.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = dest[n] & ~src[n]
		res2 = dest[n + 1] & ~src[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


# Non-inplace ops
cdef inline uint32_t bitsetintersect(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the intersection of src1 and src2.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] & src2[n]
		res2 = src1[n + 1] & src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


cdef inline uint32_t bitsetunion(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the union of src1 and src2.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] | src2[n]
		res2 = src1[n + 1] | src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


cdef inline uint32_t bitsetxor(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the xor of src1 and src2.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] ^ src2[n]
		res2 = src1[n + 1] ^ src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


cdef inline uint32_t bitsetsubtract(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the src2 - src1.

	:returns: number of set bits in result."""
	cdef size_t n
	cdef uint64_t res1, res2
	cdef uint32_t result = 0
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] & ~src2[n]
		res2 = src1[n + 1] & ~src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2
		result += bit_popcount(res1)
		result += bit_popcount(res2)
	return result


# Count cardinality only
cdef inline uint32_t bitsetunioncount(uint64_t *src1, uint64_t *src2) nogil:
	"""return the cardinality of the union of dest and src.

	:returns: number of set bits in result.
	Both operands are assumed to have a fixed number of bits ``BLOCKSIZE``."""
	cdef uint32_t result = 0
	cdef size_t n
	for n in range(<size_t>(BLOCKSIZE // BITSIZE)):
		result += bit_popcount(src1[n] | src2[n])
	return result


cdef inline uint32_t bitsetintersectcount(uint64_t *src1, uint64_t *src2) nogil:
	"""return the cardinality of the intersection of dest and src.

	:returns: number of set bits in result.
	Both operands are assumed to have a fixed number of bits ``BLOCKSIZE``."""
	cdef uint32_t result = 0
	cdef size_t n
	for n in range(<size_t>(BLOCKSIZE // BITSIZE)):
		result += bit_popcount(src1[n] & src2[n])
	return result


cdef inline void bitsetintersectunioncount(uint64_t *src1, uint64_t *src2,
		uint32_t *intersection_count, uint32_t *union_count) nogil:
	"""Compute the cardinalities of the intersection and union of dest and src.

	:returns: number of set bits in result.
	Both operands are assumed to have a fixed number of bits ``BLOCKSIZE``."""
	cdef size_t n
	for n in range(<size_t>(BLOCKSIZE // BITSIZE)):
		intersection_count[0] += bit_popcount(src1[n] & src2[n])
		union_count[0] += bit_popcount(src1[n] | src2[n])


cdef inline bint bitsubset(uint64_t *vec1, uint64_t *vec2) nogil:
	"""Test whether vec1 is a subset of vec2.

	i.e., all set bits of vec1 should be set in vec2."""
	cdef size_t n
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		if (vec1[n] & vec2[n]) != vec1[n] or (
				vec1[n + 1] & vec2[n + 1]) != vec1[n + 1]:
			return False
	return True


cdef inline bint bitdisjoint(uint64_t *vec1, uint64_t *vec2) nogil:
	"""Test whether vec1 is disjoint from vec2.

	i.e., len(vec1 & vec2) = 0."""
	cdef size_t n
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		if (vec1[n] & vec2[n]) or (vec1[n + 1] & vec2[n + 1]):
			return False
	return True


cdef inline int select64(uint64_t w, int i) except -1:
	"""Given a 64-bit int w, return the position of the ith 1-bit."""
	cdef uint64_t part1 = w & 0xFFFFFFFFUL
	cdef int wfirsthalf = bit_popcount(part1)
	if wfirsthalf > i:
		return select32(part1, i)
	else:
		return select32(<uint32_t>(w >> 32), i - wfirsthalf) + 32


cdef inline int select32(uint32_t w, int i) except -1:
	"""Given a 32-bit int w, return the position of the ith 1-bit."""
	cdef uint64_t part1 = w & 0xFFFFUL
	cdef int wfirsthalf = bit_popcount(part1)
	if wfirsthalf > i:
		return select16(part1, i)
	else:
		return select16(w >> 16, i - wfirsthalf) + 16


cdef inline int select16(uint16_t w, int i) except -1:
	"""Given a 16-bit int w, return the position of the ith 1-bit."""
	cdef int sumtotal = 0, counter
	for counter in range(16):
		sumtotal += (w >> counter) & 1
		if sumtotal > i:
			return counter
	raise IndexError('select16: index %d out of range 0..%d.' % (
			i, bit_popcount(w)))
