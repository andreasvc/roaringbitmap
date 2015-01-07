"""Benchmarks for roaringbitmap"""
from __future__ import division, print_function, absolute_import, \
        unicode_literals
import random
import timeit
from roaringbitmap import roaringbitmap

N = int(1e5)  # number of random elements
M = 100  # number of test runs
MAX = 1 << 20  # range of elements


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
				'from roaringbitmap.roaringbitmap import RoaringBitmap; '
				).timeit(number=M)
	return a, b


def bench_eq():
	a = timeit.Timer('ref == ref2',
			setup='from __main__ import DATA1; '
				'ref = set(DATA1); ref2 = set(DATA1)').timeit(number=M)
	b = timeit.Timer('rb == rb2',
			setup='from __main__ import DATA1; '
				'from roaringbitmap.roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA1)').timeit(number=M)
	return a, b


def bench_neq():
	a = timeit.Timer('ref == ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb == rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap.roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_and():
	a = timeit.Timer('ref & ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb & rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap.roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def bench_iand():
	a = timeit.Timer('ref &= ref2',
			setup='from __main__ import DATA1, DATA2; '
				'ref = set(DATA1); ref2 = set(DATA2)').timeit(number=M)
	b = timeit.Timer('rb &= rb2',
			setup='from __main__ import DATA1, DATA2; '
				'from roaringbitmap.roaringbitmap import RoaringBitmap; '
				'rb = RoaringBitmap(DATA1); '
				'rb2 = RoaringBitmap(DATA2)').timeit(number=M)
	return a, b


def main():
	fmt = '%8s %8s %16s %8s'
	numfmt = '%5.3g'
	print('Sets with %d random elements; %d runs' % (N, M))
	print(fmt % ('', 'set()', 'RoaringBitmap()', 'ratio'))
	for func in (bench_init, bench_iand, bench_and, bench_eq, bench_neq):
		a, b = func()
		print(fmt % (func.__name__.split('_', 1)[1].ljust(8),
				numfmt % a, numfmt % b, numfmt % (a / b)))

DATA1, DATA2 = pair()

if __name__ == '__main__':
	main()
