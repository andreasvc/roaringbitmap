Roaring Bitmap in Cython
========================

A roaring bitmap is an efficient compressed bitmap.
Useful for storing a large number of integers, e.g., for an inverted index used
in search indexes and databases. In particular, it is possible to quickly
compute the intersection of a series of sets, which can be used to implement a
query as the conjunction of subqueries.

Requirements
------------
Cython

Installation
------------
$ make

Usage
-----
A RoaringBitmap() can be used as a replacement for a normal Python set as long
as elements are 32-bit integers. The datastructure is mutable, although
initializing with a sorted iterable is most efficient.

References
----------
http://roaringbitmap.org/
Paper: http://arxiv.org/abs/1402.6407
