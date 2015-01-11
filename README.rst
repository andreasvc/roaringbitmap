Roaring Bitmap in Cython
========================

A roaring bitmap is an efficient compressed datastructure to store a set
of integers. A Roaring bitmap stores a set of 32-bit integers in a series of
arrays and bitmaps, whichever takes the least space (which is always
``2 ** 16`` bits or less).

This datastructure is useful for storing a large number of integers, e.g., for
an inverted index used in search indexes and databases. In particular, it is
possible to quickly compute the intersection of a series of sets, which can be
used to implement a query as the conjunction of subqueries.

This implementation is mostly a translation from the Java implementation at
https://github.com/lemire/RoaringBitmap

An additional feature of this implementation is that it uses arrays not only
when a block contains less than ``2 ** 12`` elements, but also when it contains
more than ``2 ** 32 - 2 ** 12`` elements; i.e., blocks that are mostly full are
stored just as compactly as blocks that are mostly empty. Other blocks are
encoded as bitmaps of fixed size. This trick is based on the implementation in
Lucene, cf. https://issues.apache.org/jira/browse/LUCENE-5983

Requirements
------------
- Python 2.7+/3   http://www.python.org (headers required, e.g. python-dev package)
- Cython 0.20+    http://www.cython.org

Installation
------------
``$ make``

Usage
-----
A ``RoaringBitmap()`` can be used as a replacement for a normal (mutable)
Python set containing (unsigned) 32-bit integers::

    >>> from roaringbitmap import RoaringBitmap
    >>> RoaringBitmap(range(10)) & RoaringBitmap(range(5, 15))
    RoaringBitmap({5, 6, 7, 8, 9})

Benchmarks
----------
Output of ``$ python benchmarks.py``::

    sparse set
    100 runs with sets of 200 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init     0.000854          0.00768    0.111
    and       0.00113         0.000158     7.16
    or        0.00195         0.000269     7.26
    xor       0.00166         0.000214     7.76
    sub       0.00103         0.000158     6.53
    eq        0.00048         0.000506    0.949
    neq      5.96e-06         3.79e-05    0.157

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init        0.297             1.18    0.253
    and         0.223         0.000504      442
    or          0.451         0.000507      889
    xor         0.406         0.000525      773
    sub         0.165         0.000512      322
    eq         0.0586          0.00754     7.77
    neq      9.06e-06         4.91e-05    0.184

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                set()  RoaringBitmap()    ratio
    init        0.508             2.02    0.252
    and         0.617          0.00111      558
    or          0.992          0.00111      896
    xor          0.89          0.00107      830
    sub         0.349           0.0011      317
    eq          0.117           0.0168     6.95
    neq       1.1e-05          5.6e-05    0.196

References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
