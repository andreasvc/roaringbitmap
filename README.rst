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
    init     0.000944           0.0101   0.0931
    iand      1.3e-05         3.63e-06     3.57
    and       0.00105         0.000177     5.93
    ior      1.01e-05         3.87e-06     2.61
    or        0.00197         0.000252     7.82
    eq       0.000464         0.000993    0.467
    neq      5.22e-06         3.05e-05    0.171

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                set()  RoaringBitmap()    ratio
    init        0.315             1.74    0.181
    iand       0.0029          1.1e-05      265
    and          0.23         0.000463      496
    ior       0.00173         1.22e-05      141
    or          0.521         0.000538      970
    eq         0.0509          0.00415     12.3
    neq      8.76e-06         3.89e-05    0.225

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                set()  RoaringBitmap()    ratio
    init        0.526             2.89    0.182
    iand      0.00687         1.92e-05      357
    and         0.621         0.000912      681
    ior         0.006         1.91e-05      314
    or          0.983         0.000918 1.07e+03
    eq         0.0991           0.0106     9.38
    neq       9.5e-06         4.14e-05     0.23

Usage
-----
A ``RoaringBitmap()`` can be used as a replacement for a normal Python set as
long as elements are 32-bit integers. The datastructure is mutable, although
initializing with a sorted iterable is most efficient.

References
----------
- http://roaringbitmap.org/
- Paper: http://arxiv.org/abs/1402.6407
