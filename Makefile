all:
	python3 setup.py install --user --with-cython

clean:
	rm -rf build/
	find src/ -name '*.c' -delete
	find src/ -name '*.so' -delete
	find src/ -name '*.pyc' -delete
	find src/ -name '*.html' -delete
	rm -rf src/__pycache__

test: all
	ulimit -Sv 500000; python3 `which py.test` tests/unittests.py

bench: all
	ulimit -Sv 500000; python3 tests/benchmarks.py

lint:
	pep8 --ignore=E1,W1 tests/*.py \
	&& pep8 --ignore=E1,W1,F,E901,E225,E227,E211 \
			src/*.pyx src/*.pxd src/*.pxi

py2:
	python2 setup.py install --user --with-cython

test2: py2
	python2 `which py.test` tests/unittests.py

bench2: all
	ulimit -Sv 500000; python2 tests/benchmarks.py

debug:
	python3-dbg setup.py install --user --with-cython --debug

debug2:
	python2-dbg setup.py install --user --with-cython --debug

testdebug: debug
	gdb -ex run --args python3-dbg `which py.test` tests/unittests.py -v

testdebug2: debug2
	gdb -ex run --args python2-dbg `which py.test` tests/unittests.py -v

testdebug35:
	python3.5-dbg setup.py install --user --with-cython --debug && \
		gdb -ex run --args python3.5-dbg `which py.test` tests/unittests.py -v

valgrind35:
	python3.5-dbg setup.py install --user --with-cython --debug
	valgrind --tool=memcheck --suppressions=valgrind-python.supp \
		--leak-check=full --show-leak-kinds=definite \
		python3.5-dbg `which py.test` tests/unittests.py -v
