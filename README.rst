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
    init      0.00085          0.00818      0.1
    and       0.00113         0.000117     9.67
    or        0.00192         0.000213     9.01
    xor        0.0017         0.000205     8.29
    sub         0.001         0.000152      6.6
    eq       0.000497         0.000505     0.98
    neq      5.01e-06          4.1e-05     0.12

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init        0.296             1.21     0.24
    and         0.232         0.000455      509
    or          0.467         0.000464 1.01e+03
    xor         0.416         0.000461      903
    sub         0.169         0.000461      366
    eq         0.0621          0.00483     12.9
    neq         1e-05         4.39e-05     0.23

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                set()  RoaringBitmap()    ratio
    init         0.51              2.1     0.24
    and         0.615         0.000895      687
    or           1.02         0.000897 1.14e+03
    xor         0.908         0.000899 1.01e+03
    sub         0.344          0.00093      370
    eq           0.12           0.0105     11.5
    neq      9.06e-06          5.1e-05     0.18

References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
