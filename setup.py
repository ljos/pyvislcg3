from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

setup(
    name = 'pyvislcg3',
    description = 'Python bindings for vislcg3',
    author = 'Bjarte Johansen',
    url = 'https://github.com/ljos/pyvislcg3',
    version = '0.0.1',
    packages = ['cg3'],
    ext_modules = cythonize([
        Extension(
            'cg3.core',
            ['cg3/core.pyx'],
            include_dirs =['.', 'c'],
            libraries=['cg3']
        )
    ])
)
