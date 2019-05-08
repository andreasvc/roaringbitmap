cdef inline bint block_contains(Block *self, uint16_t elem) nogil:
	cdef bint found
	if self.state == DENSE:
		found = TESTBIT(self.buf.dense, elem)
	elif self.state == POSITIVE:
		found = binarysearch(self.buf.sparse,
				0, self.cardinality, elem) >= 0
	else:  # self.state == INVERTED:
		found = binarysearch(self.buf.sparse,
				0, BLOCKSIZE - self.cardinality, elem) < 0
	return found


cdef inline void block_add(Block *self, uint16_t elem) nogil:
	cdef int i
	if self.state == DENSE:
		setbitcard(self.buf.dense, elem, &self.cardinality)
	elif self.state == POSITIVE:
		i = binarysearch(self.buf.sparse, 0, self.cardinality, elem)
		if i < 0:
			insert(self, -i - 1, elem)
	elif self.state == INVERTED:
		i = binarysearch(
				self.buf.sparse, 0, BLOCKSIZE - self.cardinality, elem)
		if i >= 0:
			remove(self, i)


cdef inline void block_discard(Block *self, uint16_t elem) nogil:
	cdef int i
	if self.state == DENSE:
		clearbitcard(self.buf.dense, elem, &self.cardinality)
		block_convert(self)
	elif self.state == POSITIVE:
		i = binarysearch(self.buf.sparse, 0, self.cardinality, elem)
		if i >= 0:
			remove(self, i)
	elif self.state == INVERTED:
		i = binarysearch(
				self.buf.sparse, 0, BLOCKSIZE - self.cardinality, elem)
		if i < 0:
			insert(self, -i - 1, elem)
			block_convert(self)


cdef uint64_t block_pop(Block *self) except BLOCKSIZE:
	"""Remove and return the largest element."""
	cdef int n
	cdef uint64_t cur
	cdef int idx, low
	if self.state == DENSE:
		idx = BITNSLOTS(BLOCKSIZE) - 1
		cur = self.buf.dense[idx]
		n = reviteratesetbits(self.buf.dense, &cur, &idx)
		if n != -1:
			block_discard(self, n)
			return n
	elif self.state == POSITIVE:
		if self.cardinality == 0:
			raise ValueError('pop from empty roaringbitmap')
		self.cardinality -= 1
		return self.buf.sparse[self.cardinality]
	elif self.state == INVERTED:
		if self.cardinality == BLOCKSIZE:
			block_discard(self, BLOCKSIZE - 1)
		for low in reversed(range(self.buf.sparse[
					BLOCKSIZE - self.cardinality - 1] + 1, BLOCKSIZE)):
			block_discard(self, low)
			return low
		if self.cardinality < BLOCKSIZE - 1:
			for n in reversed(range(BLOCKSIZE - self.cardinality - 1)):
				for low in reversed(range(
						self.buf.sparse[n] + 1,
						self.buf.sparse[n + 1])):
					block_discard(self, low)
					return low
		for low in reversed(range(self.buf.sparse[0])):
			block_discard(self, low)
			return low


cdef void block_initrange(
		Block *self, uint16_t start, uint32_t stop, uint32_t step) nogil:
	"""Allocate block and set a range of elements."""
	cdef uint32_t n, m, a, b
	cdef uint64_t mask = 0
	cdef uint64_t ones = ~(<uint64_t>0)
	self.cardinality = (stop - start + step - 1) // step
	if self.cardinality == BLOCKSIZE:
		self.buf.sparse = NULL
		self.capacity = 0
		self.state = INVERTED
	elif self.cardinality < MAXARRAYLENGTH:
		self.buf.sparse = allocsparse(self.cardinality)
		self.capacity = self.cardinality
		self.state = POSITIVE
		n = 0
		m = start
		while m < stop:
			self.buf.sparse[n] = m
			n += 1
			m += step
	elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
		self.buf.sparse = allocsparse(BLOCKSIZE - self.cardinality)
		self.capacity = BLOCKSIZE - self.cardinality
		self.state = INVERTED
		for n in range(0, start):
			self.buf.sparse[n] = n
		n = start
		a = start
		while a < stop:
			for b in range(1, step):
				self.buf.sparse[n] = a + b
				n += 1
			a += step
		for m in range(stop, BLOCKSIZE):
			self.buf.sparse[n] = m
			n += 1
	elif step == 0:
		return
	elif 64 % step == 0:
		self.buf.dense = allocdense()
		self.capacity = BITMAPSIZE // sizeof(uint16_t)
		self.state = DENSE
		n = start % step
		while n < 64:
			SETBIT(&mask, n)
			n += step
		a, b = start // 64, (stop - 1) // 64
		for n in range(a):
			self.buf.dense[n] = 0
		if a == b:
			self.buf.dense[a] = (mask & (ones << (start % 64))
					& (ones >> ((~stop + 1) % 64)))
		else:
			self.buf.dense[a] = mask & (ones << (start % 64))
			for n in range(a + 1, b):
				self.buf.dense[n] = mask
			self.buf.dense[b] = mask & (ones >> ((~stop + 1) % 64))
		for n in range(b + 1, <uint32_t>BITNSLOTS(BLOCKSIZE)):
			self.buf.dense[n] = 0
	else:
		self.buf.dense = allocdense()
		self.capacity = BITMAPSIZE // sizeof(uint16_t)
		self.state = DENSE
		memset(self.buf.dense, 0, BITMAPSIZE)
		n = start
		while n < stop:
			SETBIT(self.buf.dense, n)
			n += step


cdef void block_clamp(
		Block *result, Block *src, uint16_t start, uint32_t stop):
	"""Copy ``src`` to ``result`` but restrict elements to range
	``start <= n < stop``."""
	cdef Buffer buf
	cdef int idx, elem, n, m, a, b
	cdef uint32_t alloc
	cdef uint64_t cur, ones = ~(<uint64_t>0)
	if src.state == DENSE or src.state == INVERTED:
		buf = block_asdense(src)
		if stop - start < MAXARRAYLENGTH:
			idx = BITNSLOTS(BLOCKSIZE) - 1
			cur = buf.dense[idx] & (BITMASK(stop + 1) - 1)
			elem = reviteratesetbits(buf.dense, &cur, &idx)
			stop = min(stop, elem + 1)
			idx = BITSLOT(start)
			cur = buf.dense[idx] & ~(BITMASK(start) - 1)
			elem = iteratesetbits(buf.dense, &cur, &idx)
			start = max(start, elem)
			# FIXME pessimistic allocation; count set bits?
			alloc = min(stop - start, src.cardinality)
			convertalloc(result, POSITIVE, alloc)
			n = 0
			while elem != -1 and elem < <int>stop:
				result.buf.sparse[n] = elem
				n += 1
				elem = iteratesetbits(buf.dense, &cur, &idx)
			result.cardinality = n
			trimcapacity(result, result.cardinality)
		else:  # return bitmap
			convertalloc(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
			a, b = start // 64, (stop - 1) // 64
			result.cardinality = src.cardinality
			for n in range(a):
				result.cardinality -= bit_popcount(buf.dense[n])
				result.buf.dense[n] = 0
			result.cardinality -= bit_popcount(buf.dense[a])
			result.buf.dense[a] = buf.dense[a] & (ones << (start % 64))
			if a == b:
				result.buf.dense[a] &= (ones >> ((-stop) % 64))
			result.cardinality += bit_popcount(result.buf.dense[a])
			if a != b:
				for n in range(a + 1, b):
					result.buf.dense[n] = buf.dense[n]
				result.cardinality -= bit_popcount(buf.dense[b])
				result.buf.dense[b] = (ones >> ((-stop) % 64)) & buf.dense[b]
				result.cardinality += bit_popcount(result.buf.dense[b])
			for n in range(b + 1, BITNSLOTS(BLOCKSIZE)):
				result.cardinality -= bit_popcount(buf.dense[n])
				result.buf.dense[n] = 0
		if buf.ptr != src.buf.ptr:
			aligned_free(buf.ptr)
		block_convert(result)
	elif src.state == POSITIVE:
		n, m = 0, src.cardinality
		result.cardinality = 0
		if start > src.buf.sparse[0]:
			n = binarysearch(src.buf.sparse, 0, src.cardinality, start)
			n = -n - 1 if n < 0 else n
			if <uint32_t>n >= src.cardinality:
				return
		if stop <= src.buf.sparse[n]:
			return
		elif stop <= src.buf.sparse[m - 1]:
			m = binarysearch(src.buf.sparse, n, src.cardinality, stop)
			m = -m - 1 if m < 0 else m
		if n > m:
			return
		alloc = m - n
		convertalloc(result, POSITIVE, alloc)
		memcpy(result.buf.ptr, &(src.buf.sparse[n]), alloc * sizeof(uint16_t))
		result.cardinality = alloc


cdef void block_and(Block *result, Block *self, Block *other) nogil:
	"""Non-inplace intersection; result may be preallocated."""
	cdef uint32_t n, alloc, length = 0
	cdef uint16_t elem
	if self.state == DENSE and other.state == DENSE:
		result.cardinality = bitsetintersectcount(
				self.buf.dense, other.buf.dense)
		if result.cardinality < MAXARRAYLENGTH:
			convertalloc(result, POSITIVE, result.cardinality)
			extractintersection(
					result.buf.sparse, self.buf.dense, other.buf.dense)
		else:
			convertalloc(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
			bitsetintersectnocard(
					result.buf.dense, self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		alloc = other.cardinality
		convertalloc(result, POSITIVE, alloc)
		for n in range(other.cardinality):
			elem = other.buf.sparse[n]
			result.buf.sparse[length] = elem
			length += TESTBIT(self.buf.dense, elem)
		result.cardinality = length
		trimcapacity(result, result.cardinality)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = min(self.cardinality, other.cardinality) + OVERALLOC
		convertalloc(result, POSITIVE, alloc)
		result.cardinality = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				result.buf.sparse)
		trimcapacity(result, result.cardinality)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = 2 * BLOCKSIZE - (self.cardinality + other.cardinality)
		convertalloc(result, INVERTED, alloc)
		length = union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				result.buf.sparse)
		result.cardinality = BLOCKSIZE - length
		trimcapacity(result, length)
		block_convert(result)
	elif self.state == POSITIVE and other.state == INVERTED:
		alloc = self.cardinality
		convertalloc(result, POSITIVE, alloc)
		result.cardinality = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				result.buf.sparse)
		trimcapacity(result, result.cardinality)
	elif self.state == INVERTED and other.state == POSITIVE:
		block_and(result, other, self)
	elif self.state == POSITIVE and other.state == DENSE:
		block_and(result, other, self)
	elif self.state == DENSE and other.state == INVERTED:
		block_iand(block_copy(result, self), other)
	elif self.state == INVERTED and other.state == DENSE:
		block_iand(block_copy(result, other), self)


cdef void block_or(Block *result, Block *self, Block *other) nogil:
	"""Non-inplace union; result may be preallocated."""
	cdef uint32_t alloc, length = 0
	if self.state == DENSE and other.state == DENSE:
		convertalloc(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
		result.cardinality = bitsetunion(result.buf.dense,
				self.buf.dense, other.buf.dense)
		block_convert(result)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = self.cardinality + other.cardinality
		if alloc >= MAXARRAYLENGTH:
			convertalloc(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
			result.cardinality = union2by2bitmap(
					self.buf.sparse, other.buf.sparse,
					self.cardinality, other.cardinality,
					result.buf.dense)
			block_convert(result)
		else:
			convertalloc(result, POSITIVE, alloc)
			result.cardinality = union2by2(
					self.buf.sparse, other.buf.sparse,
					self.cardinality, other.cardinality,
					result.buf.sparse)
			trimcapacity(result, result.cardinality)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = BLOCKSIZE - min(self.cardinality, other.cardinality)
		alloc += OVERALLOC
		convertalloc(result, INVERTED, alloc)
		length = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				result.buf.sparse)
		result.cardinality = BLOCKSIZE - length
		trimcapacity(result, length)
	elif self.state == POSITIVE and other.state == INVERTED:
		convertalloc(result, INVERTED, BLOCKSIZE - other.cardinality)
		length = difference(
				other.buf.sparse, self.buf.sparse,
				BLOCKSIZE - other.cardinality, self.cardinality,
				result.buf.sparse)
		result.cardinality = BLOCKSIZE - length
		trimcapacity(result, length)
	elif self.state == INVERTED and other.state == POSITIVE:
		block_or(result, other, self)
	elif self.state == POSITIVE and other.state == DENSE:
		block_ior(block_copy(result, other), self)
	elif self.state == DENSE and other.state == POSITIVE:
		block_ior(block_copy(result, self), other)
	elif self.state == DENSE and other.state == INVERTED:
		block_ior(block_copy(result, other), self)
	elif self.state == INVERTED and other.state == DENSE:
		block_ior(block_copy(result, self), other)


cdef void block_xor(Block *result, Block *self, Block *other) nogil:
	"""Non-inplace xor; result may be preallocated."""
	cdef int alloc
	cdef size_t n
	if self.state == DENSE and other.state == DENSE:
		convertalloc(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
		result.cardinality = bitsetxor(result.buf.dense,
				self.buf.dense, other.buf.dense)
		block_convert(result)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = self.cardinality + other.cardinality
		convertalloc(result, POSITIVE, alloc)
		result.cardinality = xor2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				result.buf.sparse)
		trimcapacity(result, result.cardinality)
		block_convert(result)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = 2 * BLOCKSIZE - (self.cardinality + other.cardinality)
		convertalloc(result, POSITIVE, alloc)
		result.cardinality = xor2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				result.buf.sparse)
		trimcapacity(result, result.cardinality)
		block_convert(result)
	elif self.state == POSITIVE and other.state == INVERTED:
		convertalloc(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
		result.cardinality = self.cardinality
		for n in range(self.cardinality):
			SETBIT(result.buf.dense, self.buf.sparse[n])
		for n in range(<size_t>(BLOCKSIZE - other.cardinality)):
			togglebitcard(
					result.buf.dense, other.buf.sparse[n], &result.cardinality)
		block_convert(result)
	elif self.state == INVERTED and other.state == POSITIVE:
		block_xor(result, other, self)
	elif self.state == DENSE and other.state == INVERTED:
		block_ixor(block_copy(result, self), other)
	elif self.state == INVERTED and other.state == DENSE:
		block_ixor(block_copy(result, other), self)
	elif self.state == DENSE and other.state == POSITIVE:
		block_ixor(block_copy(result, self), other)
	elif self.state == POSITIVE and other.state == DENSE:
		block_ixor(block_copy(result, other), self)


cdef void block_sub(Block *result, Block *self, Block *other) nogil:
	"""Non-inplace subtract; result may be preallocated."""
	cdef uint32_t n, alloc, length = 0
	cdef uint16_t elem
	if self.state == DENSE and other.state == DENSE:
		convertalloc(result, DENSE, BITMAPSIZE // sizeof(uint16_t))
		result.cardinality = bitsetsubtract(result.buf.dense,
				self.buf.dense, other.buf.dense)
		block_convert(result)
	elif self.state == POSITIVE and other.state == POSITIVE:
		convertalloc(result, POSITIVE, self.cardinality)
		result.cardinality = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				result.buf.sparse)
		trimcapacity(result, result.cardinality)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = 2 * BLOCKSIZE - (self.cardinality + other.cardinality)
		convertalloc(result, POSITIVE, alloc)
		result.cardinality = difference(
				other.buf.sparse, self.buf.sparse,
				BLOCKSIZE - other.cardinality, BLOCKSIZE - self.cardinality,
				result.buf.sparse)
		trimcapacity(result, result.cardinality)
		block_convert(result)
	elif self.state == POSITIVE and other.state == INVERTED:
		convertalloc(result, POSITIVE, self.cardinality + OVERALLOC)
		result.cardinality = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				result.buf.sparse)
		trimcapacity(result, result.cardinality)
	elif self.state == INVERTED and other.state == POSITIVE:
		convertalloc(result, INVERTED, other.cardinality + OVERALLOC)
		length = union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, other.cardinality,
				result.buf.sparse)
		result.cardinality = BLOCKSIZE - length
		trimcapacity(result, length)
		block_convert(result)
	elif self.state == POSITIVE and other.state == DENSE:
		convertalloc(result, POSITIVE, self.cardinality)
		for n in range(self.cardinality):
			elem = self.buf.sparse[n]
			result.buf.sparse[length] = elem
			length += TESTBIT(other.buf.dense, elem) == 0
		result.cardinality = length
		trimcapacity(result, length)
	elif self.state == DENSE and other.state == INVERTED:
		convertalloc(result, POSITIVE, BLOCKSIZE - other.cardinality)
		for n in range(other.cardinality):
			elem = other.buf.sparse[n]
			result.buf.sparse[length] = elem
			length += TESTBIT(self.buf.dense, elem)
		result.cardinality = length
		trimcapacity(result, length)
	elif self.state == INVERTED and other.state == DENSE:
		replacearray(result, block_asdense(self),
				BITMAPSIZE // sizeof(uint16_t))
		result.cardinality = self.cardinality
		result.state = DENSE
		block_isub(result, other)
	elif self.state == DENSE and other.state == POSITIVE:
		block_isub(block_copy(result, self), other)


cdef void block_iand(Block *self, Block *other) nogil:
	cdef Buffer buf
	cdef uint32_t n, alloc, length = 0
	cdef uint16_t elem
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetintersectcount(
				self.buf.dense, other.buf.dense)
		if self.cardinality < MAXARRAYLENGTH:
			buf.sparse = allocsparse(self.cardinality)
			extractintersection(
					buf.sparse, self.buf.dense, other.buf.dense)
			replacearray(self, buf, self.cardinality)
			self.state = POSITIVE
		else:
			bitsetintersectnocard(
					self.buf.dense, self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		buf.sparse = allocsparse(other.cardinality)
		self.cardinality = 0
		for n in range(other.cardinality):
			elem = other.buf.sparse[n]
			buf.sparse[self.cardinality] = elem
			self.cardinality += TESTBIT(self.buf.dense, elem)
		replacearray(self, buf, other.cardinality)
		self.state = POSITIVE
		trimcapacity(self, self.cardinality)
	elif self.state == DENSE and other.state == INVERTED:
		for n in range(BLOCKSIZE - other.cardinality):
			clearbitcard(
					self.buf.dense, other.buf.sparse[n], &self.cardinality)
	elif self.state == POSITIVE and other.state == DENSE:
		for n in range(self.cardinality):
			elem = self.buf.sparse[n]
			self.buf.sparse[length] = elem
			length += TESTBIT(other.buf.dense, elem)
		self.cardinality = length
		trimcapacity(self, length)
	elif self.state == POSITIVE and other.state == POSITIVE:
		self.cardinality = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				self.buf.sparse)
		trimcapacity(self, self.cardinality)
	elif self.state == INVERTED and other.state == DENSE:
		buf.dense = allocdense()
		memset(buf.ptr, 255, BITMAPSIZE)
		for n in range(BLOCKSIZE - self.cardinality):
			CLEARBIT(buf.dense, self.buf.sparse[n])
		replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))
		self.state = DENSE
		self.cardinality = bitsetintersect(
				self.buf.dense, self.buf.dense, other.buf.dense)
	elif self.state == POSITIVE and other.state == INVERTED:
		length = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				self.buf.sparse)
		self.cardinality = length
		trimcapacity(self, length)
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
		trimcapacity(self, length)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = 2 * BLOCKSIZE - (self.cardinality + other.cardinality)
		buf.sparse = allocsparse(alloc)
		length = union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				buf.sparse)
		replacearray(self, buf, alloc)
		self.cardinality = BLOCKSIZE - length
		trimcapacity(self, length)
	block_convert(self)


cdef void block_ior(Block *self, Block *other) nogil:
	cdef Buffer buf
	cdef uint32_t n, alloc, length = 0
	cdef uint16_t elem
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetunion(
				self.buf.dense, self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			setbitcard(self.buf.dense, other.buf.sparse[n], &self.cardinality)
	elif self.state == POSITIVE and other.state == DENSE:
		buf.dense = allocdense()
		memcpy(buf.dense, other.buf.dense, BITMAPSIZE)
		length = other.cardinality
		for n in range(self.cardinality):
			setbitcard(buf.dense, self.buf.sparse[n], &length)
		replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))
		self.state = DENSE
		self.cardinality = length
	elif self.state == DENSE and other.state == INVERTED:
		alloc = BLOCKSIZE - other.cardinality
		buf.sparse = allocsparse(alloc)
		memcpy(buf.sparse, other.buf.sparse,
				(BLOCKSIZE - other.cardinality) * sizeof(uint16_t))
		for n in range(BLOCKSIZE - other.cardinality):
			elem = other.buf.sparse[n]
			buf.sparse[length] = elem
			length += TESTBIT(self.buf.dense, elem) == 0
		replacearray(self, buf, alloc)
		self.cardinality = BLOCKSIZE - length
		self.state = INVERTED
		trimcapacity(self, length)
	elif self.state == INVERTED and other.state == DENSE:
		buf.sparse = allocsparse(self.cardinality)
		for n in range(BLOCKSIZE - self.cardinality):
			elem = self.buf.sparse[n]
			buf.sparse[length] = elem
			length += TESTBIT(other.buf.dense, elem) == 0
		replacearray(self, buf, self.cardinality)
		self.cardinality = BLOCKSIZE - length
		trimcapacity(self, length)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = self.cardinality + other.cardinality
		if alloc >= MAXARRAYLENGTH:
			buf.dense = allocdense()
			self.cardinality = union2by2bitmap(
					self.buf.sparse, other.buf.sparse,
					self.cardinality, other.cardinality,
					buf.dense)
			replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))
			self.state = DENSE
		else:
			buf.sparse = allocsparse(alloc)
			self.cardinality = union2by2(
					self.buf.sparse, other.buf.sparse,
					self.cardinality, other.cardinality,
					buf.sparse)
			replacearray(self, buf, alloc)
			trimcapacity(self, self.cardinality)
	elif self.state == POSITIVE and other.state == INVERTED:
		buf.sparse = allocsparse(BLOCKSIZE - other.cardinality)
		length = difference(
				other.buf.sparse, self.buf.sparse,
				BLOCKSIZE - other.cardinality, self.cardinality,
				buf.sparse)
		self.buf.sparse = buf.sparse
		self.state = INVERTED
		self.cardinality = BLOCKSIZE - length
		trimcapacity(self, length)
	elif self.state == INVERTED and other.state == POSITIVE:
		length = difference(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, other.cardinality,
				self.buf.sparse)
		self.cardinality = BLOCKSIZE - length
		trimcapacity(self, length)
	elif self.state == INVERTED and other.state == INVERTED:
		length = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				self.buf.sparse)
		self.cardinality = BLOCKSIZE - length
		trimcapacity(self, length)
	block_convert(self)


cdef void block_ixor(Block *self, Block *other) nogil:
	cdef Buffer buf
	cdef uint32_t n, length = 0, alloc
	if ((self.state == POSITIVE and other.state == DENSE)
			or (self.state == POSITIVE and other.state == INVERTED)
			or (self.state == INVERTED and other.state == DENSE)
			or (self.state == INVERTED and other.state == POSITIVE)):
		block_todense(self)
	# fall through
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetxor(
				self.buf.dense, self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			togglebitcard(
					self.buf.dense, other.buf.sparse[n], &self.cardinality)
	elif self.state == DENSE and other.state == INVERTED:
		buf.dense = allocdense()
		memset(buf.dense, 255, BITMAPSIZE)
		for n in range(BLOCKSIZE - other.cardinality):
			CLEARBIT(buf.dense, other.buf.sparse[n])
		self.cardinality = bitsetxor(
				self.buf.dense, self.buf.dense, buf.dense)
		aligned_free(buf.ptr)
	elif self.state == POSITIVE and other.state == POSITIVE:
		alloc = self.cardinality + other.cardinality
		buf.sparse = allocsparse(alloc)
		length = xor2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				buf.sparse)
		replacearray(self, buf, alloc)
		trimcapacity(self, length)
		self.cardinality = length
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = 2 * BLOCKSIZE - (self.cardinality + other.cardinality)
		buf.sparse = allocsparse(alloc)
		self.cardinality = xor2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				buf.sparse)
		self.state = POSITIVE
		replacearray(self, buf, alloc)
		trimcapacity(self, self.cardinality)
	block_convert(self)


cdef void block_isub(Block *self, Block *other) nogil:
	cdef Buffer buf
	cdef uint32_t n, alloc, length = 0,
	cdef uint16_t elem
	if self.state == INVERTED and other.state == DENSE:
		block_todense(self)
		# fall through, treat as DENSE - DENSE.
	if self.state == DENSE and other.state == DENSE:
		self.cardinality = bitsetsubtract(
				self.buf.dense, self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			clearbitcard(
					self.buf.dense, other.buf.sparse[n], &self.cardinality)
	elif self.state == DENSE and other.state == INVERTED:
		alloc = BLOCKSIZE - other.cardinality
		buf.sparse = allocsparse(alloc)
		for n in range(other.cardinality):
			elem = other.buf.sparse[n]
			buf.sparse[length] = elem
			length += TESTBIT(self.buf.dense, elem)
		replacearray(self, buf, alloc)
		self.cardinality = length
		self.state = POSITIVE
		trimcapacity(self, length)
	elif self.state == POSITIVE and other.state == DENSE:
		for n in range(self.cardinality):
			elem = self.buf.sparse[n]
			self.buf.sparse[length] = elem
			length += TESTBIT(other.buf.dense, elem) == 0
		self.cardinality = length
		trimcapacity(self, length)
	elif self.state == POSITIVE and other.state == POSITIVE:
		self.cardinality = difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				self.buf.sparse)
		trimcapacity(self, self.cardinality)
	elif self.state == INVERTED and other.state == INVERTED:
		alloc = 2 * BLOCKSIZE - (self.cardinality + other.cardinality)
		buf.sparse = allocsparse(alloc)
		self.cardinality = difference(
				other.buf.sparse, self.buf.sparse,
				BLOCKSIZE - other.cardinality, BLOCKSIZE - self.cardinality,
				buf.sparse)
		replacearray(self, buf, alloc)
		self.state = POSITIVE
		trimcapacity(self, self.cardinality)
	elif self.state == INVERTED and other.state == POSITIVE:
		alloc = 2 * BLOCKSIZE - (self.cardinality + other.cardinality)
		buf.sparse = allocsparse(alloc)
		length = union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, other.cardinality,
				buf.sparse)
		replacearray(self, buf, alloc)
		self.cardinality = BLOCKSIZE - length
		trimcapacity(self, length)
	elif self.state == POSITIVE and other.state == INVERTED:
		self.cardinality = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				self.buf.sparse)
		trimcapacity(self, self.cardinality)
	block_convert(self)


cdef bint block_issubset(Block *self, Block *other) nogil:
	cdef int m = 0
	cdef size_t n
	if self.cardinality > other.cardinality:
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
			if m >= <int>(BLOCKSIZE - other.cardinality):
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
		for n in range(<size_t>(BLOCKSIZE - other.cardinality)):
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


cdef bint block_isdisjoint(Block *self, Block *other) nogil:
	# could return counterexample, or -1 if True
	cdef int m = 0
	cdef uint32_t n
	if self.cardinality == 0 or other.cardinality == 0:
		return True
	elif self.cardinality + other.cardinality > BLOCKSIZE:
		return False
	elif self.state == DENSE and other.state == DENSE:
		return bitdisjoint(self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			if TESTBIT(self.buf.dense, other.buf.sparse[n]):
				return False
	elif self.state == POSITIVE and other.state == POSITIVE:
		for n in range(self.cardinality):
			m = binarysearch(other.buf.sparse,
					m, other.cardinality, self.buf.sparse[n])
			if m >= 0:
				return False
			m = -m - 1
			if m >= <int>other.cardinality:
				break
	elif self.state == POSITIVE and other.state == INVERTED:
		for n in range(self.cardinality):
			m = binarysearch(other.buf.sparse,
					m, BLOCKSIZE - other.cardinality, self.buf.sparse[n])
			if m < 0:
				return False
	elif (self.state == POSITIVE and other.state == DENSE
			or self.state == INVERTED and other.state == POSITIVE):
		return block_isdisjoint(other, self)
	elif (self.state == INVERTED and other.state in (DENSE, INVERTED)
			or self.state == DENSE and other.state == INVERTED):
		return False
	return True


cdef uint32_t block_andlen(Block *self, Block *other) nogil:
	"""Cardinality of intersection."""
	cdef uint32_t n, result = 0
	if self.state == DENSE and other.state == DENSE:
		return bitsetintersectcount(self.buf.dense, other.buf.dense)
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			result += TESTBIT(self.buf.dense, other.buf.sparse[n])
	elif self.state == DENSE and other.state == INVERTED:
		result = self.cardinality
		for n in range(BLOCKSIZE - other.cardinality):
			result -= TESTBIT(self.buf.dense, other.buf.sparse[n])
	elif self.state == POSITIVE and other.state == INVERTED:
		return difference(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, BLOCKSIZE - other.cardinality,
				NULL)
	elif self.state == POSITIVE and other.state == POSITIVE:
		return intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality,
				NULL)
	elif self.state == INVERTED and other.state == INVERTED:
		return BLOCKSIZE - union2by2(
				self.buf.sparse, other.buf.sparse,
				BLOCKSIZE - self.cardinality, BLOCKSIZE - other.cardinality,
				NULL)
	elif self.state == POSITIVE and other.state == DENSE:
		return block_andlen(other, self)
	elif self.state == INVERTED and other.state == DENSE:
		return block_andlen(other, self)
	elif self.state == INVERTED and other.state == POSITIVE:
		return block_andlen(other, self)
	return result


cdef uint32_t block_orlen(Block *self, Block *other) nogil:
	"""Cardinality of union."""
	return <size_t>self.cardinality + other.cardinality - block_andlen(
			self, other)


cdef void block_andorlen(Block *self, Block *other,
		uint32_t *intersection_result, uint32_t *union_result) nogil:
	"""Cardinality of both intersection and union."""
	cdef uint32_t n
	if self.state == DENSE and other.state == DENSE:
		bitsetintersectunioncount(self.buf.dense, other.buf.dense,
				self.cardinality, other.cardinality,
				intersection_result, union_result)
	elif self.state == POSITIVE and other.state == POSITIVE:
		intersection_result[0] = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality, NULL)
		union_result[0] = (<size_t>self.cardinality + other.cardinality
				- intersection_result[0])
	elif self.state == INVERTED and other.state == INVERTED:
		union_result[0] = intersect2by2(
				self.buf.sparse, other.buf.sparse,
				self.cardinality, other.cardinality, NULL)
		union_result[0] = BLOCKSIZE - union_result[0]
		intersection_result[0] = BLOCKSIZE - (<size_t>self.cardinality
				+ other.cardinality - union_result[0])
	elif self.state == DENSE and other.state == POSITIVE:
		for n in range(other.cardinality):
			intersection_result[0] += TESTBIT(
					self.buf.dense, other.buf.sparse[n])
		union_result[0] = (<size_t>self.cardinality + other.cardinality
				- intersection_result[0])
	elif self.state == DENSE and other.state == INVERTED:
		intersection_result[0] = self.cardinality
		for n in range(BLOCKSIZE - other.cardinality):
			intersection_result[0] -= TESTBIT(
					self.buf.dense, other.buf.sparse[n])
		union_result[0] = BLOCKSIZE - (<size_t>self.cardinality
				+ other.cardinality - intersection_result[0])
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


cdef int block_rank(Block *self, uint16_t x) nogil:
	"""Number of 1-bits in this bitmap ``<= x``."""
	cdef int result = 0, leftover
	cdef size_t size, n
	if self.state == DENSE:
		leftover = (x + 1) & (BITSIZE - 1)
		for n in range(<size_t>BITSLOT(x + 1)):
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
		if size == 0:
			return x + 1
		result = binarysearch(self.buf.sparse, 0, size, x)
		if result >= 0:
			return x - result
		else:
			return x + result + 2


cdef int block_select(Block *self, uint16_t i) except -1:
	"""Find smallest x s.t. rank(x) >= i."""
	cdef int n, size, w = 0
	if i >= self.cardinality:
		raise IndexError('select: index %d out of range 0..%d.' % (
				i, self.cardinality))
	elif self.state == DENSE:
		for n in range(BLOCKSIZE // BITSIZE):
			w = bit_popcount(self.buf.dense[n])
			if w > i:
				return BITSIZE * n + select64(self.buf.dense[n], i)
			i -= w
	elif self.state == POSITIVE:
		return self.buf.sparse[i]
	elif self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
		if size == 0:
			return i
		elif size == 1:
			return i + (self.buf.sparse[0] <= i)
		if self.buf.sparse[0] > i:
			return i
		# find the pair of non-members between which the i'th member lies
		# FIXME: use custom binary search
		for n in range(1, size):
			# subtract n because this inverted block stores n non-members
			if self.buf.sparse[n] - n > i:
				# result lies between value at n-1 and n
				# add rest of i not covered by values up to n-1
				w = self.buf.sparse[n - 1]
				return w + (i - (w - (n - 1))) + 1
		return self.buf.sparse[size - 1] + i + 1


cdef Block *block_copy(Block *dest, Block *src) nogil:
	"""Copy src to dest; dest may be preallocated."""
	cdef size_t size = getsize(src)
	convertalloc(dest, src.state, size)
	dest.cardinality = src.cardinality
	memcpy(dest.buf.ptr, src.buf.ptr, size * sizeof(uint16_t))
	return dest


cdef str block_repr(uint16_t key, Block *self, verbose):
	verbosestr = ''
	if verbose and self.state in (POSITIVE, INVERTED):
		verbosestr = ', data=[%s]' % ', '.join([
				str(self.buf.sparse[n]) for n in range(getsize(self))])
	if self.state == DENSE:
		return 'D(key=%d, bits=%d, cap=%d)' % (key, self.cardinality, BLOCKSIZE)
	elif self.state == POSITIVE:
		return 'P(key=%d, ints=%d, cap=%d%s)' % (
				key, self.cardinality, self.capacity, verbosestr)
	elif self.state == INVERTED:
		return 'I(key=%d, ints=%d, cap=%d%s)' % (
				key, BLOCKSIZE - self.cardinality, self.capacity, verbosestr)
	else:
		raise ValueError('repr: illegal block state=%d, key=%d, crd=%d, cap=%d'
				% (self.state, key, self.cardinality, self.capacity))


cdef inline void block_convert(Block *self) nogil:
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
			printf("%s", <char *>"convert: positive array too large.")
			abort()
	elif self.state == INVERTED:
		if MAXARRAYLENGTH <= self.cardinality <= BLOCKSIZE - MAXARRAYLENGTH:
			block_todense(self)
		elif self.cardinality < MAXARRAYLENGTH:
			printf("%s", <char *>"convert: inverted array too large.")
			abort()


cdef inline Buffer block_asdense(Block *self) nogil:
	# Return dense copy of array in block
	cdef uint32_t n
	cdef Buffer buf
	if self.state == DENSE:
		return self.buf
	buf.dense = allocdense()
	if self.state == POSITIVE:
		memset(buf.dense, 0, BITMAPSIZE)
		for n in range(self.cardinality):
			SETBIT(buf.dense, self.buf.sparse[n])
	elif self.state == INVERTED:
		memset(buf.dense, 255, BITMAPSIZE)
		for n in range(BLOCKSIZE - self.cardinality):
			CLEARBIT(buf.dense, self.buf.sparse[n])
	return buf


cdef inline void block_todense(Block *self) nogil:
	# To dense bitvector; modifies self.
	cdef Buffer buf = block_asdense(self)
	self.state = DENSE
	replacearray(self, buf, BITMAPSIZE // sizeof(uint16_t))


cdef inline void block_toposarray(Block *self) nogil:
	# To positive sparse array
	cdef Buffer buf
	cdef uint32_t length
	if self.state == DENSE:
		buf.sparse = allocsparse(self.cardinality)
		length = extractsetbits(buf.sparse, self.buf.dense)
		if length != self.cardinality:
			abort()
		self.state = POSITIVE
		replacearray(self, buf, length)
	elif self.state == INVERTED:
		printf("%s", <char *>"cannot convert positive to inverted array.")
		abort()


cdef inline void block_toinvarray(Block *self) nogil:
	# To inverted sparse array
	cdef Buffer buf
	if self.state == DENSE:
		buf.sparse = allocsparse(BLOCKSIZE - self.cardinality)
		length = extractunsetbits(buf.sparse, self.buf.dense)
		if length != BLOCKSIZE - self.cardinality:
			abort()
		self.state = INVERTED
		replacearray(self, buf, length)
	elif self.state == POSITIVE:
		printf("%s", <char *>"cannot convert inverted to positive array.")
		abort()


cdef inline uint16_t *allocsparse(int length) nogil:
	# Variable length integer vector
	cdef Buffer buf
	buf.ptr = aligned_malloc((length or 1) * sizeof(uint16_t), sizeof(void *))
	if buf.ptr is NULL:
		abort()
	return buf.sparse


cdef inline uint64_t *allocdense() nogil:
	# Fixed-size, aligned bitmap.
	# NB: initialization up to caller.
	cdef Buffer buf
	buf.ptr = aligned_malloc(BITMAPSIZE, 32)
	if buf.ptr is NULL:
		abort()
	return buf.dense


cdef inline void replacearray(Block *self, Buffer buf, size_t cap) nogil:
	aligned_free(self.buf.ptr)
	self.buf.ptr = buf.ptr
	self.capacity = cap


cdef inline void extendarray(Block *self, int k) nogil:
	"""Extend array allocation with k elements + amortization."""
	cdef int desired, newcapacity, size = self.cardinality
	cdef void *tmp
	if self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
	desired = size + k
	if desired < self.capacity:
		return
	newcapacity = 2 * desired if size < 1024 else 5 * desired // 4
	tmp = realloc(self.buf.ptr, newcapacity * sizeof(uint16_t))
	if tmp is NULL:
		abort()
	self.buf.ptr = tmp
	self.capacity = newcapacity


cdef inline void trimcapacity(Block *self, int k) nogil:
	"""Reduce array capacity to k+4 if currently larger."""
	cdef void *tmp
	if k * 2 < self.capacity:
		tmp = realloc(self.buf.ptr, (k + 4) * sizeof(uint16_t))
		if tmp is NULL:
			abort()
		self.buf.ptr = tmp
		self.capacity = k + 4


cdef void convertalloc(Block *self, int state, int alloc) nogil:
	"""(Re)allocate array of type `state` and `size` capacity as needed.

	self may be unallocated, but then it must be initialized with zeroes
	so as not to contain invalid non-NULL pointers."""
	cdef void *tmp
	if state == DENSE:
		if self.state != DENSE or self.buf.ptr is NULL:
			aligned_free(self.buf.ptr)
			self.buf.dense = allocdense()
			self.capacity = BITMAPSIZE // sizeof(uint16_t)
	elif state == POSITIVE:
		if self.state == DENSE:
			aligned_free(self.buf.ptr)
			self.buf.sparse = allocsparse(alloc)
			self.capacity = alloc
		elif alloc > self.capacity or self.buf.ptr is NULL:
			tmp = realloc(self.buf.ptr, alloc * sizeof(uint16_t))
			if tmp is NULL:
				abort()
			self.buf.ptr = tmp
			self.capacity = alloc
	else:  # state == INVERTED:
		if self.state == DENSE:
			aligned_free(self.buf.ptr)
			self.buf.sparse = allocsparse(alloc)
			self.capacity = alloc
		elif alloc > self.capacity or self.buf.ptr is NULL:
			tmp = realloc(self.buf.ptr, alloc * sizeof(uint16_t))
			if tmp is NULL:
				abort()
			self.buf.ptr = tmp
			self.capacity = alloc
	self.state = state


cdef inline void insert(Block *self, int i, uint16_t elem) nogil:
	"""Insert element at index i."""
	cdef int size = self.cardinality
	if self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
	extendarray(self, 1)
	if i < size:
		memmove(&(self.buf.sparse[i + 1]), &(self.buf.sparse[i]),
				(size - i) * sizeof(uint16_t))
	self.buf.sparse[i] = elem
	self.cardinality += 1 if self.state == POSITIVE else -1


cdef inline void remove(Block *self, int i) nogil:
	"""Remove i'th element from array."""
	cdef int size = self.cardinality
	if self.state == INVERTED:
		size = BLOCKSIZE - self.cardinality
	memmove(&(self.buf.sparse[i]), &(self.buf.sparse[i + 1]),
			(size - i - 1) * sizeof(uint16_t))
	self.cardinality += 1 if self.state == INVERTED else -1


cdef inline size_t getsize(Block *self) nogil:
	"""Return size in uint16_t elements of a block's array/bitmap.

	(excluding unused capacity)."""
	if self.state == DENSE:
		return BITMAPSIZE // 2
	elif self.state == POSITIVE:
		return self.cardinality
	elif self.state == INVERTED:
		return BLOCKSIZE - self.cardinality
