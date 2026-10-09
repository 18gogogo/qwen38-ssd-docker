# 部署指南：Qwen3.8-Flash-Next AutoRound 3bpw（單卡 SSD offload 版）

目標機：任何一張 **Ampere sm80 64GB GPU** 嘅 Linux 機（Ubuntu 24.04 + Docker + NVIDIA driver 610.x + nvidia-container-toolkit；實測機：CMP 170HX 主機）
鏡像：`18gogogo/170hx1-qwen38nextf:sm80`（Docker Hub public，已綁定 klee100 實測環境）
模型：`klee100/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP`（142.5 GiB，直接喺目標機下載）

---

## 步驟 1：拉鏡像（~8.6 GB，約 10–20 分鐘，視乎網速）

```bash
docker pull 18gogogo/170hx1-qwen38nextf:sm80
```

## 步驟 2：下載模型到 ~/models/（142.5 GiB，要耐）

```bash
mkdir -p ~/models
docker run --rm \
  -v ~/models:/dl \
  18gogogo/170hx1-qwen38nextf:sm80 \
  download /dl/Qwen3.8-Flash-Next-AutoRound-3bpw-MTP
```

- 完成時會顯示 `MODEL DOWNLOADED OK ... (≈142.5 GiB)`
- 下載中途可以 Ctrl-C 停，重跑會續傳（safetensors 分片級續傳）

## 步驟 3：起服務（端口 9393，單卡，顯式參數版 — A 版共享）

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
- `--name qwen38-ssd`：容器名，之後 start/stop/logs 都靠佢
- `--gpus '"device=0"'`：只佔用指定嗰張卡（單卡機用 0；多卡機先 `nvidia-smi` 揀空閒嗰張）
- `--ipc host`：共用宿主機共享記憶體（vLLM 多進程 worker 要用，唔加會 segfault）
- `-p 9393:8000`：宿主機 9393 → 容器內 8000（撞端口自己改）
- `-e QWEN_CONTEXT=262144`：上下文 262K tokens（模型原生上限，=預設 auto）
- `-e QWEN_SEQS=16`：同時最多 16 條請求排隊（原作者實測 667 tok/s 就係 16 併發）
- `-e QWEN_BATCH_TOKENS=2048`：prefill 每批 2048 tokens（2K chunk，配合 SSD offload）
- `-e QWEN_GPU_MEMORY=0.96`：容許用嗰張卡 96% VRAM（47.3G 權重 + KV cache 空間）
- `-e QWEN_MTP=1`：開 MTP 投機解碼（每步預測 1 token，加速 decode）
- `-v ...:/model:ro`：模型 bind mount 入容器，`:ro` 只讀（防容器內誤寫污染模型）
- `--restart no`：手動先啟動，開機唔自動跑（要自動改 `--restart unless-stopped`）
- 鏡像內 entrypoint 自動處理：PLE SSD offload、bfloat16、prefix caching、chunked prefill、mamba align、reasoning/tool parser、cudagraph —— 全部係原作者實測配置

### C 版：一人獨享版（同模型、同端口，只改一個數）

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

同 A 版唯一分別：`QWEN_SEQS=1` —— 一次只服務一條請求，一個人獨享成個 262K 上下文（KV 只佔 6 GiB）。適合深度用長文件，唔使同人爭。

### A↔C 切換方法（兩版共用同一容器名同端口，同時只可以行一個）

```bash
docker stop qwen38-ssd && docker rm qwen38-ssd
# 然後貼上面 A 版或 C 版嘅 docker run 指令
```

⚠️ 切換要重新載入模型，每次約 8–10 分鐘，唔係即刻切。

⚠️ `device=N` 揀邊張卡：
- 先 `nvidia-smi` 睇邊張卡空閒
- 單卡機用 `device=0`；多卡機揀一張空閒卡

## 步驟 4：等開機 + 驗證（約 8–10 分鐘，PLE 表要由 SSD 準備）

```bash
docker logs -f qwen38-ssd        # 見到 Application startup complete 就得（Ctrl-C 離開，唔會停個容器）
curl http://localhost:9393/v1/models
```

## 步驟 5：用佢（OpenAI 格式）

```bash
curl http://localhost:9393/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"你好"}],"max_tokens":128}'
```

- baseURL 係 `http://<機器IP>:9393/v1`
- reasoning 模型：`content` 可能係 null 而 `reasoning` 有嘢，屬正常
- API key 隨便填一個非空字串（vLLM 預設唔驗）

---

## 注意事項（老實講）

1. **RAM 要求低**（~15 GiB）：PLE 95 GiB 表唔食 RAM、唔食 VRAM，留喺 SSD 異步讀 —— 這是此鏡像的核心賣點
2. **VRAM ~47.3 GiB**：一張 64 GiB CMP170HX 搞掂，多卡機其餘卡留俾其他服務
3. **實驗性模型**：原作者明言有「算術題會答錯」嘅一致性 bug；純文字 workload 經 134 個請求驗證 OK
4. **Vision 權重在但未實測**：如果想試圖片，喺 chat 訊息加 image_url（OpenAI 格式），行唔行到要實試先知
5. **SSD 品質影響速度**：原作者用企業級 SATA 實測 decode 111 tok/s；模型目錄放 SSD（唔好放 USB 外置盤），想再快睇 README 調速指南
6. `--restart no`：手動啟動習慣，開機唔會自動起

## 調速掣一覽

見 [README.md](README.md) 🎛️ 環境變數表 + 🚀 調速指南（目標 ~120 tok/s、快首字）。
