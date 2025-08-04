from spack.package import *
import os
import shutil

class Mattak(MakefilePackage):
    """C++ library used by the RNO-G experiment."""

    homepage = "https://github.com/RNO-G/mattak"
    git      = "https://github.com/RNO-G/mattak.git"

    version('main', branch="main")
    depends_on('gmake', type='build')  # Pull in compiler support
    depends_on('cmake', type='build')
    depends_on('root')
    depends_on('py-pybind11')
    
    def setup_build_environment(self, env):
        pybind11_prefix = self.spec['py-pybind11'].prefix
        pyver = self.spec['python'].version.up_to(2)
        pybind11_dir = os.path.join(
            pybind11_prefix.lib,
            f'python{pyver}',
            'site-packages',
            'pybind11',
            'share',
            'cmake',
            'pybind11'
        )
        env.set('CMAKE_ARGS', f'-Dpybind11_DIR={pybind11_dir}')

    def build(self, spec, prefix):
        os.environ['RNO_G_INSTALL_DIR'] = str(prefix)
        os.environ['CMAKE_FLAGS'] = '-DLIBRNO_G_SUPPORT=ON'
        cc  = os.environ.get('SPACK_CC', shutil.which('gcc'))
        cxx = os.environ.get('SPACK_CXX', shutil.which('g++'))
        os.environ['CC'] = cc
        os.environ['CXX'] = cxx

        print(f"Building with CC={os.environ['CC']}, CXX={os.environ['CXX']}")
        make()

    def install(self, spec, prefix):
        # Same env may still be needed here
        os.environ['RNO_G_INSTALL_DIR'] = str(prefix)
        os.environ['CMAKE_FLAGS'] = '-DLIBRNO_G_SUPPORT=ON'
        cc  = os.environ.get('SPACK_CC', shutil.which('gcc'))
        cxx = os.environ.get('SPACK_CXX', shutil.which('g++'))
        os.environ['CC'] = cc
        os.environ['CXX'] = cxx

        print(f"Installing to prefix: {prefix}")
        make('install')
