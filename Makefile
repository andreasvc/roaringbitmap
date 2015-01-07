all:
	python setup.py install --user

inplace:
	python setup.py build_ext --inplace

py3:
	python3 setup.py install --user
	python3 setup.py build_ext --inplace

clean:
	rm -rf build/
	find roaringbitmap -name '*.c' -delete
	find roaringbitmap -name '*.so' -delete
	find roaringbitmap -name '*.pyc' -delete
	find roaringbitmap -name '*.html' -delete
	rm -rf roaringbitmap/__pycache__

test: py3
	py.test tests/unittests.py

bench: py3
	python3 benchmarks.py
