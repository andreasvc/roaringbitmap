#ifndef ROARINGBITMAP_CPU_FEATURES_H_
#define ROARINGBITMAP_CPU_FEATURES_H_

#if defined(ROARINGBITMAP_REQUIRE_POPCNT) && defined(_MSC_VER)
#include <intrin.h>
#endif

/* Release wheels define this when they are compiled with -mpopcnt. Source
 * builds and non-x86 wheels do not require features beyond their target's
 * normal architecture baseline. */
static int roaring_cpu_supports_required_features(void) {
#if defined(ROARINGBITMAP_REQUIRE_POPCNT)
	#if !(defined(__i386__) || defined(__x86_64__) || \
			defined(_M_IX86) || defined(_M_X64))
	return 0;
	#elif defined(__GNUC__) || defined(__clang__)
	return __builtin_cpu_supports("popcnt") != 0;
	#elif defined(_MSC_VER)
	int registers[4];
	__cpuid(registers, 1);
	return (registers[2] & (1 << 23)) != 0;
	#else
	return 0;
	#endif
#else
	return 1;
#endif
}

#endif
