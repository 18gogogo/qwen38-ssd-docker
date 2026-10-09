#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Downloads the klee100 checkpoint (142.5 GiB, 13 safetensors shards) to a local dir.
# Usage: docker run --rm -v /home/ubuntu/models:/dl <image> download /dl/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP
# Pinned to the exact weight revision klee100's repo uses (ce0e0b94...).
set -euo pipefail

DEST="${1:-/model}"
export DEST

/opt/vllm/.venv/bin/python - <<'PY'
import os
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="klee100/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP",
    revision="ce0e0b94083895bd836b916f29bf105c40a8162a",
    local_dir=os.environ["DEST"],
    max_workers=2,
)
total = sum(
    f.stat().st_size
    for root, _, files in os.walk(os.environ["DEST"])
    for f in (os.path.join(root, x) for x in files)
)
print(f"MODEL DOWNLOADED OK -> {os.environ['DEST']} ({total/2**30:.1f} GiB)")
PY
