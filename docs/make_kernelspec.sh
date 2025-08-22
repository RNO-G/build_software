#!/usr/bin/env bash
# make_kernelspec_from_active_venv.sh
# Create a Jupyter kernelspec INSIDE the currently-activated venv.

set -euo pipefail

# --- detect active venv ---
if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  echo "ERROR: No active virtual environment detected."
  echo "  Activate one, e.g.:"
  echo "    source /path/to/venv/bin/activate"
  exit 1
fi

PY="$VIRTUAL_ENV/bin/python"
if [[ ! -x "$PY" ]]; then
  echo "ERROR: $PY not found or not executable. Is the venv valid?"
  exit 1
fi

# --- fixed setup script path ---
SETUP_SCRIPT="/cvmfs/rnog.opensciencegrid.org/software/setup.sh"

# --- kernel name/display name ---
KERNEL_NAME="$(basename "$VIRTUAL_ENV")"
DISPLAY_NAME="Python ($KERNEL_NAME)"

# --- ensure minimal deps for VS Code kernel discovery/launch ---
"$PY" -m pip install -U ipykernel jupyter_client pyzmq tornado traitlets comm >/dev/null

# --- write kernelspec inside the venv ---
KDIR="$VIRTUAL_ENV/share/jupyter/kernels/$KERNEL_NAME"
KJSON="$KDIR/kernel.json"
mkdir -p "$KDIR"

cat > "$KJSON" <<EOF
{
  "argv": [
    "/bin/bash",
    "-lc",
    "source $SETUP_SCRIPT && exec $PY -m ipykernel -f {connection_file}"
  ],
  "display_name": "$DISPLAY_NAME",
  "language": "python"
}
EOF

echo "✅ Kernelspec written: $KJSON"
echo "   Display: $DISPLAY_NAME"
echo "→ In VS Code: Select Kernel → Jupyter Kernels → $DISPLAY_NAME"
