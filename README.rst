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

    sparse set
    100 runs with sets of 200 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init      0.00124          0.00788    0.158
    and       0.00125         0.000196     6.39
    or        0.00202         0.000243     8.31
    xor       0.00172         0.000254     6.77
    sub      0.000934         0.000175     5.34
    eq       0.000267          0.00049    0.545
    neq      6.91e-06          4.1e-05    0.169
    andlen    0.00132         0.000206     6.41

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init        0.425             1.97    0.216
    and         0.363         0.000484      749
    or          0.573         0.000471     1216
    xor         0.521          0.00048     1084
    sub         0.258          0.00047      548
    eq         0.0703           0.0144     4.89
    neq      1.41e-05         8.01e-05    0.176
    andlen      0.367         0.000249     1472

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                set()  RoaringBitmap()    ratio
    init        0.812                2    0.405
    and         0.704         0.000533     1320
    or           1.07         0.000528     2034
    xor          1.08         0.000985     1092
    sub         0.494         0.000986      501
    eq           0.15           0.0319     4.69
    neq       1.5e-05         9.49e-05    0.158
    andlen      0.882         0.000489     1804

References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
