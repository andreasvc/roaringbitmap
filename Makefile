all:
	python setup.py install --user --with-cython

clean:
	rm -rf build/
	find src/ -name '*.c' -delete
	find src/ -name '*.so' -delete
	find src/ -name '*.pyc' -delete
	find src/ -name '*.html' -delete
	rm -rf src/__pycache__

test: all
	ulimit -Sv 500000; py.test tests/unittests.py

bench: all
	ulimit -Sv 500000; python tests/benchmarks.py

lint:
	pep8 --ignore=E1,W1 tests/*.py \
	&& pep8 --ignore=E1,W1,F,E901,E225,E227,E211 \
			src/*.pyx src/*.pxd src/*.pxi

py3:
	python3 setup.py install --user --with-cython

test3: py3
	python3 `which py.test` tests/unittests.py
