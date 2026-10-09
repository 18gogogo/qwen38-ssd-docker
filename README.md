# Qwen3.8-Flash-Next · 單卡 64GB SSD-Offload Docker 鏡像

[![Docker Pulls](https://img.shields.io/docker/pulls/18gogogo/170hx1-qwen38nextf.svg)](https://hub.docker.com/r/18gogogo/170hx1-qwen38nextf)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

用**一張 Ampere sm80 64GB GPU**（例如 NVIDIA CMP 170HX）跑 **Qwen3.8-Flash-Next 262K 上下文**嘅 vLLM OpenAI 兼容服務。
賣點：模型 95 GiB 嘅 PLE 層由 SSD 異步串流，**唔食 VRAM、唔食 RAM** —— VRAM 只需 ~47.3 GiB、主機 RAM 只需 ~15 GiB。

*Run Qwen3.8-Flash-Next (262K context) on a single Ampere sm80 64GB GPU (e.g. CMP 170HX) with vLLM. The 95 GiB PLE layer streams from SSD asynchronously — ~47 GiB VRAM, ~15 GiB RAM. OpenAI-compatible API.*

---

## 🙏 鳴謝 Credits（核心功勞屬於原作者）

呢個 repo 只係將以下原作者嘅成果包裝成方便嘅 Docker 鏡像 + 參數化，請支持佢哋：

- **[iIIusi0n / klee100 — qwen3.8-flash-next-cmp170hx](https://github.com/iIIusi0n/qwen3.8-flash-next-cmp170hx)**（Apache-2.0）— PLE-SSD offload patch、實測啟動參數同安裝腳本，係呢個鏡像嘅核心
- **[klee100 — Qwen3.8-Flash-Next-AutoRound-3bpw-MTP](https://huggingface.co/klee100/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP)** — AutoRound 3bpw 量化模型權重（142.5 GiB；本 repo 指定 revision `ce0e0b94`）
- **Qwen 團隊** — Qwen3.8-Flash-Next 原始模型
- **[vLLM 項目](https://github.com/vllm-project/vllm)** — 推理引擎（鏡像內釘住 revision `a5a30471`）

本 repo 相對上游嘅改動：Dockerfile 容器化、`entrypoint.sh` 參數化（`QWEN_*` 環境變數）、`download-model.sh` 下載腳本。許可證照舊 [Apache-2.0](LICENSE)。

## ☕ 支持呢個項目

[![Buy me a coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/tenantreview)

## 📦 快速開始（三步）

**1. 拉鏡像（~8.6 GB）**

```bash
docker pull 18gogogo/170hx1-qwen38nextf:sm80
```

**2. 下載模型（142.5 GiB，斷線可續傳）**

```bash
mkdir -p ~/models
docker run --rm \
  -v ~/models:/dl \
  18gogogo/170hx1-qwen38nextf:sm80 \
  download /dl/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP
```

完成會顯示 `MODEL DOWNLOADED OK ... (≈142.5 GiB)`。

**3. 起服務（一人獨享版）**

```bash
docker run -d \
  --name qwen38-ssd \
  --gpus '"device=0"' \
  --ipc host \
  -p 9393:8000 \
  -e QWEN_CONTEXT=262144 \
  -e QWEN_SEQS=1 \
  -e QWEN_BATCH_TOKENS=2048 \
  -e QWEN_GPU_MEMORY=0.96 \
  -e QWEN_MTP=1 \
  -v ~/models/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP:/model:ro \
  --restart no \
  18gogogo/170hx1-qwen38nextf:sm80
```

`docker logs -f qwen38-ssd` 等 8–10 分鐘，見到 `Application startup complete` 即得。驗證：

```bash
curl http://localhost:9393/v1/models
```

完整部署文件（共享版/獨享版/切換/注意事項）：**[DEPLOY.md](DEPLOY.md)**

## 🎛️ 全部環境變數（調速掣）

| 變數 | 預設 | 作用 |
|---|---|---|
| `QWEN_CONTEXT` | `auto`（=262144） | 上下文長度，模型上限 262K |
| `QWEN_SEQS` | `16` | 同時服務請求數：**1 = 一人獨享**；16 = 共享版 |
| `QWEN_BATCH_TOKENS` | `2048` | prefill 每批 tokens（加大 → 首字更快，食多少少 VRAM） |
| `QWEN_GPU_MEMORY` | `0.96` | 容許用嗰張卡幾多比例 VRAM |
| `QWEN_MTP` | `1` | MTP 投機解碼 tokens 數（0 = 關） |
| `QWEN_SSD_WORKERS` | `16` | SSD 並發讀取線程數 |
| `QWEN_SSD_CACHE_MB` | `512` | PLE 熱點頁緩存（MiB，食主機 RAM） |
| `QWEN_SSD_DEPTH` | `256` | SSD IO queue depth |
| `QWEN_SSD_PREFETCH` | `16384` | decode 預取 tokens 數 |
| `QWEN_GRAPH_MODE` | `FULL_AND_PIECEWISE` | cudagraph 模式 |
| `QWEN_EAGER` | `0` | `1` = 關 cudagraph（debug 用） |
| `QWEN_MODEL_DIR` | `/model` | 容器內模型路徑 |
| `QWEN_SERVED_NAME` | `Qwen3.8-Flash-Next` | API 回傳嘅 model 名 |
| `QWEN_HOST` / `QWEN_PORT` | `0.0.0.0` / `8000` | 綁定地址/端口 |

## 🚀 調速指南（目標 ~120 tok/s、快首字）

基線（原作者 klee100 實測，企業級 SATA SSD）：decode **~111 tok/s**。想迫近/超越 120 tok/s，按效益次序試，**一次改一樣，用真實 workload 前後對比**：

1. **換快 SSD（效益最大）**：PLE 層運行時由 SSD 讀，SATA → NVMe 係質變。模型目錄同 Docker 資料目錄都放最快嗰隻 SSD。
2. `QWEN_SSD_WORKERS=32`（再試 64）：NVMe 先食得起咁多並發線程。
3. `QWEN_SSD_DEPTH=512`（再試 1024）：IO 隊列深度，同上配合。
4. `QWEN_SSD_CACHE_MB=4096`（主機有 32GB+ RAM 先試 8192）：熱點頁食 RAM 換 IO，直接省讀取。
5. `QWEN_SSD_PREFETCH=32768`：預取提前量加大可以鋪平 IO 延遲（過大會浪費頻寬）。
6. **首字（TTFT）**：`QWEN_BATCH_TOKENS=4096`（再試 8192）：prefill 批次大 = 長 prompt 出首 token 更快。prefix caching 已開，重複 system prompt 幾乎即刻。

⚠️ 老實講：120 tok/s 未經本 repo 實測，實際數值好取決於 SSD 同 workload。每次改完自己 bench（例如 `vllm bench serve` 或 curl 計時）先好信。

## 🔧 度身訂做（改自己鏡像）

調速邏輯全部喺 [`entrypoint.sh`](entrypoint.sh)（`QWEN_*` 環境變數 → vLLM 參數），模型下載喺 [`download-model.sh`](download-model.sh)，構建喺 [`Dockerfile`](Dockerfile)。改完自己 build：

```bash
git clone https://github.com/18gogogo/qwen38-ssd-docker.git
cd qwen38-ssd-docker
# 改你想改嘅檔案
docker build -t 你的用戶名/qwen38-ssd:sm80 .
docker login && docker push 你的用戶名/qwen38-ssd:sm80
```

之後你嘅 `docker run` 用返自己個鏡像名。

## ⚠️ 已知限制（老實講）

- **實驗性模型**：原作者明言算術題有一致性 bug（純文字 workload 經 134 個請求驗證 OK）
- **Vision 權重在但未實測**：想試圖片，chat 訊息加 `image_url`（OpenAI 格式）
- **sm80 64GB 級專用**（CMP 170HX 等）；其他架構/細卡未試過
- `--restart no` 預設：手動 `docker start qwen38-ssd`（要開機自動跑改 `--restart unless-stopped`）

## 📄 License

[Apache-2.0](LICENSE) — 沿用上游 [iIIusi0n/qwen3.8-flash-next-cmp170hx](https://github.com/iIIusi0n/qwen3.8-flash-next-cmp170hx) 條款。
