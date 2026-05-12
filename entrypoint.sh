#!/bin/bash
set -e

# ---- Optional path overrides (for RunPod / cloud deployments) ---------------
# When running without docker-compose (e.g. on RunPod), set MODELS_PATH,
# CUSTOM_NODES_PATH, OUTPUT_PATH, INPUT_PATH as env vars pointing at existing
# directories on a network volume. The entrypoint symlinks them into /comfyui/.
# With docker-compose these dirs are bind-mounted directly, so this is a no-op.
for var_pair in \
    "MODELS_PATH:/comfyui/models" \
    "CUSTOM_NODES_PATH:/comfyui/custom_nodes" \
    "OUTPUT_PATH:/comfyui/output" \
    "INPUT_PATH:/comfyui/input" \
    "USER_PATH:/comfyui/user"; do
    var_name="${var_pair%%:*}"
    target="${var_pair#*:}"
    eval "src_path=\$$var_name"
    # Skip if var is unset, path doesn't exist, or is already mounted/linked
    if [ -n "$src_path" ] && [ -d "$src_path" ] && [ ! -L "$target" ] && [ "$(readlink -f "$target")" != "$(readlink -f "$src_path")" ]; then
        echo "[entrypoint] Linking $target -> $src_path"
        rm -rf "$target"
        ln -sfn "$src_path" "$target"
    fi
done

# ---- SSH/SFTP server (optional, for RunPod / cloud access) ------------------
# Set PUBLIC_KEY env var to enable. Generates host keys on first run.
if [ -n "$PUBLIC_KEY" ]; then
    echo "[entrypoint] Setting up SSH..."
    mkdir -p ~/.ssh
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    # Generate host keys if missing
    for type in rsa ecdsa ed25519; do
        [ -f "/etc/ssh/ssh_host_${type}_key" ] || ssh-keygen -t "$type" -f "/etc/ssh/ssh_host_${type}_key" -q -N ''
    done
    # Allow root login with key only
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    service ssh start
    echo "[entrypoint] SSH/SFTP server started on port 22"
fi

# ---- ComfyUI-Manager (auto-install on first run) ----------------------------
if [ ! -d "/comfyui/custom_nodes/ComfyUI-Manager" ]; then
    echo "[entrypoint] ComfyUI-Manager not found — installing..."
    git clone --depth 1 \
        https://github.com/ltdrdata/ComfyUI-Manager.git \
        /comfyui/custom_nodes/ComfyUI-Manager
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
