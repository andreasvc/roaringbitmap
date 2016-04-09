# Set / search operations on integer arrays

cdef inline int binarysearch(uint16_t *data, int begin, int end,
		uint16_t elem) nogil:
	"""Binary search for short `elem` in array `data`.

	:returns: positive index ``i`` if ``elem`` is found; otherwise return a
		negative value ``i`` such that ``-i - 1`` is the index where ``elem``
		should be inserted."""
	cdef int low = begin
	cdef int high = end - 1
	cdef int middleidx
	cdef uint16_t middleval
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


cdef inline int advance(uint16_t *data, int pos, int length,
		uint16_t minitem) nogil:
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


cdef uint32_t intersect2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest) nogil:
	if length1 * 64 < length2:
		return intersectgalloping(data1, length1, data2, length2, dest)
	elif length2 * 64 < length1:
		return intersectgalloping(data2, length2, data1, length1, dest)
	if dest is NULL:
		return intersectcard(data1, data2, length1, length2)
	# elif data1 is not dest and data2 is not dest:
	# 	# NB: dest must have 8 elements extra capacity
	# 	return intersect_uint16(data1, length1, data2, length2, dest)
	return intersect_general16(data1, length1, data2, length2, dest)
	# return intersectlocal2by2(data1, length1, data2, length2, dest)


cdef inline int intersectlocal2by2(uint16_t *data1, int length1,
		uint16_t *data2, int length2, uint16_t *dest) nogil:
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


cdef inline int intersectcard(uint16_t *data1, uint16_t *data2,
		int length1, int length2) nogil:
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
			pos += 1
			k1 += 1
			if k1 == length1:
				return pos
			k2 += 1
			if k2 == length2:
				return pos


cdef inline int intersectgalloping(
		uint16_t *small, int lensmall,
		uint16_t *large, int lenlarge,
		uint16_t *dest) nogil:
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
			if dest is not NULL:
				dest[pos] = small[k2]
			pos += 1
			k2 += 1
			if k2 == lensmall:
				return pos
			k1 = advance(large, k1, lenlarge, small[k2])
			if k1 == lenlarge:
				return pos


cdef int union2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest,
		uint32_t *intersect_count) nogil:
	cdef int k1 = 0, k2 = 0, pos = 0, n_elems
	if length2 == 0:
		if dest is not NULL:
			memcpy(dest, data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		if dest is not NULL:
			memcpy(dest, data2, length2 * sizeof(uint16_t))
		return length2
	elif length1 > length2:
		return union2by2(data2, data1, length2, length1, dest, intersect_count)
	while True:
		if data1[k1] < data2[k2]:
			if dest is not NULL:
				dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				break
		elif data1[k1] > data2[k2]:
			if dest is not NULL:
				dest[pos] = data2[k2]
			pos += 1
			k2 += 1
			if k2 >= length2:
				break
		else:  # data1[k1] == data2[k2]
			if dest is not NULL:
				dest[pos] = data1[k1]
			pos += 1
			intersect_count[0] += 1
			k1 += 1
			k2 += 1
			if k1 >= length1 or k2 >= length2:
				break
	if k1 < length1:
		n_elems = length1 - k1
		if dest is not NULL:
			memcpy(&(dest[pos]), &(data1[k1]), n_elems * sizeof(uint16_t))
		pos += n_elems
	elif k2 < length2:
		n_elems = length2 - k2
		if dest is not NULL:
			memcpy(&(dest[pos]), &(data2[k2]), n_elems * sizeof(uint16_t))
		pos += n_elems
	return pos


cdef int difference(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest) nogil:
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		if dest is not NULL:
			memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		return 0
	while True:
		if data1[k1] < data2[k2]:
			if dest is not NULL:
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
			elif k2 >= length2:
				break
		else:  # data1[k1] > data2[k2]
			k2 += 1
			if k2 >= length2:
				break
	while k1 < length1:
		if dest is not NULL:
			dest[pos] = data1[k1]
		pos += 1
		k1 += 1
	return pos


cdef int xor2by2(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint16_t *dest) nogil:
	cdef int k1 = 0, k2 = 0, pos = 0
	if length2 == 0:
		if dest is not NULL:
			memcpy(<void *>dest, <void *>data1, length1 * sizeof(uint16_t))
		return length1
	elif length1 == 0:
		if dest is not NULL:
			memcpy(<void *>dest, <void *>data2, length2 * sizeof(uint16_t))
		return length2
	while True:
		if data1[k1] < data2[k2]:
			if dest is not NULL:
				dest[pos] = data1[k1]
			pos += 1
			k1 += 1
			if k1 >= length1:
				break
		elif data1[k1] == data2[k2]:
			k1 += 1
			k2 += 1
			if k1 >= length1 or k2 >= length2:
				break
		else:  # data1[k1] > data2[k2]
			if dest is not NULL:
				dest[pos] = data2[k2]
			pos += 1
			k2 += 1
			if k2 >= length2:
				break
	if k1 >= length1:
		while k2 < length2:
			if dest is not NULL:
				dest[pos] = data2[k2]
			pos += 1
			k2 += 1
	elif k2 >= length2:
		while k1 < length1:
			if dest is not NULL:
				dest[pos] = data1[k1]
			pos += 1
			k1 += 1
	return pos


cdef void symmetricdifflen(uint16_t *data1, uint16_t *data2,
		int length1, int length2, uint32_t *diff1, uint32_t *diff2) nogil:
	"""Computes length of differences. diff1 will equal |data1 - data2|,
	diff2 will equal |data2 - data1|."""
	cdef int k1 = 0, k2 = 0
	if length2 == 0:
		diff1[0] = length1
		return
	elif length1 == 0:
		diff2[0] = length2
		return
	while True:
		if data1[k1] < data2[k2]:
			diff1[0] += 1
			k1 += 1
			if k1 >= length1:
				break
		elif data1[k1] == data2[k2]:
			k1 += 1
			k2 += 1
			if k1 >= length1:
				break
			if k2 >= length2:
				break
		else:  # data1[k1] > data2[k2]
			diff2[0] += 1
			k2 += 1
			if k2 >= length2:
				break
		if k1 >= length1:
			while k2 < length2:
				diff2[0] += 1
				k2 += 1
			return
		if k2 >= length2:
			while k1 < length1:
				diff1[0] += 1
				k1 += 1
			return
