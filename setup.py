from setuptools import setup, Extension
from Cython.Build import cythonize

setup(
    name = 'pyvislcg3',
    description = 'Python bindings for vislcg3',
    author = 'Bjarte Johansen',
    url = 'https://github.com/ljos/pyvislcg3',
    version = '0.0.1',
    packages = ['cg3'],
    license = 'GPLv3',
    install_requires = [
        'funcparserlib>=0.3.6'
    ],
    ext_modules = cythonize([
        Extension(
            'cg3.core',
            ['cg3/core.pyx'],
            libraries=['cg3']
        )
    ])
)
