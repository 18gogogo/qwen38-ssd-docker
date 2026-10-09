#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Serves Qwen3.8-Flash-Next AutoRound 3bpw (klee100 PLE-SSD patch) inside Docker.
# Modeled on iIIusi0n/qwen3.8-flash-next-cmp170hx scripts/serve.sh (their tested flags).
# Env overrides (all optional): QWEN_MODEL_DIR, QWEN_SERVED_NAME, QWEN_HOST, QWEN_PORT,
#   QWEN_CONTEXT, QWEN_SEQS, QWEN_BATCH_TOKENS, QWEN_GPU_MEMORY, QWEN_MTP, QWEN_EAGER,
#   QWEN_SSD_WORKERS, QWEN_SSD_CACHE_MB, QWEN_SSD_DEPTH, QWEN_SSD_PREFETCH.
set -euo pipefail

VLLM_VENV=/opt/vllm/.venv
export PATH="$VLLM_VENV/bin:/usr/local/cuda/bin:$PATH"
export OMP_NUM_THREADS="${QWEN_OMP_THREADS:-1}"
export MKL_NUM_THREADS="${QWEN_OMP_THREADS:-1}"
export TOKENIZERS_PARALLELISM=false
export CUDA_DEVICE_ORDER=PCI_BUS_ID

mode="${1:-serve}"

# ---- non-serve modes -------------------------------------------------------
if [[ "$mode" == "download" ]]; then
    shift
    exec /opt/download-model.sh "${1:-/model}"
fi
if [[ "$mode" != "serve" ]]; then
    exec "$@"
fi

# ---- serve mode (default) --------------------------------------------------
export VLLM_USE_BREAKABLE_CUDAGRAPH=1
export HF_HUB_OFFLINE=1   # model is fully on disk via bind mount; no hub access needed

QWEN_MTP="${QWEN_MTP:-1}"
spec=()
if (( QWEN_MTP > 0 )); then
    spec=(--speculative-config "{\"method\":\"mtp\",\"num_speculative_tokens\":${QWEN_MTP}}")
fi
capture_sizes="${QWEN_CAPTURE_SIZES:-[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,20,22,24,26,28,30,32,64,128,256,512,1024,2048]}"
graph=(--compilation-config "{\"cudagraph_mode\":\"${QWEN_GRAPH_MODE:-FULL_AND_PIECEWISE}\",\"cudagraph_capture_sizes\":${capture_sizes}}")
if [[ "${QWEN_EAGER:-0}" == "1" ]]; then
    graph=(--enforce-eager)
fi

exec "$VLLM_VENV/bin/vllm" serve "${QWEN_MODEL_DIR:-/model}" \
    --served-model-name "${QWEN_SERVED_NAME:-Qwen3.8-Flash-Next}" \
    --host "${QWEN_HOST:-0.0.0.0}" --port "${QWEN_PORT:-8000}" \
    --dtype bfloat16 \
    --max-model-len "${QWEN_CONTEXT:-auto}" \
    --max-num-seqs "${QWEN_SEQS:-16}" \
    --max-num-batched-tokens "${QWEN_BATCH_TOKENS:-2048}" \
    --gpu-memory-utilization "${QWEN_GPU_MEMORY:-0.96}" \
    --safetensors-load-strategy lazy \
    --mamba-cache-mode align \
    --enable-prefix-caching \
    --enable-chunked-prefill \
    --reasoning-parser qwen3 \
    --enable-auto-tool-choice --tool-call-parser qwen3_xml \
    --additional-config "{\"ple_ssd_offload\":true,\"ple_ssd_workers\":${QWEN_SSD_WORKERS:-16},\"ple_ssd_cache_mb\":${QWEN_SSD_CACHE_MB:-512},\"ple_ssd_native_library\":\"/opt/vllm/optimization/ple_ssd_io.so\",\"ple_ssd_io_depth\":${QWEN_SSD_DEPTH:-256},\"ple_ssd_prefetch_tokens\":${QWEN_SSD_PREFETCH:-16384}}" \
    "${graph[@]}" "${spec[@]}"
