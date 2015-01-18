all:
	python setup.py install --user

clean:
	rm -rf build/
	find roaringbitmap -name '*.c' -delete
	find roaringbitmap -name '*.so' -delete
	find roaringbitmap -name '*.pyc' -delete
	find roaringbitmap -name '*.html' -delete
	rm -rf roaringbitmap/__pycache__

test: all
	ulimit -Sv 500000; py.test tests/unittests.py

bench: all
	ulimit -Sv 500000; python tests/benchmarks.py

lint:
	pep8 --ignore=E1,W1 \
			roaringbitmap/*.py tests/*.py \
	&& pep8 --ignore=E1,W1,F,E901,E225,E227,E211 \
			roaringbitmap/*.pyx roaringbitmap/*.pxd \

py3:
	python3 setup.py install --user

test3: py3
	python3 `which py.test` tests/unittests.py
