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
SPACK_VERSION="v1.0.0"

# ==== Derived Paths ====
SPACK_DIR="${TOPDIR}/spack_internals/spack_${OS_TAG}_${SPACK_VERSION}"
ENV_NAME="${OS_TAG}"
YAML_SOURCE="./${OS_TAG}.yaml"
VIEWDIR="${TOPDIR}/${OS_TAG}"
NPROC=32

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
spack compiler add # find the compilers we have so far
echo "[+] Bootstrapping gcc@15.1.0..."
if ! spack compilers | grep -q gcc@15.1.0; then
    # install the compiler we want, and force rebuild binutils
    # along with telling it to ignore any fancy optimizations
    # that might not be available globally
    spack install --add -j "$NPROC" gcc@15.1.0 +binutils ^zlib-ng~opt
    spack compiler find $(spack location -i gcc@15.1.0)
fi

# ==== STEP 3: Create Environment (with view), and activate ====
echo "[+] Creating and activating Spack environment..."
spack env create "$ENV_NAME" "$YAML_SOURCE" --with-view "$VIEWDIR"
spack env activate "$ENV_NAME"

# ==== STEP 4: Concretize and Install Full Stack ====
echo "[+] Installing full environment..."
spack concretize --fresh --reuse
spack install -j "$NPROC"

# ==== STEP 5: Install Python Needs ====
python3 -m pip install --upgrade pip
pip3 install gnureadline h5py healpy \
    iminuit tables tqdm matplotlib numpy pandas pynverse astropy \
    scipy pybind11 uproot awkward \
    tinydb tinydb-serialization aenum pymongo dash plotly \
    toml peakutils configparser filelock "pybind11[global]"

# ==== STEP 6: Create Setup Script ====
echo "[+] Creating setup script..."
PYVER=$("$VIEWDIR/bin/python3" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
SETUP_SCRIPT="$VIEWDIR/setup_${OS_TAG}.sh"

cat > "$SETUP_SCRIPT" <<EOS
#!/bin/bash
export MYPROJ_ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export PATH="\$MYPROJ_ROOT/bin:\$PATH"
export LD_LIBRARY_PATH="\$MYPROJ_ROOT/lib:\$MYPROJ_ROOT/lib64:\$LD_LIBRARY_PATH"
export PYTHONPATH="\$MYPROJ_ROOT/lib/python$PYVER/site-packages:\$PYTHONPATH"
# Source ROOT's environment setup script
if [ -f "\$MYPROJ_ROOT/bin/thisroot.sh" ]; then
    source "\$MYPROJ_ROOT/bin/thisroot.sh"
fi
EOS

chmod +x "$SETUP_SCRIPT"
echo "[✓] Setup script written to: $SETUP_SCRIPT"
