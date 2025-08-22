OF
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
