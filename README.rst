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
    init         0.000373          0.00067    0.557
    initsort     0.000375          0.00038    0.986
    and          0.000492         6.95e-05     7.07
    or           0.000547         8.87e-05     6.16
    xor           0.00049          8.8e-05     5.57
    sub          0.000349         8.35e-05     4.18
    iand         1.23e-05         3.56e-06     3.47
    ior          9.13e-06         3.14e-06     2.91
    ixor         8.29e-06         3.59e-06     2.31
    isub         7.33e-06         3.13e-06     2.34
    eq           0.000171         6.94e-06     24.6
    neq          4.64e-06         2.15e-05    0.216
    jaccard       0.00103         4.95e-05     20.7

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                    set()  RoaringBitmap()    ratio
    init             0.41            0.314      1.3
    initsort        0.383            0.173     2.22
    and             0.405         0.000268     1508
    or              0.643         0.000373     1720
    xor             0.495         0.000215     2303
    sub             0.245         0.000204     1202
    iand          0.00408         7.08e-06      576
    ior           0.00561         6.05e-06      926
    ixor          0.00249         6.46e-06      385
    isub          0.00234         6.94e-06      337
    eq               0.14         5.39e-05     2600
    neq          6.79e-06         8.98e-06    0.755
    jaccard         0.878         0.000177     4962

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                    set()  RoaringBitmap()    ratio
    init            0.226           0.0651     3.46
    initsort        0.202           0.0786     2.57
    and             0.155         0.000135     1146
    or              0.197           0.0002      985
    xor             0.185         0.000198      933
    sub              0.12         0.000125      961
    iand          0.00174         4.73e-06      367
    ior          0.000929         3.73e-06      248
    ixor          0.00113         3.99e-06      282
    isub          0.00107         3.84e-06      279
    eq             0.0607         1.65e-05     3685
    neq          6.77e-06         8.57e-06     0.79
    jaccard         0.352         8.27e-05     4250

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
