"""Functions for working with bitvectors.

NB: most functions are in bit.pxd to facilitate function inlining."""


def test():
	cdef uint64_t ulongvec[2]
	ulongvec[0] = 1UL << (sizeof(uint64_t) * 8 - 1)
	ulongvec[1] = 1
	assert anextset(ulongvec, 0, 2) == sizeof(uint64_t) * 8 - 1, (
			anextset(ulongvec, 0, 2), sizeof(uint64_t) * 8 - 1)
	assert anextset(ulongvec, sizeof(uint64_t) * 8, 2) == sizeof(uint64_t) * 8, (
		anextset(ulongvec, sizeof(uint64_t) * 8, 2), sizeof(uint64_t) * 8)
	assert anextunset(ulongvec, 0, 2) == 0, (
		anextunset(ulongvec, 0, 2), 0)
	assert anextunset(ulongvec, sizeof(uint64_t) * 8 - 1, 2) == (
			sizeof(uint64_t) * 8 + 1), (anextunset(ulongvec,
			sizeof(uint64_t) * 8 - 1, 2), sizeof(uint64_t) * 8 + 1)
	ulongvec[0] = 0
	assert anextset(ulongvec, 0, 2) == sizeof(uint64_t) * 8, (
		anextset(ulongvec, 0, 2), sizeof(uint64_t) * 8)
	ulongvec[1] = 0
	assert anextset(ulongvec, 0, 2) == -1, (
		anextset(ulongvec, 0, 2), -1)
	ulongvec[0] = ~0UL
	assert anextunset(ulongvec, 0, 2) == sizeof(uint64_t) * 8, (
		anextunset(ulongvec, 0, 2), sizeof(uint64_t) * 8)
	print('it worked')
