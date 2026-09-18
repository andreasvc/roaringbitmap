PYTHON3 ?= python3
PYTHON2 ?= python2

# pip builds in an isolated temporary directory, so retain Make's knowledge that
# the current sources have already been built and installed for this Python.
BUILD_INPUTS := setup.py pyproject.toml README.rst \
	$(wildcard src/*.pyx src/*.pxi src/*.pxd src/*.h)
PYTHON3_TAG := $(shell $(PYTHON3) -c \
	'import sys; print("%s-%d.%d" % (sys.implementation.name, *sys.version_info[:2]))')
INSTALL_STAMP := build/.installed-$(PYTHON3_TAG)

.PHONY: all dev clean test bench lint py2 test2 bench2 debug debug2 \
	testdebug testdebug2 valgrind

all: $(INSTALL_STAMP)

$(INSTALL_STAMP): $(BUILD_INPUTS)
	$(PYTHON3) -m pip install --user .
	@mkdir -p $(@D)
	@touch $@

dev:
	$(PYTHON3) -m pip install --user --group dev

clean:
	rm -rf build/ src/roaringbitmap.h
	find src/ -name '*.c' -delete
	find src/ -name '*.so' -delete
	find src/ -name '*.pyc' -delete
	find src/ -name '*.html' -delete
	find tests/ -name '*.pyc' -delete
	rm -rf src/__pycache__ tests/__pycache__

test: all
	ulimit -Sv 500000; $(PYTHON3) -m pytest tests/unittests.py

bench: all
	ulimit -Sv 500000; $(PYTHON3) tests/benchmarks.py

lint:
	$(PYTHON3) -m pycodestyle --ignore=E1,W1,W503 tests/*.py \
	&& $(PYTHON3) -m pycodestyle --ignore=E1,W1,F,E901,E225,E227,E211,W503 \
			src/*.pyx src/*.pxi

py2:
	$(PYTHON2) -m pip install --user .

test2: py2
	$(PYTHON2) -m pytest tests/unittests.py

bench2: py2
	ulimit -Sv 500000; $(PYTHON2) tests/benchmarks.py

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
		python3-dbg -m pytest tests/unittests.py -v
