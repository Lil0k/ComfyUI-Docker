# ComfyUI Docker

A GPU-accelerated Docker setup for [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with CUDA support, persistent models, and automatic [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) installation.

## Prerequisites

- Docker (Docker Desktop on Windows/macOS, or Docker Engine on Linux)
- NVIDIA GPU with up-to-date drivers
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### Windows: WSL 2 Memory Configuration

Docker Desktop on Windows runs containers inside WSL 2, which by default limits RAM to 50% of the host's total memory. This may not be enough for large models. To increase it, create or edit `%UserProfile%\.wslconfig`:

```ini
[wsl2]
memory=24GB
```

Adjust the value based on your system's total RAM. After saving, restart WSL and Docker Desktop:

```
wsl --shutdown
```

## Quick Start

1. **Clone the repo and configure paths:**

   ```bash
   git clone <repo-url> && cd comfyui-docker
   ```

   Edit `.env` to point `MODELS_PATH` at your existing models directory (should follow ComfyUI's layout: `checkpoints/`, `loras/`, `vae/`, `controlnet/`, etc.).

2. **Build and start** (pick the env file that matches your GPU):

   ```bash
   # RTX 3090 Ti (CUDA 12.6, PyTorch cu126)
   docker compose --env-file .env --env-file .env.rtx3090ti up --build -d

   # RTX 5090 (CUDA 13.0, PyTorch cu130)
   docker compose --env-file .env --env-file .env.rtx5090 up --build -d
   ```

   The image and container are tagged with the GPU name (e.g. `comfyui:rtx3090ti`, `comfyui-rtx3090ti`), so you can have both images built side by side.

   To **build only** (without starting):

   ```bash
   docker compose --env-file .env --env-file .env.rtx5090 build
   ```

   To **run an already-built image** without rebuilding, omit `--build`:

   ```bash
   docker compose --env-file .env --env-file .env.rtx3090ti up -d
   ```

3. **Open the UI:** [http://localhost:8188](http://localhost:8188)

   ComfyUI-Manager is installed automatically on first boot.

4. **View logs / stop:**

   ```bash
   docker compose --env-file .env --env-file .env.rtx3090ti logs -f
   docker compose --env-file .env --env-file .env.rtx3090ti down
   ```

## Project Structure

| File | Purpose |
|---|---|
| `Dockerfile` | CUDA + Python + PyTorch + ComfyUI (versions are parameterized) |
| `entrypoint.sh` | Auto-installs ComfyUI-Manager and Comfy Pilot on first boot, installs custom node deps, then launches ComfyUI |
| `docker-compose.yml` | GPU passthrough, volume mounts, port mapping |
| `.env` | Shared config: host paths and port |
| `.env.rtx3090ti` | GPU-specific build args for RTX 3090 Ti (CUDA 12.6, cu126) |
| `.env.rtx5090` | GPU-specific build args for RTX 5090 / Blackwell (CUDA 12.8, PyTorch nightly cu128) |
| `.dockerignore` | Keeps large directories out of the build context (only lets `custom_nodes/*/requirements.txt` through) |

## Configuration

### Environment Variables (`.env`)

| Variable | Default | Description |
|---|---|---|
| `MODELS_PATH` | `./models` | Host path to your models directory |
| `CUSTOM_NODES_PATH` | `./custom_nodes` | Host path for custom nodes (persists Manager-installed nodes) |
| `OUTPUT_PATH` | `./output` | Host path for generated images |
| `INPUT_PATH` | `./input` | Host path for input images |
| `COMFYUI_PORT` | `8188` | Port exposed on the host |

### GPU-Specific Build Configuration

Build args are defined in `.env.<gpu>` files and passed through `docker-compose.yml`:

| Variable | Description | Example |
|---|---|---|
| `CUDA_VERSION` | NVIDIA CUDA base image version | `12.6.3`, `12.8.1` |
| `CUDA_VARIANT` | CUDA base image type (`runtime` or `devel`) | `runtime`, `devel` |
| `TORCH_CUDA` | PyTorch CUDA wheel variant | `cu126`, `cu128` |
| `TORCH_CHANNEL` | `stable` for release wheels, `nightly` for pre-release | `stable`, `nightly` |
| `GPU_TAG` | Tag for the image and container name | `rtx3090ti`, `rtx5090` |
| `COMFYUI_REF` | ComfyUI git ref (branch/tag) | `master`, `v0.16.3` |

The CUDA toolkit version in the container must be **<=** the version supported by the NVIDIA driver on the host.

> **Blackwell GPUs (RTX 50-series):** As of March 2026, stable PyTorch does **not** ship sm_120 kernels. You must use `TORCH_CHANNEL=nightly` and PyTorch nightly builds. The `.env.rtx5090` preset is already configured for this. Also use `CUDA_VARIANT=devel` — the runtime image causes CUBLAS errors on Blackwell.

#### Adding support for another GPU

Create a new `.env.<gpu>` file with the appropriate versions. For example, for an RTX 4090:

```bash
# .env.rtx4090
CUDA_VERSION=12.8.1
TORCH_CUDA=cu128
GPU_TAG=rtx4090
# Add TORCH_CHANNEL=nightly if stable PyTorch doesn't support your GPU yet
```

Then build with:

```bash
docker compose --env-file .env --env-file .env.rtx4090 up --build -d
```

#### One-off overrides

You can override any variable directly on the command line:

```bash
CUDA_VERSION=12.8.1 TORCH_CUDA=cu128 GPU_TAG=test \
  docker compose --env-file .env up --build -d
```

Or pin a specific ComfyUI version:

```bash
docker compose --env-file .env --env-file .env.rtx5090 build \
  --build-arg COMFYUI_REF=v0.16.3
```

### Extra ComfyUI Flags

Uncomment and edit the `command:` line in `docker-compose.yml` to pass additional flags:

```yaml
command: ["--listen", "0.0.0.0", "--port", "8188", "--highvram"]
```

## Cloud Deployment (RunPod, etc.)

The image supports cloud platforms where a persistent network volume is mounted (e.g. RunPod mounts it at `/workspace`). Set environment variables to point at existing directories on the volume — the entrypoint will symlink them into the container's ComfyUI installation.

The same `MODELS_PATH`, `CUSTOM_NODES_PATH`, `OUTPUT_PATH`, and `INPUT_PATH` variables from `.env` are reused. When running without docker-compose, set them as container env vars — the entrypoint will symlink them into `/comfyui/`.

### RunPod Setup

1. **Push the image to Docker Hub** (or any public registry):

   ```bash
   docker compose --env-file .env --env-file .env.rtx5090 build
   docker tag comfyui:rtx5090 yourusername/comfyui:rtx5090
   docker push yourusername/comfyui:rtx5090
   ```

2. **Create a RunPod pod template** with:
   - **Container image:** `yourusername/comfyui:rtx5090`
   - **Expose HTTP port:** `8188`
   - **Environment variables:**
     ```
     MODELS_PATH=/workspace/ComfyUI/models
     CUSTOM_NODES_PATH=/workspace/ComfyUI/custom_nodes
     OUTPUT_PATH=/workspace/ComfyUI/output
     INPUT_PATH=/workspace/ComfyUI/input
     USER_PATH=/workspace/ComfyUI/user
     PUBLIC_KEY=ssh-ed25519 AAAA... your-key-here
     ```
   - **Volume mount path:** `/workspace` (RunPod default)

3. The entrypoint auto-detects these paths and symlinks them, so your existing models and nodes are available immediately.

### SSH/SFTP Access

Set the `PUBLIC_KEY` environment variable to your SSH public key to enable SSH/SFTP on port 22. This is useful for uploading files to RunPod (models, images, etc.) via SFTP clients like FileZilla or WinSCP.

```bash
# Also works with docker run
docker run --gpus all -p 8188:8188 -p 22:22 \
  -e PUBLIC_KEY="ssh-ed25519 AAAA..." \
  comfyui:rtx5090
```

On RunPod, port 22 is exposed automatically when SSH is enabled in the pod settings. Connect with:

```bash
ssh root@<pod-ip> -p <exposed-port>
sftp root@<pod-ip> -P <exposed-port>
```

## Comfy Pilot (Claude Code Integration)

[Comfy Pilot](https://github.com/ConstantineB6/comfy-pilot) lets Claude Code see and edit your ComfyUI workflows in real time — create nodes, wire them, change parameters, and queue prompts, all from a Claude Code conversation.

Comfy Pilot is auto-installed on first container startup (just like ComfyUI-Manager). No extra dependencies are required inside the container.

### How It Works

```
Host machine                        Docker container
────────────                        ────────────────
Claude Code CLI                     ComfyUI + Comfy Pilot plugin
     │                                   │
     ├─ spawns ─→ mcp_server.py          │  (REST endpoints on :8188)
     │                │                   │
     │                └── HTTP ──────────→┘
     │                   localhost:8188
```

Claude Code runs on your host and spawns the MCP server (a pure-stdlib Python script) as a subprocess. The MCP server talks to ComfyUI inside Docker over `localhost:8188` (port-forwarded from the container). The browser-side JS syncs the live canvas state to the server, so Claude Code can read and manipulate it.

### Setup (One-Time, After First `docker compose up`)

1. **Make sure the container has started at least once** so that `comfy-pilot` is cloned into your `custom_nodes/` directory.

2. **Register the MCP server with Claude Code** (run this on your host):

   ```bash
   claude mcp add comfyui -- python ./custom_nodes/comfy-pilot/mcp_server.py
   ```

   Run this from the repo root. You need Python on your PATH.

3. **Open ComfyUI in your browser** at [http://localhost:8188](http://localhost:8188). The browser must be open for Comfy Pilot to sync the canvas state.

4. **Start Claude Code.** It now has access to these MCP tools:

   | Tool | What it does |
   |---|---|
   | `get_workflow` | Read the live canvas workflow |
   | `edit_graph` | Create, delete, move, wire, and configure nodes |
   | `run` | Queue the current workflow for execution |
   | `get_node_types` | Search all available node types |
   | `get_node_info` | Get detailed specs for a node type |
   | `view_image` | View output images from Preview/Save nodes |
   | `get_status` | Queue status, GPU/VRAM stats |
   | `search_custom_nodes` | Search ComfyUI Manager registry |
   | `install_custom_node` | Install a custom node package |
   | `download_model` | Download models from HuggingFace/CivitAI |

### Example Prompts

- *"Create a txt2img workflow using my SDXL checkpoint"*
- *"Change the sampler to DPM++ 2M Karras and increase steps to 30"*
- *"Add a ControlNet node wired between the positive prompt and the sampler"*
- *"Run the workflow and show me the output"*

### Notes

- On Windows, the embedded terminal panel in ComfyUI's UI is disabled (PTY limitation). Use Claude Code from your normal terminal instead.
- The MCP server auto-discovers ComfyUI at `localhost:8188`. If you changed `COMFYUI_PORT` in `.env`, the server will still probe common ports and find it.

## Design Decisions

- **Models are volume-mounted, not baked in** -- share an existing models directory directly into the container.
- **Custom nodes persist on the host** -- bind-mounted from `CUSTOM_NODES_PATH`, so anything installed via Manager survives container rebuilds.
- **ComfyUI-Manager auto-installs on first run** -- lives in the persistent custom nodes directory and can update itself.
- **Custom node dependencies are pre-installed at build time** -- any `requirements.txt` found in `custom_nodes/*/` is installed during `docker build` and the node names are saved to a manifest (`/opt/built_node_deps.txt`). On container startup, nodes in the manifest are skipped entirely; only nodes added after the last image build trigger a `pip install`. Rebuild the image (`docker compose up --build`) after adding new custom nodes to bake their deps in too.
- **`shm_size: 16g`** -- PyTorch uses shared memory for data loading; the default 64 MB is too small and causes crashes.
- **All versions are parameterized** -- pin or bump CUDA, PyTorch, and ComfyUI versions via build args without editing the Dockerfile.
