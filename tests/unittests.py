"""Unit tests for roaringbitmap"""
from __future__ import division, print_function, absolute_import, \
        unicode_literals
import random
import pytest
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
			assert ref == rb
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
			assert ref == rb

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

	def test_iand(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref &= ref2
			rb &= rb2
			assert ref == rb

	def test_ior(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref |= ref2
			rb |= rb2
			assert ref == rb

	def test_and(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref & ref2 == rb & rb2

	def test_or(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref | ref2 == rb | rb2

	def test_xor(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref ^ ref2 == rb ^ rb2

	def test_sub(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref - ref2 == rb - rb2

	def test_ixor(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref ^= ref2
			rb ^= rb2
			assert len(ref) == len(rb)
			assert ref == rb

	def test_isub(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref -= ref2
			rb -= rb2
			assert len(ref) <= len(set(data1))
			assert len(rb) <= len(set(data1))
			assert len(ref) == len(rb)
			assert ref == rb
