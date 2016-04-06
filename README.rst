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

License
-------
This code is licensed under GNU GPL v2, or any later version at your option.

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

For API documentation cf. http://roaringbitmap.readthedocs.org

Benchmarks
----------
Output of ``$ make bench``::

    small sparse set
    100 runs with sets of 200 random elements n s.t. 0 <= n < 40000
                    set()  RoaringBitmap()    ratio
    init          0.00173          0.00317    0.546
    and           0.00213         0.000357     5.98
    or            0.00352         0.000505     6.97
    xor            0.0031         0.000535      5.8
    sub           0.00193         0.000396     4.87
    eq           0.000872         2.51e-05     34.8
    neq          9.87e-06         1.37e-05    0.723
    andlen        0.00216         0.000347     6.22
    orlen         0.00349         0.000318       11
    jaccard       0.00578         0.000314     18.4

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                    set()  RoaringBitmap()    ratio
    init            0.818            0.728     1.12
    and             0.851         0.000657     1294
    or                1.2         0.000529     2274
    xor              1.11          0.00101     1098
    sub             0.515         0.000984      523
    eq              0.192         0.000121     1583
    neq          8.55e-06         1.23e-05    0.694
    andlen          0.612         0.000238     2570
    orlen               1          0.00023     4365
    jaccard          1.65         0.000306     5405

    large sparse set
    100 runs with sets of 131072 random elements n s.t. 0 <= n < 2147483648
                    set()  RoaringBitmap()    ratio
    init             1.93             54.3   0.0356
    and              1.41            0.562     2.51
    or               3.01             1.62     1.86
    xor              3.62             4.71     0.77
    sub              1.79             7.87    0.228
    eq              0.305           0.0872      3.5
    neq          8.94e-06          0.00821  0.00109
    andlen           1.35            0.212     6.37
    orlen            2.85            0.229     12.5
    jaccard           4.6             0.43     10.7

References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
