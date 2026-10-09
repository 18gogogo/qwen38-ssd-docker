# Qwen3.8-Flash-Next AutoRound 3bpw + PLE-SSD offload (klee100 patch) — SM80 single-GPU
# Build on any x86_64 Linux with Docker (no GPU needed for the build).
# Runtime target: one Ampere sm80 GPU with 64GB VRAM (tested on CMP 170HX).
# Base matches klee100 tested env: CUDA 13.3 toolkit, torch cu130, Python 3.12, uv venv.
FROM nvidia/cuda:13.3.1-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV VLLM_WORKDIR=/opt/vllm \
    VLLM_SOURCE=/opt/vllm/src \
    VLLM_VENV=/opt/vllm/.venv \
    CUDA_HOME=/usr/local/cuda \
    PATH=/root/.local/bin:$PATH

RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates build-essential xz-utils \
 && rm -rf /var/lib/apt/lists/*

# uv (Python package manager used by klee100's installer)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# vLLM source pinned to the EXACT revision the klee100 patch targets
RUN mkdir -p /opt/vllm \
 && (git clone --filter=blob:none https://github.com/vllm-project/vllm.git /opt/vllm/src \
     || git clone https://github.com/vllm-project/vllm.git /opt/vllm/src) \
 && git -C /opt/vllm/src checkout a5a30471ff2bb7f0824f2da10e358af98d304472

# klee100 repo: patch + scripts + tested constraints
RUN git clone https://github.com/iIIusi0n/qwen3.8-flash-next-cmp170hx.git /opt/qwen38-ssd

# Their tested installer: apply patch -> uv venv (py3.12) -> precompiled wheel (cu130)
# -> editable install of patched source -> compile ple_ssd_io.so
RUN /opt/qwen38-ssd/scripts/install-runtime.sh

COPY entrypoint.sh download-model.sh /opt/
RUN chmod +x /opt/entrypoint.sh /opt/download-model.sh \
 && ls -la /opt/vllm/optimization/ple_ssd_io.so \
 && /opt/vllm/.venv/bin/vllm --version || true

EXPOSE 8000
ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["serve"]
