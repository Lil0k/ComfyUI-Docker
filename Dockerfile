# =============================================================================
# ComfyUI Docker — Core Setup
# =============================================================================
# Build args let you pin or upgrade versions without editing the Dockerfile.
#
#   docker build \
#     --build-arg CUDA_VERSION=13.0.1 \
#     --build-arg TORCH_CUDA=cu130 \
#     --build-arg COMFYUI_REF=master \
#     -t comfyui .
#
# CUDA compatibility note:
#   The CUDA toolkit version in the container must be <= the version supported
#   by the NVIDIA driver on the host. A 12.4 container works fine on a host
#   whose driver supports 12.8. Bump CUDA_VERSION + TORCH_CUDA together when
#   you want a newer stack.
# =============================================================================

ARG CUDA_VERSION=13.0.1
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04

# ---- build-time configuration -----------------------------------------------
ARG TORCH_CUDA=cu130
ARG COMFYUI_REF=master

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
    && rm -rf /var/lib/apt/lists/*

# ---- python virtual environment ---------------------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /comfyui

# ---- ComfyUI core -----------------------------------------------------------
RUN git clone --depth 1 --branch ${COMFYUI_REF} \
        https://github.com/comfyanonymous/ComfyUI.git .

# ---- PyTorch (installed before requirements.txt so pip doesn't re-resolve) ---
RUN pip install \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/${TORCH_CUDA}

# ---- ComfyUI python dependencies -------------------------------------------
RUN pip install -r requirements.txt

# ---- common custom-node dependencies (avoids IMPORT FAILED on first boot) --
RUN pip install opencv-python-headless soundfile piexif gguf

# ---- directory structure for volume mounts ----------------------------------
RUN mkdir -p models output input custom_nodes user

# ---- entrypoint -------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--listen", "0.0.0.0", "--port", "8188"]
