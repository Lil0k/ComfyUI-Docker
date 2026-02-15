#!/bin/bash
set -e

# ---- ComfyUI-Manager (auto-install on first run) ----------------------------
if [ ! -d "/comfyui/custom_nodes/ComfyUI-Manager" ]; then
    echo "[entrypoint] ComfyUI-Manager not found — installing..."
    git clone --depth 1 \
        https://github.com/ltdrdata/ComfyUI-Manager.git \
        /comfyui/custom_nodes/ComfyUI-Manager
fi

# Install / update Manager's python deps
if [ -f "/comfyui/custom_nodes/ComfyUI-Manager/requirements.txt" ]; then
    pip install -q -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt 2>/dev/null || true
fi

# ---- Launch ComfyUI ---------------------------------------------------------
# CMD args (e.g. --listen 0.0.0.0 --port 8188) are passed through as "$@"
exec python main.py "$@"
