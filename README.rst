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

This implementation is based on the Java and C implementations at
https://github.com/lemire/RoaringBitmap
and https://github.com/lemire/CRoaring

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
    init         0.000835          0.00227    0.369
    initsort     0.000853          0.00112    0.763
    and           0.00101         0.000171     5.94
    or            0.00168         0.000213     7.88
    xor           0.00151         0.000278     5.41
    sub           0.00118         0.000177     6.69
    iand         1.31e-05         3.35e-06      3.9
    ior          9.51e-06         3.61e-06     2.64
    ixor         9.24e-06         3.67e-06     2.52
    isub         6.92e-06         3.16e-06     2.19
    eq           0.000431         1.21e-05     35.7
    neq          6.32e-06            1e-05    0.631
    jaccard       0.00275         0.000153     17.9

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                    set()  RoaringBitmap()    ratio
    init            0.552            0.425      1.3
    initsort        0.683            0.368     1.86
    and             0.613         0.000338     1814
    or              0.971         0.000336     2890
    xor             0.889         0.000337     2639
    sub             0.342         0.000387      882
    iand          0.00648         1.08e-05      600
    ior             0.006         1.13e-05      528
    ixor          0.00413         1.27e-05      324
    isub          0.00426         1.12e-05      381
    eq             0.0982         0.000111      882
    neq             1e-05         1.49e-05    0.671
    jaccard           1.6         0.000309     5169

    large sparse set
    100 runs with sets of 131072 random elements n s.t. 0 <= n < 2147483648
                    set()  RoaringBitmap()    ratio
    init             1.71             9.02     0.19
    initsort         2.82             3.36     0.84
    and              1.36            0.431     3.15
    or               2.92            0.513      5.7
    xor              3.42            0.511     6.69
    sub              1.32            0.645     2.05
    iand           0.0158          0.00373     4.24
    ior            0.0151          0.00424     3.56
    ixor           0.0212           0.0045     4.71
    isub           0.0114           0.0038     3.01
    eq              0.329            0.123     2.67
    neq          1.06e-05         1.62e-05    0.653
    jaccard          4.58            0.215     21.3

References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
