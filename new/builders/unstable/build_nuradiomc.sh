#!/bin/sh
# Build script for NuRadioMC (and radiotools, which it needs).
# These pip install into rnog_build, not the base python, so they're only on the path
# with "source setup.sh --nuradio". That way people can use their own NuRadioMC in a venv.
# Everything else NuRadioMC needs is already in the base stack (see build.sh), hence --no-deps.

# Set script parameters
PACKAGE_NAME="NuRadioMC"
REPO_URL="https://github.com/nu-radio/NuRadioMC.git"
BRANCH="develop"
PACKAGE_DIR_NAME="NuRadioMC"
RADIOTOOLS_VERSION="0.2.5"
# NuRadioMC imports six all over the place but doesn't list it as a dependency
SIX_VERSION="1.17.0"
# for galactic noise (channelGalacticNoiseAdder). pygdsm needs ephem, the rest it needs is already in the base stack
PYGDSM_VERSION="1.7.1"
EPHEM_VERSION="4.2.1"
# antenna models to download now, since NuRadioReco can't download them later on read-only cvmfs.
# the first three are what the RNO-G detector files use (vpol, hpol, lpda), hpol_v4 is the newer hpol,
# and the plain InfFirn lpda is what the RNO-G cosmic ray array file uses. Add more here if people need them
ANTENNAS="RNOG_vpol_4inch_center_n1.73 RNOG_quadslot_v3_air_rescaled_to_n1.74 createLPDA_100MHz_InfFirn_n1.4 RNOG_hpol_v4_8inch_center_n1.74 createLPDA_100MHz_InfFirn"
# PROPOSAL tables (for secondaries from muons and taus). These are the only four configs NuRadioMC has
# pre-made tables for. Greenland is the RNO-G one, the others are small enough (8-34 MB each) to just grab too
PROPOSAL_CONFIGS="Greenland InfIce SouthPole MooresBay"


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


# Clone the package (shallow, keeps .git so the commit hash is recorded)
cd "$SOURCE_DIR"
if [ $SKIP_DOWNLOAD = false ]; then
	echo "Cloning $PACKAGE_NAME to $SOURCE_DIR"
	GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$PACKAGE_DIR_NAME" || exit 11
fi

# Set required environment variables
if [ $SKIP_BUILD = false ]; then
	export RNOG_UTIL_INSTALL_DIR="${BUILD_DIR%/}"
	export RNOG_DEPS_INSTALL_DIR="${DEPS_BUILD_DIR%/}"
	# lib64 too, spack put spdlog there and PROPOSAL needs it (setup.sh does the same for users)
	export LD_LIBRARY_PATH="$RNOG_DEPS_INSTALL_DIR/lib:$RNOG_DEPS_INSTALL_DIR/lib64:$LD_LIBRARY_PATH"
fi

# Run package installation
if [ $SKIP_BUILD = false ]; then
	echo "Installing $PACKAGE_NAME, radiotools, six, pygdsm, and ephem"
	cd "$SOURCE_DIR"
	pip3 install --no-deps --prefix "$RNOG_UTIL_INSTALL_DIR" "./$PACKAGE_DIR_NAME" "radiotools==$RADIOTOOLS_VERSION" "six==$SIX_VERSION" "pygdsm==$PYGDSM_VERSION" "ephem==$EPHEM_VERSION" || exit 21
	SITE_PACKAGES=$(echo "$RNOG_UTIL_INSTALL_DIR"/lib/python3.*/site-packages)

	# the c++ ray tracer. NuRadioMC tries to compile this itself the first time it's imported,
	# which won't work on read-only cvmfs, so build it now with their own script (needs GSL)
	echo "Building the NuRadioMC c++ ray tracer"
	GSLDIR="$RNOG_DEPS_INSTALL_DIR" PYTHON=python3 bash "$SITE_PACKAGES/NuRadioMC/SignalProp/AnalyticRayTracingImpl/install.sh" || exit 22

	# data files. NuRadioMC downloads these into its own folders the first time they're used,
	# so use each one once here: the antenna models, the ARZ shower library, the neutrino cross sections,
	# and the PROPOSAL tables (setting up a propagator downloads them, and if they somehow don't match
	# our PROPOSAL build, PROPOSAL makes new ones right there, which is also fine)
	echo "Downloading antenna models ($ANTENNAS), the shower library, the cross sections, and PROPOSAL tables ($PROPOSAL_CONFIGS)"
	PYTHONPATH="$SITE_PACKAGES:$PYTHONPATH" python3 -c "
from NuRadioReco.detector.antennapattern import AntennaPatternProvider
from NuRadioMC.SignalGen.ARZ.ARZ import ARZ
from NuRadioMC.utilities import cross_sections
provider = AntennaPatternProvider()
for name in '$ANTENNAS'.split():
    provider.load_antenna_pattern(name)
ARZ()
cross_sections._read_differential_cross_section_BGR18()
from NuRadioMC.EvtGen.NuRadioProposal import ProposalFunctions
for config in '$PROPOSAL_CONFIGS'.split():
    functions = ProposalFunctions(config_file=config)
    for particle_code in [13, -13, 15, -15]:
        functions._ProposalFunctions__get_propagator(particle_code=particle_code)
" || exit 23
fi

# Clean up source directory if requested
if [ $CLEAN_SOURCE = true ]; then
	echo "Removing $PACKAGE_NAME source directory from $SOURCE_DIR"
	cd "$SOURCE_DIR"
	rm -rf "$PACKAGE_DIR_NAME"
fi

echo "$PACKAGE_NAME installed in $RNOG_UTIL_INSTALL_DIR"
