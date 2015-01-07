
/* http://c-faq.com/misc/bitsets.html */
#define BITSIZE 			(8 * sizeof(uint64_t))
#define BITMASK(b) 			(1UL << ((b) % BITSIZE))
#define BITSLOT(b) 			((b) / BITSIZE)
#define SETBIT(a, b) 		((a)[BITSLOT(b)] |= BITMASK(b))
#define TOGGLEBIT(a, b)		((a)[BITSLOT(b)] ^= BITMASK(b))
#define CLEARBIT(a, b) 		((a)[BITSLOT(b)] &= ~BITMASK(b))
#define TESTBIT(a, b) 		((a)[BITSLOT(b)] & BITMASK(b))
#define BITNSLOTS(nb) 		(((nb) + BITSIZE - 1) / BITSIZE)

/* 3D array indexing (implicit third index k = 0) */
#define IDX(i,j,jmax,kmax)	((i * jmax + j) * kmax)
