#!/bin/bash
set -euo pipefail

# ==== ARGUMENTS ====
if [ $# -ne 2 ]; then
    echo "Usage: $0 <os_tag> <topdir>"
    echo "Example: $0 el9 /cvmfs/myorg/software"
    exit 1
fi

OS_TAG="$1"
TOPDIR="$2"
SPACK_VERSION="v1.0.2"

# ==== Derived Paths ====
SPACK_DIR="${TOPDIR}/.spack_internals/spack_${OS_TAG}_${SPACK_VERSION}"
ENV_NAME="${OS_TAG}"
YAML_SOURCE="./${OS_TAG}.yaml"
VIEWDIR="${TOPDIR}/${OS_TAG}"
NPROC=4

echo "[+] Using OS tag:     $OS_TAG"
echo "[+] Using TOPDIR:     $TOPDIR"
echo "[+] Using VIEWDIR:    $VIEWDIR"
echo "[+] Using SPACK DIR:  $SPACK_DIR"

# ==== STEP 1: Clone Spack if Needed ====
if [ ! -d "$SPACK_DIR" ]; then
    echo "[+] Cloning Spack into $SPACK_DIR..."
    mkdir -p "$(dirname "$SPACK_DIR")"
    git clone --depth=1 --branch "$SPACK_VERSION" https://github.com/spack/spack.git "$SPACK_DIR"
fi
source "$SPACK_DIR/share/spack/setup-env.sh"

# ==== STEP 2: Upgrade GCC first ====
# spack compiler add # find the compilers we have so far
# echo "[+] Bootstrapping gcc@15.2.0..."
# if ! spack compilers | grep -q gcc@15.2.0; then
#     # install the compiler we want, and force rebuild binutils
#     # along with telling it to ignore any fancy optimizations
#     # that might not be available globally
#     spack install --add -j "$NPROC" gcc@15.2.0 +binutils ^zlib-ng~opt
#     spack compiler find $(spack location -i gcc@15.2.0)
# fi

# ==== STEP 2: Upgrade GCC first ====

spack compiler add

# Unpin/neutralize external gcc so the solver can choose a new gcc
if spack config get packages | grep -q '^  gcc:'; then
  echo "[+] Neutralizing external gcc pin..."
  spack config rm packages:gcc:externals || true
  spack config add "packages:gcc:buildable:true"
fi

TARGET_GCC="15.2.0"
BOOTSTRAP_FLOOR="11.3.0"
INTERMEDIATE_GCC="12.3.0"
NPROC="${NPROC:-4}"

version_ge() { [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

mapfile -t GCC_VERS < <(spack compilers | awk '/^gcc@/ {sub("gcc@","",$1); print $1}' | sort -V)
BEST_GCC=""; [ ${#GCC_VERS[@]} -gt 0 ] && BEST_GCC="${GCC_VERS[-1]}"

if [ -z "$BEST_GCC" ] || ! version_ge "$BEST_GCC" "$BOOTSTRAP_FLOOR"; then
  echo "[+] Building intermediate gcc@${INTERMEDIATE_GCC} (from %gcc@${BEST_GCC:-system})..."
  FROM_SPEC=""; [ -n "$BEST_GCC" ] && FROM_SPEC="%gcc@${BEST_GCC}"
  spack install -j "$NPROC" gcc@${INTERMEDIATE_GCC} ${FROM_SPEC}
  spack compiler find "$(spack location -i gcc@${INTERMEDIATE_GCC})"
  BEST_GCC="${INTERMEDIATE_GCC}"
else
  echo "[+] Bootstrap floor met with gcc@${BEST_GCC}."
fi

if spack compilers | grep -q "gcc@${TARGET_GCC}\b"; then
  echo "[+] gcc@${TARGET_GCC} already registered; skipping build."
else
  echo "[+] Building gcc@${TARGET_GCC} with %gcc@${BEST_GCC} ..."
  spack install --add -j "$NPROC" gcc@${TARGET_GCC} %gcc@${BEST_GCC} +binutils ^zlib-ng~opt
  spack compiler find "$(spack location -i gcc@${TARGET_GCC})"
fi

echo "[+] Compilers now:"
spack compilers

# ==== STEP 3: Create Environment (with view), and activate ====
echo "[+] Creating and activating Spack environment..."
spack env create "$ENV_NAME" "$YAML_SOURCE" --with-view "$VIEWDIR"
spack env activate "$ENV_NAME"

# ==== STEP 4: Concretize and Install Full Stack ====
echo "[+] Adding custom repo..."
spack repo add "./spack_packages"
echo "[+] Starting concretization..."
spack concretize --fresh --reuse
echo "[+] Concretization finished. Starting installation..."
spack install -j "$NPROC"

# ==== STEP 5: Install Python Needs ====
echo "[+] Installing final pip packages..."
python3 -m pip install --upgrade pip
pip3 install gnureadline h5py healpy \
    iminuit tables tqdm matplotlib numpy pandas pynverse astropy \
    scipy uproot awkward libconf \
    tinydb tinydb-serialization aenum pymongo dash plotly \
    toml peakutils configparser filelock pre-commit

# ==== STEP 6: Create Setup Script ====
echo "[+] Creating setup script..."
PYVER=$("$VIEWDIR/bin/python3" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
SETUP_SCRIPT="$TOPDIR/setup_${OS_TAG}.sh"

cat > "$SETUP_SCRIPT" <<EOS
#!/bin/bash
if [ -n "\${ZSH_VERSION:-}" ]; then _SRC="\${(%):-%N}"; else _SRC="\${BASH_SOURCE[0]:-\$0}"; fi
export MYPROJ_ROOT="\$(cd "\$(dirname "\$_SRC")/$OS_TAG" && pwd)"

# Executables from the view
export PATH="\$MYPROJ_ROOT/bin:\$PATH"

# Some exports for CMake
export CMAKE_PREFIX_PATH="\$MYPROJ_ROOT\${CMAKE_PREFIX_PATH:+:\$CMAKE_PREFIX_PATH}"
export CC="\$MYPROJ_ROOT/bin/gcc"
export CXX="\$MYPROJ_ROOT/bin/g++"
export FC="\$MYPROJ_ROOT/bin/gfortran"

# Optional convenience vars some scripts still look for
export ROOTSYS="\$MYPROJ_ROOT"
export GSLDIR="\$MYPROJ_ROOT"

# Python modules installed into the view
export PYTHONPATH="\$MYPROJ_ROOT/lib/python$PYVER/site-packages\${PYTHONPATH:+:\$PYTHONPATH}"

# PyROOT modules (what thisroot.sh would add, but via the view)
for d in "\$MYPROJ_ROOT/lib/root" "\$MYPROJ_ROOT/lib64/root"; do
  if [ -d "\$d" ]; then
    case ":\$PYTHONPATH:" in
      *:"\$d":*) : ;;  # already present
      *) export PYTHONPATH="\$d\${PYTHONPATH:+:\$PYTHONPATH}";;
    esac
  fi
done

export LD_LIBRARY_PATH="\$MYPROJ_ROOT/lib:\$MYPROJ_ROOT/lib64\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="\$MYPROJ_ROOT/lib/root:\$LD_LIBRARY_PATH"

# control blas's enthusiasm
# specifically important for numpy, which, when blas is enabled, 
# will spin up threads for *all* cores on import
export OPENBLAS_NUM_THREADS=${OPENBLAS_NUM_THREADS:-1}
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-1}     # catches OpenMP builds
export MKL_NUM_THREADS=${MKL_NUM_THREADS:-1}     # if anyone uses MKL
export BLIS_NUM_THREADS=${BLIS_NUM_THREADS:-1}   # if BLIS shows up
export VECLIB_MAXIMUM_THREADS=${VECLIB_MAXIMUM_THREADS:-1}  # Apple Accelerate
export NUMEXPR_MAX_THREADS=${NUMEXPR_MAX_THREADS:-1}        # if numexpr is used
EOS

chmod +x "$SETUP_SCRIPT"
echo "[✓] Setup script written to: $SETUP_SCRIPT"
