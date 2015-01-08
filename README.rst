Roaring Bitmap in Cython
========================

A roaring bitmap is an efficient compressed bitmap.
Useful for storing a large number of integers, e.g., for an inverted index used
in search indexes and databases. In particular, it is possible to quickly
compute the intersection of a series of sets, which can be used to implement a
query as the conjunction of subqueries.

Requirements
------------
- Python 2.7+/3   http://www.python.org (headers required, e.g. python-dev package)
- Cython 0.20+    http://www.cython.org

Installation
------------

::
    $ make

Benchmarks
----------

::
    $ python3 benchmarks.py
    sparse set
    100 runs with sets of 200 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init     0.000842          0.00999   0.0842
    iand     1.31e-05         3.73e-06     3.52
    and       0.00107         0.000163     6.53
    ior      1.02e-05         1.24e-05    0.821
    or         0.0017         0.000617     2.76
    eq       0.000431         0.000841    0.512
    neq      5.32e-06         3.12e-05     0.17

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init        0.316             1.75    0.181
    iand       0.0029         1.31e-05      222
    and         0.231          0.00052      444
    ior        0.0017         1.13e-05      151
    or          0.449         0.000535      840
    eq         0.0505          0.00401     12.6
    neq      8.53e-06         4.01e-05    0.213

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                set()  RoaringBitmap()    ratio
    init        0.511             2.89    0.177
    iand      0.00677         2.02e-05      335
    and         0.611         0.000918      665
    ior       0.00592         2.06e-05      288
    or          0.967         0.000952 1.02e+03
    eq         0.0981           0.0103      9.5
    neq      1.01e-05         4.11e-05    0.246

Usage
-----
A ``RoaringBitmap()`` can be used as a replacement for a normal Python set as
long as elements are 32-bit integers. The datastructure is mutable, although
initializing with a sorted iterable is most efficient.

References
----------
- http://roaringbitmap.org/
- Paper: http://arxiv.org/abs/1402.6407
