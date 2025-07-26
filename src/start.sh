#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────
# Debug: Check if storage paths exist
echo "worker-comfyui: Checking storage paths..."
ls -la /runpod-volume/ || echo "ERROR: /runpod-volume not found"
ls -la /runpod-volume/ComfyUI/ || echo "ERROR: /runpod-volume/ComfyUI not found"

# Link network-volume ComfyUI resources into installed ComfyUI
echo "worker-comfyui: Creating symbolic links..."

ln -sf /runpod-volume/ComfyUI/custom_nodes /comfyui/custom_nodes/custom_nodes
ln -sf /runpod-volume/ComfyUI/output       /comfyui/output

# Verify links were created
# echo "worker-comfyui: Verifying symbolic links..."
# ls -la /comfyui/models || echo "ERROR: /comfyui/models link failed"
ls -la /comfyui/custom_nodes/custom_nodes || echo "ERROR: /comfyui/custom_nodes/custom_nodes link failed"
ls -la /comfyui/output || echo "ERROR: /comfyui/output link failed"
# ─────────────────────────────────────────────────────────────

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi