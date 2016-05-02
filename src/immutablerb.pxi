cdef class ImmutableRoaringBitmap(RoaringBitmap):
	"""A roaring bitmap that does not allow mutation operations.

	Any operation resulting in a new roaring bitmap is returned as a mutable
	RoaringBitmap. Stores data in one contiguous block of memory for efficient
	serialization."""
	cdef readonly object state  # object to be kept for ptr to remain valid
	cdef char *ptr  # the data
	cdef size_t bufsize  # length in bytes of data
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
			self.__setstate__(iob.__getstate__())
		else:
			ob = ensurerb(iterable or ())
			self.__setstate__(ob.__getstate__())

	def __dealloc__(self):
		pass  # nothing to declare

	def __getstate__(self):
		if self.state is None:
			state = array.clone(chararray, self.bufsize, False)
			memcpy(state.data.as_chars, self.ptr, self.bufsize)
			return state
		return self.state

	def __setstate__(self, array.array state):
		"""`state` is a char array with the pickle format of RoaringBitmap.
		Instead of copying this data, it will be used directly.
		"""
		self.state = state
		# FIXME: 32 byte alignment depends on state.data being aligned.
		self._setptr(state.data.as_chars, len(state))

	cdef void _setptr(self, char *ptr, size_t size) nogil:
		self.ptr = ptr
		self.offset = <size_t>ptr
		self.bufsize = size
		self._hash = -1
		self.size = (<uint32_t *>ptr)[0]
		self.capacity = self.size
		self.keys = <uint16_t *>&(ptr[sizeof(uint32_t)])
		# pointers will be adjusted on the fly with self.offset
		self.data = <Block *>&(ptr[
				sizeof(uint32_t) + self.size * (sizeof(uint16_t))])

	def __hash__(self):
		cdef size_t n
		if self._hash == -1:
			self._hash = 5381
			for n in range(self.bufsize):
				self._hash = ((self._hash << 5) + self._hash) + self.ptr[n]
				# i.e., self._hash *= 33 ^ self.ptr[n]
		return self._hash

	def __richcmp__(x, y, int op):
		cdef ImmutableRoaringBitmap iob1, iob2
		if (isinstance(x, ImmutableRoaringBitmap)
				and isinstance(y, ImmutableRoaringBitmap)):
			if op == 2:  # ==
				iob1, iob2 = x, y
				if (iob1.bufsize != iob2.bufsize
						or iob1.__hash__() != iob2.__hash__()):
					return False
				return memcmp(iob1.ptr, iob2.ptr, iob1.bufsize) == 0
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
