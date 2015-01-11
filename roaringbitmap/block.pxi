# The number of shorts to store a bitmap of 2**16 bits
DEF BITMAPSIZE = BLOCKSIZE // 16


cdef inline Block new_Block(uint16_t key):
	cdef Block block = Block.__new__(Block)
	block.key = key
	block.dense = block.inverted = False
	block.cardinality = 0
	block.buffer = array.clone(ushortarray, 0, False)
	return block


@cython.freelist(4)
@cython.final
cdef class Block(object):
	"""A set of 2**16 integers, stored as bitmap, positive array,
	or inverted array."""
	# Whether this block contains a bitvector; otherwise sparse array
	cdef bint dense
	# If dense==False, whether array elements represent 0-bits or 1-bits
	cdef bint inverted
	cdef uint16_t key  # the high bits of elements in this block
	cdef uint16_t cardinality  # the number of elements
	cdef array.array buffer  # bitvector, positive sparse, or inverted sparse

	def __cinit__(self):
		pass

	def __init__(self):
		pass  # should only be used by pickle

	cdef copy(self):
		cdef Block answer = new_Block(self.key)
		answer.dense = self.dense
		answer.inverted = self.inverted
		answer.cardinality = self.cardinality
		answer.buffer = array.copy(self.buffer)
		return answer

	cdef contains(self, uint16_t elem):
		cdef bint found
		if self.dense:
			return TESTBIT(self.buffer.data.as_ulongs, elem)
		else:
			if self.inverted:
				found = binarysearch(self.buffer.data.as_ushorts,
						0, BLOCKSIZE - self.cardinality, elem) >= 0
				return not found
			found = binarysearch(self.buffer.data.as_ushorts,
					0, self.cardinality, elem) >= 0
			return found

	cdef add(self, uint16_t elem):
		cdef int i
		if self.dense:
			if not TESTBIT(self.buffer.data.as_ulongs, elem):
				SETBIT(self.buffer.data.as_ulongs, elem)
				self.cardinality += 1
				self.resize()
		else:
			i = binarysearch(self.buffer.data.as_ushorts,
					0, self.cardinality, elem)
			if self.inverted and i >= 0:
				del self.buffer[i]
				self.cardinality += 1
			elif i < 0:
				self.buffer.insert(-i - 1, elem)
				self.cardinality += 1
				self.resize()

	cdef discard(self, uint16_t elem):
		cdef int i
		if self.dense:
			if TESTBIT(self.buffer.data.as_ulongs, elem):
				CLEARBIT(self.buffer.data.as_ulongs, elem)
				self.cardinality -= 1
				self.resize()
		elif self.inverted:
			i = binarysearch(self.buffer.data.as_ushorts,
					0, BLOCKSIZE - self.cardinality, elem)
			if i < 0:
				self.buffer.insert(-i - 1, elem)
				self.cardinality -= 1
				self.resize()
		else:  # positive array
			i = binarysearch(self.buffer.data.as_ushorts,
					0, self.cardinality, elem)
			if i >= 0:
				del self.buffer[i]
				self.cardinality -= 1

	cdef iand(self, Block other):
		cdef array.array tmp
		cdef int length, n
		if self.dense:
			if other.dense:
				self.cardinality = bitsetintersectinplace(
						self.buffer.data.as_ulongs,
						other.buffer.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE))
			elif other.inverted:
				for n in range(BLOCKSIZE - other.cardinality):
					if TESTBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n]):
						CLEARBIT(self.buffer.data.as_ulongs,
								other.buffer.data.as_ushorts[n])
						self.cardinality -= 1
			else:  # not other.inverted
				tmp = array.clone(ushortarray, 0, False)
				self.cardinality = 0
				for n in range(other.cardinality):
					if TESTBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n]):
						tmp.data.as_ushorts[self.cardinality
								] = other.buffer.data.as_ushorts[n]
						self.cardinality += 1
				array.resize(tmp, self.cardinality)
				self.dense = False
				self.inverted = False
				self.buffer = tmp
		elif other.dense:
			if self.inverted:
				tmp = array.clone(ushortarray, BITMAPSIZE, False)
				memset(tmp.data.as_uchars, 255, BLOCKSIZE // sizeof(char))
				for n in range(BLOCKSIZE - self.cardinality):
					CLEARBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
			else:  # not other.inverted
				tmp = array.clone(ushortarray, BITMAPSIZE, True)
				for n in range(self.cardinality):
					SETBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
			self.cardinality = bitsetintersectinplace(
					tmp.data.as_ulongs,
					other.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
			self.dense = True
			self.inverted = False
			self.buffer = tmp
		# not self.dense and not other.dense
		elif not self.inverted and not other.inverted:
			self.cardinality = intersect2by2(
					self.buffer.data.as_ushorts,
					other.buffer.data.as_ushorts,
					self.cardinality, other.cardinality,
					self.buffer.data.as_ushorts)
			array.resize(self.buffer, self.cardinality)
		elif self.inverted and other.inverted:
			tmp = array.clone(ushortarray,
					BLOCKSIZE - (self.cardinality + other.cardinality),
					False)
			length = union2by2(
					self.buffer.data.as_ushorts,
					other.buffer.data.as_ushorts,
					BLOCKSIZE - self.cardinality,
					BLOCKSIZE - other.cardinality,
					tmp.data.as_ushorts)
			array.resize(tmp, length)
			self.cardinality = BLOCKSIZE - length
			self.buffer = tmp
		elif self.inverted and not other.inverted:
			tmp = array.clone(ushortarray,
					max(BLOCKSIZE - self.cardinality, other.cardinality),
					False)
			length = difference(
					other.buffer.data.as_ushorts,
					self.buffer.data.as_ushorts,
					other.cardinality,
					BLOCKSIZE - self.cardinality,
					tmp.data.as_ushorts)
			array.resize(tmp, length)
			self.inverted = False
			self.cardinality = length
			self.buffer = tmp
		elif not self.inverted and other.inverted:
			length = difference(
					self.buffer.data.as_ushorts,
					other.buffer.data.as_ushorts,
					self.cardinality, BLOCKSIZE - other.cardinality,
					self.buffer.data.as_ushorts)
			array.resize(self.buffer, length)
			self.cardinality = length
		self.resize()

	cdef ior(self, Block other):
		cdef array.array tmp
		cdef int length, n
		if self.dense and other.dense:
			self.cardinality = bitsetunioninplace(
					self.buffer.data.as_ulongs,
					other.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
		elif self.dense and not other.dense:
			if other.inverted:
				tmp = array.copy(other.buffer)
				length = 0
				for n in range(BLOCKSIZE - other.cardinality):
					if not TESTBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n]):
						tmp.data.as_ushorts[length] = (
								other.buffer.data.as_ushorts[n])
						length += 1
				array.resize(tmp, length)
				self.cardinality = BLOCKSIZE - length
				self.dense = False
				self.inverted = True
				self.buffer = tmp
			else:  # other has positive array
				for n in range(other.cardinality):
					if not TESTBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n]):
						SETBIT(self.buffer.data.as_ulongs,
								other.buffer.data.as_ushorts[n])
						self.cardinality += 1
		elif not self.dense and other.dense:
			if self.inverted:
				tmp = array.clone(ushortarray, self.cardinality, False)
				length = 0
				for n in range(BLOCKSIZE - self.cardinality):
					if not TESTBIT(other.buffer.data.as_ulongs,
							self.buffer.data.as_ushorts[n]):
						tmp.data.as_ushorts[length] = (
							self.buffer.data.as_ushorts[n])
						length += 1
				array.resize(tmp, length)
				self.cardinality = BLOCKSIZE - length
				self.buffer = tmp
			else:  # self has positive array
				tmp = array.copy(other.buffer)
				length = other.cardinality
				array.resize(tmp, length + self.cardinality)
				for n in range(self.cardinality):
					if not TESTBIT(tmp.data.as_ulongs,
							self.buffer.data.as_ushorts[n]):
						length += 1
					SETBIT(tmp.data.as_ulongs, self.buffer.data.as_ushorts[n])
				self.dense = True
				self.inverted = False
				self.cardinality = length
				self.buffer = tmp
		elif not self.dense and not other.dense:
			if not self.inverted and not other.inverted:
				tmp = array.clone(ushortarray,
						self.cardinality + other.cardinality,
						False)
				self.cardinality = union2by2(self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						self.cardinality, other.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, self.cardinality)
				self.buffer = tmp
			elif self.inverted and other.inverted:
				length = intersect2by2(self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						BLOCKSIZE - other.cardinality,
						self.buffer.data.as_ushorts)
				array.resize(self.buffer, length)
				self.cardinality = BLOCKSIZE - length
			elif self.inverted and not other.inverted:
				length = difference(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						other.cardinality,
						self.buffer.data.as_ushorts)
				array.resize(self.buffer, length)
				self.cardinality = BLOCKSIZE - length
			elif not self.inverted and other.inverted:
				tmp = array.clone(ushortarray, BLOCKSIZE - self.cardinality,
						False)
				length = difference(
						other.buffer.data.as_ushorts,
						self.buffer.data.as_ushorts,
						BLOCKSIZE - other.cardinality,
						self.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, length)
				self.inverted = True
				self.cardinality = BLOCKSIZE - length
				self.buffer = tmp
		self.resize()

	cdef isub(self, Block other):
		cdef Block tmp2
		cdef int length, n
		if self.dense and other.dense:
			self.cardinality = bitsetsubtractinplace(
					self.buffer.data.as_ulongs,
					other.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
		elif self.dense and not other.dense:
			if other.inverted:
				tmp2 = other.copy()
				tmp2.todense()
				self.isub(tmp2)
				del tmp2
				return
			else:  # other has positive array
				for n in range(other.cardinality):
					if TESTBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n]):
						CLEARBIT(self.buffer.data.as_ulongs,
								other.buffer.data.as_ushorts[n])
						self.cardinality -= 1
		elif not self.dense and other.dense:
			if self.inverted:
				self.todense()
				self.isub(other)
				return
			else:  # self has positive array
				length = 0
				for n in range(self.cardinality):
					if not TESTBIT(other.buffer.data.as_ulongs,
							self.buffer.data.as_ushorts[n]):
						self.buffer.data.as_ushorts[length] = (
								self.buffer.data.as_ushorts[n])
						length += 1
				array.resize(self.buffer, length)
				self.cardinality = length
		elif not self.dense and not other.dense:
			if not self.inverted and not other.inverted:
				self.cardinality = difference(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						self.cardinality, other.cardinality,
						self.buffer.data.as_ushorts)
				array.resize(self.buffer, self.cardinality)
			elif self.inverted and other.inverted:
				tmp = array.clone(ushortarray,
						BLOCKSIZE - (self.cardinality + other.cardinality),
						False)
				length = union2by2(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						BLOCKSIZE - other.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, length)
				self.cardinality = BLOCKSIZE - length
				self.buffer = tmp
			elif self.inverted and not other.inverted:
				length = intersect2by2(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						BLOCKSIZE - self.cardinality, other.cardinality,
						self.buffer.data.as_ushorts)
				array.resize(self.buffer, length)
				self.cardinality = BLOCKSIZE - length
			elif not self.inverted and other.inverted:
				self.cardinality = intersect2by2(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						self.cardinality, other.cardinality,
						self.buffer.data.as_ushorts)
				array.resize(self.buffer, self.cardinality)
		self.resize()

	cdef ixor(self, Block other):
		cdef array.array tmp
		cdef Block tmp2
		cdef int length, n
		if self.dense and other.dense:
			self.cardinality = bitsetxorinplace(
					self.buffer.data.as_ulongs,
					other.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE))
		elif self.dense and not other.dense:
			if other.inverted:
				tmp2 = other.copy()
				tmp2.todense()
				self.ixor(tmp2)
				del tmp2
				return
			else:  # other has positive array
				for n in range(other.cardinality):
					if TESTBIT(self.buffer.data.as_ulongs,
							other.buffer.data.as_ushorts[n]):
						CLEARBIT(self.buffer.data.as_ulongs,
							self.buffer.data.as_ushorts[n])
						self.cardinality -= 1
		elif not self.dense and other.dense:
			if self.inverted:
				self.todense()
				self.ixor(other)
				return
			else:  # self has positive array
				self.todense()
				self.ixor(other)
				return
		elif not self.dense and not other.dense:
			if not self.inverted and not other.inverted:
				tmp = array.clone(ushortarray,
						self.cardinality + other.cardinality,
						False)
				length = xor2by2(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						self.cardinality,
						other.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, length)
				self.cardinality = length
				self.buffer = tmp
			elif self.inverted and other.inverted:
				tmp = array.clone(ushortarray,
						BLOCKSIZE - (self.cardinality + other.cardinality),
						False)
				length = xor2by2(
						self.buffer.data.as_ushorts,
						other.buffer.data.as_ushorts,
						BLOCKSIZE - self.cardinality,
						BLOCKSIZE - other.cardinality,
						tmp.data.as_ushorts)
				array.resize(tmp, length)
				self.cardinality = BLOCKSIZE - length
				self.buffer = tmp
			elif self.inverted and not other.inverted:
				self.todense()
				self.ixor(other)
				return
			elif not self.inverted and other.inverted:
				self.todense()
				self.ixor(other)
				return
		self.resize()

	cdef flip(self):
		"""In-place complement of this block."""
		if self.dense:
			for n in range(BITNSLOTS(BLOCKSIZE)):
				self.buffer.data.as_ulongs[n] = ~self.buffer.data.as_ulongs[n]
		else:
			self.inverted = not self.inverted
		# FIXME: need notion of maximium element
		self.cardinality = BLOCKSIZE - self.cardinality

	cdef resize(self):
		"""Convert between dense, sparse, inverted sparse as needed."""
		if self.dense:
			if self.cardinality < MAXARRAYLENGTH:
				self.toposarray()
			elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
				self.toinvarray()
		elif self.inverted:  # not dense
			if (MAXARRAYLENGTH < self.cardinality
					< BLOCKSIZE - MAXARRAYLENGTH):
				self.todense()
			elif self.cardinality < MAXARRAYLENGTH:
				# shouldn't happen?
				raise ValueError
		else:  # not dense, not self.inverted
			if MAXARRAYLENGTH < self.cardinality < BLOCKSIZE - MAXARRAYLENGTH:
				# To dense bitvector
				self.todense()
			elif self.cardinality > BLOCKSIZE - MAXARRAYLENGTH:
				# shouldn't happen?
				raise ValueError

	cdef todense(self):
		# To dense bitvector
		cdef array.array tmp
		cdef int n
		if self.inverted:
			tmp = array.clone(ushortarray, BITMAPSIZE, False)
			memset(tmp.data.as_uchars, 255, BLOCKSIZE // sizeof(char))
			for n in range(BLOCKSIZE - self.cardinality):
				CLEARBIT(tmp.data.as_ulongs,
						self.buffer.data.as_ushorts[n])
		else:
			tmp = array.clone(ushortarray, BITMAPSIZE, True)
			for n in range(self.cardinality):
				SETBIT(tmp.data.as_ulongs, self.buffer.data.as_ushorts[n])
		self.dense = True
		self.inverted = False
		self.buffer = tmp

	cdef toposarray(self):
		# To positive sparse array
		cdef array.array tmp
		cdef int n, elem, idx
		cdef uint64_t cur
		if self.dense:
			tmp = array.clone(ushortarray, self.cardinality, False)

			cur = self.buffer.data.as_ulongs[0]
			idx = n = 0
			elem = iteratesetbits(self.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE), &cur, &idx)
			while elem != -1:
				tmp.data.as_ushorts[n] = elem
				n += 1
				elem = iteratesetbits(self.buffer.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE), &cur, &idx)
			assert n == self.cardinality
			self.dense = False
			self.inverted = False
			self.buffer = tmp
		else:
			raise ValueError("don't do this")

	cdef toinvarray(self):
		# To inverted sparse array
		cdef array.array tmp
		cdef int n, elem, idx
		cdef uint64_t cur
		if self.dense:
			tmp = array.clone(ushortarray, BLOCKSIZE - self.cardinality,
					False)
			cur = self.buffer.data.as_ulongs[0]
			idx = n = 0
			elem = iterateunsetbits(self.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE), &cur, &idx)
			while elem != -1:
				tmp.data.as_ushorts[n] = elem
				n += 1
				elem = iterateunsetbits(self.buffer.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE), &cur, &idx)
			assert n == BLOCKSIZE - self.cardinality
			self.dense = False
			self.inverted = True
			self.buffer = tmp
		else:
			raise ValueError("don't do this")

	def iterblock(self):
		cdef uint32_t high = self.key << 16
		cdef uint32_t low = 0
		cdef uint64_t cur
		cdef int n, idx
		if self.dense:
			cur = self.buffer.data.as_ulongs[0]
			idx = 0
			n = iteratesetbits(self.buffer.data.as_ulongs,
					BITNSLOTS(BLOCKSIZE), &cur, &idx)
			while n != -1:
				low = n
				yield high | low
				n = iteratesetbits(self.buffer.data.as_ulongs,
						BITNSLOTS(BLOCKSIZE), &cur, &idx)
		elif self.inverted:
			if self.cardinality < BLOCKSIZE:
				for low in range(0, self.buffer.data.as_ushorts[0]):
					yield high | low
				if self.cardinality < BLOCKSIZE - 1:
					for n in range(BLOCKSIZE - self.cardinality - 1):
						for low in range(
								self.buffer.data.as_ushorts[n],
								self.buffer.data.as_ushorts[n + 1]):
							yield high | low
					for low in range(self.buffer.data.as_ushorts[
							BLOCKSIZE - self.cardinality - 1], BLOCKSIZE):
						yield high | low
		else:
			for n in range(self.cardinality):
				low = self.buffer.data.as_ushorts[n]
				yield high | low

	def pop(self):
		"""Remove and return the smallest element."""
		if self.cardinality == 0:
			raise ValueError
		elem = next(iter(self))
		self.discard(elem)
		return elem

	def __repr__(self):
		if self.dense:
			return 'bitmap(%r)' % self.buffer
		elif self.inverted:
			return 'invertedarray(%r)' % self.buffer
		else:
			return 'array(%r)' % self.buffer

	def __reduce__(self):
		return (Block, None, (self.key, self.dense, self.inverted,
				self.cardinality, self.buffer))

	def __setstate__(self, key, dense, inverted, cardinality, buffer):
		self.key = key
		self.dense = dense
		self.inverted = inverted
		self.cardinality = cardinality
		self.buffer = buffer


cdef inline int min(int a, int b):
	return a if a <= b else b


cdef inline int max(int a, int b):
	return a if a >= b else b
