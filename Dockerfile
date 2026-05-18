# =============================================================================
# ComfyUI Docker — Core Setup
# =============================================================================
# Build args let you pin or upgrade versions without editing the Dockerfile.
#
#   docker compose --env-file .env --env-file .env.rtx5090 up --build
#
# CUDA compatibility note:
#   The CUDA toolkit version in the container must be <= the version supported
#   by the NVIDIA driver on the host. Bump CUDA_VERSION + TORCH_CUDA together
#   when you want a newer stack. See .env.rtx* files for GPU-specific presets.
# =============================================================================

ARG CUDA_VERSION
ARG CUDA_VARIANT=runtime
FROM nvidia/cuda:${CUDA_VERSION}-${CUDA_VARIANT}-ubuntu22.04

# ---- build-time configuration -----------------------------------------------
ARG TORCH_CUDA
ARG TORCH_CHANNEL=stable
ARG COMFYUI_REF=master
# INSTALL_NODE_DEPS: "true" → bake custom-node requirements into the image,
# "false" → skip them at build time (they install on first boot instead).
# Skipping keeps the image small / build fast when the node set changes often.
ARG INSTALL_NODE_DEPS=true

# ---- environment ------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore

# ---- system packages --------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev \
        git wget curl ffmpeg \
        # OpenCV / image-processing runtime deps
        libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender1 \
        # needed by some pip packages that compile C extensions
        build-essential \
        # SSH/SFTP server (optional, activated by PUBLIC_KEY env var at runtime)
        openssh-server \
    && mkdir -p /var/run/sshd \
    && rm -rf /var/lib/apt/lists/*

# ---- python virtual environment ---------------------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /comfyui

# ---- ComfyUI core -----------------------------------------------------------
RUN git clone --depth 1 --branch ${COMFYUI_REF} \
        https://github.com/Comfy-Org/ComfyUI.git .

# ---- PyTorch (installed before requirements.txt so pip doesn't re-resolve) ---
# TORCH_CHANNEL: "stable" → release wheels, "nightly" → --pre nightly wheels.
# Blackwell (sm_120) GPUs require nightly builds until PyTorch stable adds sm_120.
RUN if [ "$TORCH_CHANNEL" = "nightly" ]; then \
        pip install --pre torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/nightly/${TORCH_CUDA}; \
    else \
        pip install torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/${TORCH_CUDA}; \
    fi

# ---- ComfyUI python dependencies -------------------------------------------
RUN pip install -r requirements.txt

# ---- common custom-node dependencies (avoids IMPORT FAILED on first boot) --
RUN pip install opencv-python-headless soundfile piexif gguf

# ---- custom node requirements (baked in to avoid long startup waits) --------
# .dockerignore allows only custom_nodes/*/requirements.txt into the context.
# COPY them in, install everything, then remove the leftovers — the real
# custom_nodes directory is bind-mounted at runtime.
# /opt/built_node_deps.txt lists nodes whose deps are baked in; the entrypoint
# reads it to decide what to (re)install at runtime. When INSTALL_NODE_DEPS is
# "false" the file is left empty, so the entrypoint installs everything on boot.
COPY custom_nodes/ /tmp/custom_node_reqs/
RUN mkdir -p /opt && : > /opt/built_node_deps.txt && \
    if [ "$INSTALL_NODE_DEPS" = "true" ]; then \
        for req in /tmp/custom_node_reqs/*/requirements.txt; do \
            [ -f "$req" ] || continue; \
            node_name=$(basename "$(dirname "$req")"); \
            echo "[build] Installing deps for $node_name"; \
            pip install -r "$req" || true; \
            echo "$node_name" >> /opt/built_node_deps.txt; \
        done; \
    else \
        echo "[build] INSTALL_NODE_DEPS=false — skipping custom-node dep bake-in"; \
    fi && rm -rf /tmp/custom_node_reqs

# ---- directory structure for volume mounts ----------------------------------
RUN mkdir -p models output input custom_nodes user

# ---- entrypoint -------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--listen", "0.0.0.0", "--port", "8188"]
