all:
	python setup.py install --user

inplace: all
	# python setup.py build_ext --inplace
	cp build/lib.*/roaringbitmap/*.so roaringbitmap/

clean:
	rm -rf build/
	find roaringbitmap -name '*.c' -delete
	find roaringbitmap -name '*.so' -delete
	find roaringbitmap -name '*.pyc' -delete
	find roaringbitmap -name '*.html' -delete
	rm -rf roaringbitmap/__pycache__

# FIXME which is it
test: all inplace
	py.test tests/unittests.py

bench: all inplace
	python benchmarks.py

lint:
	pep8 --ignore=E1,W1 \
			roaringbitmap/*.py tests/*.py benchmarks.py \
	&& pep8 --ignore=E1,W1,F,E901,E225,E227,E211 \
			roaringbitmap/*.pyx roaringbitmap/*.pxd \

py3:
	python3 setup.py install --user
	# python3 setup.py build_ext --inplace
	cp build/lib.*/roaringbitmap/*.so roaringbitmap/

test3: all inplace
	python3 `which py.test` tests/unittests.py
