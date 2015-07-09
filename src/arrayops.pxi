# Set / search operations on arrays

cdef int binarysearch(uint16_t *data, int begin, int end, uint16_t elem):
	"""Binary search for short `elem` in array `data`."""
	cdef int low = begin
	cdef int high = end - 1
	cdef int middleidx, middleval
	# accelerate the possibly common case of a just appended value
	if end > 0 and data[end - 1] < elem:
		return -end - 1
	while low <= high:
		middleidx = (low + high) >> 1
		middleval = data[middleidx]
		if middleval < elem:
			low = middleidx + 1
		elif middleval > elem:
			high = middleidx - 1
		else:
			return middleidx
	return -(low + 1)


cdef int intersect2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	if length1 * 64 < length2:
		return intersectgalloping(data1, length1, data2, length2, dest)
	elif length2 * 64 < length1:
		return intersectgalloping(data2, length2, data1, length1, dest)
	return intersectlocal2by2(data1, data2, length1, length2, dest)


cdef int intersectlocal2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length1 == 0 or length2 == 0:
		return 0
	while True:
		if data2[k2] < data1[k1]:
			while True:
				k2 += 1
				if k2 == length2:
					return pos
				elif data2[k2] >= data1[k1]:
					break
		elif data1[k1] < data2[k2]:
			while True:
				k1 += 1
				if k1 == length1:
					return pos
				elif data1[k1] >= data2[k2]:
					break
		else:  # data1[k1] == data2[k2]
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 == length1:
				return pos
			k2 += 1
			if k2 == length2:
				return pos


cdef int intersectgalloping(
		uint16_t *small, int lensmall,
		uint16_t *large, int lenlarge,
		uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if lensmall == 0:
		return 0
	while True:
		if large[k1] < small[k2]:
			k1 = advance(large, k1, lenlarge, small[k2])
			if k1 == lenlarge:
				return pos
		if small[k2] < large[k1]:
			k2 += 1
			if k2 == lensmall:
				return pos
		else:  # large[k2] == small[k1]
			dest[pos] = small[k2]
			pos += 1
			k2 += 1
			if k2 == lensmall:
				return pos
			k1 = advance(large, k1, lenlarge, small[k2])
			if k1 == lenlarge:
				return pos


cdef int advance(uint16_t *data, int pos, int length, uint16_t minitem):
	cdef int lower = pos + 1
	cdef int spansize = 1
	cdef int upper, mid
	if lower >= length or data[lower] >= minitem:
		return lower
	while lower + spansize < length and data[lower + spansize] < minitem:
		spansize *= 2
	upper = (lower + spansize) if lower + spansize < length else (length - 1)
	if data[upper] == minitem:
		return upper
	if data[upper] < minitem:
		return length
	lower += spansize >> 1
	while lower + 1 != upper:
		mid = (<unsigned int>lower + <unsigned int>upper) >> 1
		if data[mid] == minitem:
			return mid
		elif data[mid] < minitem:
			lower = mid
		else:
			upper = mid
	return upper


cdef int union2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		memcpy(<void *>dest, <void *>data2, length2 * sizeof(uint16_t))
		return length2
	while True:
		if data1[k1] < data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
		elif data1[k1] == data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			k2 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos
		else:  # data1[k1] > data2[k2]
			dest[pos] = data2[k2]
			pos += 1
			k2 += 1
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos


cdef int difference(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		return 0
	while True:
		if data1[k1] < data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				return pos
		elif data1[k1] == data2[k2]:
			k1 += 1
			k2 += 1
			if k1 >= length1:
				return pos
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos
		else:  # data1[k1] > data2[k2]
			k2 += 1
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos


cdef int xor2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest):
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		memcpy(<void *>dest, <void *>data2, length2 * sizeof(uint16_t))
		return length2
	while True:
		if data1[k1] < data2[k2]:
			dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
		elif data1[k1] == data2[k2]:
			k1 += 1
			k2 += 1
			if k1 >= length1:
				while k2 < length2:
					dest[pos] = data2[k2]
					pos += 1
					k2 += 1
				return pos
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos
		else:  # data1[k1] > data2[k2]
			dest[pos] = data2[k2]
			pos += 1
			k2 += 1
			if k2 >= length2:
				while k1 < length1:
					dest[pos] = data1[k1]
					pos += 1
					k1 += 1
				return pos
