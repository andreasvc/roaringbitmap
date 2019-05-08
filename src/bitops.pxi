"""Oerations on fixed-size bitvectors.

All bitvector operands are assumed to have ``BLOCKSIZE`` elements (bits).
"""

# Store result, return cardinality
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


# Only store result, no cardinality
cdef inline void bitsetintersectnocard(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the intersection of src1 and src2."""
	cdef size_t n
	cdef uint64_t res1, res2
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] & src2[n]
		res2 = src1[n + 1] & src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2


cdef inline void bitsetunionnocard(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the union of src1 and src2."""
	cdef size_t n
	cdef uint64_t res1, res2
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] | src2[n]
		res2 = src1[n + 1] | src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2


cdef inline void bitsetxornocard(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the xor of src1 and src2."""
	cdef size_t n
	cdef uint64_t res1, res2
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] ^ src2[n]
		res2 = src1[n + 1] ^ src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2


cdef inline void bitsetsubtractnocard(uint64_t *dest,
		uint64_t *src1, uint64_t *src2) nogil:
	"""dest gets the src2 - src1."""
	cdef size_t n
	cdef uint64_t res1, res2
	for n in range(0, <size_t>(BLOCKSIZE // BITSIZE), 2):
		res1 = src1[n] & ~src2[n]
		res2 = src1[n + 1] & ~src2[n + 1]
		dest[n] = res1
		dest[n + 1] = res2


# Count cardinality only
cdef inline uint32_t bitsetintersectcount(uint64_t *src1, uint64_t *src2) nogil:
	"""return the cardinality of the intersection of dest and src.

	:returns: number of set bits in result.
	Both operands are assumed to have a fixed number of bits ``BLOCKSIZE``."""
	cdef uint32_t result = 0
	cdef size_t n
	for n in range(<size_t>(BLOCKSIZE // BITSIZE)):
		result += bit_popcount(src1[n] & src2[n])
	return result


# Other operations
cdef inline int iteratesetbits(uint64_t *vec,
		uint64_t *cur, int *idx) nogil:
	"""Iterate over set bits in an array of unsigned long.

	:param cur: pointer to variable to maintain state,
		``cur`` should be initialized to the first element of
		the bit array ``vec``, i.e., ``cur = vec[idx]``.
	:param idx: pointer to variable to maintain state,
		``idx`` should be initialized to 0.
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

	:param cur: should be initialized as: ``cur = ~vec[idx]``.
	:param idx: pointer to variables to maintain state,
		``idx`` should be initialized to 0.
	"""
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

	:param cur: pointer to variable to maintain state,
		``cur`` should be initialized to the last element of
		the bit array ``vec``, i.e., ``cur = vec[idx]``.
	:param idx: pointer to variable to maintain state,
		``idx`` should be initialized to ``slots - 1``, where slots is the
		number of elements in unsigned long array ``vec``.
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


cdef inline uint32_t extractsetbits(uint16_t *dest, uint64_t *src) nogil:
	"""Store set bits of bitvector in preallocated array.

	:returns: number of elements in result."""
	cdef size_t n, length = 0, base = 0
	cdef uint64_t cur
	for n in range(<size_t>(BLOCKSIZE // BITSIZE)):
		cur = src[n]
		while cur:
			dest[length] = base + bit_ctz(cur)
			length += 1
			cur ^= cur & -cur
		base += 64
	return length


cdef inline uint32_t extractunsetbits(uint16_t *dest, uint64_t *src) nogil:
	"""Store zero bits of bitvector in preallocated array.

	:returns: number of elements in result."""
	cdef size_t n, length = 0, base = 0
	cdef uint64_t cur
	for n in range(<size_t>(BLOCKSIZE // BITSIZE)):
		cur = ~src[n]
		while cur:
			dest[length] = base + bit_ctz(cur)
			length += 1
			cur ^= cur & -cur
		base += 64
	return length


cdef inline uint32_t extractintersection(
		uint16_t *dest, uint64_t *src1, uint64_t *src2) nogil:
	"""Compute intersection of bitvectors and store in preallocated array.

	:returns: number of elements in result."""
	cdef size_t n, length = 0, base = 0
	cdef uint64_t cur
	for n in range(<size_t>(BLOCKSIZE // BITSIZE)):
		cur = src1[n] & src2[n]
		while cur:
			dest[length] = base + bit_ctz(cur)
			length += 1
			cur ^= cur & -cur
		base += 64
	return length


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


cdef inline void setbitcard(uint64_t *bitmap, uint16_t elem,
		uint32_t *cardinality) nogil:
	"""Set bit and update cardinality without branch."""
	cdef uint32_t i
	cdef uint64_t ow, nw
	i = BITSLOT(elem)
	ow = bitmap[i]
	nw = ow | BITMASK(elem)
	cardinality[0] += (ow ^ nw) >> (elem % BITSIZE)
	bitmap[i] = nw


cdef inline void clearbitcard(uint64_t *bitmap, uint16_t elem,
		uint32_t *cardinality) nogil:
	"""Clear bit and update cardinality without branch."""
	cdef uint32_t i
	cdef uint64_t ow, nw
	i = BITSLOT(elem)
	ow = bitmap[i]
	nw = ow & ~BITMASK(elem)
	cardinality[0] -= (ow ^ nw) >> (elem % BITSIZE)
	bitmap[i] = nw


cdef inline void togglebitcard(uint64_t *bitmap, uint16_t elem,
		uint32_t *cardinality) nogil:
	"""Flip bit and update cardinality without branch."""
	cdef uint32_t i
	cdef uint64_t ow, nw
	i = BITSLOT(elem)
	ow = bitmap[i]
	nw = ow ^ BITMASK(elem)
	cardinality[0] += (nw >> (elem % BITSIZE)) - (ow >> (elem % BITSIZE))
	bitmap[i] = nw
