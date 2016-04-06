cdef inline bint block_contains(Block *self, uint16_t elem) nogil:
	cdef bint found
	if self.state == DENSE:
		found = TESTBIT(self.buf.dense, elem) != 0
	elif self.state == POSITIVE:
		found = binarysearch(self.buf.sparse,
				0, self.cardinality, elem) >= 0
	else:  # self.state == INVERTED:
		found = binarysearch(self.buf.sparse,
				0, BLOCKSIZE - self.cardinality, elem) < 0
	return found


cdef inline block_add(Block *self, uint16_t elem):
	cdef int i
	if self.state == DENSE:
		if not TESTBIT(self.buf.dense, elem):
			SETBIT(self.buf.dense, elem)
			self.cardinality += 1
	elif self.state == POSITIVE:
		i = binarysearch(self.buf.sparse, 0, self.cardinality, elem)
		if i < 0:
			_insert(self, -i - 1, elem)
	elif self.state == INVERTED:
		i = binarysearch(
				self.buf.sparse, 0, BLOCKSIZE - self.cardinality, elem)
		if i >= 0:
			_removeatidx(self, i)


cdef inline block_discard(Block *self, uint16_t elem):
	cdef int i
	if self.state == DENSE:
		if TESTBIT(self.buf.dense, elem):
			CLEARBIT(self.buf.dense, elem)
			self.cardinality -= 1
			block_convert(self)
	elif self.state == POSITIVE:
		i = binarysearch(self.buf.sparse, 0, self.cardinality, elem)
		if i >= 0:
			_removeatidx(self, i)
	elif self.state == INVERTED:
		i = binarysearch(
				self.buf.sparse, 0, BLOCKSIZE - self.cardinality, elem)
		if i < 0:
			_insert(self, -i - 1, elem)
			block_convert(self)


cdef inline uint32_t block_pop(Block *self) except 1 << 16:
	"""Remove and return the largest element."""
	cdef uint32_t high = self.key << 16
	cdef uint32_t n
	cdef uint64_t cur
	cdef int idx, low
	if self.cardinality == 0:
		raise ValueError('pop from empty roaringbitmap')
	if self.state == DENSE:
		idx = BITNSLOTS(BLOCKSIZE) - 1
		cur = self.buf.dense[idx]
		n = reviteratesetbits(self.buf.dense, &cur, &idx)
		if n != -1:
			low = n
			elem = high | low
			block_discard(self, elem)
			return low
	elif self.state == POSITIVE:
		self.cardinality -= 1
		return self.buf.sparse[self.cardinality]
	elif self.state == INVERTED:
		for low in reversed(range(self.buf.sparse[
					BLOCKSIZE - self.cardinality - 1] + 1, BLOCKSIZE)):
			elem = high | low
			block_discard(self, elem)
			return low
		if self.cardinality < BLOCKSIZE - 1:
			for n in reversed(range(BLOCKSIZE - self.cardinality - 1)):
				for low in reversed(range(
						self.buf.sparse[n] + 1,
						self.buf.sparse[n + 1])):
					elem = high | low
					block_discard(self, elem)
					return low
		for low in reversed(range(self.buf.sparse[0])):
			elem = high | low
			block_discard(self, elem)
			return low


cdef inline block_initrange(Block *self, uint16_t start, uint32_t stop):
	"""Allocate block and set a range of elements."""
	cdef uint32_t n
	self.cardinality = stop - start
	if self.cardinality < MAXARRAYLENGTH:
		self.buf.sparse = allocsparse(self.cardinality)
		self.capacity = self.cardinality
		self.state = POSITIVE
		for n in range(stop - start):
			self.buf.sparse[n] = start + n
	elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
		self.buf.sparse = allocsparse(BLOCKSIZE - self.cardinality)
		self.capacity = BLOCKSIZE - self.cardinality
		self.state = INVERTED
		for n in range(0, start):
			self.buf.sparse[n] = n
		for n in range(BLOCKSIZE - stop):
			self.buf.sparse[start + n] = stop + n
	else:
		self.buf.dense = allocdense()
		self.capacity = BITMAPSIZE // sizeof(uint16_t)
		self.state = DENSE
		memset(self.buf.ptr, 0, (start // 64 + 1) * sizeof(uint64_t))
		for n in range(start, (start - (start % 64)) + 64):
			SETBIT(self.buf.dense, n)
		memset(&(self.buf.dense[BITSLOT(start) + 1]), 255,
				((BITSLOT(stop) - 1) - (BITSLOT(start) + 1) + 1)
				* sizeof(uint64_t))
		memset(&(self.buf.dense[BITSLOT(stop)]), 0,
				BITMAPSIZE - BITSLOT(stop) * sizeof(uint64_t))
		for n in range(stop - stop % 64, stop):
			SETBIT(self.buf.dense, n)


cdef block_and(Block *result, Block *self, Block *other):
	"""Non-inplace intersection; result must be preallocated."""
	cdef int n, dummy = 0, length = 0, alloc
	if self.state == DENSE and other.state == DENSE:
		_resizeconvert(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
		result.cardinality = bitsetintersect(result.buf.dense,
				self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		alloc = other.cardinality
		_resizeconvert(result, POSITIVE, alloc)
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				result.buf.sparse[length] = other.buf.sparse[n]
				length += 1
		result.cardinality = length
		_resize(result, result.cardinality)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = min(self.cardinality, other.cardinality)
		_resizeconvert(result, POSITIVE, alloc)
		result.cardinality = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				result.buf.sparse)
		_resize(result, result.cardinality)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = BLOCKSIZE - (self.cardinality + other.cardinality)
		_resizeconvert(result, INVERTED, alloc)
		length = union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				result.buf.sparse, &dummy)
		result.cardinality = BLOCKSIZE - length
		_resize(result, length)
	elif self.state == POSITIVE and other.state == INVERTED:
		alloc = self.cardinality
		_resizeconvert(result, POSITIVE, alloc)
		result.cardinality = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				result.buf.sparse)
		_resize(result, result.cardinality)
	elif self.state == INVERTED and other.state == POSITIVE:
		block_and(result, other, self)
	elif self.state == POSITIVE and other.state == DENSE:
		block_and(result, other, self)
	else:
		block_copy(result, self)
		block_iand(result, other)


cdef inline block_iand(Block *self, Block *other):
	cdef Buffer buf
	cdef int length = 0, dummy = 0, alloc
	cdef uint32_t n
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetintersectinplace(
				self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		buf.sparse = allocsparse(other.cardinality)
		self.cardinality = 0
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense,
					other.buf.sparse[n]):
				buf.sparse[self.cardinality] = other.buf.sparse[n]
				self.cardinality += 1
		replacearray(self, buf, other.cardinality)
		self.state = POSITIVE
		_resize(self, self.cardinality)
	elif self.state == DENSE and other.state == INVERTED:
		for n in range(BLOCKSIZE - other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				CLEARBIT(self.buf.dense, other.buf.sparse[n])
				self.cardinality -= 1
	elif self.state == POSITIVE and other.state == DENSE:
		for n in range(self.cardinality):
			if TESTBIT(other.buf.dense, self.buf.sparse[n]):
				self.buf.sparse[length] = self.buf.sparse[n]
				length += 1
		self.cardinality = length
		_resize(self, length)
	elif self.state == POSITIVE and other.state == POSITIVE:
		length = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				self.buf.sparse)
		self.cardinality = length
		_resize(self, length)
	elif self.state == INVERTED and other.state == DENSE:
		buf.dense = allocdense()
		memset(buf.ptr, 255, BITMAPSIZE)
		for n in range(BLOCKSIZE - self.cardinality):
			CLEARBIT(buf.dense, self.buf.sparse[n])
		replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))
		self.state = DENSE
		self.cardinality = bitsetintersectinplace(
				self.buf.dense, other.buf.dense)
	elif self.state == POSITIVE and other.state == INVERTED:
		length = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				self.buf.sparse)
		self.cardinality = length
		_resize(self, length)
	elif self.state == INVERTED and other.state == POSITIVE:
		alloc = max(BLOCKSIZE - self.cardinality, other.cardinality)
		buf.sparse = allocsparse(alloc)
		length = difference(
				other.buf.sparse, self.buf.sparse,
				other.cardinality, BLOCKSIZE - self.cardinality,
				buf.sparse)
		replacearray(self, buf, alloc)
		self.state = POSITIVE
		self.cardinality = length
		_resize(self, length)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = BLOCKSIZE - (self.cardinality + other.cardinality)
		buf.sparse = allocsparse(alloc)
		length = union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				buf.sparse, &dummy)
		replacearray(self, buf, alloc)
		self.cardinality = BLOCKSIZE - length
		_resize(self, length)
	block_convert(self)


cdef inline block_ior(Block *self, Block *other):
	cdef Buffer buf
	cdef int length = 0, alloc
	cdef uint32_t n
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetunioninplace(
				self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			if not TESTBIT(self.buf.dense, other.buf.sparse[n]):
				SETBIT(self.buf.dense, other.buf.sparse[n])
				self.cardinality += 1
	elif self.state == POSITIVE and other.state == DENSE:
		buf.dense = allocdense()
		memcpy(buf.dense, other.buf.dense, BITMAPSIZE)
		length = other.cardinality
		for n in range(self.cardinality):
			if not TESTBIT(buf.dense, self.buf.sparse[n]):
				SETBIT(buf.dense, self.buf.sparse[n])
				length += 1
		replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))
		self.state = DENSE
		self.cardinality = length
	elif self.state == DENSE and other.state == INVERTED:
		alloc = BLOCKSIZE - other.cardinality
		buf.sparse = allocsparse(alloc)
		memcpy(buf.sparse, other.buf.sparse,
				(BLOCKSIZE - other.cardinality) * sizeof(uint16_t))
		for n in range(BLOCKSIZE - other.cardinality):
			if not TESTBIT(self.buf.dense, other.buf.sparse[n]):
				buf.sparse[length] = other.buf.sparse[n]
				length += 1
		replacearray(self, buf, alloc)
		self.cardinality = BLOCKSIZE - length
		self.state = INVERTED
		_resize(self, length)
	elif self.state == INVERTED and other.state == DENSE:
		buf.sparse = allocsparse(self.cardinality)
		for n in range(BLOCKSIZE - self.cardinality):
			if not TESTBIT(other.buf.dense, self.buf.sparse[n]):
				buf.sparse[length] = self.buf.sparse[n]
				length += 1
		replacearray(self, buf, self.cardinality)
		self.cardinality = BLOCKSIZE - length
		_resize(self, length)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = self.cardinality + other.cardinality
		buf.sparse = allocsparse(alloc)
		self.cardinality = union2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				buf.sparse, &length)
		replacearray(self, buf, alloc)
		_resize(self, self.cardinality)
	elif self.state == POSITIVE and other.state == INVERTED:
		buf.sparse = allocsparse(BLOCKSIZE - self.cardinality)
		length = difference(
				other.buf.sparse, self.buf.sparse,
				BLOCKSIZE - other.cardinality, self.cardinality,
				buf.sparse)
		self.buf.sparse = buf.sparse
		self.state = INVERTED
		self.cardinality = BLOCKSIZE - length
		_resize(self, length)
	elif self.state == INVERTED and other.state == POSITIVE:
		length = difference(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, other.cardinality,
				self.buf.sparse)
		self.cardinality = BLOCKSIZE - length
		_resize(self, length)
	elif self.state == INVERTED and other.state == INVERTED:
		length = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				self.buf.sparse)
		self.cardinality = BLOCKSIZE - length
		_resize(self, length)
	block_convert(self)


cdef inline block_isub(Block *self, Block *other):
	cdef Buffer buf
	cdef int length = 0, dummy = 0, alloc
	cdef uint32_t n
	if self.state == INVERTED and other.state == DENSE:
		block_todense(self)
	# fall through
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetsubtractinplace(
				self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				CLEARBIT(self.buf.dense,
						other.buf.sparse[n])
				self.cardinality -= 1
	elif self.state == DENSE and other.state == INVERTED:
		alloc = BLOCKSIZE - other.cardinality
		buf.sparse = allocsparse(alloc)
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				buf.sparse[length] = n
				length += 1
		replacearray(self, buf, alloc)
		self.cardinality = length
		_resize(self, length)
	elif self.state == POSITIVE and other.state == DENSE:
		for n in range(self.cardinality):
			if not TESTBIT(other.buf.dense, self.buf.sparse[n]):
				self.buf.sparse[length] = self.buf.sparse[n]
				length += 1
		self.cardinality = length
		_resize(self, length)
	elif self.state == POSITIVE and other.state == POSITIVE:
		self.cardinality = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				self.buf.sparse)
		_resize(self, self.cardinality)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = BLOCKSIZE - (self.cardinality + other.cardinality)
		buf.sparse = allocsparse(alloc)
		length = union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				buf.sparse, &dummy)
		replacearray(self, buf, alloc)
		self.cardinality = BLOCKSIZE - length
		_resize(self, length)
	elif self.state == INVERTED and other.state == POSITIVE:
		length = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, other.cardinality,
				self.buf.sparse)
		self.cardinality = BLOCKSIZE - length
		_resize(self, length)
	elif self.state == POSITIVE and other.state == INVERTED:
		self.cardinality = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality, self.buf.sparse)
		_resize(self, self.cardinality)
	block_convert(self)


cdef inline block_ixor(Block *self, Block *other):
	cdef Buffer buf
	cdef int length = 0, alloc
	cdef uint32_t n
	if ((self.state == POSITIVE and other.state == DENSE)
			or (self.state == POSITIVE and other.state == INVERTED)
			or (self.state == INVERTED and other.state == DENSE)
			or (self.state == INVERTED and other.state == POSITIVE)):
		block_todense(self)
	# fall through
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetxorinplace(self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				CLEARBIT(self.buf.dense, other.buf.sparse[n])
				self.cardinality -= 1
			else:
				SETBIT(self.buf.dense, other.buf.sparse[n])
				self.cardinality += 1
	elif self.state == DENSE and other.state == INVERTED:
		buf.dense = allocdense()
		memset(buf.dense, 255, BITMAPSIZE)
		for n in range(BLOCKSIZE - other.cardinality):
			CLEARBIT(buf.dense, other.buf.sparse[n])
		self.cardinality = bitsetxorinplace(self.buf.dense, buf.dense)
		free(buf.dense)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = self.cardinality + other.cardinality
		buf.sparse = allocsparse(alloc)
		length = xor2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				buf.sparse)
		replacearray(self, buf, alloc)
		_resize(self, length)
		self.cardinality = length
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = BLOCKSIZE - (self.cardinality + other.cardinality)
		buf.sparse = allocsparse(alloc)
		length = xor2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				buf.sparse)
		replacearray(self, buf, alloc)
		_resize(self, length)
		self.cardinality = BLOCKSIZE - length
	block_convert(self)


cdef inline bint block_issubset(Block *self, Block *other) nogil:
	cdef int m = 0
	cdef uint32_t n
	if self.key != other.key or self.cardinality > other.cardinality:
		return False
	elif self.state == DENSE and other.state == DENSE:
		return bitsubset(self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == INVERTED:
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				return False
	elif self.state == POSITIVE and other.state == DENSE:
		for n in range(self.cardinality):
			if not TESTBIT(other.buf.dense, self.buf.sparse[n]):
				return False
	elif self.state == POSITIVE and other.state == INVERTED:
		# check that no self array elements exists in
		# negative other array elements
		for n in range(self.cardinality):
			m = binarysearch(other.buf.sparse,
					m, BLOCKSIZE - other.cardinality,
					self.buf.sparse[n])
			if m >= 0:
				return False
			m = -m - 1
			if m >= BLOCKSIZE - other.cardinality:
				break
	elif self.state == POSITIVE and other.state == POSITIVE:
		# check if self array elements are subset
		# of other array elements
		for n in range(self.cardinality):
			m = binarysearch(other.buf.sparse,
					m, other.cardinality, self.buf.sparse[n])
			if m < 0:
				return False
	elif self.state == INVERTED and other.state == INVERTED:
		# check if negative other array elements are subset of
		# negative self array element
		for n in range(BLOCKSIZE - other.cardinality):
			m = binarysearch(self.buf.sparse,
					m, BLOCKSIZE - self.cardinality, other.buf.sparse[n])
			if m < 0:
				return False
	elif self.state == DENSE and other.state == POSITIVE:
		return False
	elif self.state == INVERTED and other.state == DENSE:
		return False
	elif self.state == INVERTED and other.state == POSITIVE:
		return False
	return True


cdef inline bint block_isdisjoint(Block *self, Block *other) nogil:
	# could return counterexample, or -1 if True
	cdef int m = 0
	cdef uint32_t n
	if (self.key != other.key
			or self.cardinality + other.cardinality > BLOCKSIZE):
		return False
	elif self.state == DENSE and other.state == DENSE:
		for n in range(BITNSLOTS(BLOCKSIZE)):
			if self.buf.dense[n] & other.buf.dense[n]:
				return False
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				return False
	elif self.state == POSITIVE and other.state == INVERTED:
		for n in range(self.cardinality):
			m = binarysearch(other.buf.sparse,
					m, BLOCKSIZE - other.cardinality,
					self.buf.sparse[n])
			if m < 0:
				return False
	elif self.state == POSITIVE and other.state == POSITIVE:
		for n in range(self.cardinality):
			m = binarysearch(other.buf.sparse,
					m, other.cardinality, self.buf.sparse[n])
			if m >= 0:
				return False
			m = -m - 1
			if m >= other.cardinality:
				break
	elif self.state == POSITIVE and other.state == DENSE:
		return block_isdisjoint(other, self)
	elif self.state == INVERTED and other.state == POSITIVE:
		return block_isdisjoint(other, self)
	elif self.state == INVERTED and other.state in (DENSE, INVERTED):
		return False
	elif self.state == DENSE and other.state == INVERTED:
		return False
	return True


cdef inline int block_andlen(Block *self, Block *other) nogil:
	"""Cardinality of intersection."""
	cdef int result = 0, dummy = 0
	cdef uint32_t n
	if self.state == DENSE and other.state == DENSE:
		result = bitsetintersectcount(self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				result += 1
	elif self.state == DENSE and other.state == INVERTED:
		result = self.cardinality
		for n in range(BLOCKSIZE - other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				result -= 1
	elif self.state == POSITIVE and other.state == INVERTED:
		result = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				NULL)
	elif self.state == POSITIVE and other.state == POSITIVE:
		result = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				NULL)
	elif self.state == INVERTED and other.state == INVERTED:
		result = BLOCKSIZE - union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				NULL, &dummy)
	elif self.state == POSITIVE and other.state == DENSE:
		return block_andlen(other, self)
	elif self.state == INVERTED and other.state == DENSE:
		return block_andlen(other, self)
	elif self.state == INVERTED and other.state == POSITIVE:
		return block_andlen(other, self)
	return result


cdef inline int block_orlen(Block *self, Block *other) nogil:
	"""Cardinality of union."""
	cdef int result = 0, dummy = 0
	cdef uint32_t n
	if self.state == DENSE and other.state == DENSE:
		result = bitsetunioncount(self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		result = self.cardinality
		for n in range(other.cardinality):
			if not TESTBIT(self.buf.dense, other.buf.sparse[n]):
				result += 1
	elif self.state == DENSE and other.state == INVERTED:
		result = BLOCKSIZE
		for n in range(BLOCKSIZE - other.cardinality):
			if not TESTBIT(self.buf.dense, other.buf.sparse[n]):
				result -= 1
	elif self.state == POSITIVE and other.state == INVERTED:
		result = BLOCKSIZE - difference(
				other.buf.sparse, self.buf.sparse,
				BLOCKSIZE - other.cardinality, self.cardinality, NULL)
	elif self.state == POSITIVE and other.state == POSITIVE:
		result = union2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality, NULL, &dummy)
	elif self.state == INVERTED and other.state == INVERTED:
		result = BLOCKSIZE - intersect2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				NULL)
	elif self.state == POSITIVE and other.state == DENSE:
		return block_orlen(other, self)
	elif self.state == INVERTED and other.state == DENSE:
		return block_orlen(other, self)
	elif self.state == INVERTED and other.state == POSITIVE:
		return block_orlen(other, self)
	return result


cdef inline void block_andorlen(Block *self, Block *other,
		int *intersection_result, int *union_result) nogil:
	"""Cardinality of both intersection and union."""
	cdef uint32_t n
	if self.state == DENSE and other.state == DENSE:
		bitsetintersectunioncount(self.buf.dense, other.buf.dense,
				intersection_result, union_result)
	elif self.state == POSITIVE and other.state == POSITIVE:
		union_result[0] = union2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality, NULL, intersection_result)
	elif self.state == INVERTED and other.state == INVERTED:
		intersection_result[0] = union2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality, NULL, union_result)
		union_result[0] = BLOCKSIZE - union_result[0]
		intersection_result[0] = BLOCKSIZE - intersection_result[0]
	elif self.state == DENSE and other.state == POSITIVE:
		union_result[0] = self.cardinality
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				intersection_result[0] += 1
			else:
				union_result[0] += 1
	elif self.state == DENSE and other.state == INVERTED:
		intersection_result[0] = self.cardinality
		union_result[0] = BLOCKSIZE
		for n in range(BLOCKSIZE - other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				intersection_result[0] -= 1
			else:
				union_result[0] -= 1
	elif self.state == POSITIVE and other.state == INVERTED:
		symmetricdifflen(other.buf.sparse, self.buf.sparse,
				BLOCKSIZE - other.cardinality, self.cardinality,
				union_result, intersection_result)
		union_result[0] = BLOCKSIZE - union_result[0]
	elif self.state == POSITIVE and other.state == DENSE:
		block_andorlen(other, self, intersection_result, union_result)
	elif self.state == INVERTED and other.state == DENSE:
		block_andorlen(other, self, intersection_result, union_result)
	elif self.state == INVERTED and other.state == POSITIVE:
		block_andorlen(other, self, intersection_result, union_result)


cdef inline int block_rank(Block *self, uint16_t x) nogil:
	"""Number of 1-bits in this bitmap ``<= x``."""
	cdef int result = 0
	cdef int leftover
	cdef size_t size
	cdef uint32_t n
	if self.state == DENSE:
		leftover = (x + 1) & (BITSIZE - 1)
		for n in range(BITSLOT(x + 1)):
			result += bit_popcount(self.buf.dense[n])
		if leftover != 0:
			result += bit_popcount(
					self.buf.dense[BITSLOT(x + 1)] << (BITSIZE - leftover))
		return result
	elif self.state == POSITIVE:
		result = binarysearch(self.buf.sparse, 0, self.cardinality, x)
		if result >= 0:
			return result + 1
		else:
			return -result - 1
	elif self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
		result = binarysearch(self.buf.sparse, 0, size, x)
		if result >= 0:
			return x - result - 1
		else:
			return x + result - 1


cdef inline int block_select(Block *self, int i) except -1:
	"""Find smallest x s.t. rank(x) >= i."""
	cdef int n, w = 0
	cdef size_t size
	if i >= self.cardinality:
		raise IndexError('select: index %d out of range 0..%d.' % (
				i, self.cardinality))
	elif self.state == DENSE:
		for n in range(BITNSLOTS(BLOCKSIZE)):
			w = bit_popcount(self.buf.dense[n])
			if w > i:
				return BITSIZE * n + select64(self.buf.dense[n], i)
			i -= w
	elif self.state == POSITIVE:
		return self.buf.sparse[i]
	elif self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
		for n in range(size):
			if self.buf.sparse[n] - n >= i:
				return self.buf.sparse[n] - i - n
		return self.buf.sparse[size - 1] + i - size


cdef block_copy(Block *dest, Block *src):
	cdef size_t size = _getsize(src)
	dest.state = src.state
	dest.key = src.key
	dest.cardinality = src.cardinality
	if dest.state == DENSE:
		dest.buf.dense = allocdense()
	else:
		dest.buf.sparse = allocsparse(size)
		dest.capacity = size
	memcpy(dest.buf.ptr, src.buf.ptr, size * sizeof(uint16_t))


# cdef flip(Block *self):
# 	"""In-place complement of this block."""
# 	if self.state == DENSE:
# 		for n in range(BITNSLOTS(BLOCKSIZE)):
# 			self.buf.dense[n] = ~self.buf.dense[n]
# 	elif self.state == POSITIVE:
# 		self.state = INVERTED
# 	elif self.state == INVERTED:
# 		self.state = POSITIVE
# 	# FIXME: need notion of maximium element
# 	self.cardinality = BLOCKSIZE - self.cardinality


cdef block_repr(Block *self):
	if self.state == DENSE:
		return 'D(key=%d, <%d bits set>)' % (self.key, self.cardinality)
	elif self.state == POSITIVE:
		return 'P(key=%d, %r)' % (self.key, [
				self.buf.sparse[n] for n in range(self.cardinality)])
	elif self.state == INVERTED:
		return 'I(key=%d, %r)' % (self.key, [
				self.buf.sparse[n] for n in range(
					BLOCKSIZE - self.cardinality)])
	else:
		return '?%d,%d,%d' % (self.state, self.key, self.cardinality)
		# raise ValueError


cdef inline block_convert(Block *self):
	"""Convert between dense, sparse, and inverted sparse as needed."""
	if self.state == DENSE:
		if self.cardinality < MAXARRAYLENGTH:
			block_toposarray(self)
		elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
			block_toinvarray(self)
	elif self.state == POSITIVE:
		if MAXARRAYLENGTH <= self.cardinality <= BLOCKSIZE - MAXARRAYLENGTH:
			# To dense bitvector
			block_todense(self)
		elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
			# shouldn't happen.
			raise ValueError
	elif self.state == INVERTED:
		if MAXARRAYLENGTH <= self.cardinality <= BLOCKSIZE - MAXARRAYLENGTH:
			block_todense(self)
		elif self.cardinality < MAXARRAYLENGTH:
			# shouldn't happen.
			raise ValueError


cdef inline block_todense(Block *self):
	# To dense bitvector
	cdef uint32_t n
	cdef Buffer buf
	if self.state == DENSE:
		return
	buf.dense = allocdense()
	if self.state == POSITIVE:
		memset(buf.dense, 0, BITMAPSIZE)
		for n in range(self.cardinality):
			SETBIT(buf.dense, self.buf.sparse[n])
	elif self.state == INVERTED:
		memset(buf.dense, 255, BITMAPSIZE)
		for n in range(BLOCKSIZE - self.cardinality):
			CLEARBIT(buf.dense, self.buf.sparse[n])
	self.state = DENSE
	replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))


cdef inline block_toposarray(Block *self):
	# To positive sparse array
	cdef Buffer buf
	cdef int idx, elem
	cdef uint32_t n
	cdef uint64_t cur
	if self.state == DENSE:
		buf.sparse = allocsparse(self.cardinality)
		idx = n = 0
		cur = self.buf.dense[idx]
		elem = iteratesetbits(self.buf.dense, &cur, &idx)
		while elem != -1:
			buf.sparse[n] = elem
			n += 1
			elem = iteratesetbits(self.buf.dense, &cur, &idx)
		assert n == self.cardinality
		self.state = POSITIVE
		replacearray(self, buf, n)
	elif self.state == INVERTED:
		raise ValueError("don't do this")


cdef inline block_toinvarray(Block *self):
	# To inverted sparse array
	cdef Buffer buf
	cdef int idx, elem
	cdef uint32_t n
	cdef uint64_t cur
	if self.state == DENSE:
		buf.sparse = allocsparse(BLOCKSIZE - self.cardinality)
		idx = n = 0
		cur = ~(self.buf.dense[idx])
		elem = iterateunsetbits(self.buf.dense, &cur, &idx)
		while elem != -1:
			buf.sparse[n] = elem
			n += 1
			elem = iterateunsetbits(self.buf.dense, &cur, &idx)
		assert n == BLOCKSIZE - self.cardinality
		self.state = INVERTED
		replacearray(self, buf, n)
	elif self.state == POSITIVE:
		raise ValueError("don't do this")


cdef inline uint16_t *allocsparse(int length) except NULL:
	cdef Buffer buf
	buf.sparse = <uint16_t *>malloc(length * sizeof(uint16_t))
	if buf.sparse is NULL:
		raise MemoryError
	return buf.sparse


cdef inline uint64_t *allocdense() except NULL:
	# NB: initialization up to caller.
	cdef Buffer buf
	buf.ptr = NULL
	cdef int r = posix_memalign(&buf.ptr, 32, BITMAPSIZE)
	if r != 0:
		raise MemoryError
	return buf.dense


cdef inline void replacearray(Block *self, Buffer buf, size_t cap) nogil:
	free(self.buf.ptr)
	self.buf = buf
	self.capacity = cap


cdef inline _extendarray(Block *self, int k):
	"""Extend array allocation with k elements + amortization."""
	cdef int desired, newcapacity, size = self.cardinality
	if self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
	desired = size + k
	if desired < self.capacity:
		return
	newcapacity = 2 * desired if size < 1024 else 5 * desired // 4
	self.buf.ptr = realloc(self.buf.ptr, newcapacity * sizeof(uint16_t))
	if self.buf.ptr is NULL:
		raise MemoryError
	self.capacity = newcapacity


cdef inline _resize(Block *self, int k):
	"""Reduce array capacity to k+4 if currently larger."""
	if k * 2 < self.capacity:
		self.buf.ptr = realloc(self.buf.ptr, (k + 4) * sizeof(uint16_t))
		if self.buf.ptr is NULL:
			raise MemoryError
		self.capacity = k + 4


cdef _resizeconvert(Block *self, int state, int alloc):
	"""Reallocate array of type state and size capacity if neceessary."""
	cdef Buffer buf
	if state == DENSE:
		if self.state != DENSE:
			buf.dense = allocdense()
			replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))
	elif state == POSITIVE:
		if self.state == DENSE:
			buf.sparse = allocsparse(alloc)
			replacearray(self, buf, alloc)
		elif alloc > self.capacity:
			self.buf.ptr = realloc(self.buf.ptr, alloc * sizeof(uint16_t))
			if self.buf.ptr is NULL:
				raise MemoryError
			self.capacity = alloc
	elif state == INVERTED:
		if self.state == DENSE:
			buf.sparse = allocsparse(alloc)
			replacearray(self, buf, alloc)
		elif alloc > self.capacity:
			self.buf.ptr = realloc(self.buf.ptr, alloc * sizeof(uint16_t))
			if self.buf.ptr is NULL:
				raise MemoryError
			self.capacity = alloc
	self.state = state


cdef inline _insert(Block *self, int i, uint16_t elem):
	"""Insert element at index i."""
	cdef int size = self.cardinality
	if self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
	_extendarray(self, 1)
	if i < size:
		memmove(&(self.buf.sparse[i + 1]), &(self.buf.sparse[i]),
				(size - i) * sizeof(uint16_t))
	self.buf.sparse[i] = elem
	self.cardinality += 1 if self.state == POSITIVE else -1


cdef inline void _removeatidx(Block *self, int i) nogil:
	"""Remove i'th element from array."""
	cdef int size = self.cardinality
	if self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
	memmove(&(self.buf.sparse[i]), &(self.buf.sparse[i + 1]),
			(size - i - 1) * sizeof(uint16_t))
	self.cardinality += 1 if self.state == INVERTED else -1


cdef inline size_t _getsize(Block *self) nogil:
	"""Return size in uint16_t elements of a block's array/bitmap.

	(excluding unused capacity)."""
	if self.state == DENSE:
		return BITMAPSIZE // 2
	elif self.state == POSITIVE:
		return self.cardinality
	elif self.state == INVERTED:
		return BLOCKSIZE - self.cardinality
