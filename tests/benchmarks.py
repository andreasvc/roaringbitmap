"""Benchmarks for roaringbitmap"""
from __future__ import division, print_function, absolute_import, \
        unicode_literals
import random
import timeit

N = 1 << 17  # number of random elements
M = 100  # number of test runs
MAX = 1 << 20  # range of elements
DATA1, DATA2 = None, None


def pair():
	random.seed(42)
	data1 = [random.randint(0, MAX) for _ in range(N)]
	data2 = data1[:len(data1) // 2]
	data2.extend(random.randint(0, MAX) for _ in range(N // 2))
	return data1, data2


def bench_init():
	a = timeit.Timer('set(DATA1)',
			setup='from __main__ import DATA1').timeit(number=M)
	b = timeit.Timer('rb = RoaringBitmap(DATA1)',
			setup='from __main__ import DATA1; '
				'from roaringbitmap import RoaringBitmap; '
				).timeit(number=M)
	return a, b


def bench_eq():
	a = timeit.Timer('ref == ref2',
			setup='from __main__ import DATA1; '
				'ref = set(DATA1); ref2 = set(DATA1)').timeit(number=M)
	b = timeit.Timer('rb == rb2',
			setup='from __main__ import DATA1; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA1)').timeit(number=M)
	return a, b


def bench_neq():
	a = timeit.Timer('ref == ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb == rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
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


def main():
	global N, MAX, DATA1, DATA2
	for x in range(3):
		if x == 0:
			print('sparse set')
			N = 200
			MAX = 40000
		elif x == 1:
			print('dense set / high load factor')
			N = 40000 - 200
			MAX = 40000
		elif x == 2:
			print('medium load factor')
			N = 59392
			MAX = 118784
		elif x == 3:
			print('large range')
			N = 1 << 17  # number of random elements
			MAX = 1 << 31
		DATA1, DATA2 = pair()

		fmt = '%8s %8s %16s %8s'
		numfmt = '%8.3g'
		print('%d runs with sets of %d random elements n s.t. 0 <= n < %d' % (
				M, N, MAX))
		print(fmt % ('', 'set()', 'RoaringBitmap()', 'ratio'))
		for func in (bench_init,
				bench_and,  # bench_iand,
				bench_or,  # bench_ior,
				bench_xor,  # bench_ixor,
				bench_sub,  # bench_isub,
				bench_eq, bench_neq):
			a, b = func()
			ratio = a / b
			print(fmt % (func.__name__.split('_', 1)[1].ljust(8),
					numfmt % a, numfmt % b,
					(numfmt % ratio) if ratio < 100 else int(ratio)))
		print()

if __name__ == '__main__':
	main()
