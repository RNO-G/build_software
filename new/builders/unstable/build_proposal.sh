#!/bin/sh
# Build script for PROPOSAL (lepton propagation, NuRadioMC wants it), plus CubicInterpolation, which it needs.
# pip install proposal builds through conan, which drags in its own boost and everything else.
# We already have all of that from spack, so this is just the plain cmake build from their INSTALL.md.

# Set script parameters
PACKAGE_NAME="PROPOSAL"
REPO_URL="https://github.com/tudo-astroparticlephysics/PROPOSAL.git"
BRANCH="7.6.2"
PACKAGE_DIR_NAME="PROPOSAL"
CUBIC_REPO_URL="https://github.com/MaxSac/cubic_interpolation.git"
CUBIC_BRANCH="v0.1.5"
CUBIC_DIR_NAME="cubic_interpolation"


usage() {
	echo "usage: $0 [-h] [-d destination] [-s destination] [-b destination] [-r directory] [--deps directory] [--make_arg argument] [--skip_download, --skip_build] [--clean_source]"
	echo "  -h, --help                      display this help message"
	echo "  -d, --dest destination          set the destination directory (containing source and build directories)"
	echo "  -s, --source destination        set the source destination directory"
	echo "  -b, --build destination         set the build destination directory"
	echo "  -r, --root directory            set the root build directory"
	echo "  --deps directory                set the dependency build directory"
	echo "  --make_arg argument             additional argument to be passed to make"
	echo "  --skip_download                 $PACKAGE_NAME exists pre-downloaded at the source destination"
	echo "  --skip_build                    $PACKAGE_NAME has already been built at the build destination"
	echo "  --clean_source                  remove source directory after build"
}

# Parse command line options
SKIP_DOWNLOAD=false
SKIP_BUILD=false
CLEAN_SOURCE=false
while [ "$1" != "" ]; do
	case $1 in
		-h | --help )
			usage
			exit
		;;
		-d | --dest )
			shift
			DEST="$1"
		;;
		-s | --source )
			shift
			SOURCE_DIR="$1"
		;;
		-b | --build )
			shift
			BUILD_DIR="$1"
		;;
		-r | --root )
			shift
			ROOT_BUILD_DIR="$1"
		;;
		--deps )
			shift
			DEPS_BUILD_DIR="$1"
		;;
		--make_arg )
			shift
			MAKE_ARG="$1"
		;;
		--skip_download )
			SKIP_DOWNLOAD=true
		;;
		--skip_build )
			SKIP_BUILD=true
		;;
		--clean_source)
			CLEAN_SOURCE=true
		;;
		* )
			usage
			exit 1
		;;
	esac
	shift
done

if [ "$DEST" != "" ]; then
	if [ -z "$SOURCE_DIR" ]; then
		SOURCE_DIR="${DEST%/}/source/"
	fi
	if [ -z "$BUILD_DIR" ]; then
		BUILD_DIR="${DEST%/}/build/"
	fi
fi

if [ -z "$DEPS_BUILD_DIR" ]; then
	DEPS_BUILD_DIR="$BUILD_DIR"
fi

if [ -z "$ROOT_BUILD_DIR" ]; then
	ROOT_BUILD_DIR="$BUILD_DIR"
fi

if [ ! -d "$SOURCE_DIR" ]; then
	echo "Invalid source destination directory: $SOURCE_DIR"
	exit 2
fi
if [ ! -d "$BUILD_DIR" ]; then
	echo "Invalid build destination directory: $BUILD_DIR"
	exit 3
fi
if [ ! -d "$DEPS_BUILD_DIR" ]; then
	echo "Invalid dependency build directory: $DEPS_BUILD_DIR"
	exit 4
fi
if [ ! -d "$ROOT_BUILD_DIR" ]; then
	echo "Invalid root build directory: $ROOT_BUILD_DIR"
	exit 5
fi


# Clone the packages
cd "$SOURCE_DIR"
if [ $SKIP_DOWNLOAD = false ]; then
	echo "Cloning $PACKAGE_NAME and CubicInterpolation to $SOURCE_DIR"
	rm -rf "$PACKAGE_DIR_NAME" "$CUBIC_DIR_NAME"
	GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$CUBIC_BRANCH" "$CUBIC_REPO_URL" "$CUBIC_DIR_NAME" || exit 11
	GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$PACKAGE_DIR_NAME" || exit 12
fi

# Set required environment variables
if [ $SKIP_BUILD = false ]; then
	export RNOG_DEPS_INSTALL_DIR="${DEPS_BUILD_DIR%/}"
	export LD_LIBRARY_PATH="$RNOG_DEPS_INSTALL_DIR/lib:$LD_LIBRARY_PATH"
	export PATH="$RNOG_DEPS_INSTALL_DIR/bin:$PATH"
	export CMAKE_PREFIX_PATH="$RNOG_DEPS_INSTALL_DIR"
fi

# Run package installation
# Both go into the deps dir (misc_build), like healpix, since they're part of the base stack
if [ $SKIP_BUILD = false ]; then
	# CubicInterpolation first, PROPOSAL needs it.
	# Both build static libraries, and cubic needs -fPIC to end up inside the python module
	echo "Compiling CubicInterpolation"
	cd "$SOURCE_DIR/$CUBIC_DIR_NAME"
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$RNOG_DEPS_INSTALL_DIR" -DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON || exit 21
	cd build
	make "$MAKE_ARG" || exit 22
	make install "$MAKE_ARG" || exit 23

	echo "Compiling $PACKAGE_NAME"
	cd "$SOURCE_DIR/$PACKAGE_DIR_NAME"
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$RNOG_DEPS_INSTALL_DIR" -DCMAKE_INSTALL_LIBDIR=lib \
		-DBUILD_PYTHON=ON -Dpybind11_DIR="$(python3 -m pybind11 --cmakedir)" || exit 24
	cd build
	make "$MAKE_ARG" || exit 25
	make install "$MAKE_ARG" || exit 26

	# the python module gets installed next to the libraries, move it to where python looks
	PY_SITE=$(python3 -c "import site; print(site.getsitepackages()[0])")
	mv "$RNOG_DEPS_INSTALL_DIR"/lib/proposal.cpython-*.so "$PY_SITE"/ || exit 27
fi

# Clean up source directory if requested
if [ $CLEAN_SOURCE = true ]; then
	echo "Removing $PACKAGE_NAME and CubicInterpolation source directories from $SOURCE_DIR"
	cd "$SOURCE_DIR"
	rm -rf "$PACKAGE_DIR_NAME" "$CUBIC_DIR_NAME"
fi

echo "$PACKAGE_NAME installed in $RNOG_DEPS_INSTALL_DIR"
