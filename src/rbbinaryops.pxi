cdef inline richcmp(x, y, int op):
	"""Considers comparisons to RoaringBitmaps and sets;
	other types raise a TypeError."""
	cdef RoaringBitmap ob1, ob2
	cdef size_t n
	if x is None or y is None:
		if op == 2 or op == 3:
			return op == 3
		raise TypeError
	if (not isinstance(x, (RoaringBitmap, set))
			or not isinstance(y, (RoaringBitmap, set))):
		raise TypeError
	if op == 2:  # ==
		ob1, ob2 = ensurerb(x), ensurerb(y)
		if ob1.size != ob2.size:
			return False
		if memcmp(ob1.keys, ob2.keys, ob1.size * sizeof(uint16_t)) != 0:
			return False
		for n in range(ob1.size):
			if ob1.data[n].cardinality != ob2.data[n].cardinality:
				return False
		for n in range(ob1.size):
			if memcmp(
					<void *>(ob1.offset + ob1.data[n].buf.offset),
					<void *>(ob2.offset + ob2.data[n].buf.offset),
					_getsize(&(ob1.data[n])) * sizeof(uint16_t)) != 0:
				return False
		return True
	elif op == 3:  # !=
		return not richcmp(x, y, 2)
	elif op == 1:  # <=
		return ensurerb(x).issubset(y)
	elif op == 5:  # >=
		return ensurerb(x).issuperset(y)
	elif op == 0:  # <
		return len(x) < len(y) and ensurerb(x).issubset(y)
	elif op == 4:  # >
		return len(x) > len(y) and ensurerb(x).issuperset(y)
	return NotImplemented


cdef inline RoaringBitmap rb_iand(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef uint32_t pos1 = 0, pos2 = 0, res = 0
	cdef uint16_t *keys = NULL
	cdef Block *data = NULL
	cdef Block b2
	if pos1 < ob1.size and pos2 < ob2.size:
		ob1.capacity = min(ob1.size, ob2.size)
		ob1._tmpalloc(ob1.capacity, &keys, &data)
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				free(ob1.data[pos1].buf.ptr)
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_iand(&(ob1.data[pos1]), ob2._getblk(pos2, &b2))
				if ob1.data[pos1].cardinality > 0:
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
				else:
					free(ob1.data[pos1].buf.ptr)
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
		ob1._replacearrays(keys, data, res)
	return ob1


cdef inline RoaringBitmap rb_isub(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef uint32_t pos1 = 0, pos2 = 0, res = 0
	cdef uint16_t *keys = NULL
	cdef Block *data = NULL
	cdef Block b2
	if pos1 < ob1.size and pos2 < ob2.size:
		ob1.capacity = ob1.size
		ob1._tmpalloc(ob1.capacity, &keys, &data)
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				keys[res] = ob1.keys[pos1]
				data[res] = ob1.data[pos1]
				res += 1
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_isub(&(ob1.data[pos1]), ob2._getblk(pos2, &b2))
				if ob1.data[pos1].cardinality > 0:
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
				else:
					free(ob1.data[pos1].buf.ptr)
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
		if pos2 == ob2.size:
			for pos1 in range(pos1, ob1.size):
				keys[res] = ob1.keys[pos1]
				data[res] = ob1.data[pos1]
				res += 1
		ob1._replacearrays(keys, data, res)
	return ob1


cdef inline RoaringBitmap rb_ior(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef uint32_t pos1 = 0, pos2 = 0, res = 0
	cdef uint16_t *keys = NULL
	cdef Block *data = NULL
	cdef Block b2
	if ob2.size == 0:
		return ob1
	ob1.capacity = ob1.size + ob2.size
	ob1._tmpalloc(ob1.capacity, &keys, &data)
	if pos1 < ob1.size and pos2 < ob2.size:
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				keys[res] = ob1.keys[pos1]
				data[res] = ob1.data[pos1]
				res += 1
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				keys[res] = ob2.keys[pos2]
				block_copy(&(data[res]), ob2._getblk(pos2, &b2))
				res += 1
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_ior(&(ob1.data[pos1]), ob2._getblk(pos2, &b2))
				keys[res] = ob1.keys[pos1]
				data[res] = ob1.data[pos1]
				res += 1
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
	if pos1 == ob1.size:
		for pos2 in range(pos2, ob2.size):
			keys[res] = ob2.keys[pos2]
			block_copy(&(data[res]), ob2._getblk(pos2, &b2))
			res += 1
	elif pos2 == ob2.size:
		for pos1 in range(pos1, ob1.size):
			keys[res] = ob1.keys[pos1]
			data[res] = ob1.data[pos1]
			res += 1
	ob1._replacearrays(keys, data, res)
	return ob1


cdef inline RoaringBitmap rb_ixor(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef uint32_t pos1 = 0, pos2 = 0, res = 0
	cdef uint16_t *keys = NULL
	cdef Block *data = NULL
	cdef Block b2
	ob1.capacity = ob1.size + ob2.size
	ob1._tmpalloc(ob1.capacity, &keys, &data)
	if pos1 < ob1.size and pos2 < ob2.size:
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				keys[res] = ob1.keys[pos1]
				data[res] = ob1.data[pos1]
				res += 1
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				keys[res] = ob2.keys[pos2]
				block_copy(&(data[res]), ob2._getblk(pos2, &b2))
				res += 1
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_ixor(&(ob1.data[pos1]), ob2._getblk(pos2, &b2))
				if ob1.data[pos1].cardinality > 0:
					keys[res] = ob1.keys[pos1]
					data[res] = ob1.data[pos1]
					res += 1
				else:
					free(ob1.data[pos1].buf.ptr)
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
	if pos1 == ob1.size:
		for pos2 in range(pos2, ob2.size):
			keys[res] = ob2.keys[pos2]
			block_copy(&(data[res]), ob2._getblk(pos2, &b2))
			res += 1
	elif pos2 == ob2.size:
		for pos1 in range(pos1, ob1.size):
			keys[res] = ob1.keys[pos1]
			data[res] = ob1.data[pos1]
			res += 1
	ob1._replacearrays(keys, data, res)
	return ob1


cdef inline RoaringBitmap rb_and(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef RoaringBitmap result = RoaringBitmap()
	cdef uint32_t pos1 = 0, pos2 = 0
	cdef Block b1, b2
	if pos1 < ob1.size and pos2 < ob2.size:
		result._extendarray(min(ob1.size, ob2.size))
		# initialize to zero so that unallocated blocks can be detected
		memset(result.data, 0, result.capacity * sizeof(Block))
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_and(&(result.data[result.size]),
						ob1._getblk(pos1, &b1), ob2._getblk(pos2, &b2))
				if result.data[result.size].cardinality:
					result.keys[result.size] = ob1.keys[pos1]
					result.size += 1
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
		free(result.data[result.size].buf.ptr)
		result._resize(result.size)
	return result


cdef inline RoaringBitmap rb_sub(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef RoaringBitmap result = RoaringBitmap()
	cdef uint32_t pos1 = 0, pos2 = 0
	cdef Block b1, b2
	if pos1 < ob1.size and pos2 < ob2.size:
		result._extendarray(ob1.size)
		memset(result.data, 0, result.capacity * sizeof(Block))
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob1.keys[pos1], ob1._getblk(pos1, &b1))
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_sub(&(result.data[result.size]),
						ob1._getblk(pos1, &b1), ob2._getblk(pos2, &b2))
				if result.data[result.size].cardinality > 0:
					result.keys[result.size] = ob1.keys[pos1]
					result.size += 1
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
		if pos2 == ob2.size:
			for pos1 in range(pos1, ob1.size):
				result._insertcopy(
						result.size, ob1.keys[pos1], ob1._getblk(pos1, &b1))
		free(result.data[result.size].buf.ptr)
		result._resize(result.size)
	return result


cdef inline RoaringBitmap rb_or(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef RoaringBitmap result = RoaringBitmap()
	cdef uint32_t pos1 = 0, pos2 = 0
	cdef Block b1, b2
	if pos1 < ob1.size and pos2 < ob2.size:
		result._extendarray(ob1.size + ob2.size)
		memset(result.data, 0, result.capacity * sizeof(Block))
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob1.keys[pos1], ob1._getblk(pos1, &b1))
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob2.keys[pos2], ob2._getblk(pos2, &b2))
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_or(&(result.data[result.size]),
						ob1._getblk(pos1, &b1), ob2._getblk(pos2, &b2))
				result.keys[result.size] = ob1.keys[pos1]
				result.size += 1
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
	if pos1 == ob1.size:
		result._extendarray(ob2.size - pos2)
		for pos2 in range(pos2, ob2.size):
			result._insertcopy(result.size,
					ob2.keys[pos2], ob2._getblk(pos2, &b2))
	elif pos2 == ob2.size:
		result._extendarray(ob1.size - pos1)
		for pos1 in range(pos1, ob1.size):
			result._insertcopy(
					result.size, ob1.keys[pos1], ob1._getblk(pos1, &b1))
	result._resize(result.size)
	return result


cdef inline RoaringBitmap rb_xor(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef RoaringBitmap result = RoaringBitmap()
	cdef uint32_t pos1 = 0, pos2 = 0
	cdef Block b1, b2
	if pos1 < ob1.size and pos2 < ob2.size:
		result._extendarray(ob1.size + ob2.size)
		memset(result.data, 0, result.capacity * sizeof(Block))
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob1.keys[pos1], ob1._getblk(pos1, &b1))
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob2.keys[pos2], ob2._getblk(pos2, &b2))
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_xor(&(result.data[result.size]),
						ob1._getblk(pos1, &b1), ob2._getblk(pos2, &b2))
				if result.data[result.size].cardinality > 0:
					result.keys[result.size] = ob1.keys[pos1]
					result.size += 1
				pos1 += 1
				pos2 += 1
				if pos1 == ob1.size or pos2 == ob2.size:
					break
		if pos1 == ob1.size:
			result._extendarray(ob2.size - pos2)
			for pos2 in range(pos2, ob2.size):
				result._insertcopy(
						result.size, ob2.keys[pos2], ob2._getblk(pos2, &b2))
		elif pos2 == ob2.size:
			result._extendarray(ob1.size - pos1)
			for pos1 in range(pos1, ob1.size):
				result._insertcopy(
						result.size, ob1.keys[pos1], ob1._getblk(pos1, &b1))
		free(result.data[result.size].buf.ptr)
		result._resize(result.size)
	return result


cdef bint rb_isdisjoint(RoaringBitmap self, RoaringBitmap ob):
	cdef Block b1, b2
	cdef size_t n
	cdef int i = 0
	if self.size == 0 or ob.size == 0:
		return True
	for n in range(self.size):
		i = ob._binarysearch(i, ob.size, self.keys[n])
		if i < 0:
			if -i - 1 >= <int>ob.size:
				return True
			i = -i - 1
		elif not block_isdisjoint(self._getblk(n, &b1), ob._getblk(i, &b2)):
			return False
	return True


cdef inline bint rb_issubset(RoaringBitmap self, RoaringBitmap ob):
	cdef Block b1, b2
	cdef size_t n
	cdef int i = 0
	if self.size == 0:
		return True
	elif ob.size == 0:
		return False
	for n in range(self.size):
		i = ob._binarysearch(i, ob.size, self.keys[n])
		if i < 0:
			return False
	i = 0
	for n in range(self.size):
		i = ob._binarysearch(i, ob.size, self.keys[n])
		if not block_issubset(self._getblk(n, &b1), ob._getblk(i, &b2)):
			return False
	return True


cdef inline RoaringBitmap rb_clamp(RoaringBitmap self,
		uint32_t start, uint32_t stop):
	cdef Block b1
	cdef RoaringBitmap result = RoaringBitmap()
	cdef int ii = self._getindex(highbits(start)), jj = ii
	cdef int i = -ii - 1 if ii < 0 else ii, j = i
	if highbits(start) != highbits(stop):
		jj = self._getindex(highbits(stop))
		j = min(self.size - 1, -jj - 1) if jj < 0 else jj
	result._extendarray(j - i + 1)
	memset(result.data, 0, result.capacity * sizeof(Block))
	block_clamp(&(result.data[0]), self._getblk(i, &b1),
			lowbits(start), lowbits(stop) if i == j and ii >= 0 else BLOCKSIZE)
	if result.data[result.size].cardinality:
		result.keys[result.size] = self.keys[i]
		result.size += 1
	else:
		free(result.data[0].buf.ptr)
	for n in range(i + 1, j):
		block_copy(&(result.data[result.size]), self._getblk(n, &b1))
		result.keys[result.size] = self.keys[n]
		result.size += 1
	if i != j:
		block_clamp(&(result.data[result.size]), self._getblk(j, &b1),
				0, lowbits(stop) if jj >= 0 else BLOCKSIZE)
		if result.data[result.size].cardinality:
			result.keys[result.size] = self.keys[j]
			result.size += 1
		else:
			free(result.data[result.size].buf.ptr)
	result._resize(result.size)
	return result


cdef inline double rb_jaccard_dist(RoaringBitmap ob1, RoaringBitmap ob2) nogil:
		cdef Block b1, b2
		cdef uint32_t union_result = 0, intersection_result = 0, tmp1, tmp2
		cdef uint32_t pos1 = 0, pos2 = 0
		if pos1 < ob1.size and pos2 < ob2.size:
			while True:
				if ob1.keys[pos1] < ob2.keys[pos2]:
					union_result += ob1.data[pos1].cardinality
					pos1 += 1
					if pos1 == ob1.size:
						break
				elif ob1.keys[pos1] > ob2.keys[pos2]:
					union_result += ob2.data[pos2].cardinality
					pos2 += 1
					if pos2 == ob2.size:
						break
				else:
					tmp1, tmp2 = 0, 0
					block_andorlen(
							ob1._getblk(pos1, &b1),
							ob2._getblk(pos2, &b2),
							&tmp1, &tmp2)
					intersection_result += tmp1
					union_result += tmp2
					pos1 += 1
					pos2 += 1
					if pos1 == ob1.size or pos2 == ob2.size:
						break
		if pos1 == ob1.size and pos2 < ob2.size:
			for pos2 in range(pos2, ob2.size):
				union_result += ob2.data[pos2].cardinality
		elif pos2 == ob2.size and pos1 < ob1.size:
			for pos1 in range(pos1, ob1.size):
				union_result += ob1.data[pos1].cardinality
		if union_result == 0:
			return 1
		return 1 - (intersection_result / <double>union_result)
