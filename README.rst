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

To compile from source::

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
    init         0.000383         0.000627     0.61
    initsort     0.000992         0.000258     3.85
    and          0.000499         0.000125     3.98
    or           0.000507          8.9e-05      5.7
    xor          0.000479         8.14e-05     5.88
    sub          0.000335         7.57e-05     4.42
    iand         1.18e-05         2.77e-06     4.26
    ior          8.39e-06         2.75e-06     3.05
    ixor         8.12e-06         2.81e-06     2.89
    isub         6.54e-06         2.87e-06     2.28
    eq_identity  0.000183         4.78e-06     38.2
    eq_equal     0.000169         7.33e-06       23
    neq_card     4.62e-06         5.43e-06     0.85
    neq_early    1.79e-05         6.21e-06     2.89
    neq_late     0.000167         6.64e-06     25.2
    jaccard      0.000973         4.99e-05     19.5

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                        set()  RoaringBitmap()    ratio
    init            0.451            0.138     3.26
    initsort        0.349           0.0995     3.51
    and             0.362         0.000271     1336
    or              0.482         0.000248     1942
    xor              0.46         0.000258     1780
    sub             0.381         0.000444      857
    iand          0.00421         5.33e-06      790
    ior           0.00581         5.49e-06     1058
    ixor          0.00243         5.05e-06      481
    isub          0.00229         4.88e-06      469
    eq_identity     0.123         1.64e-05     7501
    eq_equal        0.137         3.75e-05     3643
    neq_card     7.49e-06         7.06e-06     1.06
    neq_early    8.08e-06         2.22e-05    0.364
    neq_late        0.139         5.42e-05     2571
    jaccard          0.88         0.000183     4806

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                        set()  RoaringBitmap()    ratio
    init            0.206           0.0967     2.13
    initsort        0.179           0.0531     3.37
    and             0.149         0.000134     1117
    or              0.209         0.000112     1862
    xor             0.186         0.000112     1653
    sub              0.12         0.000109     1092
    iand          0.00174         3.75e-06      463
    ior          0.000865         3.58e-06      241
    ixor          0.00112          3.6e-06      310
    isub          0.00102          3.5e-06      292
    eq_identity     0.052         5.39e-06     9644
    eq_equal       0.0559         1.68e-05     3318
    neq_card     7.18e-06         7.53e-06    0.954
    neq_early    7.17e-06         7.73e-06    0.928
    neq_late       0.0437         1.36e-05     3209
    jaccard         0.342         9.84e-05     3472

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
