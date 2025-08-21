# Build argument for base image selection
ARG BASE_IMAGE=runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage (defaults provided by docker-bake.hcl)
ARG COMFYUI_VERSION=latest

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8
ENV PIP_NO_CACHE_DIR=1

# uv를 먼저 설치
RUN pip install uv
# 가상 환경을 만들고 활성화
RUN uv venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# comfy-cli와 기본 패키지를 먼저 설치
RUN uv pip install comfy-cli pip setuptools wheel

# onnxruntime-gpu와 insightface를 설치
RUN uv pip install "onnxruntime-gpu==1.18.0"
RUN uv pip install "insightface==0.7.3"

# 캐시 제거는 한 번만 수행
RUN rm -rf /root/.cache/uv /root/.cache/pip

# Install ComfyUI
RUN echo "PATH: $PATH" && \
    echo "COMFYUI_VERSION: ${COMFYUI_VERSION}" && \
    which comfy && \
    comfy --help

# comfy 명령어가 제대로 설치되었는지 확인 후 실행
RUN /usr/bin/yes | /opt/venv/bin/comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --skip-prompt
# RUN /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}"

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client \
    && rm -rf /root/.cache/uv /root/.cache/pip

# Copy and install common dependencies for custom nodes
COPY requirements-custom-nodes.txt /tmp/requirements-custom-nodes.txt
RUN uv pip install -r /tmp/requirements-custom-nodes.txt \
    && rm -rf /root/.cache/uv /root/.cache/pip \
    && find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf {} +

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN
# Set default model type if none is provided
ARG MODEL_TYPE=flux1-dev-fp8

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories upfront
RUN mkdir -p models/checkpoints models/vae models/unet models/clip

# Stage 3: Final image
FROM base AS final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models