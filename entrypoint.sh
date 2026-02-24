#!/bin/bash
set -e

# ---- ComfyUI-Manager (auto-install on first run) ----------------------------
if [ ! -d "/comfyui/custom_nodes/ComfyUI-Manager" ]; then
    echo "[entrypoint] ComfyUI-Manager not found — installing..."
    git clone --depth 1 \
        https://github.com/ltdrdata/ComfyUI-Manager.git \
        /comfyui/custom_nodes/ComfyUI-Manager
fi

# ---- comfy-pilot (auto-install on first run) --------------------------------
if [ ! -d "/comfyui/custom_nodes/comfy-pilot" ]; then
    echo "[entrypoint] comfy-pilot not found — installing..."
    git clone --depth 1 \
        https://github.com/ConstantineB6/comfy-pilot.git \
        /comfyui/custom_nodes/comfy-pilot
fi

# ---- Auto-install custom node dependencies ----------------------------------
# Nodes whose deps were baked in at build time are listed in this manifest.
BUILT_DEPS="/opt/built_node_deps.txt"
echo "[entrypoint] Checking custom node requirements..."
for req in /comfyui/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue
    node_name=$(basename "$(dirname "$req")")
    if [ -f "$BUILT_DEPS" ] && grep -qxF "$node_name" "$BUILT_DEPS"; then
        echo "[entrypoint]   $node_name — deps baked in, skipping"
        continue
    fi
    echo "[entrypoint]   Installing deps for $node_name"
    pip install -q -r "$req" 2>/dev/null || true
done

# ---- Launch ComfyUI ---------------------------------------------------------
# CMD args (e.g. --listen 0.0.0.0 --port 8188) are passed through as "$@"
exec python main.py "$@"
