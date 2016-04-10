cdef class ImmutableRoaringBitmap(RoaringBitmap):
	"""A roaring bitmap that does not allow mutation operations.

	Any operation resulting in a new roaring bitmap is returned as a mutable
	RoaringBitmap. Stores data in one contiguous block of memory for efficient
	serialization."""
	cdef readonly array.array state
	cdef long _hash

	def __init__(self, iterable=None):
		"""Return a new RoaringBitmap with elements from ``iterable``.

		The elements ``x`` of a RoaringBitmap must be ``0 <= x < 2 ** 32``.
		If ``iterable`` is not specified, a new empty RoaringBitmap is
		returned. Note that a sorted iterable will significantly speed up the
		construction.
		``iterable`` may be a generator, in which case the generator is
		consumed incrementally.
		``iterable`` may be a ``range`` (Python 3) or ``xrange`` (Python 2)
		object, which will be constructed efficiently."""
		cdef RoaringBitmap ob
		cdef ImmutableRoaringBitmap iob
		if isinstance(iterable, ImmutableRoaringBitmap):
			iob = iterable
			self.__setstate__(array.copy(iob.__getstate__()))
		else:
			ob = ensurerb(iterable or ())
			self.__setstate__(ob.__getstate__())

	def __dealloc__(self):
		free(self.data)
		self.data = NULL

	def __getstate__(self):
		return self.state

	def __setstate__(self, array.array state):
		"""`state` is a char array with the pickle format of RoaringBitmap.
		Instead of copying this data, it will be used directly.
		"""
		# NB: for mmap, must avoid array/pickle.
		# FIXME: 32 byte alignment depends on state.data being aligned.
		self.state = state
		self._hash = hashbytes(state.data.as_chars, len(state))
		self.size = (<uint32_t *>state.data.as_ulongs)[0]
		self.capacity = self.size
		self.keys = <uint16_t *>&(state.data.as_chars[sizeof(uint32_t)])
		# adjust pointers in advance:
		self.data = <Block *>malloc(self.size * sizeof(Block))
		for n in range(self.size):
			self.data[n] = (<Block *>&(state.data.as_chars[
				sizeof(uint32_t) + self.size * sizeof(uint16_t)
				+ n * sizeof(Block)]))[0]
			self.data[n].buf.ptr = <void *>(
					<size_t>self.data[n].buf.ptr
					+ <size_t>self.state.data.as_chars)
		# alt: adjust pointers on the fly, no copying
		# self.data = <Block *>(&(self.state.data.as_chars)[
		#		sizeof(uint32_t) + self.size * (sizeof(uint16_t))])

	def __hash__(self):
		return self._hash

	def __richcmp__(x, y, op):
		cdef ImmutableRoaringBitmap iob1, iob2
		# cdef RoaringBitmap ob1, ob2
		# cdef int n
		if op == 2:  # ==
			if (isinstance(x, ImmutableRoaringBitmap)
					and isinstance(y, ImmutableRoaringBitmap)):
				iob1, iob2 = x, y
				if iob1._hash != iob2._hash:
					return False
		elif op == 3:  # !=
			return not (x == y)
		return richcmp(x, y, op)

	def __sizeof__(self):
		"""Return memory usage in bytes."""
		return len(self.state)

	def freeze(self):
		"""Already immutable, return self."""
		return self

	def __repr__(self):
		return 'ImmutableRoaringBitmap(%s)' % str(self)

	def copy(self):
		"""Return a copy of this RoaringBitmap."""
		cdef ImmutableRoaringBitmap result = ImmutableRoaringBitmap.__new__(
				ImmutableRoaringBitmap)
		result.__setstate__(array.copy(self.__getstate__()))
		return result

	def add(self, uint32_t elem):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def discard(self, uint32_t elem):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def remove(self, uint32_t elem):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def pop(self):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def __iand__(self, x):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def __isub__(self, x):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def __ior__(self, x):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def __ixor__(self, x):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def update(self, *bitmaps):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def intersection_update(self, *bitmaps):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def difference_update(self, *other):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def symmetric_difference_update(self, other):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def flip_range(self, start, stop):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')

	def clear(self):
		raise ValueError('ImmutableRoaringBitmap cannot be modified.')


cdef long hashbytes(char *buf, size_t len):
	cdef size_t n
	cdef long _hash = buf[0]
	for n in range(1, len):
		_hash *= 33 ^ (<uint8_t *>buf)[n]
	return _hash
