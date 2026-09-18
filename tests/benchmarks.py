"""Benchmarks for roaringbitmap"""
from __future__ import division, print_function, absolute_import, \
		unicode_literals
import random
import timeit

N = 1 << 17  # number of random elements
M = 100  # number of test runs
MAX = 1 << 20  # range of elements
DATA1, DATA2 = None, None
COMPARE_EQUAL, COMPARE_CARDINALITY = None, None
COMPARE_EARLY, COMPARE_LATE = None, None


def pair():
	random.seed(42)
	data1 = [random.randint(0, MAX) for _ in range(N)]
	data2 = data1[:len(data1) // 2]
	data2.extend(random.randint(0, MAX) for _ in range(N // 2))
	return data1, data2


def comparison_data(data):
	"""Return equal and representative non-equal comparison operands."""
	equal = sorted(set(data))
	cardinality = equal[:-1]
	used = set(equal)

	early = equal[1:]
	replacement = equal[0] + 1
	while replacement in used:
		replacement += 1
	early.append(replacement)
	early.sort()

	late = equal[:-1]
	replacement = equal[-1] + 1
	while replacement in used:
		replacement += 1
	late.append(replacement)
	return equal, cardinality, early, late


def bench_init():
	a = timeit.Timer('set(DATA1)',
			setup='from __main__ import DATA1').timeit(number=M)
	b = timeit.Timer('rb = RoaringBitmap(DATA1)',
			setup='from __main__ import DATA1; '
				'from roaringbitmap import RoaringBitmap; '
				).timeit(number=M)
	return a, b


def bench_initsort():
	a = timeit.Timer('set(data)',
			setup='from __main__ import DATA1; '
				'data = sorted(DATA1)').timeit(number=M)
	b = timeit.Timer('rb = RoaringBitmap(data)',
			setup='from __main__ import DATA1; '
				'from roaringbitmap import RoaringBitmap; '
				'data = sorted(DATA1)'
				).timeit(number=M)
	return a, b


def bench_eq_identity():
	a = timeit.Timer('ref == ref',
			setup='from __main__ import COMPARE_EQUAL; '
				'ref = set(COMPARE_EQUAL)').timeit(number=M)
	b = timeit.Timer('rb == rb',
			setup='from __main__ import COMPARE_EQUAL; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(COMPARE_EQUAL)').timeit(number=M)
	return a, b


def bench_eq_equal():
	a = timeit.Timer('ref == ref2',
			setup='from __main__ import COMPARE_EQUAL; '
				'ref = set(COMPARE_EQUAL); '
				'ref2 = set(COMPARE_EQUAL)').timeit(number=M)
	b = timeit.Timer('rb == rb2',
			setup='from __main__ import COMPARE_EQUAL; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(COMPARE_EQUAL); '
				'rb2 = RoaringBitmap(COMPARE_EQUAL)').timeit(number=M)
	return a, b


def bench_neq_cardinality():
	a = timeit.Timer('ref != ref2',
			setup='from __main__ import COMPARE_EQUAL, COMPARE_CARDINALITY; '
				'ref = set(COMPARE_EQUAL); '
				'ref2 = set(COMPARE_CARDINALITY)').timeit(number=M)
	b = timeit.Timer('rb != rb2',
			setup='from __main__ import COMPARE_EQUAL, COMPARE_CARDINALITY; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(COMPARE_EQUAL); '
				'rb2 = RoaringBitmap(COMPARE_CARDINALITY)').timeit(number=M)
	return a, b


def bench_neq_early():
	a = timeit.Timer('ref != ref2',
			setup='from __main__ import COMPARE_EQUAL, COMPARE_EARLY; '
				'ref = set(COMPARE_EQUAL); ref2 = set(COMPARE_EARLY)').timeit(
					number=M)
	b = timeit.Timer('rb != rb2',
			setup='from __main__ import COMPARE_EQUAL, COMPARE_EARLY; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(COMPARE_EQUAL); '
				'rb2 = RoaringBitmap(COMPARE_EARLY)').timeit(number=M)
	return a, b


def bench_neq_late():
	a = timeit.Timer('ref != ref2',
			setup='from __main__ import COMPARE_EQUAL, COMPARE_LATE; '
				'ref = set(COMPARE_EQUAL); ref2 = set(COMPARE_LATE)').timeit(
					number=M)
	b = timeit.Timer('rb != rb2',
			setup='from __main__ import COMPARE_EQUAL, COMPARE_LATE; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(COMPARE_EQUAL); '
				'rb2 = RoaringBitmap(COMPARE_LATE)').timeit(number=M)
	return a, b


def bench_and():
	a = timeit.Timer('ref & ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb & rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_or():
	a = timeit.Timer('ref | ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb | rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_xor():
	a = timeit.Timer('ref ^ ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb ^ rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_sub():
	a = timeit.Timer('ref - ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb - rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_iand():
	aa = [timeit.Timer('ref &= ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=1)
			for _ in range(M)]
	bb = [timeit.Timer('rb &= rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=1)
			for _ in range(M)]
	return sum(aa) / M, sum(bb) / M


def bench_ior():
	aa = [timeit.Timer('ref |= ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=1)
			for _ in range(M)]
	bb = [timeit.Timer('rb |= rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=1)
			for _ in range(M)]
	return sum(aa) / M, sum(bb) / M


def bench_ixor():
	aa = [timeit.Timer('ref ^= ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=1)
			for _ in range(M)]
	bb = [timeit.Timer('rb ^= rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=1)
			for _ in range(M)]
	return sum(aa) / M, sum(bb) / M


def bench_isub():
	aa = [timeit.Timer('ref -= ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=1)
			for _ in range(M)]
	bb = [timeit.Timer('rb -= rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=1)
			for _ in range(M)]
	return sum(aa) / M, sum(bb) / M


def bench_andlen():
	a = timeit.Timer('len(ref & ref2)',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb.intersection_len(rb2)',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_orlen():
	a = timeit.Timer('len(ref | ref2)',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb.union_len(rb2)',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_jaccard():
	a = timeit.Timer('1 - (len(ref & ref2) / len(ref | ref2))',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb.jaccard_dist(rb2)',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def main():
	global N, MAX, DATA1, DATA2
	global COMPARE_EQUAL, COMPARE_CARDINALITY, COMPARE_EARLY, COMPARE_LATE
	for x in range(3):
		if x == 0:  # benchmark positive blocks
			print('small sparse set')
			N = 200  # number of random elements
			MAX = 40000  # range of elements
		elif x == 1:  # benchmark bitmap blocks
			print('medium load factor')
			N = 59392
			MAX = 118784
		elif x == 2:  # benchmark inverted blocks
			print('dense set / high load factor')
			N = 40000 - 200
			MAX = 40000
		elif x == 3:  # benchmark large number of small blocks
			print('large sparse set')  # don't use RoaringBitmap for this case
			N = 1 << 12
			MAX = 1 << 31
		DATA1, DATA2 = pair()
		(COMPARE_EQUAL, COMPARE_CARDINALITY,
				COMPARE_EARLY, COMPARE_LATE) = comparison_data(DATA1)

		fmt = '%16s %8s %16s %8s'
		numfmt = '%8.3g'
		print('%d runs with sets of %d random elements n s.t. 0 <= n < %d' % (
				M, N, MAX))
		print(fmt % ('', 'set()', 'RoaringBitmap()', 'ratio'))
		for func in (bench_init, bench_initsort,
				bench_and, bench_or, bench_xor, bench_sub,
				bench_iand, bench_ior, bench_ixor, bench_isub,
				bench_eq_identity, bench_eq_equal,
				bench_neq_cardinality, bench_neq_early, bench_neq_late,
				# bench_andlen, bench_orlen,
				bench_jaccard):
			a, b = func()
			ratio = a / b
			print(fmt % (func.__name__.split('_', 1)[1].ljust(12),
					numfmt % a, numfmt % b,
					(numfmt % ratio) if ratio < 100 else int(ratio)))
		print()


if __name__ == '__main__':
	main()
