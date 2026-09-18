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
- Cython 3.0+       http://www.cython.org

Installation
------------

::
    $ pip install roaringbitmap

For Linux and Mac, there are binary wheels. Binary wheels for x86-64 require
the POPCNT CPU instruction and raise ``ImportError`` on unsupported CPUs.
Builds from source use ``-march=native`` by default and are optimized for the
build machine.

To compile from source:
::

    $ git clone https://github.com/andreasvc/roaringbitmap.git
    $ cd roaringbitmap
    $ make

For Python 2, build with a Cython version that supports Python 2.7::

    $ python2 -m pip install 'Cython>=3,<3.1'
    $ make py2

The C sources published on PyPI are generated with the current Cython release
and support Python 3 only.


Usage
-----

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
    init             0.000513         0.000563    0.912
    initsort         0.000872         0.000282     3.09
    and              0.000387         6.49e-05     5.97
    or               0.000531         8.26e-05     6.42
    xor              0.000715         0.000175     4.07
    sub              0.000348         8.91e-05     3.91
    iand             1.18e-05         3.01e-06     3.92
    ior              8.04e-06         2.82e-06     2.85
    ixor             9.49e-06         2.99e-06     3.18
    isub              7.2e-06         2.92e-06     2.47
    eq_identity      0.000172         4.87e-06     35.4
    eq_equal         0.000184         6.84e-06     26.9
    neq_cardinality  4.59e-06         5.54e-06    0.828
    neq_early        4.48e-05         6.06e-06     7.39
    neq_late         0.000172         6.91e-06       25
    jaccard            0.00119          5.6e-05     21.2

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                        set()  RoaringBitmap()    ratio
    init                0.437            0.133     3.29
    initsort            0.386           0.0882     4.38
    and                 0.401          0.00029     1380
    or                  0.543         0.000346     1568
    xor                 0.664         0.000274     2425
    sub                 0.294         0.000228     1290
    iand              0.00449         5.67e-06      792
    ior                0.0057         4.94e-06     1151
    ixor              0.00314          5.5e-06      570
    isub              0.00253         5.24e-06      483
    eq_identity          0.15         5.83e-06    25672
    eq_equal            0.162         4.01e-05     4038
    neq_cardinality  6.74e-06         8.93e-06    0.755
    neq_early        8.87e-06          9.4e-06    0.943
    neq_late             0.15         3.29e-05     4566
    jaccard             0.938          0.00024     3915

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                        set()  RoaringBitmap()    ratio
    init                0.247            0.095      2.6
    initsort             0.21           0.0483     4.34
    and                 0.167         0.000247      676
    or                  0.215         0.000171     1258
    xor                 0.206         0.000115     1792
    sub                 0.128         0.000117     1094
    iand              0.00177         3.97e-06      446
    ior              0.000913         3.78e-06      241
    ixor              0.00118         3.42e-06      344
    isub              0.00111          3.8e-06      292
    eq_identity         0.066         1.54e-05     4285
    eq_equal           0.0599         1.72e-05     3488
    neq_cardinality  5.77e-06         1.29e-05    0.449
    neq_early        7.85e-06         7.47e-06     1.05
    neq_late           0.0447         1.35e-05     3312
    jaccard             0.361         8.61e-05     4195

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
