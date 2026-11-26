#!/bin/bash
set -euo pipefail

# Builds one version of the RNOG software for one OS. Gets called by build_version.sh, inside the container.
# Roughly:
#   1. clone spack (if we don't have it yet), source it, and pin the package recipes to a tag
#   2. build our own gcc with whatever gcc the container has
#   3. make the spack environment from the yaml (with the view in misc_build/), and activate it
#   4. concretize + install the whole spack stack, then build healpix
#   5. set up for building our own stuff: flags, and load the gcc ROOT was built with
#   6. pip install the python packages, and build libRootFftwWrapper
#   7. wipe + build librno-g and mattak (build_rnog.sh)
#   8. write the setup.sh that users source
#
# With --rnog-only we skip building the stack and just redo librno-g and mattak (step 7).
# But step 7 still needs the environment from steps 1, 3 and 5 (spack sourced, env activated,
# flags + compiler loaded). Those lines are mixed in with the building, and can't just move
# to the top (can't activate the env before it exists, or load ROOT's compiler before ROOT exists).
# So instead of one big "if", RNOG_ONLY gets checked in a few places to skip only the parts
# that build things, and the setup lines run either way. That way nothing gets copy-pasted.

# ==== ARGUMENTS ====
if [ $# -ne 5 ] && ! { [ $# -eq 6 ] && [ "$6" = "--rnog-only" ]; }; then
    echo "Usage: $0 <git_repo_dir> <version> <os_tag> <topdir> <nproc> [--rnog-only]"
    echo "Example: $0 /path/to/cvmfs_spack trunk el9 /cvmfs/rnog.opensciencegrid.org/trunk/el9 8"
    echo "  --rnog-only  only rebuild librno-g and mattak, against an existing build"
    exit 1
fi

GIT_REPO_DIR="$1"
VERSION="$2"
OS_TAG="$3"
DESTDIR="$4"
NPROC="$5"
RNOG_ONLY=false
if [ $# -eq 6 ]; then
    RNOG_ONLY=true
fi
SPACK_VERSION="v1.2.2"
# spack-packages tag; keep in sync with the repos: section of the yaml
SPACK_PACKAGES_TAG="v2026.10.1"
# compiler we bootstrap and build the stack with; keep in sync with the yaml
GCC_VERSION="16.2.0"

# ==== CONFIGURATION STUFF ====

# NB: for spack, MISC_DIR is the *view* directory
# That is: where we want it to put the *view* on the dependencies
MISC_DIR="${DESTDIR}/misc_build" 
RNOG_BUILD_DIR="${DESTDIR}/rnog_build"
SOURCE_DIR="${DESTDIR}/source"

# where spack should go
# and a name for the spack environment
# and tell spack how to find the yaml file
# and set up some temporary files for spack, to contain its cache blast radius
YAML_SOURCE="${GIT_REPO_DIR}/builders/${VERSION}/${VERSION}.yaml"
SPACK_DIR="${DESTDIR}/.spack_internals/spack_${VERSION}_${OS_TAG}_${SPACK_VERSION}"
ENV_NAME="${VERSION}_${OS_TAG}"
SPACK_USER_CONFIG="/scratch/spack_user_config_${VERSION}_${OS_TAG}_${SPACK_VERSION}"
SPACK_USER_CACHE="/scratch/spack_user_cache_${VERSION}_${OS_TAG}_${SPACK_VERSION}"
SPACK_TMPDIR="/scratch/spack_tmpdir_${VERSION}_${OS_TAG}_${SPACK_VERSION}"

# number of processors, and the make arguments for RNOG custom scripts
export MAKE_ARGS="--make_arg -j$NPROC"

# log everything to screen
echo "=============================================="
echo "=============================================="
echo "=============================================="
echo "[+] Using OS tag:            $OS_TAG"
echo "[+] Using version:           $VERSION"
echo "[+] Git GIT_REPO_DIR:        $GIT_REPO_DIR"
echo "[+] Using DESTDIR:           $DESTDIR"
echo "[+] Using MISC_DIR:          $MISC_DIR"
echo "[+] Using RNOG_BUILD_DIR:     $RNOG_BUILD_DIR"
echo "[+] Using SOURCE_DIR:        $SOURCE_DIR"
echo "[+] Using SPACK_DIR:         $SPACK_DIR"
echo "[+] Using SPACK_PACKAGES:    $SPACK_PACKAGES_TAG"
echo "[+] Using GCC:               $GCC_VERSION"
echo "[+] Using USER CONFIG:       $SPACK_USER_CONFIG"
echo "[+] Using USER CACHE:        $SPACK_USER_CACHE"
echo "[+] Using SPACK_TMPDIR:      $SPACK_TMPDIR"
echo "[+] Build with NPROC         $NPROC"
echo "[+] RNO-G only:             $RNOG_ONLY"
echo "=============================================="
echo "=============================================="
echo "=============================================="
echo # just clear the queue
echo
echo

# ==== STEP 1: Clone Spack if Needed ====
# with --rnog-only we never clone, bootstrap gcc, or create the env, the stack should already be there
if ! $RNOG_ONLY && [ ! -d "$SPACK_DIR" ]; then
    echo "[+] Cloning Spack into $SPACK_DIR..."
    mkdir -p "$(dirname "$SPACK_DIR")"
	  git clone --depth=1 --branch "$SPACK_VERSION" https://github.com/spack/spack.git "$SPACK_DIR"
fi
# Set paths, and set up directories, BEFORE sourcing Spack
# the "before spack" is extra important because if we don't set the config and caches
# before sourcing spack, they don't get set right
export SPACK_USER_CONFIG_PATH="$SPACK_USER_CONFIG"
export SPACK_USER_CACHE_PATH="$SPACK_USER_CACHE"
export SPACK_TMPDIR="$SPACK_TMPDIR"
export TMPDIR="$SPACK_TMPDIR"
mkdir -p "$SPACK_USER_CONFIG"
mkdir -p "$SPACK_USER_CACHE"
mkdir -p "$SPACK_TMPDIR"
mkdir -p "$SOURCE_DIR"
mkdir -p "$RNOG_BUILD_DIR"
mkdir -p "$MISC_DIR"
source "$SPACK_DIR/share/spack/setup-env.sh"
spack repo update builtin --tag "$SPACK_PACKAGES_TAG"

# ==== STEP 2: Upgrade GCC ====
spack compiler add # find the compilers we have so far
spack compilers
BOOTSTRAP_COMPILER=$(spack compilers | grep "gcc@" | head -1 | grep -o 'gcc@[0-9.]*')
BOOTSTRAP_VERSION="${BOOTSTRAP_COMPILER#gcc@}"
echo "[+] Will use $BOOTSTRAP_COMPILER to bootstrap gcc@${GCC_VERSION}"
if ! $RNOG_ONLY && ! spack compilers | grep -q "gcc@${GCC_VERSION}"; then
    # install the compiler we want, and force rebuild binutils
    # along with telling it to ignore any fancy optimizations
    # that might not be available globally
    echo "[+] Bootstrapping gcc@${GCC_VERSION}..."
    spack install --add -j "$NPROC" "gcc@${GCC_VERSION} +binutils target=x86_64_v2 %gcc@${BOOTSTRAP_VERSION} ^zlib-ng~opt"
    spack compiler find $(spack location -i "gcc@${GCC_VERSION}")
fi
spack compilers

# ==== STEP 3: Create Environment (with view), and activate ====
echo "[+] Creating and activating Spack environment..."
if ! $RNOG_ONLY && [ ! -d "$SPACK_ROOT/var/spack/environments/$ENV_NAME" ]; then
    spack env create "$ENV_NAME" "$YAML_SOURCE" --with-view "$MISC_DIR"
fi
spack env activate "$ENV_NAME"

# ==== STEP 4: Concretize and Install Full Stack ====
if ! $RNOG_ONLY; then
    echo "[+] Starting concretization..."
    spack concretize --fresh
    echo "[+] Concretization finished. Starting installation..."
    spack install -j "$NPROC"

    # build healpix now, before we pip install healpy (healpix will bring in libsharp)
    ${GIT_REPO_DIR}/builders/${VERSION}/build_healpix.sh --source "$SOURCE_DIR" --build "$RNOG_BUILD_DIR" --root "$MISC_DIR" --deps "$MISC_DIR" $MAKE_ARGS || error 104 "Failed healpix build"
fi


# ==== STEP 5: Set up for building our own stuff (pip packages, and the RNOG software) ====
export PIP_CACHE_DIR=$SPACK_USER_CACHE_PATH # set pip cache (again, contain the blast radius...)
# need these to make sure pip installs healpy correctly by building it against
# our copy of cfitsio
export LDFLAGS="-L$MISC_DIR/lib -Wl,-rpath,$MISC_DIR/lib"
export CPPFLAGS="-I$MISC_DIR/include"
export PKG_CONFIG_PATH="$MISC_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"

ROOT_COMPILER=$(spack find --format '{compiler}' root | head -1)
echo "ROOT was built with: $ROOT_COMPILER"
spack load $ROOT_COMPILER

# Manually add GCC's library path since spack load didn't do it
GCC_PREFIX=$(spack location -i $ROOT_COMPILER)
export LD_LIBRARY_PATH="$GCC_PREFIX/lib64:$GCC_PREFIX/lib:$LD_LIBRARY_PATH"

echo "LD_LIBRARY_PATH after fix: $LD_LIBRARY_PATH"
echo "PATH: $PATH"

# ==== STEP 6: Python packages and libRootFftwWrapper ====
if ! $RNOG_ONLY; then
    # pip is pinned in the yaml, so don't upgrade it here
    pip3 install \
        gnureadline==8.3.3 \
        healpy==1.20.1 \
        iminuit==2.33.0 \
        tqdm==4.70.1 \
        matplotlib==3.11.2 \
        numpy==2.5.5 \
        pandas==3.1.1 \
        pynverse==0.1.4.6 \
        astropy==8.0.3 \
        scipy==1.18.1 \
        uproot==5.7.8 \
        awkward==2.15.1 \
        libconf==2.0.1 \
        tinydb==4.9.0 \
        tinydb-serialization==2.2.0 \
        aenum==3.1.17 \
        pymongo==4.20.1 \
        dash==4.5.1 \
        plotly==7.1.0 \
        toml==0.10.2 \
        peakutils==1.3.5 \
        configparser==7.3.0 \
        filelock==4.3.1 \
        pre-commit==4.7.0
    # save what pip actually installed, so we know later
    pip3 freeze > "${DESTDIR}/pip_freeze.txt"

    ${GIT_REPO_DIR}/builders/${VERSION}/build_libRootFftwWrapper.sh --source "$SOURCE_DIR" --build "$RNOG_BUILD_DIR" --root "$MISC_DIR" --deps "$MISC_DIR" $MAKE_ARGS || error 108 "Failed libRootFftwWrapper build"
fi

# ==== STEP 7: librno-g and mattak ====
# (this is the only thing --rnog-only actually builds)
${GIT_REPO_DIR}/builders/${VERSION}/build_rnog.sh "$SOURCE_DIR" "$RNOG_BUILD_DIR" "$MISC_DIR" "$NPROC" || error 109 "Failed RNO-G build"

# ==== STEP 8: Create Setup Script ====

cat > ${DESTDIR}/setup.sh << 'EOF'
#!/bin/sh
# Setup script for unstable version of the RNOG software

export RNOG_SETUP_DIR="PATH_PLACEHOLDER_REPLACE_ME"
# If the fake path in RNOG_SETUP_DIR wasn't replaced, try the working directory
if [ ! -d "$RNOG_SETUP_DIR" ]; then
	export RNOG_SETUP_DIR=$(pwd)
fi

export RNOG_UTIL_INSTALL_DIR="${RNOG_SETUP_DIR%/}/rnog_build"
export RNOG_DEPS_INSTALL_DIR="${RNOG_SETUP_DIR%/}/misc_build"
export RNOG_ROOT_LIB_DIR="${RNOG_UTIL_INSTALL_DIR%/}/lib"
export RNOG_SIM_LIB_DIR="${RNOG_UTIL_INSTALL_DIR%/}/lib"
export NUPHASE_INSTALL_DIR="$RNOG_UTIL_INSTALL_DIR"

# Executables and library stuff that we compiled
export PATH="$RNOG_UTIL_INSTALL_DIR/bin:$RNOG_DEPS_INSTALL_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$RNOG_UTIL_INSTALL_DIR/lib:$RNOG_DEPS_INSTALL_DIR/lib/root:$RNOG_DEPS_INSTALL_DIR/lib:$RNOG_DEPS_INSTALL_DIR/lib64:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$RNOG_UTIL_INSTALL_DIR/lib:$RNOG_DEPS_INSTALL_DIR/lib:$DYLD_LIBRARY_PATH"

# detect and set python (Find the python3.* site-packages directory)
SITE_PACKAGES=$(find "${RNOG_DEPS_INSTALL_DIR}/lib" -maxdepth 1 -type d -name 'python3.*' -print -quit 2>/dev/null)
if [ -n "$SITE_PACKAGES" ] && [ -d "${SITE_PACKAGES}/site-packages" ]; then
    export PYTHONPATH="${SITE_PACKAGES}/site-packages${PYTHONPATH:+:$PYTHONPATH}"
else
    echo "Warning: Could not find Python site-packages directory in ${RNOG_DEPS_INSTALL_DIR}/lib" >&2
fi

# our NuRadioMC (and radiotools, proposal) only goes on the path if you ask for it,
# with "source setup.sh --nuradio". That way people can use their own NuRadioMC in a venv.
if [ "${1:-}" = "--nuradio" ]; then
    RNOG_SITE_PACKAGES=$(find "${RNOG_UTIL_INSTALL_DIR}/lib" -maxdepth 1 -type d -name 'python3.*' -print -quit 2>/dev/null)
    if [ -n "$RNOG_SITE_PACKAGES" ] && [ -d "${RNOG_SITE_PACKAGES}/site-packages" ]; then
        export PYTHONPATH="${RNOG_SITE_PACKAGES}/site-packages${PYTHONPATH:+:$PYTHONPATH}"
    else
        echo "Warning: --nuradio given, but there's no NuRadioMC in ${RNOG_UTIL_INSTALL_DIR}/lib" >&2
    fi
fi

# Do stuff that would have been done in what thisroot.sh would add, but via the view)
export ROOTSYS="$RNOG_DEPS_INSTALL_DIR"
# export PYTHONPATH="$RNOG_DEPS_INSTALL_DIR/lib/python$PYVER/site-packages${PYTHONPATH:+:$PYTHONPATH}"
for d in "$RNOG_DEPS_INSTALL_DIR/lib/root" "$RNOG_DEPS_INSTALL_DIR/lib64/root"; do
  if [ -d "$d" ]; then
    case ":$PYTHONPATH:" in
      *:"$d":*) : ;;  # already present
      *) export PYTHONPATH="$d${PYTHONPATH:+:$PYTHONPATH}";;
    esac
  fi
done

# exports for CMake
export CMAKE_PREFIX_PATH="$RNOG_DEPS_INSTALL_DIR"
export CC="$RNOG_DEPS_INSTALL_DIR/bin/gcc"
export CXX="$RNOG_DEPS_INSTALL_DIR/bin/g++"
export FC="$RNOG_DEPS_INSTALL_DIR/bin/gfortran"

# exports for stuff besides CMake
export SQLITE_ROOT="$RNOG_DEPS_INSTALL_DIR"
export GSL_ROOT="$RNOG_DEPS_INSTALL_DIR"
export GSLDIR="$RNOG_DEPS_INSTALL_DIR"
export FFTWSYS="$RNOG_DEPS_INSTALL_DIR"

# control blas's enthusiasm
# specifically important for numpy, which, when blas is enabled, 
# will spin up threads for *all* cores on import
export OPENBLAS_NUM_THREADS=${OPENBLAS_NUM_THREADS:-1}
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-1}     # catches OpenMP builds
export MKL_NUM_THREADS=${MKL_NUM_THREADS:-1}     # if anyone uses MKL
export BLIS_NUM_THREADS=${BLIS_NUM_THREADS:-1}   # if BLIS shows up
export VECLIB_MAXIMUM_THREADS=${VECLIB_MAXIMUM_THREADS:-1}  # Apple Accelerate
export NUMEXPR_MAX_THREADS=${NUMEXPR_MAX_THREADS:-1}        # if numexpr is used


EOF

# Now replace the placeholder with the actual value
sed -i "s|PATH_PLACEHOLDER_REPLACE_ME|$DESTDIR|g" ${DESTDIR}/setup.sh
