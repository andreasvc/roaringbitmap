"""Unit tests for roaringbitmap"""
from __future__ import division, absolute_import, unicode_literals
import sys
import array
import pytest
import pickle
import tempfile
from random import seed, choice, sample, randint
try:
	import faulthandler
	faulthandler.enable()
except ImportError:
	pass
from roaringbitmap import (RoaringBitmap, ImmutableRoaringBitmap,
		MultiRoaringBitmap, bitcounttests, aligned_malloc_tests, mmaptests)
PY2 = sys.version_info[0] == 2
if PY2:
	range = xrange
	from itertools import izip_longest as zip_longest
else:
	from itertools import zip_longest

# (numitems, maxnum)
PARAMS = [
		('empty', 0, (1 << 16) - 1),
		('positive', 200, (1 << 16) - 1),
		('dense', 5000, (1 << 16) - 1),
		('inverted', 4000, (1 << 16) - 1),
		('many keys', 4000, (1 << 25) - 1)
		]


def _single():
	seed(42)
	result = []
	for name, elements, maxnum in PARAMS:
		if name == 'inverted':
			result.append((name, list(set(range(1 << 16))
				- {randint(0, maxnum) for _ in range(elements)})))
		else:
			result.append((name, sorted(
				randint(0, maxnum) for _ in range(elements))))
	return result


@pytest.fixture(scope='module')
def single():
	return _single()


@pytest.fixture(scope='module')
def pair():
	result = []
	for name1, a in _single():
		for name2, b in _single():
			if name2 != 'empty':
				b = sorted(b[:len(b) // 2] + a[len(a) // 2:])
			result.append((name1 + ':' + name2, a, b))
	return result


@pytest.fixture(scope='module')
def multi():
	a = sorted(randint(0, 2000)
			for _ in range(randint(100, 2000)))
	result = [sorted([randint(0, 2000)
			for _ in range(randint(100, 2000))] + a)
			for _ in range(100)]
	return result


def abbr(a):
	return a[:500] + '...' + a[-500:]


def test_fixtures(single):
	for name, data in single:
		rb = RoaringBitmap(data)
		if name == 'many keys':
			assert len(rb._keys()) > 100
		elif name == 'empty':
			assert len(rb) == 0
		else:
			assert name[0].upper() in rb.debuginfo()


def test_bitcount():
	assert bitcounttests()


def test_aligned_malloc():
	assert aligned_malloc_tests()


def test_mmap():
	assert mmaptests()


class Test_roaringbitmap(object):
	def test_inittrivial(self):
		data = list(range(5))
		ref = set(data)
		rb = RoaringBitmap(data)
		rb._checkconsistency()
		assert ref == rb

	def test_initsorted(self, single):
		for name, data in single:
			ref = set(sorted(data))
			rb = RoaringBitmap(sorted(data))
			rb._checkconsistency()
			assert ref == rb, name

	def test_initunsorted(self, single):
		for name, data in single:
			ref = set(data)
			rb = RoaringBitmap(data)
			rb._checkconsistency()
			assert ref == rb, name

	def test_inititerator(self, single):
		for name, data in single:
			ref = set(a for a in data)
			rb = RoaringBitmap(a for a in data)
			rb._checkconsistency()
			assert ref == rb, name

	def test_initrange(self):
		# creates a positive, dense, and inverted block, respectively
		for n in [400, 6000, 61241]:
			ref = set(range(23, n))
			rb = RoaringBitmap(range(23, n))
			rb._checkconsistency()
			assert ref == rb, ('range(23, %d)' % n)

	def test_initrangestep(self):
		# creates a positive, dense, and inverted block, respectively
		for n in [400, 6000, 61241]:
			for step in (2, 7, 113):
				ref = set(range(23, n * step, step))
				rb = RoaringBitmap(range(23, n * step, step))
				rb._checkconsistency()
				assert ref == rb, ('range(23, %d, %d)' % (n, step))
		n = 100 * (1 << 16)
		step = (1 << 16) + 7
		ref = set(range(23, n, step))
		rb = RoaringBitmap(range(23, n, step))
		rb._checkconsistency()
		assert ref == rb, ('range(23, %d, %d)' % (n, step))

	def test_inititerableallset(self):
		rb = RoaringBitmap(list(range(0, 0xffff + 1)))
		assert len(rb) == 0xffff + 1

	def test_add(self, single):
		for name, data in single:
			ref = set()
			rb = RoaringBitmap()
			for n in sorted(data):
				ref.add(n)
				rb.add(n)
			assert rb == ref, name
			with pytest.raises(OverflowError):
				rb.add(-1)
				rb.add(1 << 32)
			rb.add(0)
			rb.add((1 << 32) - 1)
			rb._checkconsistency()

	def test_discard(self, single):
		for name, data in single:
			ref = set()
			rb = RoaringBitmap()
			for n in sorted(data):
				ref.add(n)
				rb.add(n)
			for n in sorted(data):
				ref.discard(n)
				rb.discard(n)
			rb._checkconsistency()
			assert len(ref) == 0, name
			assert len(rb) == 0, name
			assert rb == ref, name

	def test_pop(self):
		rb = RoaringBitmap([60748, 28806, 54664, 28597, 58922, 75684, 56364,
			67421, 52608, 55686, 10427, 48506, 64363, 14506, 73077, 59035,
			70246, 19875, 73145, 40225, 58664, 6597, 65554, 73102, 26636,
			74227, 59566, 19023])
		while rb:
			rb.pop()
		rb._checkconsistency()
		assert len(rb) == 0

	def test_contains(self, single):
		for name, data in single:
			ref = set(data)
			rb = RoaringBitmap(data)
			for a in data:
				assert a in ref, name
				assert a in rb, name
			for a in set(range(20000)) - set(data):
				assert a not in ref, name
				assert a not in rb, name
			rb._checkconsistency()

	def test_eq(self, single):
		for name, data in single:
			ref, ref2 = set(data), set(data)
			rb, rb2 = RoaringBitmap(data), RoaringBitmap(data)
			assert (ref == ref2) == (rb == rb2), name

	def test_neq(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert (ref != ref2) == (rb != rb2), name

	def test_iter(self, single):
		for name, data in single:
			rb = RoaringBitmap(data)
			assert list(iter(rb)) == sorted(set(data)), name

	def test_reversed(self, single):
		for name, data in single:
			rb = RoaringBitmap(data)
			for a, b in zip_longest(reversed(rb), reversed(sorted(set(data)))):
				assert a == b, name

	def test_iand(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref &= ref2
			rb &= rb2
			rb._checkconsistency()
			assert rb == ref, name

	def test_ior(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref |= ref2
			rb |= rb2
			rb._checkconsistency()
			assert rb == ref, name

	def test_ixor(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref ^= ref2
			rb ^= rb2
			rb._checkconsistency()
			assert len(ref) == len(rb), name
			assert ref == rb, name

	def test_isub(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref -= ref2
			rb -= rb2
			rb._checkconsistency()
			assert len(ref) <= len(set(data1))
			assert len(rb) <= len(set(data1)), name
			assert len(ref) == len(rb), name
			assert ref == rb, name

	def test_and(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref & ref2 == set(rb & rb2), name

	def test_or(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref | ref2 == set(rb | rb2), name

	def test_xor(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref ^ ref2 == set(rb ^ rb2), name

	def test_sub(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert ref - ref2 == set(rb - rb2), name

	def test_subset(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			refans = ref <= ref2
			assert (set(rb) <= ref2) == refans, name
			assert (rb <= rb2) == refans, name
			k = len(data2) // 2
			ref, rb = set(data2[:k]), RoaringBitmap(data2[:k])
			refans = ref <= ref2
			assert (set(rb) <= ref2) == refans, name
			assert (ref <= set(rb2)) == refans, name
			assert (rb <= rb2) == refans, (name, rb.debuginfo())

	def test_disjoint(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			refans = ref.isdisjoint(ref2)
			assert rb.isdisjoint(rb2) == refans, name
			data3 = [a for a in data2 if a not in ref]
			ref3, rb3 = set(data3), RoaringBitmap(data3)
			refans2 = ref.isdisjoint(ref3)
			assert rb.isdisjoint(rb3) == refans2, name

	def test_clamp(self, single):
		for name, data in single:
			if len(data) == 0:
				continue
			a, b = sorted(sample(data, 2))
			ref = set(data).intersection(range(a, b))
			rb = RoaringBitmap(data).intersection(range(a, b))
			rb2 = RoaringBitmap(data).clamp(a, b)
			assert a <= rb2.min() and rb2.max() < b, name
			assert ref == rb2, (name, a, b)
			assert rb == rb2, (name, a, b)

	def test_clamp_issue12(self):
		b = RoaringBitmap([1, 2, 3])
		assert b.clamp(0, 65536) == b
		assert b.clamp(0, 65537) == b
		assert b.clamp(0, 65538) == b
		assert b.clamp(0, 65539) == b

	def test_clamp2(self):
		a = RoaringBitmap([0x00010001])
		b = RoaringBitmap([0x00030003, 0x00050005])
		c = RoaringBitmap([0x00070007])
		x = a | b | c
		assert x.clamp(0, 0x000FFFFF) == x
		assert x.clamp(0x000200FF, 0x000FFFFF) == b | c
		assert x.clamp(0x00030003, 0x000FFFFF) == b | c
		assert x.clamp(0, 0x00060006) == a | b
		assert x.clamp(0, 0x00050006) == a | b
		assert x.clamp(0, 0x00050005) == a | RoaringBitmap([0x00030003])

	def test_aggregateand(self, multi):
		ref = set(multi[0])
		ref.intersection_update(*[set(a) for a in multi[1:]])
		rb = RoaringBitmap(multi[0])
		rb.intersection_update(*[RoaringBitmap(a) for a in multi[1:]])
		rb._checkconsistency()
		assert rb == ref

	def test_aggregateor(self, multi):
		ref = set(multi[0])
		ref.update(*[set(a) for a in multi[1:]])
		rb = RoaringBitmap(multi[0])
		rb.update(*[RoaringBitmap(a) for a in multi[1:]])
		rb._checkconsistency()
		assert rb == ref

	def test_andlen(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert len(rb & rb2) == rb.intersection_len(rb2), name
			assert len(ref & ref2) == rb.intersection_len(rb2), name

	def test_orlen(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert len(ref | ref2) == rb.union_len(rb2), name
			assert len(rb | rb2) == rb.union_len(rb2), name

	def test_jaccard_dist(self, pair):
		for name, data1, data2 in pair:
			if len(data1) == 0 and len(data2) == 0:
				continue
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert len(ref & ref2) / float(len(ref | ref2)) == pytest.approx(
					rb.intersection_len(rb2) / float(rb.union_len(rb2))), name
			assert (1 - (len(ref & ref2) / float(len(ref | ref2)))
					== pytest.approx(rb.jaccard_dist(rb2))), name

	def test_rank(self, single):
		for name, data in single:
			if len(data) == 0:
				continue
			ref = sorted(set(data))
			rb = RoaringBitmap(data)
			for _ in range(10):
				x = choice(ref)
				assert x in rb, name
				assert rb.rank(x) == ref.index(x) + 1, name

	def test_select(self, single):
		for name, data in single:
			if len(data) == 0:
				continue
			ref = sorted(set(data))
			rb = RoaringBitmap(data)
			lrb = list(rb)
			idx = [randint(0, len(ref) - 1) for _ in range(10)]
			for i in idx:
				assert lrb[i] == ref[i], (name, i, len(ref))
				assert rb.select(i) in rb, name
				assert rb.select(i) == ref[i], name
				assert rb[i] == ref[i], name
				assert rb.rank(rb.select(i)) - 1 == i, name
				if rb.select(i) + 1 in rb:
					assert rb.rank(rb.select(i) + 1) - 1 == i + 1, name
				else:
					assert rb.rank(rb.select(i) + 1) - 1 == i, name

	def test_rank2(self):
		rb = RoaringBitmap(range(0, 100000, 7))
		rb.update(range(100000, 200000, 1000))
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

	def test_select_issue15(self):
		rb = RoaringBitmap(range(0x10000, 0x1ffff + 1))
		assert rb[0] == 0x10000
		rb.discard(0x10010)
		assert rb[0] == 0x10000
		rb = RoaringBitmap(range(0x10, 0xffff + 1))
		assert rb[0] == 0x10, rb.debuginfo(True)
		rb = RoaringBitmap(range(0x10010, 0x1ffff + 1))
		assert rb[0] == 0x10010, rb.debuginfo(True)
		lst = list(range(1, 0xccbb))
		lst.extend(range(0xcccc, 0xfffc))
		rb = RoaringBitmap(lst)
		for n in (0, 0xcccc, -1):
			assert lst[n] == rb[n], (n, lst[n], rb[n])

	def test_pickle(self, single):
		for name, data in single:
			rb = RoaringBitmap(data)
			rb_pickled = pickle.dumps(rb, protocol=-1)
			rb_unpickled = pickle.loads(rb_pickled)
			rb._checkconsistency()
			assert rb_unpickled == rb, name

	def test_invalid(self):
		with pytest.raises(TypeError):
			rb = RoaringBitmap([1, 2, 'a'])
		with pytest.raises(TypeError):
			RoaringBitmap([1, 2]) < [1, 2, 3]

	def test_slices(self):  # issue 20
		ref = list(range(10))
		rb = RoaringBitmap(range(10))
		assert list(rb[::2]) == ref[::2]
		with pytest.raises(ValueError):
			_ = rb[::-2]
		with pytest.raises(ValueError):
			_ = rb[::0]
		del rb[::2]
		del ref[::2]
		assert list(rb) == ref

	def test_minmax(self):
		rb = RoaringBitmap(range(0, 61440))
		assert rb.min() == 0
		assert rb.max() == 61439
		rb1 = RoaringBitmap(range(0, 61441))
		assert rb1.min() == 0
		assert rb1.max() == 61440
		assert rb1[61440] == 61440
		assert list(rb1)[61440] == 61440

	def test_issue19(self):
		a = RoaringBitmap()
		b = RoaringBitmap(range(4095))
		c = RoaringBitmap(range(2))
		a |= b
		a |= c
		assert len(a - b - c) == 0
		assert len((b | c) - b - c) == 0

	def test_issue22(self):
		rb = RoaringBitmap(range(0, 61440))
		rb1 = RoaringBitmap(range(0, 61441))
		assert len(rb ^ rb) == 0
		assert len(rb - rb) == 0
		assert len(rb1 ^ rb1) == 0
		assert len(rb1 - rb1) == 0
		assert len(~rb) == 0
		assert len(~rb1) == 0

		rb1 = RoaringBitmap(range(0, 61441))
		assert len(rb ^ rb) == 0
		rb1 ^= rb1
		assert len(rb1) == 0

		rb1 = RoaringBitmap(range(0, 61441))
		rb1 -= rb1
		assert len(rb1) == 0

	def test_issue24(self):
		r = RoaringBitmap(range(131071))
		assert r.pop() == 131070
		assert r.pop() == 131069

		rr = r - RoaringBitmap([130752])
		assert 130752 not in rr
		assert rr.pop() == 131068

		r.difference_update(RoaringBitmap([130752]))
		assert 130752 not in r
		assert r.pop() == 131068

	def test_issue25(self):
		r = RoaringBitmap({1})
		r.intersection_update(RoaringBitmap([]))
		assert len(r) == 0

	def test_issue28(self):
		rbm = RoaringBitmap()
		rbm.add(3995084765)
		r = rbm.clamp(0, 8388607)
		assert len(r) == 0

	def test_issue34(self):
		seed(232992)
		set_a = sample(range(235342), k=169308)
		set_b = sample(range(255999), k=255713)
		rba = RoaringBitmap(set_a)
		rbb = RoaringBitmap(set_b)
		assert rba - rbb == set(set_a) - set(set_b)
		rba -= rbb
		assert rba == set(set_a) - set(set_b)


class Test_immutablerb(object):
	def test_inittrivial(self):
		data = list(range(5))
		ref = set(data)
		rb = ImmutableRoaringBitmap(data)
		rb._checkconsistency()
		assert ref == rb
		assert type(rb) == ImmutableRoaringBitmap

	def test_initsorted(self, single):
		for name, data in single:
			ref = set(sorted(data))
			rb = ImmutableRoaringBitmap(sorted(data))
			rb._checkconsistency()
			assert ref == rb, name

	def test_initunsorted(self, single):
		for name, data in single:
			ref = set(data)
			rb = ImmutableRoaringBitmap(data)
			rb._checkconsistency()
			assert ref == rb, name

	def test_inititerator(self, single):
		for name, data in single:
			ref = set(a for a in data)
			rb = ImmutableRoaringBitmap(a for a in data)
			rb._checkconsistency()
			assert ref == rb, name

	def test_initrange(self):
		# creates a positive, dense, and inverted block, respectively
		for n in [400, 6000, 61241]:
			ref = set(range(23, n))
			rb = ImmutableRoaringBitmap(range(23, n))
			rb._checkconsistency()
			assert ref == rb, n

	def test_initrb(self):
		r = RoaringBitmap(range(5))
		i = ImmutableRoaringBitmap(r)
		r = RoaringBitmap(i)
		assert r == i

		i = ImmutableRoaringBitmap(range(5))
		r = RoaringBitmap(i)
		assert r == i

	def test_pickle(self, single):
		for name, data in single:
			rb = ImmutableRoaringBitmap(data)
			rb_pickled = pickle.dumps(rb, protocol=-1)
			rb_unpickled = pickle.loads(rb_pickled)
			rb._checkconsistency()
			assert rb_unpickled == rb, name
			assert type(rb) == ImmutableRoaringBitmap, name

	def test_and(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert ref & ref2 == set(rb & rb2), name
			assert type(rb & rb2) == RoaringBitmap, name

	def test_or(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = ImmutableRoaringBitmap(data1), ImmutableRoaringBitmap(data2)
			assert ref | ref2 == set(rb | rb2), name

	def test_xor(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = ImmutableRoaringBitmap(data1), ImmutableRoaringBitmap(data2)
			assert ref ^ ref2 == set(rb ^ rb2), name

	def test_sub(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = ImmutableRoaringBitmap(data1), ImmutableRoaringBitmap(data2)
			assert ref - ref2 == set(rb - rb2), name

	def test_aggregateand(self, multi):
		ref = set(multi[0])
		res1 = ref.intersection(*[set(a) for a in multi[1:]])
		rb = ImmutableRoaringBitmap(multi[0])
		res2 = rb.intersection(*[ImmutableRoaringBitmap(a) for a in multi[1:]])
		res2._checkconsistency()
		assert res1 == res2

	def test_aggregateor(self, multi):
		ref = set(multi[0])
		res1 = ref.union(*[set(a) for a in multi[1:]])
		rb = ImmutableRoaringBitmap(multi[0])
		res2 = rb.union(*[ImmutableRoaringBitmap(a) for a in multi[1:]])
		res2._checkconsistency()
		assert res1 == res2

	def test_andlen(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert len(rb & rb2) == rb.intersection_len(rb2), name
			assert len(ref & ref2) == rb.intersection_len(rb2), name

	def test_orlen(self, pair):
		for name, data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert len(ref | ref2) == rb.union_len(rb2), name
			assert len(rb | rb2) == rb.union_len(rb2), name

	def test_jaccard_dist(self, pair):
		for name, data1, data2 in pair:
			if len(data1) == 0 and len(data2) == 0:
				continue
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert len(ref & ref2) / float(len(ref | ref2)) == pytest.approx(
					rb.intersection_len(rb2) / float(rb.union_len(rb2))), name
			assert (1 - (len(ref & ref2) / float(len(ref | ref2)))
					== pytest.approx(rb.jaccard_dist(rb2))), name

	def test_rank(self, single):
		for name, data in single:
			if len(data) == 0:
				continue
			ref = sorted(set(data))
			rb = ImmutableRoaringBitmap(data)
			for _ in range(10):
				x = choice(ref)
				assert x in rb, name
				assert rb.rank(x) == ref.index(x) + 1, name

	def test_select(self, single):
		for name, data in single:
			if len(data) == 0:
				continue
			ref = sorted(set(data))
			rb = ImmutableRoaringBitmap(data)
			lrb = list(rb)
			idx = [0, 1, 2] + [
					randint(0, len(ref) - 1) for _ in range(10)] + [
					len(ref) - 1, len(ref) - 2]
			for i in idx:
				assert lrb[i] == ref[i], name
				assert rb.select(i) in rb, name
				assert rb.select(i) == ref[i], name
				assert rb.rank(rb.select(i)) - 1 == i, name
				if rb.select(i) + 1 in rb:
					assert rb.rank(rb.select(i) + 1) - 1 == i + 1, name
				else:
					assert rb.rank(rb.select(i) + 1) - 1 == i, name

	def test_rank2(self):
		rb = ImmutableRoaringBitmap(range(0, 100000, 7))
		rb = rb.union(range(100000, 200000, 1000))
		for k in range(100000):
			assert rb.rank(k) == 1 + k // 7
		for k in range(100000, 200000):
			assert rb.rank(k) == 1 + 100000 // 7 + 1 + (k - 100000) // 1000

	def test_select2(self):
		gap = 1
		while gap <= 1024:
			rb = ImmutableRoaringBitmap(range(0, 100000, gap))
			for k in range(0, 100000 // gap):
				assert rb.select(k) == k * gap
			gap *= 2


class Test_multirb(object):
	def test_init(self, multi):
		orig = [RoaringBitmap(a) for a in multi]
		mrb = MultiRoaringBitmap(orig)
		assert len(orig) == len(mrb)
		for rb1, rb2 in zip(orig, mrb):
			assert rb1 == rb2

	def test_none(self, multi):
		orig = [RoaringBitmap(a) for a in multi]
		orig.insert(4, RoaringBitmap())
		mrb = MultiRoaringBitmap(orig)
		assert len(orig) == len(mrb)
		for rb1, rb2 in zip(orig, mrb):
			assert rb1 == rb2
		assert mrb.intersection([4, 5]) is None

	def test_aggregateand(self, multi):
		ref = set(multi[0])
		res1 = ref.intersection(*[set(a) for a in multi[1:]])
		mrb = MultiRoaringBitmap([ImmutableRoaringBitmap(a) for a in multi])
		res2 = mrb.intersection(list(range(len(mrb))))
		assert res1 == res2

	def test_jaccard(self, multi):
		mrb = MultiRoaringBitmap([ImmutableRoaringBitmap(a) for a in multi])
		indices1 = array.array(b'L' if PY2 else 'L', [0, 6, 8])
		indices2 = array.array(b'L' if PY2 else 'L', [1, 7, 6])
		res = mrb.jaccard_dist(indices1, indices2)
		ref = array.array(b'd' if PY2 else 'd', [mrb[i].jaccard_dist(mrb[j])
				for i, j in zip(indices1, indices2)])
		assert res == ref

	def test_andor_len_pairwise(self, multi):
		mrb = MultiRoaringBitmap([ImmutableRoaringBitmap(a) for a in multi])
		indices1 = array.array(b'L' if PY2 else 'L', [0, 6, 8])
		indices2 = array.array(b'L' if PY2 else 'L', [1, 7, 6])
		res1 = array.array(b'L' if PY2 else 'L', [0] * len(indices1))
		res2 = array.array(b'L' if PY2 else 'L', [0] * len(indices1))
		mrb.andor_len_pairwise(indices1, indices2, res1, res2)
		ref1 = array.array(b'L' if PY2 else 'L')
		ref2 = array.array(b'L' if PY2 else 'L')
		for i, j in zip(indices1, indices2):
			ref1.append(len(mrb[i] & mrb[j]))
			ref2.append(len(mrb[i] | mrb[j]))
		assert res1 == ref1
		assert res2 == ref2

	def test_clamp(self, multi):
		a, b = sorted(sample(multi[0], 2))
		ref = set.intersection(
				*[set(x) for x in multi]) & set(range(a, b))
		mrb = MultiRoaringBitmap([RoaringBitmap(x) for x in multi])
		rb = mrb.intersection(list(range(len(mrb))), start=a, stop=b)
		assert a <= rb.min() and rb.max() < b
		assert ref == rb

	def test_serialize(self, multi):
		orig = [RoaringBitmap(a) for a in multi]
		mrb = MultiRoaringBitmap(orig)
		with tempfile.NamedTemporaryFile(delete=False) as tmp:
			mrb2 = MultiRoaringBitmap(orig, filename=tmp.name)
			del mrb2
			mrb_deserialized = MultiRoaringBitmap.fromfile(tmp.name)
			assert len(orig) == len(mrb)
			assert len(orig) == len(mrb_deserialized)
			for rb1, rb2, rb3 in zip(orig, mrb, mrb_deserialized):
				assert rb1 == rb2
				assert rb1 == rb3
				rb3._checkconsistency()
				assert type(rb3) == ImmutableRoaringBitmap

	def test_multi1(self):
		for_multi = []
		for i in range(5):
			for_multi += [RoaringBitmap(sample(range(99999), 200))]
		mrb = MultiRoaringBitmap(for_multi)
		assert len(mrb) == 5
		assert mrb[4] == for_multi[4]
		with pytest.raises(IndexError):
			mrb[5]
		assert mrb[-1] == for_multi[-1]
		list(mrb)
		for n, rb in enumerate(mrb):
			assert rb == for_multi[n], n

	def test_multi2(self):
		for_multi_pre = []
		for x in range(3):
			for_multi = []
			for i in range(5):
				for_multi += [RoaringBitmap(sample(range(99999), 200))]
			mrb = MultiRoaringBitmap(for_multi)
			for_multi_pre += [mrb[0], mrb[1]]

		assert type(for_multi_pre) is list
		for_multi_pre[-1]
		list(for_multi_pre)

	def test_eq(self, multi):
		orig = [RoaringBitmap(a) for a in multi]
		mrb = MultiRoaringBitmap(orig)
		mrb2 = MultiRoaringBitmap(orig)
		mrb3 = MultiRoaringBitmap(orig[1:])
		assert mrb == orig
		assert mrb == mrb2
		assert mrb != orig[1:]
		assert mrb != mrb3
