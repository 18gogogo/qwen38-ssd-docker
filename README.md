# Qwen3.8-Flash-Next · 單卡 64GB SSD-Offload Docker 鏡像

[![Docker Pulls](https://img.shields.io/docker/pulls/18gogogo/170hx1-qwen38nextf.svg)](https://hub.docker.com/r/18gogogo/170hx1-qwen38nextf)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

以**一張 Ampere sm80 64GB GPU**（例如 NVIDIA CMP 170HX）運行 **Qwen3.8-Flash-Next 262K 上下文**的 vLLM OpenAI 相容服務。
核心特點：模型 95 GiB 的 PLE 層由 SSD 非同步串流，**不佔用 VRAM、不佔用主機 RAM** —— VRAM 僅需 ~47.3 GiB、主機 RAM 僅需 ~15 GiB。

*Run Qwen3.8-Flash-Next (262K context) on a single Ampere sm80 64GB GPU (e.g. CMP 170HX) with vLLM. The 95 GiB PLE layer streams from SSD asynchronously — ~47 GiB VRAM, ~15 GiB RAM. OpenAI-compatible API.*

---

## 🙏 鳴謝 Credits（核心功勞屬於原作者）

本 repo 僅將以下原作者的成果包裝為方便使用的 Docker 鏡像並加以參數化，請支持他們：

- **[iIIusi0n / klee100 — qwen3.8-flash-next-cmp170hx](https://github.com/iIIusi0n/qwen3.8-flash-next-cmp170hx)**（Apache-2.0）— PLE-SSD offload patch、實測啟動參數與安裝腳本，是本鏡像的核心
- **[klee100 — Qwen3.8-Flash-Next-AutoRound-3bpw-MTP](https://huggingface.co/klee100/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP)** — AutoRound 3bpw 量化模型權重（142.5 GiB；本 repo 指定 revision `ce0e0b94`）
- **Qwen 團隊** — Qwen3.8-Flash-Next 原始模型
- **[vLLM 項目](https://github.com/vllm-project/vllm)** — 推理引擎（鏡像內釘住 revision `a5a30471`）

本 repo 相對上游的改動：Dockerfile 容器化、`entrypoint.sh` 參數化（`QWEN_*` 環境變數）、`download-model.sh` 下載腳本。授權條款沿用 [Apache-2.0](LICENSE)。

## ☕ 支持本項目

[![Buy me a coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/tenantreview)

## 📦 快速開始（三步）

**1. 拉取鏡像（~8.6 GB）**

```bash
docker pull 18gogogo/170hx1-qwen38nextf:sm80
```

**2. 下載模型（142.5 GiB，支援斷點續傳）**

```bash
mkdir -p ~/models
docker run --rm \
  -v ~/models:/dl \
  18gogogo/170hx1-qwen38nextf:sm80 \
  download /dl/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP
```

完成時會顯示 `MODEL DOWNLOADED OK ... (≈142.5 GiB)`。

**3. 啟動服務（一人獨享版）**

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

`docker logs -f qwen38-ssd` 等待 8–10 分鐘，看到 `Application startup complete` 即表示就緒。驗證：

```bash
curl http://localhost:9393/v1/models
```

完整部署文件（共享版/獨享版/切換/注意事項）：**[DEPLOY.md](DEPLOY.md)**

## 🎛️ 全部環境變數（調速參數）

| 變數 | 預設 | 作用 |
|---|---|---|
| `QWEN_CONTEXT` | `auto`（=262144） | 上下文長度，模型上限 262K |
| `QWEN_SEQS` | `16` | 同時服務請求數：**1 = 一人獨享**；16 = 共享版 |
| `QWEN_BATCH_TOKENS` | `2048` | prefill 每批 tokens（加大 → 首字更快，佔用少量 VRAM） |
| `QWEN_GPU_MEMORY` | `0.96` | 允許使用該卡多少比例 VRAM |
| `QWEN_MTP` | `1` | MTP 投機解碼 tokens 數（0 = 關閉） |
| `QWEN_SSD_WORKERS` | `16` | SSD 並發讀取執行緒數 |
| `QWEN_SSD_CACHE_MB` | `512` | PLE 熱點頁快取（MiB，佔用主機 RAM） |
| `QWEN_SSD_DEPTH` | `256` | SSD IO queue depth |
| `QWEN_SSD_PREFETCH` | `16384` | decode 預取 tokens 數 |
| `QWEN_GRAPH_MODE` | `FULL_AND_PIECEWISE` | cudagraph 模式 |
| `QWEN_EAGER` | `0` | `1` = 關閉 cudagraph（除錯用） |
| `QWEN_MODEL_DIR` | `/model` | 容器內模型路徑 |
| `QWEN_SERVED_NAME` | `Qwen3.8-Flash-Next` | API 回傳的 model 名稱 |
| `QWEN_HOST` / `QWEN_PORT` | `0.0.0.0` / `8000` | 綁定地址/端口 |

## 🚀 調速指南（目標 ~120 tok/s、加快首字）

基線（原作者 klee100 實測，企業級 SATA SSD）：decode **~111 tok/s**。想接近或超越 120 tok/s，請按效益順序嘗試，**一次只改一項，以真實 workload 前後對比**：

1. **更換更快的 SSD（效益最大）**：PLE 層運行時由 SSD 讀取，SATA → NVMe 是質變。模型目錄與 Docker 資料目錄都放在最快的 SSD 上。
2. `QWEN_SSD_WORKERS=32`（再試 64）：NVMe 才能承受如此多並發執行緒。
3. `QWEN_SSD_DEPTH=512`（再試 1024）：IO 佇列深度，與上一項配合。
4. `QWEN_SSD_CACHE_MB=4096`（主機有 32GB+ RAM 才試 8192）：熱點頁佔用 RAM 換取 IO，直接減少讀取。
5. `QWEN_SSD_PREFETCH=32768`：預取提前量加大可以鋪平 IO 延遲（過大會浪費頻寬）。
6. **首字（TTFT）**：`QWEN_BATCH_TOKENS=4096`（再試 8192）：prefill 批次加大 = 長 prompt 產生首 token 更快。prefix caching 已啟用，重複 system prompt 幾乎即時。

⚠️ 誠實說明：120 tok/s 未經本 repo 實測，實際數值很大程度取決於 SSD 與 workload。每次修改後請自行 benchmark（例如 `vllm bench serve` 或 curl 計時）再作判斷。

## 🔧 自訂參數（度身訂做）

所有調速邏輯都在 [`entrypoint.sh`](entrypoint.sh)：**不需要重建鏡像**，只需在 `docker run` 加上 `-e` 環境變數即可自訂。全部可調參數見上方 🎛️ 表格。示例：

```bash
# 示例：加大 SSD 併發 + 關閉 MTP
docker run -d \
  --name qwen38-ssd \
  --gpus '"device=0"' \
  --ipc host \
  -p 9393:8000 \
  -e QWEN_SEQS=1 \
  -e QWEN_SSD_WORKERS=32 \
  -e QWEN_MTP=0 \
  -v ~/models/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP:/model:ro \
  --restart no \
  18gogogo/170hx1-qwen38nextf:sm80
```

想改更深入的行為（例如更換 vLLM 啟動參數）？直接編輯 [`entrypoint.sh`](entrypoint.sh)，再自行 build：

```bash
git clone https://github.com/18gogogo/qwen38-ssd-docker.git
cd qwen38-ssd-docker
# 修改你想修改的檔案
docker build -t 你的用戶名/qwen38-ssd:sm80 .
docker login && docker push 你的用戶名/qwen38-ssd:sm80
```

之後你的 `docker run` 改用你自己的鏡像名。

## ⚠️ 已知限制（誠實說明）

- **實驗性模型**：原作者明言算術題有一致性 bug（純文字 workload 經 134 個請求驗證 OK）
- **Vision 權重存在但未實測**：想嘗試圖片，在 chat 訊息加入 `image_url`（OpenAI 格式）
- **sm80 64GB 級專用**（CMP 170HX 等）；其他架構/較小記憶體卡未測試
- `--restart no` 預設：手動 `docker start qwen38-ssd`（如需開機自動啟動改用 `--restart unless-stopped`）

## 📄 License

[Apache-2.0](LICENSE) — 沿用上游 [iIIusi0n/qwen3.8-flash-next-cmp170hx](https://github.com/iIIusi0n/qwen3.8-flash-next-cmp170hx) 條款。
