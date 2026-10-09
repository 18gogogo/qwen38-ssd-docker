# 部署指南：Qwen3.8-Flash-Next AutoRound 3bpw（單卡 SSD offload 版）

目標機：任何配備**一張 Ampere sm80 64GB GPU** 的 Linux 主機（Ubuntu 24.04 + Docker + NVIDIA driver 610.x + nvidia-container-toolkit；實測機型：CMP 170HX 主機）
鏡像：`18gogogo/170hx1-qwen38nextf:sm80`（Docker Hub public，已綁定 klee100 實測環境）
模型：`klee100/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP`（142.5 GiB，直接在目標機下載）

---

## 步驟 1：拉取鏡像（~8.6 GB，約 10–20 分鐘，視乎網速）

```bash
docker pull 18gogogo/170hx1-qwen38nextf:sm80
```

## 步驟 2：下載模型至 ~/models/（142.5 GiB，需時較長）

```bash
mkdir -p ~/models
docker run --rm \
  -v ~/models:/dl \
  18gogogo/170hx1-qwen38nextf:sm80 \
  download /dl/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP
```

- 完成時會顯示 `MODEL DOWNLOADED OK ... (≈142.5 GiB)`
- 下載中途可以 Ctrl-C 中斷，重新執行會自動續傳（safetensors 分片級續傳）

## 步驟 3：啟動服務（端口 9393，單卡，顯式參數版 — A 版共享）

```bash
docker run -d \
  --name qwen38-ssd \
  --gpus '"device=0"' \
  --ipc host \
  -p 9393:8000 \
  -e QWEN_CONTEXT=262144 \
  -e QWEN_SEQS=16 \
  -e QWEN_BATCH_TOKENS=2048 \
  -e QWEN_GPU_MEMORY=0.96 \
  -e QWEN_MTP=1 \
  -v ~/models/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP:/model:ro \
  --restart no \
  18gogogo/170hx1-qwen38nextf:sm80
```

各參數作用：
- `--name qwen38-ssd`：容器名稱，之後 start/stop/logs 都靠它
- `--gpus '"device=0"'`：只佔用指定那張卡（單卡機用 0；多卡機請先以 `nvidia-smi` 選擇空閒的卡）
- `--ipc host`：共用宿主機共享記憶體（vLLM 多進程 worker 必需，缺少會 segfault）
- `-p 9393:8000`：宿主機 9393 → 容器內 8000（端口衝突請自行修改）
- `-e QWEN_CONTEXT=262144`：上下文 262K tokens（模型原生上限，等於預設 auto）
- `-e QWEN_SEQS=16`：同時最多 16 條請求排隊（原作者實測 667 tok/s 即為 16 併發）
- `-e QWEN_BATCH_TOKENS=2048`：prefill 每批 2048 tokens（2K chunk，配合 SSD offload）
- `-e QWEN_GPU_MEMORY=0.96`：允許使用該卡 96% VRAM（47.3G 權重 + KV cache 空間）
- `-e QWEN_MTP=1`：啟用 MTP 投機解碼（每步預測 1 token，加速 decode）
- `-v ...:/model:ro`：模型 bind mount 進容器，`:ro` 唯讀（防止容器內誤寫污染模型）
- `--restart no`：手動啟動，開機不自動執行（如需自動啟動請改 `--restart unless-stopped`）
- 鏡像內 entrypoint 自動處理：PLE SSD offload、bfloat16、prefix caching、chunked prefill、mamba align、reasoning/tool parser、cudagraph —— 全部採用原作者實測配置

### C 版：一人獨享版（同模型、同端口，只改一個數值）

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

與 A 版唯一差別：`QWEN_SEQS=1` —— 一次只服務一條請求，一人獨享整個 262K 上下文（KV 僅佔 6 GiB）。適合深度處理長文件，無需與他人爭用。

### A↔C 切換方法（兩版共用同一容器名與端口，同一時間只能運行一個）

```bash
docker stop qwen38-ssd && docker rm qwen38-ssd
# 然後貼上 A 版或 C 版的 docker run 指令
```

⚠️ 切換需要重新載入模型，每次約 8–10 分鐘，並非即時切換。

⚠️ `device=N` 選擇哪張卡：
- 先以 `nvidia-smi` 查看哪張卡空閒
- 單卡機用 `device=0`；多卡機選擇一張空閒卡

## 步驟 4：等待啟動 + 驗證（約 8–10 分鐘，PLE 表需由 SSD 準備）

```bash
docker logs -f qwen38-ssd        # 看到 Application startup complete 即就緒（Ctrl-C 離開，不會停止容器）
curl http://localhost:9393/v1/models
```

## 步驟 5：開始使用（OpenAI 格式）

```bash
curl http://localhost:9393/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"你好"}],"max_tokens":128}'
```

- baseURL 為 `http://<機器IP>:9393/v1`
- reasoning 模型：`content` 可能為 null 而 `reasoning` 有內容，屬正常現象
- API key 填任意非空字串即可（vLLM 預設不驗證）

---

## 注意事項（誠實說明）

1. **RAM 要求低**（~15 GiB）：PLE 95 GiB 表不佔 RAM、不佔 VRAM，留在 SSD 非同步讀取 —— 這是本鏡像的核心賣點
2. **VRAM ~47.3 GiB**：一張 64 GiB CMP170HX 即可應付，多卡機其餘卡可留給其他服務
3. **實驗性模型**：原作者明言有「算術題會答錯」的一致性 bug；純文字 workload 經 134 個請求驗證 OK
4. **Vision 權重存在但未實測**：如想嘗試圖片，在 chat 訊息加入 image_url（OpenAI 格式），能否運行需實際測試
5. **SSD 品質影響速度**：原作者以企業級 SATA 實測 decode 111 tok/s；模型目錄請放在 SSD（不要放在 USB 外接硬碟），想再快請參閱 README 調速指南
6. `--restart no`：手動啟動習慣，開機不會自動啟動

## 調速參數一覽

請參閱 [README.md](README.md) 🎛️ 環境變數表 + 🚀 調速指南（目標 ~120 tok/s、加快首字）。所有 `QWEN_*` 參數均可透過 `docker run -e` 自行調校，無需重建鏡像。
