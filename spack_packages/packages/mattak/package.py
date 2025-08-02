from spack.package import *
import os

class Mattak(CMakePackage):
    """C++ library used by the RNO-G experiment."""

    homepage = "https://github.com/RNO-G/mattak"
    git      = "https://github.com/RNO-G/mattak.git"

    version('main', branch="main")

    depends_on('cmake', type='build')

    def install(self, spec, prefix):
        os.environ['RNO_G_INSTALL_DIR'] = str(prefix)
        os.environ['CC'] = spack_cc
        os.environ['CXX'] = spack_cxx
        os.environ['CMAKE_FLAGS'] = '-DLIBRNO_G_SUPPORT=ON'

        print(f"Installing to prefix: {prefix}")
        print(f"Using CC: {os.environ['CC']}")
        print(f"Using CXX: {os.environ['CXX']}")

        # args = self.std_cmake_args + [
        #     f'-DCMAKE_INSTALL_PREFIX={prefix}',
        #     f'-DCMAKE_C_COMPILER={spack_cc}',
        #     f'-DCMAKE_CXX_COMPILER={spack_cxx}',
        #     '-DLIBRNO_G_SUPPORT=ON'
        # ]
        # cmake('.', *args)
        make()
        make('install')
