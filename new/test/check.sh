#!/bin/bash
# Quick sanity checks on a build. Sources the setup.sh you give it, and runs a few commands.
#
# On the real thing (anywhere with cvmfs, e.g. OSC):
#   bash test/check.sh /cvmfs/rnog.opensciencegrid.org/software/unstable/el9/setup.sh
#
# On a build that's still sitting in /tmp, use test_build.sh instead:
#   bash test/test_build.sh unstable el9

if [ $# -ne 1 ]; then
    echo "Usage: $0 <path to per-OS setup.sh>"
    exit 1
fi
SETUP="$1"
source "$SETUP" --nuradio || exit 1

FAILS=0
check() {
    if bash -c "$2" > /dev/null 2>&1; then
        echo "PASS  $1"
    else
        echo "FAIL  $1      ($2)"
        FAILS=$((FAILS + 1))
    fi
}

check "gcc is ours, not the system one" '[ "$(command -v gcc)" = "$RNOG_DEPS_INSTALL_DIR/bin/gcc" ]'
check "gcc runs"                        'gcc --version'
check "root runs"                       'root-config --version'
check "import ROOT works"               'python3 -c "import ROOT; ROOT.TH1F"'
check "root has x11, davix, and imt"    'for f in x11 davix imt; do [ "$(root-config --has-$f)" = yes ] || exit 1; done'
check "python packages import"          'python3 -c "import numpy, scipy, matplotlib, healpy, uproot, awkward, pandas, astropy, numba, h5py, proposal"'
check "librno-g is there"               '[ -f "$RNOG_UTIL_INSTALL_DIR/lib/librno-g.so" ]'
check "mattak lib is there"             '[ -f "$RNOG_UTIL_INSTALL_DIR/lib/libmattak.so" ]'
check "import mattak works"             'python3 -c "import mattak.Dataset"'
check "proposal can make a muon"        'python3 -c "import proposal; proposal.particle.MuMinusDef()"'
check "import NuRadioMC works"          'python3 -c "import NuRadioMC, NuRadioReco, radiotools, pygdsm"'
check "NuRadioMC c++ ray tracer built"   'python3 -c "from NuRadioMC.SignalProp.AnalyticRayTracingImpl.CPPAnalyticRayTracing import wrapper"'
check "RNO-G vpol antenna model is there" 'python3 -c "import os, NuRadioReco.detector.antennapattern as a; n = \"RNOG_vpol_4inch_center_n1.73\"; assert os.path.exists(os.path.join(a.path_to_antennamodels, n, n + \".pkl\"))"'
check "shower library and cross sections are there" 'python3 -c "import os, NuRadioMC; d = os.path.dirname(NuRadioMC.__file__); assert os.path.exists(d + \"/SignalGen/ARZ/shower_library/library_v1.2.pkl\") and os.path.exists(d + \"/utilities/data/BGR18_dsigma_dy_H2O.npz\")"'
check "PROPOSAL Greenland tables are there" 'python3 -c "import glob, os, NuRadioMC; assert glob.glob(os.path.dirname(NuRadioMC.__file__) + \"/EvtGen/proposal_tables/Greenland/*.dat\")"'
check "no missing libraries"            'out=$(ldd "$RNOG_UTIL_INSTALL_DIR"/lib/*.so "$RNOG_DEPS_INSTALL_DIR"/bin/root.exe) && ! grep -q "not found" <<< "$out"'

# the el9 GLIBC thing (see README.md): nothing should need GLIBC_2.35 or newer,
# or it won't run on older el9 sites like OSC. Only makes sense for el9.
case "$SETUP" in
    */el9/*)
        check "el9: nothing needs GLIBC_2.35+" \
            'out=$(objdump -T "$RNOG_DEPS_INSTALL_DIR"/bin/gcc "$RNOG_DEPS_INSTALL_DIR"/bin/root.exe "$RNOG_UTIL_INSTALL_DIR"/lib/*.so) && ! grep -qE "GLIBC_2\.(3[5-9]|[4-9][0-9])" <<< "$out"'
        ;;
esac

echo
if [ $FAILS -eq 0 ]; then
    echo "All good."
else
    echo "$FAILS check(s) failed. Run the command in brackets by hand to see what's wrong."
    exit 1
fi
