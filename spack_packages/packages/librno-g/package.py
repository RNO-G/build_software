from spack.package import *

class LibrnoG(MakefilePackage):
    """C++ library used by the RNO-G experiment."""

    homepage = "https://github.com/RNO-G/librno-g"
    git      = "https://github.com/RNO-G/librno-g.git"

    version('master', branch='master')

    depends_on('zlib')
    depends_on('py-pybind11', type='build')
    depends_on('python', type='build')

    def install(self, spec, prefix):
        make('install', 'PREFIX={0}'.format(prefix))
