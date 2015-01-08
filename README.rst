Roaring Bitmap in Cython
========================

A roaring bitmap is an efficient compressed bitmap.
Useful for storing a large number of integers, e.g., for an inverted index used
in search indexes and databases. In particular, it is possible to quickly
compute the intersection of a series of sets, which can be used to implement a
query as the conjunction of subqueries.

This implementation is mostly a translation from the Java implementation at
https://github.com/lemire/RoaringBitmap

A difference is that this implementation uses arrays not only when a block
contains less than ``1 << 12`` elements, but also when it contains more than
``1 << 32 - 1 << 12`` elements; i.e., blocks that are mostly full are stored
just as compactly as blocks that are mostly empty. Other blocks are encoded as
bitmaps of fixed size. This trick is based on the implementation
in Lucene, cf. https://issues.apache.org/jira/browse/LUCENE-5983

Requirements
------------
- Python 2.7+/3   http://www.python.org (headers required, e.g. python-dev package)
- Cython 0.20+    http://www.cython.org

Installation
------------
``$ make``

Benchmarks
----------
``$ python3 benchmarks.py``::
    sparse set
    100 runs with sets of 200 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init     0.000868           0.0104   0.0833
    iand      1.3e-05         3.69e-06     3.51
    and       0.00106          0.00017     6.24
    ior      9.68e-06         3.94e-06     2.46
    or        0.00172         0.000251     6.85
    eq       0.000438         0.000868    0.505
    neq      5.26e-06         3.13e-05    0.168

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init        0.315             1.76    0.179
    iand      0.00305         1.16e-05      262
    and         0.236         0.000466      506
    ior       0.00167          1.2e-05      139
    or          0.456         0.000471      967
    eq         0.0495          0.00414       12
    neq      8.58e-06         3.94e-05    0.218

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                set()  RoaringBitmap()    ratio
    init        0.506             3.08    0.165
    iand      0.00683         1.71e-05      400
    and         0.638          0.00094      678
    ior       0.00616         1.95e-05      316
    or          0.985         0.000933 1.06e+03
    eq         0.0985           0.0104     9.44
    neq      8.73e-06         4.18e-05    0.209

Usage
-----
A ``RoaringBitmap()`` can be used as a replacement for a normal Python set as
long as elements are 32-bit integers. The datastructure is mutable, although
initializing with a sorted iterable is most efficient.

References
----------
- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
- Paper: http://arxiv.org/abs/1402.6407
