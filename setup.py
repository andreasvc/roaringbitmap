"""Generic setup.py for Cython code."""
import os
import platform
import sys
from setuptools import Extension, setup

PY2 = sys.version_info[0] == 2

# In releases, include C sources but not Cython sources; otherwise, use cython
# to figure out which files may need to be re-cythonized.
USE_CYTHON = os.path.exists('src/roaringbitmap.pyx')
if USE_CYTHON:
	try:
		from Cython.Build import cythonize
		from Cython.Distutils import build_ext
		from Cython.Compiler import Options
		Options.fast_fail = True
	except ImportError:
		raise RuntimeError('could not import Cython.')
	cmdclass = dict(build_ext=build_ext)
else:
	cmdclass = dict()

DEBUG = '--debug' in sys.argv
if DEBUG:
	sys.argv.remove('--debug')

MTUNE = '--with-mtune' in sys.argv
if MTUNE:
        sys.argv.remove('--with-mtune')

# Release wheels must not inherit all instruction sets from the CI host.  The
# x86-64 wheels deliberately require POPCNT, which provides most of the
# performance benefit of -march=native while remaining a predictable target.
WHEEL_BUILD = os.environ.get('ROARINGBITMAP_BUILD_WHEEL') == '1'

with open('README.rst') as inp:
	README = inp.read()

METADATA = dict(name='roaringbitmap',
		version='0.7.4',
		description='Roaring Bitmap',
		long_description=README,
		long_description_content_type='text/x-rst',
		author='Andreas van Cranenburgh',
		author_email='A.W.van.Cranenburgh@rug.nl',
		url='http://roaringbitmap.readthedocs.io',
		license='GPL-2.0-or-later',
		platforms=['Many'],
		classifiers=[
				'Development Status :: 4 - Beta',
				'Intended Audience :: Science/Research',
				'Operating System :: POSIX',
				'Programming Language :: Python :: 2.7',
				'Programming Language :: Python :: 3.3',
				'Programming Language :: Cython',
		],
)

# some of these directives increase performance,
# but at the cost of failing in mysterious ways.
directives = {
		'profile': False,
		'cdivision': True,
		'nonecheck': False,
		'wraparound': False,
		'boundscheck': False,
		'infer_types': None,
		'embedsignature': True,
		'warn.unused': True,
		'warn.unreachable': True,
		'warn.maybe_uninitialized': True,
		'warn.undeclared': False,
		'warn.unused_arg': False,
		'warn.unused_result': False,
		}

if __name__ == '__main__':
	if sys.version_info[:2] < (2, 7) or (3, 0) <= sys.version_info[:2] < (3, 3):
		raise RuntimeError('Python version 2.7 or >= 3.3 required.')
	os.environ['GCC_COLORS'] = 'auto'
	# NB: could also use Cython compile-time definition,
	# but this would lead to different C output for Python 2/3.
	extra_compile_args = ['-DPY2=%d' % PY2]  # '-fopt-info-vec-missed',
	if sys.platform == 'win32':
		# https://docs.microsoft.com/en-us/cpp/intrinsics/bitscanforward-bitscanforward64?view=vs-2017
		extra_compile_args += ['-EHsc']
	else:
		extra_compile_args += [
				'-Wno-strict-prototypes', '-Wno-unreachable-code', '-Wextra']
	extra_link_args = []
	if not DEBUG and sys.platform != 'win32':
		extra_compile_args += ['-O3', '-DNDEBUG']
		if WHEEL_BUILD:
			if platform.machine().lower() in ('amd64', 'x86_64'):
				extra_compile_args += [
						'-DROARINGBITMAP_REQUIRE_POPCNT=1', '-mpopcnt']
		else:
			extra_compile_args += (
					['-mtune=native'] if MTUNE else ['-march=native'])
		extra_link_args += ['-DNDEBUG']
	if USE_CYTHON:
		if DEBUG:
			directives.update(wraparound=True, boundscheck=True)
			if sys.platform == 'win32':
				extra_compile_args += ['-DDEBUG', '-Od', '-Zi']
				extra_link_args += ['-DEBUG']
			else:
				extra_compile_args += ['-g', '-O0',
						# '-fsanitize=address', '-fsanitize=undefined',
						'-fno-omit-frame-pointer']
				extra_link_args += ['-g']
		ext_modules = cythonize(
				[Extension(
					'*',
					sources=['src/*.pyx'],
					extra_compile_args=extra_compile_args,
					extra_link_args=extra_link_args)],
				annotate=True,
				compiler_directives=directives,
				language_level=3)
	else:
		ext_modules = [Extension(
				'roaringbitmap',
				sources=['src/roaringbitmap.c'],
				extra_compile_args=extra_compile_args,
				extra_link_args=extra_link_args)]
	setup(
			cmdclass=cmdclass,
			ext_modules=ext_modules,
			**METADATA)
