cdef inline richcmp(x, y, int op):
	cdef RoaringBitmap ob1, ob2
	cdef int n
	if op == 2:  # ==
		if not isinstance(x, RoaringBitmap):
			# FIXME: what is best approach here?
			# cost of constructing RoaringBitmap vs loss of sort with set()
			# if non-RoaringBitmap is small, constructing new one is better
			return RoaringBitmap(x) == y if len(x) < 1024 else x == set(y)
		elif not isinstance(y, RoaringBitmap):
			return x == RoaringBitmap(y) if len(y) < 1024 else set(x) == y
		ob1, ob2 = x, y
		if ob1.size != ob2.size:
			return False
		if memcmp(ob1.keys, ob2.keys, ob1.size * sizeof(uint16_t)) != 0:
			return False
		for n in range(ob1.size):
			if ob1.data[n].cardinality != ob2.data[n].cardinality:
				return False
		for n in range(ob1.size):
			if memcmp(
					<void *>(<size_t>ob1.data[n].buf.sparse + ob1.offset),
					<void *>(<size_t>ob2.data[n].buf.sparse + ob2.offset),
					_getsize(&(ob1.data[n])) * sizeof(uint16_t)) != 0:
				return False
		return True
	elif op == 3:  # !=
		return not (x == y)
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
	cdef int pos1 = 0, pos2 = 0, res = 0
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
				block_iand(&(ob1.data[pos1]),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
	cdef int pos1 = 0, pos2 = 0, res = 0
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
				block_isub(&(ob1.data[pos1]),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
	cdef int pos1 = 0, pos2 = 0, res = 0
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
				block_copy(&(data[res]),
						ob2._addoff(&(ob2.data[pos2]), &b2))
				res += 1
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_ior(&(ob1.data[pos1]),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
			block_copy(&(data[res]),
					ob2._addoff(&(ob2.data[pos2]), &b2))
			res += 1
	elif pos2 == ob2.size:
		for pos1 in range(pos1, ob1.size):
			keys[res] = ob1.keys[pos1]
			data[res] = ob1.data[pos1]
			res += 1
	ob1._replacearrays(keys, data, res)
	return ob1


cdef inline RoaringBitmap rb_ixor(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef int pos1 = 0, pos2 = 0, res = 0
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
				block_copy(&(data[res]),
						ob2._addoff(&(ob2.data[pos2]), &b2))
				res += 1
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_ixor(&(ob1.data[pos1]),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
			block_copy(&(data[res]),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
	cdef int pos1 = 0, pos2 = 0
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
						ob1._addoff(&(ob1.data[pos1]), &b1),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
	cdef int pos1 = 0, pos2 = 0
	cdef Block b1, b2
	if pos1 < ob1.size and pos2 < ob2.size:
		result._extendarray(ob1.size)
		memset(result.data, 0, result.capacity * sizeof(Block))
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob1.keys[pos1],
						ob1._addoff(&(ob1.data[pos1]), &b1))
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_sub(&(result.data[result.size]),
						ob1._addoff(&(ob1.data[pos1]), &b1),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
						result.size, ob1.keys[pos1],
						ob1._addoff(&(ob1.data[pos1]), &b1))
	result._resize(result.size)
	return result


cdef inline RoaringBitmap rb_or(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef RoaringBitmap result = RoaringBitmap()
	cdef int pos1 = 0, pos2 = 0
	cdef Block b1, b2
	if pos1 < ob1.size and pos2 < ob2.size:
		result._extendarray(ob1.size + ob2.size)
		memset(result.data, 0, result.capacity * sizeof(Block))
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob1.keys[pos1],
						ob1._addoff(&(ob1.data[pos1]), &b1))
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob2.keys[pos2],
						ob2._addoff(&(ob2.data[pos2]), &b2))
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_or(&(result.data[result.size]),
						ob1._addoff(&(ob1.data[pos1]), &b1),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
					ob2.keys[pos2], ob2._addoff(&(ob2.data[pos2]), &b2))
	elif pos2 == ob2.size:
		result._extendarray(ob1.size - pos1)
		for pos1 in range(pos1, ob1.size):
			result._insertcopy(
					result.size, ob1.keys[pos1],
					ob1._addoff(&(ob1.data[pos1]), &b1))
	result._resize(result.size)
	return result


cdef inline RoaringBitmap rb_xor(RoaringBitmap ob1, RoaringBitmap ob2):
	cdef RoaringBitmap result = RoaringBitmap()
	cdef int pos1 = 0, pos2 = 0
	cdef Block b1, b2
	if pos1 < ob1.size and pos2 < ob2.size:
		result._extendarray(ob1.size + ob2.size)
		memset(result.data, 0, result.capacity * sizeof(Block))
		while True:
			if ob1.keys[pos1] < ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob1.keys[pos1],
						ob1._addoff(&(ob1.data[pos1]), &b1))
				pos1 += 1
				if pos1 == ob1.size:
					break
			elif ob1.keys[pos1] > ob2.keys[pos2]:
				result._insertcopy(
						result.size, ob2.keys[pos2],
						ob2._addoff(&(ob2.data[pos2]), &b2))
				pos2 += 1
				if pos2 == ob2.size:
					break
			else:  # ob1.keys[pos1] == ob2.keys[pos2]:
				block_xor(&(result.data[result.size]),
						ob1._addoff(&(ob1.data[pos1]), &b1),
						ob2._addoff(&(ob2.data[pos2]), &b2))
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
					result.size, ob2.keys[pos2],
					ob2._addoff(&(ob2.data[pos2]), &b2))
	elif pos2 == ob2.size:
		result._extendarray(ob1.size - pos1)
		for pos1 in range(pos1, ob1.size):
			result._insertcopy(
					result.size, ob1.keys[pos1],
					ob1._addoff(&(ob1.data[pos1]), &b1))
	result._resize(result.size)
	return result


cdef bint rb_isdisjoint(RoaringBitmap self, RoaringBitmap ob):
	cdef Block b1, b2
	cdef int i = 0, n
	if self.size == 0 or ob.size == 0:
		return True
	for n in range(self.size):
		i = ob._binarysearch(i, ob.size, self.keys[n])
		if i < 0:
			if -i - 1 >= ob.size:
				return True
		elif not block_isdisjoint(
				self._addoff(&(self.data[n]), &b1),
				ob._addoff(&(ob.data[i]), &b2)):
			return False
	return True


cdef inline bint rb_issubset(RoaringBitmap self, RoaringBitmap ob):
	cdef Block b1, b2
	cdef int i = 0, n
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
		if not block_issubset(
				self._addoff(&(self.data[n]), &b1),
				ob._addoff(&(ob.data[i]), &b2)):
			return False
	return True
