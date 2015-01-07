"""Unit tests for roaringbitmap"""
from __future__ import division, print_function, absolute_import, \
        unicode_literals
import random
import pytest
from roaringbitmap import roaringbitmap

N = int(1e5)  # number of random elements to generate
MAX = 1 << 20  # with each element 0 < n < MAX


@pytest.fixture(scope='module')
def pair():
	random.seed(42)
	data1 = [random.randint(0, MAX) for _ in range(N)]
	data2 = data1[:len(data1) // 2]
	data2.extend(random.randint(0, MAX) for _ in range(N // 2))
	return data1, data2


class Test_roaringbitmap(object):
	def test_init(self, pair):
		data, _ = pair
		ref = set(data)
		rb = roaringbitmap.RoaringBitmap(data)
		assert ref == set(rb)

	def test_eq(self, pair):
		data, _ = pair
		ref = set(data)
		ref2 = set(data)
		rb = roaringbitmap.RoaringBitmap(data)
		rb2 = roaringbitmap.RoaringBitmap(data)
		assert ref == ref2
		assert rb == rb2
		a = ref == ref2
		b = rb == rb2
		assert a == b

	def test_neq(self, pair):
		data1, data2 = pair
		ref = set(data1)
		ref2 = set(data2)
		rb = roaringbitmap.RoaringBitmap(data1)
		rb2 = roaringbitmap.RoaringBitmap(data2)
		assert ref != ref2
		assert rb != rb2
		a = ref != ref2
		b = rb != rb2
		assert a == b

	def test_add(self, pair):
		data, _ = pair
		ref = set()
		rb = roaringbitmap.RoaringBitmap()
		for n in sorted(data):
			ref.add(n)
			rb.add(n)
		assert ref == rb

	def test_discard(self, pair):
		data, _ = pair
		ref = set()
		rb = roaringbitmap.RoaringBitmap()
		for n in sorted(data):
			ref.add(n)
			rb.add(n)
		for n in sorted(data):
			ref.discard(n)
			rb.discard(n)
		assert len(ref) == 0
		assert len(rb) == 0
		assert ref == rb

	def test_and(self, pair):
		data1, data2 = pair
		ref = set(data1)
		ref2 = set(data2)
		rb = roaringbitmap.RoaringBitmap(data1)
		rb2 = roaringbitmap.RoaringBitmap(data2)
		assert ref & ref2 == rb & rb2

	def test_iand(self, pair):
		data1, data2 = pair
		ref = set(data1)
		ref2 = set(data2)
		rb = roaringbitmap.RoaringBitmap(data1)
		rb2 = roaringbitmap.RoaringBitmap(data2)
		ref &= ref2
		rb &= rb2
		assert ref == rb

	def test_or(self, pair):
		data1, data2 = pair
		ref = set(data1)
		ref2 = set(data2)
		rb = roaringbitmap.RoaringBitmap(data1)
		rb2 = roaringbitmap.RoaringBitmap(data2)
		assert ref | ref2 == rb | rb2

	def test_ior(self, pair):
		data1, data2 = pair
		ref = set(data1)
		ref2 = set(data2)
		rb = roaringbitmap.RoaringBitmap(data1)
		rb2 = roaringbitmap.RoaringBitmap(data2)
		ref |= ref2
		rb |= rb2
		assert ref == rb
