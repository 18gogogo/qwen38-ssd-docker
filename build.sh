#!/usr/bin/env bash
# Build the image on any x86_64 Linux box with Docker (no GPU needed for the build).
# Default tag is local — rename to <你的Docker用戶名>/<名>:sm80 before pushing to Docker Hub.
set -euo pipefail
cd "$(dirname -- "$0")"
docker build -t vllm-qwen38-ssd:sm80 .
