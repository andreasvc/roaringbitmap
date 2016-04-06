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
    init          0.00054          0.00668   0.0808
    and          0.000404         8.51e-05     4.75
    or           0.000537         9.48e-05     5.67
    xor          0.000452         8.36e-05     5.41
    sub          0.000401         6.97e-05     5.75
    eq           0.000159         0.000831    0.191
    neq          2.61e-06         2.05e-05    0.127
    andlen       0.000416         5.47e-05     7.61
    orlen        0.000532         4.43e-05       12
    jaccard_dist  0.00113         0.000105     10.8

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                    set()  RoaringBitmap()    ratio
    init             0.18             1.37    0.132
    and            0.0962         0.000152      633
    or               0.17         0.000137     1248
    xor             0.123         0.000134      912
    sub             0.074         0.000138      537
    eq             0.0335           0.0133     2.53
    neq          4.24e-06         2.44e-05    0.174
    andlen         0.0962         7.74e-05     1244
    orlen           0.185         8.97e-05     2057
    jaccard_dist    0.299         0.000168     1786

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                    set()  RoaringBitmap()    ratio
    init            0.245             2.04     0.12
    and             0.263         0.000287      914
    or              0.418         0.000284     1473
    xor             0.314         0.000283     1107
    sub             0.157         0.000292      536
    eq             0.0674           0.0295     2.28
    neq          5.04e-06         2.57e-05    0.196
    andlen          0.262         0.000175     1501
    orlen           0.468         0.000158     2970
    jaccard_dist    0.759         0.000315     2411
References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
