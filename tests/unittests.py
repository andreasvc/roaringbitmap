"""Unit tests for roaringbitmap"""
from __future__ import division, print_function, absolute_import, \
        unicode_literals
import random
import pytest
try:
	from itertools import zip_longest
except ImportError:
	from itertools import izip_longest as zip_longest
from roaringbitmap import RoaringBitmap

# (numitems, maxnum)
PARAMS = [(200, 40000),
	(40000 - 200, 40000),
	(59392, 118784),
	(40000, 1 << 31)]


@pytest.fixture(scope='module')
def single():
	random.seed(42)
	result = []
	for elements, maxnum in PARAMS:
		result.append([random.randint(0, maxnum) for _ in range(elements)])
	return result


@pytest.fixture(scope='module')
def pair():
	random.seed(42)
	result = []
	for a in single():
		for elements, maxnum in PARAMS:
			b = a[:len(a) // 2]
			b.extend(random.randint(0, maxnum) for _ in range(elements // 2))
			result.append((a, b))
	return result


class Test_roaringbitmap(object):
	def test_init(self, single):
		for data in single:
			ref = set(data)
			rb = RoaringBitmap(data)
			assert ref == set(rb)

	def test_add(self, single):
		for data in single:
			ref = set()
			rb = RoaringBitmap()
			for n in sorted(data):
				ref.add(n)
				rb.add(n)
			assert set(ref) == set(rb)
			assert rb == ref
			with pytest.raises(OverflowError):
				rb.add(-1)
				rb.add(1 << 32)
			rb.add(0)
			rb.add((1 << 32) - 1)

	def test_discard(self, single):
		for data in single:
			ref = set()
			rb = RoaringBitmap()
			for n in sorted(data):
				ref.add(n)
				rb.add(n)
			for n in sorted(data):
				ref.discard(n)
				rb.discard(n)
			assert len(ref) == 0
			assert len(rb) == 0
			assert set(ref) == set(rb)
			assert rb == ref

	def test_contains(self, single):
		for data in single:
			ref = set(data)
			rb = RoaringBitmap(data)
			for a in data:
				assert a in ref
				assert a in rb
			for a in set(range(20000)) - set(data):
				assert a not in ref
				assert a not in rb

	def test_eq(self, single):
		for data in single:
			ref, ref2 = set(data), set(data)
			rb, rb2 = RoaringBitmap(data), RoaringBitmap(data)
			assert ref == ref2
			assert rb == rb2
			a = ref == ref2
			b = rb == rb2
			assert a == b

	def test_neq(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref != ref2
			assert rb != rb2
			a = ref != ref2
			b = rb != rb2
			assert a == b

	def test_iter(self, single):
		for data in single:
			rb = RoaringBitmap(data)
			assert list(iter(rb)) == sorted(set(data))

	def test_reversed(self, single):
		for data in single:
			rb = RoaringBitmap(data)
			for a, b in zip_longest(reversed(rb), reversed(sorted(set(data)))):
				assert a == b

	def test_iand(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref &= ref2
			rb &= rb2
			assert set(ref) == set(rb)
			assert rb == ref

	def test_ior(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref |= ref2
			rb |= rb2
			assert set(ref) == set(rb)
			assert rb == ref

	def test_and(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref & ref2 == set(rb & rb2)

	def test_or(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref | ref2 == set(rb | rb2)

	def test_xor(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref ^ ref2 == set(rb ^ rb2)

	def test_sub(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref - ref2 == set(rb - rb2)

	def test_ixor(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref ^= ref2
			rb ^= rb2
			assert len(ref) == len(rb)
			assert ref == set(rb)

	def test_isub(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref -= ref2
			rb -= rb2
			assert len(ref) <= len(set(data1))
			assert len(rb) <= len(set(data1))
			assert len(ref) == len(rb)
			assert ref == set(rb)

	def test_subset(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert not ref <= ref2
			assert not set(rb) <= ref2
			assert not rb <= rb2
			k = len(data2) // 2
			ref, rb = set(data2[:k]), RoaringBitmap(data2[:k])
			assert ref <= ref2
			assert set(rb) <= ref2
			assert rb <= rb2

	def test_disjoint(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert not ref.isdisjoint(ref2)
			assert not rb.isdisjoint(rb2)
			data3 = [a for a in data2 if a not in ref]
			ref3, rb3 = set(data3), RoaringBitmap(data3)
			assert ref.isdisjoint(ref3)
			assert rb.isdisjoint(rb3)

	def test_aggregateand(self):
		data = [[random.randint(0, 1000) for _ in range(2000)]
				for _ in range(10)]
		ref = set(data[0])
		ref.intersection_update(*[set(a) for a in data[1:]])
		rb = RoaringBitmap(data[0])
		rb.intersection_update(*[RoaringBitmap(a) for a in data[1:]])
		assert ref == set(rb)
		assert rb == ref

	def test_aggregateor(self):
		data = [[random.randint(0, 1000) for _ in range(2000)]
				for _ in range(10)]
		ref = set(data[0])
		ref.update(*[set(a) for a in data[1:]])
		rb = RoaringBitmap(data[0])
		rb.update(*[RoaringBitmap(a) for a in data[1:]])
		assert ref == set(rb)
		assert rb == ref

	def test_rank(self, single):
		for data in single:
			ref = sorted(set(data))
			rb = RoaringBitmap(data)
			print(len(rb))
			for _ in range(10):
				x = random.choice(ref)
				assert x in rb
				assert rb.rank(x) == ref.index(x) + 1

	def test_select(self, single):
		for data in single:
			ref = sorted(set(data))
			rb = RoaringBitmap(data)
			lrb = list(rb)
			idx = [random.randint(0, len(ref)) for _ in range(10)]
			for i in idx:
				assert lrb[i] == ref[i]
				assert rb.select(i) in rb
				assert rb.select(i) == ref[i]
				assert rb.rank(rb.select(i)) - 1 == i
				if rb.select(i) + 1 in rb:
					assert rb.rank(rb.select(i) + 1) - 1 == i + 1
				else:
					assert rb.rank(rb.select(i) + 1) - 1 == i

	def test_rank2(self):
		rb = RoaringBitmap(range(0, 100000, 7))
		rb.update(range(100000, 200000, 1000))
		print(len(rb))
		for k in range(100000):
			assert rb.rank(k) == 1 + k // 7
		for k in range(100000, 200000):
			assert rb.rank(k) == 1 + 100000 // 7 + 1 + (k - 100000) // 1000

	def test_select2(self):
		gap = 1
		while gap <= 1024:
			rb = RoaringBitmap(range(0, 100000, gap))
			for k in range(0, 100000 // gap):
				assert rb.select(k) == k * gap
			gap *= 2
