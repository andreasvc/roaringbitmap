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

An additional feature of this implementation is that it uses arrays not only
when a block contains less than ``2 ** 12`` elements, but also when it contains
more than ``2 ** 32 - 2 ** 12`` elements; i.e., blocks that are mostly full are
stored just as compactly as blocks that are mostly empty. Other blocks are
encoded as bitmaps of fixed size. This trick is based on the implementation in
Lucene, cf. https://issues.apache.org/jira/browse/LUCENE-5983

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
    init         0.000838          0.00231    0.362
    initsort     0.000847          0.00126    0.675
    and           0.00104         0.000141     7.36
    or            0.00172         0.000188     9.13
    xor           0.00152         0.000235     6.46
    sub          0.000956         0.000172     5.57
    iand         1.29e-05         3.46e-06     3.72
    ior          9.63e-06          3.6e-06     2.67
    ixor         9.07e-06          3.7e-06     2.45
    isub         7.09e-06         3.22e-06      2.2
    eq           0.000451         1.13e-05     40.1
    neq          6.32e-06         8.54e-06     0.74
    jaccard       0.00278         0.000155       18

    medium load factor
    100 runs with sets of 59392 random elements n s.t. 0 <= n < 118784
                    set()  RoaringBitmap()    ratio
    init            0.508             0.43     1.18
    initsort        0.692            0.389     1.78
    and             0.613         0.000309     1987
    or              0.973         0.000317     3065
    xor             0.891         0.000311     2864
    sub             0.346         0.000313     1104
    iand          0.00647         1.13e-05      575
    ior           0.00599         1.22e-05      489
    ixor          0.00417         1.31e-05      318
    isub          0.00431         1.18e-05      363
    eq             0.0982         0.000112      873
    neq          9.87e-06         1.29e-05    0.763
    jaccard          1.59         0.000315     5047

    dense set / high load factor
    100 runs with sets of 39800 random elements n s.t. 0 <= n < 40000
                    set()  RoaringBitmap()    ratio
    init            0.313            0.114     2.75
    initsort        0.341            0.199     1.71
    and              0.23         0.000165     1394
    or              0.453         0.000153     2958
    xor              0.41         0.000174     2361
    sub             0.168         0.000163     1030
    iand          0.00288         5.95e-06      484
    ior           0.00166         5.91e-06      281
    ixor          0.00194         5.68e-06      342
    isub           0.0017         6.48e-06      262
    eq             0.0493         4.51e-05     1092
    neq          9.85e-06          1.3e-05    0.759
    jaccard         0.717         0.000154     4641

References
----------
Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin (2014),
Better bitmap performance with Roaring bitmaps,
http://arxiv.org/abs/1402.6407

- http://roaringbitmap.org/
- https://github.com/lemire/RoaringBitmap
- https://issues.apache.org/jira/browse/LUCENE-5983
