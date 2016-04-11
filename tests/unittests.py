"""Unit tests for roaringbitmap"""
from __future__ import division, absolute_import, unicode_literals
import sys
import random
import pytest
import pickle
import tempfile
try:
	from itertools import zip_longest
except ImportError:
	from itertools import izip_longest as zip_longest
try:
	import faulthandler
	faulthandler.enable()
except ImportError:
	pass
if sys.version_info[0] < 3:
	range = xrange
from roaringbitmap import RoaringBitmap, ImmutableRoaringBitmap, \
		MultiRoaringBitmap

# (numitems, maxnum)
PARAMS = [
	(200, 65535),
	(65535 - 200, 65535),
	(40000, 65535),
	(4000, 1 << 31)]


@pytest.fixture(scope='module')
def single():
	random.seed(42)
	result = []
	for elements, maxnum in PARAMS:
		result.append([random.randint(0, maxnum) for _ in range(elements)])
	return result


@pytest.fixture(scope='module')
def pair():
	result = []
	for a in single():
		for b in single():
			for elements, maxnum in PARAMS:
				b = b[:len(b) // 2]
				b.extend(random.randint(0, maxnum)
						for _ in range(elements // 2))
				result.append((a, b))
	return result


@pytest.fixture(scope='module')
def multi():
	a = [random.randint(0, 1000)
			for _ in range(random.randint(100, 2000))]
	result = [[random.randint(0, 1000)
			for _ in range(random.randint(100, 2000))] + a
			for _ in range(100)]
	return result


class Test_multirb(object):
	def test_init(self, multi):
		orig = [RoaringBitmap(a) for a in multi]
		mrb = MultiRoaringBitmap(orig)
		assert len(orig) == len(mrb)
		for rb1, rb2 in zip(orig, mrb):
			assert rb1 == rb2

	def test_none(self, multi):
		orig = [RoaringBitmap(a) for a in multi]
		orig.insert(4, None)
		mrb = MultiRoaringBitmap(orig)
		assert len(orig) == len(mrb)
		for rb1, rb2 in zip(orig, mrb):
			assert rb1 == rb2
		assert mrb.intersection([4, 5]) == None

	def test_aggregateand(self, multi):
		ref = set(multi[0])
		res1 = ref.intersection(*[set(a) for a in multi[1:]])
		mrb = MultiRoaringBitmap([ImmutableRoaringBitmap(a) for a in multi])
		res2 = mrb.intersection(list(range(len(mrb))))
		assert res1 == res2

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


class Test_immutablerb(object):
	def test_inittrivial(self):
		data = list(range(5))
		ref = set(data)
		rb = ImmutableRoaringBitmap(data)
		rb._checkconsistency()
		assert ref == rb
		assert type(rb) == ImmutableRoaringBitmap

	def test_initsorted(self, single):
		for data in single:
			ref = set(sorted(data))
			rb = RoaringBitmap(sorted(data))
			rb._checkconsistency()
			assert ref == rb

	def test_initunsorted(self, single):
		for data in single:
			ref = set(data)
			rb = RoaringBitmap(data)
			rb._checkconsistency()
			assert ref == rb

	def test_inititerator(self, single):
		for data in single:
			ref = set(a for a in data)
			rb = RoaringBitmap(a for a in data)
			rb._checkconsistency()
			assert ref == rb

	def test_initrange(self):
		# creates a positive, dense, and inverted block, respectively
		for n in [400, 6000, 61241]:
			ref = set(range(23, n))
			rb = RoaringBitmap(range(23, n))
			rb._checkconsistency()
			assert ref == rb

	def test_pickle(self, single):
		for data in single:
			rb = ImmutableRoaringBitmap(data)
			rb_pickled = pickle.dumps(rb, protocol=-1)
			rb_unpickled = pickle.loads(rb_pickled)
			rb._checkconsistency()
			assert rb_unpickled == rb
			assert type(rb) == ImmutableRoaringBitmap

	def test_and(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert ref & ref2 == set(rb & rb2)
			assert type(rb & rb2) == RoaringBitmap

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
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert len(rb & rb2) == rb.intersection_len(rb2)
			assert len(ref & ref2) == rb.intersection_len(rb2)

	def test_orlen(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert len(ref | ref2) == rb.union_len(rb2)
			assert len(rb | rb2) == rb.union_len(rb2)

	def test_jaccard_dist(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb = ImmutableRoaringBitmap(data1)
			rb2 = ImmutableRoaringBitmap(data2)
			assert abs((len(ref & ref2) / float(len(ref | ref2)))
					- rb.intersection_len(rb2)
					/ float(rb.union_len(rb2))) < 0.001
			assert abs((1 - (len(ref & ref2) / float(len(ref | ref2))))
					- rb.jaccard_dist(rb2)) < 0.001

	def test_rank(self, single):
		for data in single:
			ref = sorted(set(data))
			rb = ImmutableRoaringBitmap(data)
			for _ in range(10):
				x = random.choice(ref)
				assert x in rb
				assert rb.rank(x) == ref.index(x) + 1

	def test_rank2(self):
		rb = ImmutableRoaringBitmap(range(0, 100000, 7))
		rb = rb.union(range(100000, 200000, 1000))
		for k in range(100000):
			assert rb.rank(k) == 1 + k // 7
		for k in range(100000, 200000):
			assert rb.rank(k) == 1 + 100000 // 7 + 1 + (k - 100000) // 1000

	def test_select(self, single):
		for data in single:
			ref = sorted(set(data))
			rb = ImmutableRoaringBitmap(data)
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

	def test_select2(self):
		gap = 1
		while gap <= 1024:
			rb = ImmutableRoaringBitmap(range(0, 100000, gap))
			for k in range(0, 100000 // gap):
				assert rb.select(k) == k * gap
			gap *= 2


class Test_roaringbitmap(object):
	def test_inittrivial(self):
		data = list(range(5))
		ref = set(data)
		rb = RoaringBitmap(data)
		rb._checkconsistency()
		assert ref == rb

	def test_initsorted(self, single):
		for data in single:
			ref = set(sorted(data))
			rb = RoaringBitmap(sorted(data))
			rb._checkconsistency()
			assert ref == rb

	def test_initunsorted(self, single):
		for data in single:
			ref = set(data)
			rb = RoaringBitmap(data)
			rb._checkconsistency()
			assert ref == rb

	def test_inititerator(self, single):
		for data in single:
			ref = set(a for a in data)
			rb = RoaringBitmap(a for a in data)
			rb._checkconsistency()
			assert ref == rb

	def test_initrange(self):
		# creates a positive, dense, and inverted block, respectively
		for n in [400, 6000, 61241]:
			ref = set(range(23, n))
			rb = RoaringBitmap(range(23, n))
			rb._checkconsistency()
			assert ref == rb

	def test_add(self, single):
		for data in single:
			ref = set()
			rb = RoaringBitmap()
			for n in sorted(data):
				ref.add(n)
				rb.add(n)
			assert rb == ref
			with pytest.raises(OverflowError):
				rb.add(-1)
				rb.add(1 << 32)
			rb.add(0)
			rb.add((1 << 32) - 1)
			rb._checkconsistency()

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
			rb._checkconsistency()
			assert len(ref) == 0
			assert len(rb) == 0
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
			rb._checkconsistency()

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
			rb._checkconsistency()
			assert rb == ref

	def test_ior(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref |= ref2
			rb |= rb2
			rb._checkconsistency()
			assert rb == ref

	def test_ixor(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref ^= ref2
			rb ^= rb2
			rb._checkconsistency()
			assert len(ref) == len(rb)
			assert ref == rb

	def test_isub(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			ref -= ref2
			rb -= rb2
			rb._checkconsistency()
			assert len(ref) <= len(set(data1))
			assert len(rb) <= len(set(data1))
			assert len(ref) == len(rb)
			assert ref == rb

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

	def test_subset(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			refans = ref <= ref2
			assert (set(rb) <= ref2) == refans
			assert (rb <= rb2) == refans
			k = len(data2) // 2
			ref, rb = set(data2[:k]), RoaringBitmap(data2[:k])
			refans = ref <= ref2
			assert (set(rb) <= ref2) == refans
			assert (rb <= rb2) == refans

	def test_disjoint(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			refans = ref.isdisjoint(ref2)
			assert rb.isdisjoint(rb2) == refans
			data3 = [a for a in data2 if a not in ref]
			ref3, rb3 = set(data3), RoaringBitmap(data3)
			refans2 = ref.isdisjoint(ref3)
			assert rb.isdisjoint(rb3) == refans2

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
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert len(rb & rb2) == rb.intersection_len(rb2)
			assert len(ref & ref2) == rb.intersection_len(rb2)

	def test_orlen(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert len(ref | ref2) == rb.union_len(rb2)
			assert len(rb | rb2) == rb.union_len(rb2)

	def test_jaccard_dist(self, pair):
		for data1, data2 in pair:
			ref, ref2 = set(data1), set(data2)
			rb, rb2 = RoaringBitmap(data1), RoaringBitmap(data2)
			assert abs((len(ref & ref2) / float(len(ref | ref2)))
					- rb.intersection_len(rb2)
					/ float(rb.union_len(rb2))) < 0.001
			assert abs((1 - (len(ref & ref2) / float(len(ref | ref2))))
					- rb.jaccard_dist(rb2)) < 0.001

	def test_rank(self, single):
		for data in single:
			ref = sorted(set(data))
			rb = RoaringBitmap(data)
			for _ in range(10):
				x = random.choice(ref)
				assert x in rb
				assert rb.rank(x) == ref.index(x) + 1

	def test_rank2(self):
		rb = RoaringBitmap(range(0, 100000, 7))
		rb.update(range(100000, 200000, 1000))
		for k in range(100000):
			assert rb.rank(k) == 1 + k // 7
		for k in range(100000, 200000):
			assert rb.rank(k) == 1 + 100000 // 7 + 1 + (k - 100000) // 1000

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

	def test_select2(self):
		gap = 1
		while gap <= 1024:
			rb = RoaringBitmap(range(0, 100000, gap))
			for k in range(0, 100000 // gap):
				assert rb.select(k) == k * gap
			gap *= 2

	def test_pickle(self, single):
		for data in single:
			rb = RoaringBitmap(data)
			rb_pickled = pickle.dumps(rb, protocol=-1)
			rb_unpickled = pickle.loads(rb_pickled)
			rb._checkconsistency()
			assert rb_unpickled == rb
