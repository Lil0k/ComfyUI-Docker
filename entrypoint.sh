#!/bin/bash
set -e

# ---- ComfyUI-Manager (auto-install on first run) ----------------------------
if [ ! -d "/comfyui/custom_nodes/ComfyUI-Manager" ]; then
    echo "[entrypoint] ComfyUI-Manager not found — installing..."
    git clone --depth 1 \
        https://github.com/ltdrdata/ComfyUI-Manager.git \
        /comfyui/custom_nodes/ComfyUI-Manager
fi

# ---- Auto-install custom node dependencies ----------------------------------
echo "[entrypoint] Checking custom node requirements..."
for req in /comfyui/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue
    echo "[entrypoint]   Installing deps from $req"
    pip install -q -r "$req" 2>/dev/null || true
done

# ---- Launch ComfyUI ---------------------------------------------------------
# CMD args (e.g. --listen 0.0.0.0 --port 8188) are passed through as "$@"
exec python main.py "$@"
