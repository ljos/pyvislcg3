from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

setup(
    ext_modules = cythonize([
        Extension(
            "cg3",
            ["src/cg3/cg3.pyx", "src/memstream/memstream.c"],
            include_dirs =["src"],
            libraries=["cg3"]
        )
    ])
)
