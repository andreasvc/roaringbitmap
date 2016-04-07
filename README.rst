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
    init         0.000835          0.00155    0.538
    and           0.00103         0.000161     6.36
    or            0.00169         0.000221     7.64
    xor           0.00148         0.000259     5.74
    sub           0.00095         0.000199     4.78
    eq           0.000436         1.28e-05     33.9
    neq          5.26e-06         6.21e-06    0.846
    andlen        0.00103         0.000164     6.27
    orlen          0.0017         0.000152     11.2
    jaccard       0.00277         0.000151     18.3

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                    set()  RoaringBitmap()    ratio
    init            0.777            0.717     1.08
    and             0.849         0.000747     1136
    or               1.26         0.000996     1264
    xor              1.18         0.000991     1187
    sub             0.515          0.00099      520
    eq              0.191         0.000237      805
    neq          1.65e-05         1.82e-05    0.908
    andlen           0.85          0.00047     1806
    orlen            1.26         0.000472     2661
    jaccard           2.1          0.00063     3332

    large sparse set
    100 runs with sets of 131072 random elements n s.t. 0 <= n < 2147483648
                    set()  RoaringBitmap()    ratio
    init             2.45             12.2      0.2
    and              1.89            0.895     2.11
    or               3.68             2.41     1.53
    xor               4.5             3.77      1.2
    sub               1.8             10.3    0.175
    eq              0.605            0.167     3.61
    neq          1.42e-05           0.0134  0.00106
    andlen           1.89            0.511     3.69
    orlen            3.68            0.408     9.01
    jaccard          5.59            0.403     13.9

References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
