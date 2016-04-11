

cdef class MultiRoaringBitmap(object):
	"""A sequence of immutable roaring bitmaps.

	Bitmaps are addressed with 32-bit indices.
	Everything is stored in a single contiguous block of memory."""
	cdef uint32_t size  # the number of roaring bitmaps
	cdef uint32_t *offsets  # byte offset in ptr for each roaring bitmap
	cdef uint32_t *sizes  # the size of each roaring bitmap, used as heuristic
	cdef uint32_t *ptr  # the data
	cdef object state  # array or mmap which should be kept alive for ptr

	def __init__(self, list init):
		cdef ImmutableRoaringBitmap irb
		cdef array.array state  # FIXME use numpy, supports mmap
		cdef int alignment = 32
		cdef uint32_t alloc, offset
		cdef char *ptr
		tmp = [rb.freeze() for rb in init]
		self.size = len(tmp)
		alloc = sizeof(uint32_t) + 2 * self.size * sizeof(uint32_t)
		alloc += alignment - alloc % alignment
		offset = alloc
		for irb in tmp:
			alloc += irb.bufsize
		state = array.clone(chararray, alloc, True)
		self.state = state
		self.ptr = <uint32_t *>state.data.as_ulongs
		self.ptr[0] = self.size
		self.offsets = &(self.ptr[1])
		self.sizes = &(self.ptr[1 + self.size])
		ptr = <char *>self.ptr
		for n, irb in enumerate(tmp):
			# offset
			self.ptr[1 + n] = offset
			# size
			self.ptr[1 + n + self.size] = irb.bufsize
			# copy data
			memcpy(&(ptr[offset]), irb.ptr, irb.bufsize)
			offset += irb.bufsize

	def __getstate__(self):
		return self.state

	def __setstate__(self, array.array state):
		self.state = state
		self.ptr = <uint32_t *>state.data.as_ulongs
		self.size = self.ptr[0]
		self.offsets = &(self.ptr[1])
		self.sizes = &(self.ptr[1 + self.size])
		# rest is data

	def __len__(self):
		return self.size

	def __getitem__(self, i):
		"""Return a copy of bitmap i as an ImmutableRoaringBitmap."""
		cdef ImmutableRoaringBitmap ob1
		ob1 = ImmutableRoaringBitmap.__new__(ImmutableRoaringBitmap)
		ob1._setptr(&(<char *>self.ptr)[self.offsets[i]], self.sizes[i])
		return ob1

	def intersection(self, indices):
		"""Given a list of indices of roaring bitmaps in this collection,
		return their intersecion as a mutable RoaringBitmap."""
		cdef ImmutableRoaringBitmap ob1, ob2
		cdef RoaringBitmap result
		cdef char *ptr = <char *>self.ptr
		cdef int i, j, n
		# TODO with nogil:
		# TODO mmap through numpy
		indices.sort(key=lambda n: self.sizes[n])
		ob1 = ImmutableRoaringBitmap.__new__(ImmutableRoaringBitmap)
		ob2 = ImmutableRoaringBitmap.__new__(ImmutableRoaringBitmap)
		i, j = indices[0], indices[1]
		ob1._setptr(&(ptr[self.offsets[i]]), self.sizes[i])
		ob2._setptr(&(ptr[self.offsets[j]]), self.sizes[j])
		result = rb_and(ob1, ob2)
		for n in indices[2:]:
			i = indices[n]
			# swap out contents of ImmutableRoaringBitmap object
			ob1._setptr(&(ptr[self.offsets[i]]), self.sizes[i])
			rb_iand(result, ob1)
			if result.size == 0:
				break
		return result
