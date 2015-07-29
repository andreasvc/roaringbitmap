"""Generic setup.py for Cython code."""
import os
import sys
from distutils.core import setup
from distutils.extension import Extension
try:
	from Cython.Build import cythonize
	from Cython.Distutils import build_ext
	USE_CYTHON = '--with-cython' in sys.argv
except ImportError:
	USE_CYTHON = False
	assert '--with-cython' not in sys.argv, 'Cython not found.'
try:
	sys.argv.remove('--with-cython')
except ValueError:
	pass


metadata = dict(name='roaringbitmap',
		version='0.2',
		description='Roaring Bitmap',
		long_description=open('README.rst').read(),
		author='Andreas van Cranenburgh',
		author_email='A.W.vanCranenburgh@uva.nl',
		url='https://github.com/andreasvc/roaringbitmap/',
		classifiers=[
				'Development Status :: 4 - Beta',
				'Intended Audience :: Science/Research',
				'License :: OSI Approved :: GNU General Public License (GPL)',
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
		'fast_fail': True,
		'nonecheck': False,
		'wraparound': False,
		'boundscheck': False,
		'embedsignature': True,
		'warn.unused': True,
		'warn.unreachable': True,
		'warn.maybe_uninitialized': True,
		'warn.undeclared': False,
		'warn.unused_arg': False,
		'warn.unused_result': False,
		}

if __name__ == '__main__':
	os.environ['GCC_COLORS'] = 'auto'
	if USE_CYTHON:
		extensions = [Extension(
				'*',
				sources=['src/*.pyx'],
				extra_compile_args=['-O3', '-DNDEBUG', '-march=native'],
				# extra_compile_args=['-O0', '-g'],
				# extra_link_args=['-g'],
				)]
		ext_modules = cythonize(
				extensions,
				annotate=True,
				compiler_directives=directives,
				language_level=3,
		)
	else:
		ext_modules = [Extension(
				'roaringbitmap',
				sources=['src/roaringbitmap.c'],
				extra_compile_args=['-O3', '-DNDEBUG', '-march=native'],
				)]
	setup(
			cmdclass=dict(build_ext=build_ext),
			ext_modules=ext_modules,
			**metadata)
