Roaring Bitmap in Cython
========================

A roaring bitmap is an efficient compressed datastructure to store a set
of integers. A Roaring bitmap stores a set of 32-bit integers in a series of
arrays and bitmaps, whichever takes the least space (which is always
``2 ** 16`` bits or less).

This datastructure is useful for storing a large number of integers, e.g., for
an inverted index used by search engines and databases. In particular, it is
possible to quickly compute the intersection of a series of sets, which can be
used to implement a query as the conjunction of subqueries.

This implementation is based on the Java and C implementations at
https://github.com/lemire/RoaringBitmap
and https://github.com/lemire/CRoaring

Additional features of this implementation:

- Inverted list representation: blocks that are mostly full are stored
  compactly as an array of non-members (instead of as an array of members or a
  fixed-size bitmap).
- Collections of immutable roaring bitmaps can be efficiently serialized with
  ``mmap`` in a single file.

Missing features w.r.t. CRoaring:

- Run-length encoded blocks
- Various AVX2 / SSE optimizations

See also PyRoaringBitmap, a Python wrapper of CRoaring:
https://github.com/Ezibenroc/PyRoaringBitMap

License, requirements
---------------------
The code is licensed under GNU GPL v2, or any later version at your option.

- Python 2.7+/3.3+  http://www.python.org (headers required, e.g. python-dev package)
- Cython 0.20+      http://www.cython.org

Installation, usage
-------------------

::

    $ git clone https://github.com/andreasvc/roaringbitmap.git
    $ cd roaringbitmap
    $ make

(or ``make py2`` for Python 2)

A ``RoaringBitmap()`` can be used as a replacement for a normal (mutable)
Python set containing (unsigned) 32-bit integers:

.. code-block:: python

    >>> from roaringbitmap import RoaringBitmap
    >>> RoaringBitmap(range(10)) & RoaringBitmap(range(5, 15))
    RoaringBitmap({5, 6, 7, 8, 9})

``ImmutableRoaringBitmap`` is an immutable variant (analogous to ``frozenset``)
which is stored compactly as a contiguous block of memory.

A sequence of immutable RoaringBitmaps can be stored in a single file and
accessed efficiently with ``mmap``, without needing to copy or deserialize:

.. code-block:: python

    >>> from roaringbitmap import MultiRoaringBitmap
    >>> mrb = MultiRoaringBitmap([range(n, n + 5) for n in range(10)], filename='index')

    >>> mrb = MultiRoaringBitmap.fromfile('index')
    >>> mrb[5]
    ImmutableRoaringBitmap({5, 6, 7, 8, 9})

For API documentation cf. http://roaringbitmap.readthedocs.io

Benchmarks
----------
Output of ``$ make bench``::

    small sparse set
    100 runs with sets of 200 random elements n s.t. 0 <= n < 40000
                    set()  RoaringBitmap()    ratio
    init         0.000834          0.00138    0.603
    initsort      0.00085         0.000394     2.16
    and           0.00102         8.49e-05     12.1
    or            0.00171         0.000169     10.1
    xor           0.00152         0.000213     7.11
    sub          0.000934         0.000197     4.74
    iand         1.29e-05         2.97e-06     4.35
    ior           9.7e-06         3.26e-06     2.98
    ixor         8.98e-06         3.43e-06     2.62
    isub         6.83e-06          3.3e-06     2.07
    eq           0.000438         1.17e-05     37.6
    neq          6.37e-06         7.81e-06    0.816
    jaccard        0.0029         0.000126     23.1

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                    set()  RoaringBitmap()    ratio
    init            0.564            0.324     1.74
    initsort        0.696            0.273     2.55
    and             0.613         0.000418     1466
    or              0.976         0.000292     3344
    xor             0.955         0.000294     3250
    sub             0.346         0.000316     1092
    iand          0.00658         1.14e-05      575
    ior           0.00594         1.08e-05      548
    ixor          0.00434         1.12e-05      385
    isub          0.00431         1.09e-05      397
    eq             0.0991         0.000116      851
    neq          9.62e-06         1.29e-05    0.743
    jaccard          1.62          0.00025     6476

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                    set()  RoaringBitmap()    ratio
    init             0.33           0.0775     4.26
    initsort        0.352            0.148     2.38
    and              0.24         0.000223     1078
    or               0.45         0.000165     2734
    xor             0.404         0.000161     2514
    sub             0.169         0.000173      973
    iand          0.00287         6.02e-06      477
    ior           0.00179         6.34e-06      282
    ixor          0.00195         5.53e-06      353
    isub           0.0017         6.35e-06      267
    eq             0.0486         4.65e-05     1045
    neq          1.01e-05         1.13e-05    0.888
    jaccard         0.722         0.000118     6136

See https://github.com/Ezibenroc/roaring_analysis/ for a performance comparison
of PyRoaringBitmap and this library.

References
----------
- http://roaringbitmap.org/
- Chambi, S., Lemire, D., Kaser, O., & Godin, R. (2016). Better bitmap
  performance with Roaring bitmaps. Software: practice and experience, 46(5),
  pp. 709-719. http://arxiv.org/abs/1402.6407
- The idea of using the inverted list representation is based on
  https://issues.apache.org/jira/browse/LUCENE-5983
