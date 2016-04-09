#include <stddef.h>
#include <stdint.h>

#if defined(__SSE4_2__)
#include <nmmintrin.h>
#endif

/**
 * Generic intersection function. Passes unit tests.
 *
 * From CRoaring, array_util.c
 * cf. https://github.com/lemire/CRoaring/src/array_util.c
 */
int32_t intersect_general16(const uint16_t *A, const size_t lenA,
        const uint16_t *B, const size_t lenB, uint16_t *out) {
    const uint16_t *initout = out;
    if (lenA == 0 || lenB == 0) return 0;
    const uint16_t *endA = A + lenA;
    const uint16_t *endB = B + lenB;

    while (1) {
        while (*A < *B) {
SKIP_FIRST_COMPARE:
            if (++A == endA) return (out - initout);
        }
        while (*A > *B) {
            if (++B == endB) return (out - initout);
        }
        if (*A == *B) {
            *out++ = *A;
            if (++A == endA || ++B == endB) return (out - initout);
        } else {
            goto SKIP_FIRST_COMPARE;
        }
    }
    return (out - initout);  // NOTREACHED
}


#if defined(__SSE4_2__)

static inline int32_t intersect_uint16(
        const uint16_t* __restrict a, size_t a_size,
       const uint16_t* __restrict b, size_t b_size,
       uint16_t* __restrict result) {
    // from https://highlyscalable.wordpress.com/2012/06/05/fast-intersection-sorted-lists-sse/
    size_t count = 0;
    static __m128i shuffle_mask16[256];
    static int built_shuffle_mask = 0;
    int i, j;
    if (!built_shuffle_mask) {
        built_shuffle_mask = 1;
        for (i = 0; i < 256; i++) {
            uint8_t mask[16];
            memset(mask, 0xFF, sizeof(mask));
            int counter = 0;
            for (j = 0; j < 16; j++) {
                if (i & (1 << j)) {
                    mask[counter++] = 2 * j;
                    mask[counter++] = 2 * j + 1;
                }
            }
            __m128i v_mask = _mm_loadu_si128((const __m128i *)mask);
            shuffle_mask16[i] = v_mask;
        }
    }
    size_t i_a = 0, i_b = 0;
    size_t st_a = (a_size / 8) * 8;
    size_t st_b = (b_size / 8) * 8;

    while(i_a < st_a && i_b < st_b) {
        __m128i v_a = _mm_loadu_si128((__m128i *)&a[i_a]);
        __m128i v_b = _mm_loadu_si128((__m128i *)&b[i_b]);
        __m128i v_cmp = _mm_cmpestrm(v_a, 8, v_b, 8,
                _SIDD_UWORD_OPS|_SIDD_CMP_EQUAL_ANY|_SIDD_BIT_MASK);
        int r = _mm_extract_epi32(v_cmp, 0);
        __m128i v_shuf = _mm_shuffle_epi8(v_b, shuffle_mask16[r]);
        _mm_storeu_si128((__m128i *)&result[count], v_shuf);
        count += _mm_popcnt_u32(r);
        uint16_t a_max = _mm_extract_epi16(v_a, 7);
        uint16_t b_max = _mm_extract_epi16(v_b, 7);
        i_a += (a_max <= b_max) * 8;
        i_b += (a_max >= b_max) * 8;
    }
    a += i_a;
    a_size -= i_a;
    b += i_b;
    b_size -= i_b;
    result += count;
    return intersect_general16(a, a_size, b, b_size, result);
}

#else  /* __SSE4_2__ */

int32_t intersect_uint16(const uint16_t *A, size_t s_a,
        const uint16_t *B, size_t s_b, uint16_t *C) {
    return intersect_general16(A, s_a, B, s_b, C);
}

#endif  /* __SSE4_2__ */
