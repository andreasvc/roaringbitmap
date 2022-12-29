all:
	python3 setup.py install --user

clean:
	rm -rf build/ src/roaringbitmap.h
	find src/ -name '*.c' -delete
	find src/ -name '*.so' -delete
	find src/ -name '*.pyc' -delete
	find src/ -name '*.html' -delete
	find tests/ -name '*.pyc' -delete
	rm -rf src/__pycache__ tests/__pycache__

test: all
	ulimit -Sv 500000; python3 -m pytest tests/unittests.py

bench: all
	ulimit -Sv 500000; python3 tests/benchmarks.py

lint:
	pycodestyle --ignore=E1,W1,W503 tests/*.py \
	&& pycodestyle --ignore=E1,W1,F,E901,E225,E227,E211,W503 \
			src/*.pyx src/*.pxi

py2:
	python2 setup.py install --user

test2: py2
	python2 -m pytest tests/unittests.py

bench2: all
	ulimit -Sv 500000; python2 tests/benchmarks.py

debug:
	python3-dbg setup.py install --user --debug

debug2:
	python2-dbg setup.py install --user --debug

testdebug: debug
	gdb -ex run --args python3-dbg -m pytest tests/unittests.py -v

testdebug2: debug2
	gdb -ex run --args python2-dbg -m pytest tests/unittests.py -v

valgrind:
	python3-dbg setup.py install --user --debug
	valgrind --tool=memcheck --suppressions=valgrind-python.supp \
		--leak-check=full --show-leak-kinds=definite \
		python3.5-dbg -m pytest tests/unittests.py -v
