/* http://c-faq.com/misc/bitsets.html */
/* Original, any word size:
#define BITSIZE				(8 * sizeof(uint64_t))
#define BITSLOT(b)			((b) / BITSIZE)
#define BITMASK(b)			(1ULL << ((b) % BITSIZE))
#define TESTBIT(a, b)		((a)[BITSLOT(b)] & BITMASK(b))
NB: TESTBIT returns 0 or a value with bit b set
Fix word size at 64 bits:
 */
#define BITSIZE				(64)
#define BITSIZE1			(BITSIZE - 1)
#define BITSLOT(b)			((b) >> 6)
#define BITMASK(b)			(1ULL << ((b) & BITSIZE1))
#define SETBIT(a, b)		((a)[BITSLOT(b)] |= BITMASK(b))
#define TOGGLEBIT(a, b)		((a)[BITSLOT(b)] ^= BITMASK(b))
#define CLEARBIT(a, b)		((a)[BITSLOT(b)] &= ~BITMASK(b))
#define BITNSLOTS(nb)		(((nb) + BITSIZE1) / BITSIZE)
#define TESTBIT(a, b)		(((a)[BITSLOT(b)] >> (b & BITSIZE1)) & 1)
/* NB: TESTBIT returns 0 or 1*/

#ifdef _MSC_VER
#define ALIGNED_INLINE __inline
#else
#define ALIGNED_INLINE inline
#endif

/* https://stackoverflow.com/q/16376942 */
ALIGNED_INLINE void* aligned_malloc(size_t size, size_t align) {
	void *result;
	#ifdef _MSC_VER
	result = _aligned_malloc(size, align);
	#else
	if (posix_memalign(&result, align, size))
		result = 0;
	#endif
	return result;
}

ALIGNED_INLINE void aligned_free(void *ptr) {
	#ifdef _MSC_VER
	_aligned_free(ptr);
	#else
	free(ptr);
	#endif
}
