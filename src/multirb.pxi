cdef class MultiRoaringBitmap(object):
	"""A sequence of immutable roaring bitmaps.

	Bitmaps are addressed with 32-bit indices.
	Everything is stored in a single contiguous block of memory.

	>>> mrb = MultiRoaringBitmap([
	...    RoaringBitmap({0, 1, 2}),
	...    RoaringBitmap({1, 6, 8}),
	...    RoaringBitmap({1, 7, 2})])
	>>> mrb.intersection(list(range(len(mrb))))
	RoaringBitmap({1})
	>>> mrb[0] | mrb[1]
	RoaringBitmap({0, 1, 2, 6, 8})
	"""
	cdef uint32_t size  # the number of roaring bitmaps
	cdef uint32_t *offsets  # byte offset in ptr for each roaring bitmap
	cdef uint32_t *sizes  # the size of each roaring bitmap, used as heuristic
	cdef uint32_t *ptr  # the data
	cdef object state  # array or mmap which should be kept alive for ptr
	cdef object file

	def __init__(self, list init, filename=None):
		"""
		:param init: a list of set-like objects (e.g., RoaringBitmaps).
		:param filename: if given, result is stored in an mmap'd file.
			File is overwritten if it already exists."""
		cdef ImmutableRoaringBitmap irb
		cdef uint32_t alloc, offset
		cdef int alignment = 32
		cdef char [:] vstate
		if filename is not None:
			self.file = open(filename, 'wb')

		tmp = [ImmutableRoaringBitmap(a) for a in init]
		self.size = len(tmp)
		alloc = sizeof(uint32_t) + 2 * self.size * sizeof(uint32_t)
		extra = alignment - alloc % alignment
		alloc += extra
		offset = alloc
		for irb in tmp:
			alloc += irb.bufsize

		self.state = mmap.mmap(
				-1 if filename is None
				else self.file.fileno(),
				alloc, access=mmap.ACCESS_WRITE)
		vstate = MagicMemoryView(self.state, (alloc, ), b'c')
		self.ptr = <uint32_t *>&vstate[0]

		self.ptr[0] = self.size
		self.offsets = &(self.ptr[1])
		self.sizes = &(self.ptr[1 + self.size])
		for n in range(1 + 2 * self.size,
				1 + 2 * self.size + extra // sizeof(uint32_t)):
			self.ptr[n] = 0
		for n, irb in enumerate(tmp):
			# offset
			self.ptr[1 + n] = offset
			# size
			self.ptr[1 + n + self.size] = irb.bufsize
			# copy data
			memcpy(&(vstate[offset]), irb.ptr, irb.bufsize)
			offset += irb.bufsize
		if filename is not None:
			self.state.flush()

	def __dealloc__(self):
		if isinstance(self.state, mmap.mmap):
			self.state.close()
			if self.file is not None:
				self.file.close()

	@classmethod
	def fromfile(cls, filename):
		"""Load a MultiRoaringBitmap from a file using mmap."""
		cdef MultiRoaringBitmap ob
		cdef char [:] vstate
		ob = MultiRoaringBitmap.__new__(MultiRoaringBitmap)
		ob.file = open(filename, 'rb')
		ob.state = mmap.mmap(ob.file.fileno(), 0, access=mmap.ACCESS_READ)
		vstate = MagicMemoryView(ob.state, (len(ob.state), ), b'c')
		ob.ptr = <uint32_t *>&vstate[0]
		ob.size = ob.ptr[0]
		ob.offsets = &(ob.ptr[1])
		ob.sizes = &(ob.ptr[1 + ob.size])
		# rest is data
		return ob

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
		indices.sort(key=lambda n: self.sizes[n])
		ob1 = ImmutableRoaringBitmap.__new__(ImmutableRoaringBitmap)
		ob2 = ImmutableRoaringBitmap.__new__(ImmutableRoaringBitmap)
		# TODO with nogil:
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
