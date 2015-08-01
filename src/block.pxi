cdef inline Block new_Block(uint16_t key):
	cdef Block block = Block.__new__(Block)
	block.key = key
	block.state = POSITIVE
	block.cardinality = 0
	return block


@cython.freelist(4)
@cython.final
cdef class Block(object):
	"""A set of 2**16 integers, stored as bitmap or array."""
	# Whether this block contains a bitvector (DENSE); otherwise sparse array;
	# The array can contain elements corresponding to 0-bits (INVERTED)
	# or 1-bits (POSITIVE).
	cdef uint8_t state  # either DENSE, INVERTED, or POSITIVE
	cdef uint16_t key  # the high bits of elements in this block
	cdef uint32_t cardinality  # the number of elements
	cdef array.array buf  # data: sparse array or fixed-size bitvector

	def __cinit__(self):
		pass

	def __init__(self):
		pass  # should only be used by pickle

	cdef copy(self):
		cdef Block answer = new_Block(self.key)
		answer.state = self.state
		answer.cardinality = self.cardinality
		answer.buf = array.copy(self.buf)
		return answer

	cdef bint contains(self, uint16_t elem):
		cdef bint found
		if self.state == DENSE:
			found = TESTBIT(self.buf.data.as_ulongs, elem) != 0
		elif self.state == INVERTED:
			found = binarysearch(self.buf.data.as_ushorts,
					0, BLOCKSIZE - self.cardinality, elem) < 0
		else:  # self.state == POSITIVE:
			found = binarysearch(self.buf.data.as_ushorts,
					0, self.cardinality, elem) >= 0
		return found

	cdef add(self, uint16_t elem):
		cdef int i
		if self.state == DENSE:
			if not TESTBIT(self.buf.data.as_ulongs, elem):
				SETBIT(self.buf.data.as_ulongs, elem)
				self.cardinality += 1
				self.resize()
		elif self.state == INVERTED:
			i = binarysearch(self.buf.data.as_ushorts,
					0, BLOCKSIZE - self.cardinality, elem)
			if i >= 0:
				del self.buf[i]
				self.cardinality += 1
		elif self.state == POSITIVE:
			i = binarysearch(self.buf.data.as_ushorts,
					0, self.cardinality, elem)
			if i < 0:
				self.buf.insert(-i - 1, elem)
				self.cardinality += 1
				self.resize()

	cdef discard(self, uint16_t elem):
		cdef int i
		if self.state == DENSE:
			if TESTBIT(self.buf.data.as_ulongs, elem):
				CLEARBIT(self.buf.data.as_ulongs, elem)
				self.cardinality -= 1
				self.resize()
		elif self.state == INVERTED:
			i = binarysearch(self.buf.data.as_ushorts,
					0, BLOCKSIZE - self.cardinality, elem)
			if i < 0:
				self.buf.insert(-i - 1, elem)
				self.cardinality -= 1
				self.resize()
		elif self.state == POSITIVE:
			i = binarysearch(self.buf.data.as_ushorts,
					0, self.cardinality, elem)
			if i >= 0:
				del self.buf[i]
				self.cardinality -= 1

	cdef _and(self, Block other):
		cdef Block result
		cdef int n
		if self.state == DENSE:
			if other.state == POSITIVE:
				result = new_Block(self.key)
				result.buf = array.clone(ushortarray, other.cardinality, False)
				result.state = POSITIVE
				result.cardinality = 0
				for n in range(other.cardinality):
					if TESTBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n]):
						result.buf.data.as_ushorts[self.cardinality
								] = other.buf.data.as_ushorts[n]
						result.cardinality += 1
				array.resize(result.buf, result.cardinality)
				return result
		result = self.copy()
		result &= other
		return result

	cdef iand(self, Block other):
		cdef array.array tmp
		cdef int length, n
		if self.state == DENSE:
			if other.state == POSITIVE:
				tmp = array.clone(ushortarray, other.cardinality, False)
				self.cardinality = 0
				for n in range(other.cardinality):
					if TESTBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n]):
						tmp.data.as_ushorts[self.cardinality
								] = other.buf.data.as_ushorts[n]
						self.cardinality += 1
				self.buf = tmp
				array.resize(self.buf, self.cardinality)
				self.state = POSITIVE
			elif other.state == DENSE:
				self.cardinality = bitsetintersectinplace(
						self.buf.data.as_ulongs,
						other.buf.data.as_ulongs)
			elif other.state == INVERTED:
				for n in range(BLOCKSIZE - other.cardinality):
					if TESTBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n]):
						CLEARBIT(self.buf.data.as_ulongs,
								other.buf.data.as_ushorts[n])
						self.cardinality -= 1
		elif other.state == DENSE:
			tmp = array.clone(ushortarray, BITMAPSIZE // sizeof(short), False)
			if self.state == INVERTED:
				memset(tmp.data.as_chars, 255, BITMAPSIZE)
				for n in range(BLOCKSIZE - self.cardinality):
					CLEARBIT(tmp.data.as_ulongs, self.buf.data.as_ushorts[n])
			else:  # self.state == POSITIVE:
				memset(tmp.data.as_chars, 0, BITMAPSIZE)
				for n in range(self.cardinality):
					SETBIT(tmp.data.as_ulongs, self.buf.data.as_ushorts[n])
			self.buf = tmp
			self.cardinality = bitsetintersectinplace(
					self.buf.data.as_ulongs, other.buf.data.as_ulongs)
			self.state = DENSE
		elif self.state == POSITIVE and other.state == POSITIVE:
			length = intersect2by2(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					self.cardinality, other.cardinality,
					self.buf.data.as_ushorts)
			array.resize(self.buf, length)
			self.cardinality = length
		elif self.state == INVERTED and other.state == INVERTED:
			tmp = array.clone(ushortarray,
					BLOCKSIZE - (self.cardinality + other.cardinality),
					False)
			length = union2by2(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					BLOCKSIZE - self.cardinality,
					BLOCKSIZE - other.cardinality,
					tmp.data.as_ushorts)
			self.buf = tmp
			array.resize(self.buf, length)
			self.cardinality = BLOCKSIZE - length
		elif self.state == INVERTED and other.state == POSITIVE:
			tmp = array.clone(ushortarray,
					max(BLOCKSIZE - self.cardinality, other.cardinality),
					False)
			length = difference(
					other.buf.data.as_ushorts,
					self.buf.data.as_ushorts,
					other.cardinality,
					BLOCKSIZE - self.cardinality,
					tmp.data.as_ushorts)
			self.buf = tmp
			array.resize(self.buf, length)
			self.state = POSITIVE
			self.cardinality = length
		elif self.state == POSITIVE and other.state == INVERTED:
			length = difference(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					self.cardinality, BLOCKSIZE - other.cardinality,
					self.buf.data.as_ushorts)
			array.resize(self.buf, length)
			self.cardinality = length
		self.resize()

	cdef ior(self, Block other):
		cdef array.array tmp
		cdef int length, n
		if self.state == POSITIVE:
			if other.state == POSITIVE:
				tmp = array.clone(ushortarray,
						self.cardinality + other.cardinality,
						False)
				self.cardinality = union2by2(self.buf.data.as_ushorts,
						other.buf.data.as_ushorts,
						self.cardinality, other.cardinality,
						tmp.data.as_ushorts)
				self.buf = tmp
				array.resize(self.buf, self.cardinality)
			elif other.state == DENSE:
				tmp = array.clone(ushortarray, BITMAPSIZE // sizeof(short),
						False)
				memcpy(tmp.data.as_chars, other.buf.data.as_chars,
						BITMAPSIZE)
				length = other.cardinality
				for n in range(self.cardinality):
					if not TESTBIT(tmp.data.as_ulongs,
							self.buf.data.as_ushorts[n]):
						SETBIT(tmp.data.as_ulongs, self.buf.data.as_ushorts[n])
						length += 1
				self.buf = tmp
				self.state = DENSE
				self.cardinality = length
			elif other.state == INVERTED:
				tmp = array.clone(ushortarray, BLOCKSIZE - self.cardinality,
						False)
				length = difference(
						other.buf.data.as_ushorts,
						self.buf.data.as_ushorts,
						BLOCKSIZE - other.cardinality,
						self.cardinality,
						tmp.data.as_ushorts)
				self.buf = tmp
				array.resize(self.buf, length)
				self.state = INVERTED
				self.cardinality = BLOCKSIZE - length
		elif self.state == DENSE:
			if other.state == POSITIVE:
				for n in range(other.cardinality):
					if not TESTBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n]):
						SETBIT(self.buf.data.as_ulongs,
								other.buf.data.as_ushorts[n])
						self.cardinality += 1
			elif other.state == DENSE:
				self.cardinality = bitsetunioninplace(
						self.buf.data.as_ulongs,
						other.buf.data.as_ulongs)
			elif other.state == INVERTED:
				tmp = array.copy(other.buf)
				length = 0
				for n in range(BLOCKSIZE - other.cardinality):
					if not TESTBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n]):
						tmp.data.as_ushorts[length] = (
								other.buf.data.as_ushorts[n])
						length += 1
				self.buf = tmp
				array.resize(self.buf, length)
				self.cardinality = BLOCKSIZE - length
				self.state = INVERTED
		elif self.state == INVERTED:
			if other.state == POSITIVE:
				length = difference(
						self.buf.data.as_ushorts,
						other.buf.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						other.cardinality,
						self.buf.data.as_ushorts)
				array.resize(self.buf, length)
				self.cardinality = BLOCKSIZE - length
			elif other.state == DENSE:
				tmp = array.clone(ushortarray, self.cardinality, False)
				length = 0
				for n in range(BLOCKSIZE - self.cardinality):
					if not TESTBIT(other.buf.data.as_ulongs,
							self.buf.data.as_ushorts[n]):
						tmp.data.as_ushorts[length] = (
							self.buf.data.as_ushorts[n])
						length += 1
				self.buf = tmp
				array.resize(self.buf, length)
				self.cardinality = BLOCKSIZE - length
			elif other.state == INVERTED:
				length = intersect2by2(self.buf.data.as_ushorts,
						other.buf.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						BLOCKSIZE - other.cardinality,
						self.buf.data.as_ushorts)
				array.resize(self.buf, length)
				self.cardinality = BLOCKSIZE - length
		self.resize()

	cdef isub(self, Block other):
		cdef Block tmp2
		cdef int length, n
		if self.state == DENSE and other.state == DENSE:
			self.cardinality = bitsetsubtractinplace(
					self.buf.data.as_ulongs,
					other.buf.data.as_ulongs)
		elif self.state == DENSE and other.state == INVERTED:
			tmp2 = other.copy()
			tmp2.todense()
			self.isub(tmp2)
			del tmp2
			return
		elif self.state == DENSE and other.state == POSITIVE:
			for n in range(other.cardinality):
				if TESTBIT(self.buf.data.as_ulongs,
						other.buf.data.as_ushorts[n]):
					CLEARBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n])
					self.cardinality -= 1
		elif self.state == INVERTED and other.state == DENSE:
			self.todense()
			self.isub(other)
			return
		elif self.state == POSITIVE and other.state == DENSE:
			length = 0
			for n in range(self.cardinality):
				if not TESTBIT(other.buf.data.as_ulongs,
						self.buf.data.as_ushorts[n]):
					self.buf.data.as_ushorts[length] = (
							self.buf.data.as_ushorts[n])
					length += 1
			array.resize(self.buf, length)
			self.cardinality = length
		elif self.state == POSITIVE and other.state == POSITIVE:
			self.cardinality = difference(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					self.cardinality, other.cardinality,
					self.buf.data.as_ushorts)
			array.resize(self.buf, self.cardinality)
		elif self.state == INVERTED and other.state == INVERTED:
			tmp = array.clone(ushortarray,
					BLOCKSIZE - (self.cardinality + other.cardinality),
					False)
			length = union2by2(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					BLOCKSIZE - self.cardinality,
					BLOCKSIZE - other.cardinality,
					tmp.data.as_ushorts)
			self.buf = tmp
			array.resize(self.buf, length)
			self.cardinality = BLOCKSIZE - length
		elif self.state == INVERTED and other.state == POSITIVE:
			length = intersect2by2(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					BLOCKSIZE - self.cardinality, other.cardinality,
					self.buf.data.as_ushorts)
			array.resize(self.buf, length)
			self.cardinality = BLOCKSIZE - length
		elif self.state == POSITIVE and other.state == INVERTED:
			self.cardinality = intersect2by2(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					self.cardinality, other.cardinality,
					self.buf.data.as_ushorts)
			array.resize(self.buf, self.cardinality)
		self.resize()

	cdef ixor(self, Block other):
		cdef array.array tmp
		cdef Block tmp2
		cdef int length, n
		if self.state == DENSE and other.state == DENSE:
			self.cardinality = bitsetxorinplace(
					self.buf.data.as_ulongs,
					other.buf.data.as_ulongs)
		elif self.state == DENSE and other.state == INVERTED:
			tmp2 = other.copy()
			tmp2.todense()
			self.ixor(tmp2)
			del tmp2
			return
		elif self.state == DENSE and other.state == POSITIVE:
			for n in range(other.cardinality):
				if TESTBIT(self.buf.data.as_ulongs,
						other.buf.data.as_ushorts[n]):
					CLEARBIT(self.buf.data.as_ulongs,
						other.buf.data.as_ushorts[n])
					self.cardinality -= 1
		elif self.state == INVERTED and other.state == DENSE:
			self.todense()
			self.ixor(other)
			return
		elif self.state == POSITIVE and other.state == DENSE:
			self.todense()
			self.ixor(other)
			return
		elif self.state == POSITIVE and other.state == POSITIVE:
			tmp = array.clone(ushortarray,
					self.cardinality + other.cardinality,
					False)
			length = xor2by2(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					self.cardinality,
					other.cardinality,
					tmp.data.as_ushorts)
			self.buf = tmp
			array.resize(self.buf, length)
			self.cardinality = length
		elif self.state == INVERTED and other.state == INVERTED:
			tmp = array.clone(ushortarray,
					BLOCKSIZE - (self.cardinality + other.cardinality),
					False)
			length = xor2by2(
					self.buf.data.as_ushorts,
					other.buf.data.as_ushorts,
					BLOCKSIZE - self.cardinality,
					BLOCKSIZE - other.cardinality,
					tmp.data.as_ushorts)
			self.buf = tmp
			array.resize(self.buf, length)
			self.cardinality = BLOCKSIZE - length
		elif self.state == INVERTED and other.state == POSITIVE:
			self.todense()
			self.ixor(other)
			return
		elif self.state == POSITIVE and other.state == INVERTED:
			self.todense()
			self.ixor(other)
			return
		self.resize()

	cdef issubset(self, Block other):
		cdef int n, m = 0
		if self.key != other.key or self.cardinality > other.cardinality:
			return False
		elif self.state == DENSE:
			if other.state == DENSE:
				return bitsubset(
					self.buf.data.as_ulongs,
					other.buf.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
			elif other.state == INVERTED:
				for n in range(other.cardinality):
					if TESTBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n]):
						return False
			elif other.state == POSITIVE:
				return False
		elif self.state == INVERTED:
			if other.state == DENSE:
				return False
			if other.state == INVERTED:
				# check if negative other array elements are subset of
				# negative self array element
				for n in range(BLOCKSIZE - other.cardinality):
					m = binarysearch(self.buf.data.as_ushorts,
							m, BLOCKSIZE - self.cardinality,
							other.buf.data.as_ushorts[n])
					if m < 0:
						return False
			elif other.state == POSITIVE:
				return False
		elif self.state == POSITIVE:
			if other.state == DENSE:
				for n in range(self.cardinality):
					if not TESTBIT(other.buf.data.as_ulongs,
							self.buf.data.as_ushorts[n]):
						return False
			elif other.state == INVERTED:
				# check that no self array elements exists in
				# negative other array elements
				for n in range(self.cardinality):
					m = binarysearch(other.buf.data.as_ushorts,
							m, BLOCKSIZE - other.cardinality,
							self.buf.data.as_ushorts[n])
					if m >= 0:
						return False
					m = -m - 1
					if m >= BLOCKSIZE - other.cardinality:
						break
			elif other.state == POSITIVE:
				# check if self array elements are subset
				# of other array elements
				for n in range(self.cardinality):
					m = binarysearch(other.buf.data.as_ushorts,
							m, other.cardinality,
							self.buf.data.as_ushorts[n])
					if m < 0:
						return False
		return True

	cdef isdisjoint(self, Block other):
		# could return counterexample, or -1 if True
		cdef int n, m = 0
		if (self.key != other.key
				or self.cardinality + other.cardinality > BLOCKSIZE):
			return False
		elif self.state == POSITIVE:
			if other.state == POSITIVE:
				for n in range(self.cardinality):
					m = binarysearch(other.buf.data.as_ushorts,
							m, other.cardinality,
							self.buf.data.as_ushorts[n])
					if m >= 0:
						return False
					m = -m - 1
					if m >= other.cardinality:
						break
			elif other.state == DENSE:
				for n in range(self.cardinality):
					if TESTBIT(other.buf.data.as_ulongs,
							self.buf.data.as_ushorts[n]):
						return False
			elif other.state == INVERTED:
				for n in range(self.cardinality):
					m = binarysearch(other.buf.data.as_ushorts,
							m, BLOCKSIZE - other.cardinality,
							self.buf.data.as_ushorts[n])
					if m < 0:
						return False
		elif self.state == DENSE:
			if other.state == POSITIVE:
				for n in range(other.cardinality):
					if TESTBIT(self.buf.data.as_ulongs,
							other.buf.data.as_ushorts[n]):
						return False
			elif other.state == DENSE:
				for n in range(BITNSLOTS(BLOCKSIZE)):
					if (self.buf.data.as_ulongs[n]
							& other.buf.data.as_ulongs[n]):
						return False
			else:  # other.state == INVERTED:
				return False
		else:  # self.state == INVERTED:
			if other.state == POSITIVE:
				for n in range(other.cardinality):
					m = binarysearch(self.buf.data.as_ushorts,
							m, BLOCKSIZE - self.cardinality,
							other.buf.data.as_ushorts[n])
					if m < 0:
						return False
			else:  # other.state in (DENSE, INVERTED)
				return False
		return True

	cdef int rank(self, uint16_t x):
		"""Number of 1-bits in this bitmap ``<= x``."""
		cdef int answer = 0
		cdef int leftover
		if self.state == POSITIVE:
			answer = binarysearch(self.buf.data.as_ushorts,
					0, self.cardinality, x)
			if answer >= 0:
				return answer + 1
			else:
				return -answer - 1
		elif self.state == DENSE:
			leftover = (x + 1) & (BITSIZE - 1)
			for n in range(BITSLOT(x + 1)):
				answer += bit_popcount(self.buf.data.as_ulongs[n])
			if leftover != 0:
				answer += bit_popcount(self.buf.data.as_ulongs[BITSLOT(x + 1)]
						<< (BITSIZE - leftover))
			return answer
		elif self.state == INVERTED:
			answer = binarysearch(self.buf.data.as_ushorts, 0,
					self.cardinality, x)
			if answer >= 0:
				return x - answer - 1
			else:
				return x + answer - 1

	cdef int select(self, int i):
		"""Find smallest x s.t. rank(x) >= i."""
		cdef int n, w = 0
		if i >= self.cardinality:
			raise IndexError('Index out of range.')
		elif self.state == POSITIVE:
			return self.buf.data.as_ushorts[i]
		elif self.state == DENSE:
			for n in range(BITNSLOTS(BLOCKSIZE)):
				w = bit_popcount(self.buf.data.as_ulongs[n])
				if w > i:
					return BITSIZE * n + select64(
							self.buf.data.as_ulongs[n], i)
				i -= w
		elif self.state == INVERTED:
			for n in range(BLOCKSIZE - self.cardinality):
				if self.buf.data.as_ulongs[n] - n >= i:
					return self.buf.data.as_ushorts[n] - (
							i - n)
			return self.buf.data.as_ushorts[len(self.buf) - 1] + (
					i - len(self.buf))

	cdef flip(self):
		"""In-place complement of this block."""
		if self.state == DENSE:
			for n in range(BITNSLOTS(BLOCKSIZE)):
				self.buf.data.as_ulongs[n] = ~self.buf.data.as_ulongs[n]
		elif self.state == POSITIVE:
			self.state = INVERTED
		elif self.state == INVERTED:
			self.state = POSITIVE
		# FIXME: need notion of maximium element
		self.cardinality = BLOCKSIZE - self.cardinality

	cdef resize(self):
		"""Convert between dense, sparse, inverted sparse as needed."""
		if self.state == DENSE:
			if self.cardinality < MAXARRAYLENGTH:
				self.toposarray()
			elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
				self.toinvarray()
		elif self.state == INVERTED:
			if (MAXARRAYLENGTH < self.cardinality
					< BLOCKSIZE - MAXARRAYLENGTH):
				self.todense()
			elif self.cardinality < MAXARRAYLENGTH:
				# shouldn't happen?
				raise ValueError
		elif self.state == POSITIVE:
			if MAXARRAYLENGTH < self.cardinality < BLOCKSIZE - MAXARRAYLENGTH:
				# To dense bitvector
				self.todense()
			elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
				# shouldn't happen?
				raise ValueError

	def __sizeof__(self):
		"""Return memory usage in bytes."""
		return (sizeof(self.state) + sizeof(self.key)
				+ sizeof(self.cardinality) + sys.getsizeof(self.buf))

	cdef todense(self):
		# To dense bitvector
		cdef int n
		tmp = array.clone(ushortarray, BITMAPSIZE // sizeof(short), False)
		if self.state == INVERTED:
			memset(tmp.data.as_chars, 255, BITMAPSIZE)
			for n in range(BLOCKSIZE - self.cardinality):
				CLEARBIT(tmp.data.as_ulongs, self.buf.data.as_ushorts[n])
		else:  # self.state == POSITIVE:
			memset(tmp.data.as_chars, 0, BITMAPSIZE)
			for n in range(self.cardinality):
				SETBIT(tmp.data.as_ulongs, self.buf.data.as_ushorts[n])
		self.state = DENSE
		self.buf = tmp

	cdef toposarray(self):
		# To positive sparse array
		cdef array.array tmp
		cdef int n, idx, elem
		cdef uint64_t cur
		if self.state == DENSE:
			tmp = array.clone(ushortarray, self.cardinality, False)
			idx = n = 0
			cur = self.buf.data.as_ulongs[idx]
			elem = iteratesetbits(self.buf.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE), &cur, &idx)
			while elem != -1:
				tmp.data.as_ushorts[n] = elem
				n += 1
				elem = iteratesetbits(self.buf.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE), &cur, &idx)
			assert n == self.cardinality
			self.state = POSITIVE
			self.buf = tmp
		elif self.state == INVERTED:
			raise ValueError("don't do this")

	cdef toinvarray(self):
		# To inverted sparse array
		cdef array.array tmp
		cdef int n, idx, elem
		cdef uint64_t cur
		if self.state == DENSE:
			tmp = array.clone(ushortarray, BLOCKSIZE - self.cardinality,
					False)
			idx = n = 0
			cur = ~self.buf.data.as_ulongs[idx]
			elem = iterateunsetbits(self.buf.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE), &cur, &idx)
			while elem != -1:
				tmp.data.as_ushorts[n] = elem
				n += 1
				elem = iterateunsetbits(self.buf.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE), &cur, &idx)
			assert n == BLOCKSIZE - self.cardinality
			self.state = INVERTED
			self.buf = tmp
		elif self.state == POSITIVE:
			raise ValueError("don't do this")

	def __iter__(self):
		cdef uint32_t high = self.key << 16
		cdef uint64_t cur
		cdef int n, idx, low
		if self.cardinality == BLOCKSIZE:
			for low in range(BLOCKSIZE):
				yield high | low
		elif self.state == DENSE:
			idx = 0
			cur = self.buf.data.as_ulongs[idx]
			n = iteratesetbits(self.buf.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE), &cur, &idx)
			while n != -1:
				low = n
				yield high | low
				n = iteratesetbits(self.buf.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE), &cur, &idx)
		elif self.state == INVERTED:
			for low in range(self.buf.data.as_ushorts[0]):
				yield high | low
			if self.cardinality < BLOCKSIZE - 1:
				for n in range(BLOCKSIZE - self.cardinality - 1):
					for low in range(
							self.buf.data.as_ushorts[n] + 1,
							self.buf.data.as_ushorts[n + 1]):
						yield high | low
				for low in range(self.buf.data.as_ushorts[
						BLOCKSIZE - self.cardinality - 1] + 1, BLOCKSIZE):
					yield high | low
		elif self.state == POSITIVE:
			for n in range(self.cardinality):
				low = self.buf.data.as_ushorts[n]
				yield high | low

	def __reversed__(self):
		cdef uint32_t high = self.key << 16
		cdef uint64_t cur
		cdef int n, idx, low
		if self.cardinality == BLOCKSIZE:
			for low in reversed(range(BLOCKSIZE)):
				yield high | low
		elif self.state == POSITIVE:
			for n in reversed(range(self.cardinality)):
				low = self.buf.data.as_ushorts[n]
				yield high | low
		elif self.state == DENSE:
			idx = BITNSLOTS(BLOCKSIZE) - 1
			cur = self.buf.data.as_ulongs[idx]
			n = reviteratesetbits(self.buf.data.as_ulongs, &cur, &idx)
			while n != -1:
				low = n
				yield high | low
				n = reviteratesetbits(self.buf.data.as_ulongs, &cur, &idx)
		elif self.state == INVERTED:
			for low in reversed(range(self.buf.data.as_ushorts[
						BLOCKSIZE - self.cardinality - 1] + 1, BLOCKSIZE)):
				yield high | low
			if self.cardinality < BLOCKSIZE - 1:
				for n in reversed(range(BLOCKSIZE - self.cardinality - 1)):
					for low in reversed(range(
							self.buf.data.as_ushorts[n] + 1,
							self.buf.data.as_ushorts[n + 1])):
						yield high | low
			for low in reversed(range(self.buf.data.as_ushorts[0])):
				yield high | low

	def pop(self):
		"""Remove and return the largest element."""
		if self.cardinality == 0:
			raise ValueError
		if self.state == POSITIVE:
			self.cardinality -= 1
			return self.buf.pop()
		elem = next(reversed(self))
		self.discard(elem)
		return elem

	def __repr__(self):
		if self.state == DENSE:
			return 'bitmap(%r)' % self.buf
		elif self.state == INVERTED:
			return 'invertedarray(%r)' % self.buf
		elif self.state == POSITIVE:
			return 'array(%r)' % self.buf

	cdef allocarray(self):
		self.buf = array.clone(ushortarray, 0, False)

	def __reduce__(self):
		return (Block, (), dict(
				key=self.key,
				state=self.state,
				cardinality=self.cardinality,
				buf=self.buf))

	def __setstate__(self, state):
		self.key = state['key']
		self.state = state['state']
		self.cardinality = state['cardinality']
		self.buf = state['buf']


cdef inline int min(int a, int b):
	return a if a <= b else b


cdef inline int max(int a, int b):
	return a if a >= b else b
