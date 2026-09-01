# 모델별 VRAM 계산 근거

대상 하드웨어: **RTX 5090 32GB × 1 (Blackwell, sm_120)**
사용 가능 예산: **약 30GB** (CUDA 컨텍스트 + 작업 버퍼 ~2GB 제외)

---

## 계산의 4가지 항목

```
필요 VRAM = ① 가중치  +  ② KV 캐시  +  ③ 활성화/작업버퍼  +  ④ CUDA 컨텍스트
              고정        배치×컨텍스트     수백MB~2GB        ~0.5~1GB
```

**①은 고정, ②는 곱셈으로 늘어납니다.** 방심하면 ②가 ①보다 커집니다.

### ① 가중치 어림셈

```
가중치 GB ≈ 파라미터 수(B) × 정밀도 바이트
```

| 정밀도 | 바이트/파라미터 | 8B | 27B |
|---|---|---|---|
| BF16/FP16 | 2.0 | 16 GB | 54 GB |
| FP8 / Q8_0 | ~1.0 | 8 GB | 27~30 GB |
| Q4_K_M | ~0.6 | 5 GB | 16~18 GB |

> Q4가 0.5가 아니라 ~0.6인 이유: 블록별 스케일 값 + 일부 레이어를 고정밀도로 남김.

### ② KV 캐시 공식 (표준 트랜스포머)

```
토큰당 바이트 = 2 × L × H_kv × head_dim × 정밀도바이트
                ↑ K와 V

L         = num_hidden_layers
H_kv      = num_key_value_heads     ← GQA면 쿼리 헤드보다 적음
head_dim  = head_dim
정밀도    = FP16 → 2 bytes

총량 = 토큰당 바이트 × 컨텍스트 × 배치
```

필요한 값은 전부 HuggingFace `config.json`에 있습니다:

```bash
curl -s https://huggingface.co/<org>/<model>/raw/main/config.json | python3 -m json.tool
```

---

## Qwen3-8B (표준 트랜스포머) — 커리큘럼 실습용

`config.json` 실측값:

| 키 | 값 |
|---|---|
| `num_hidden_layers` | 36 |
| `num_attention_heads` | 32 |
| `num_key_value_heads` | **8** (GQA 4:1) |
| `head_dim` | 128 |
| `hidden_size` | 4096 |
| `max_position_embeddings` | 40960 |

```
KV 캐시 = 2 × 36 × 8 × 128 × 2 bytes = 147,456 B = 144 KB / 토큰
```

**GQA의 위력**: 만약 H_kv가 쿼리 헤드와 같은 32였다면 576 KB/토큰(4배)이 됩니다.
32K 컨텍스트에서 4.5GB vs 18GB의 차이입니다.

### 예산표 (배치 1)

| 정밀도 | 가중치 | KV 8K | KV 32K | 8K 합 | 32K 합 |
|---|---|---|---|---|---|
| **fp16** | 16.4 GB | 1.2 | 4.5 | **17.6** ✅ | **20.9** ✅ |
| q8_0 | 8.7 GB | 1.2 | 4.5 | 9.9 ✅ | 13.2 ✅ |
| q4_K_M | 5.0 GB | 1.2 | 4.5 | 6.2 ✅ | 9.5 ✅ |

> ✅ **fp16 원본이 32K까지 여유롭게 들어갑니다.**
> → 3단계 "풀 모델 vs 양자화" 비교의 **기준선을 확보할 수 있습니다.**
> 24GB(3090 1대)에서는 빠듯한 부분이라 5090이 유리합니다.

---

## Qwen3.8-27B (하이브리드 선형 어텐션 + VLM) — 실사용용

> 2026-08-14 릴리스. Apache 2.0. **표준 공식이 그대로 적용되지 않습니다.**

### 구조

```
64층 = 16 × ( 3 × [Gated DeltaNet → FFN]  →  1 × [Gated Attention → FFN] )
                    ↑ 선형 어텐션 48층          ↑ full attention 16층
```

| 키 | 값 |
|---|---|
| `num_hidden_layers` | 64 |
| `full_attention_interval` | **4** → full attention은 **16층만** |
| `num_attention_heads` | 24 |
| `num_key_value_heads` | **4** (GQA 6:1) |
| `head_dim` | **256** |
| `linear_num_key_heads` / `linear_num_value_heads` | 16 / 48 |
| `linear_key_head_dim` / `linear_value_head_dim` | 128 / 128 |
| `mamba_ssm_dtype` | float32 |
| `max_position_embeddings` | 262,144 (YaRN으로 1M) |
| `vision_config` | depth 27, hidden 1152, patch 16 → **네이티브 VLM** |

### KV 캐시 — full attention 16층에만 존재

```
층당 = 2 × 4 KV헤드 × 256 head_dim × 2 bytes = 4,096 B = 4 KB / 층 / 토큰
전체 = 4 KB × 16층 = 64 KB / 토큰

※ 64층이 전부 full attention이었다면 → 256 KB/토큰 (4배)
```

### 선형 어텐션 48층 — 고정 크기 순환 상태

**컨텍스트 길이와 무관하게 크기가 변하지 않습니다** (Mamba/SSM 계열 특성).

```
층당 상태 ≈ 48 V헤드 × 128 × 128 × 4 bytes(fp32) ≈ 3 MB
전체 ≈ 3 MB × 48층 ≈ 약 150 MB   ← 8K든 262K든 동일
```

> 📌 **이것이 하이브리드의 요점입니다.**
> 커리큘럼 8단계의 "KV 캐시는 컨텍스트에 선형 증가"가
> 이 모델에서는 **1/4 기울기의 선형**이 됩니다.
> 그래서 27B를 단일 32GB 카드에서 128K 컨텍스트로 돌릴 수 있습니다.

### 예산표 (배치 1, Ollama 태그 실측 크기)

| 태그 | 가중치 | 8K | 32K | 128K | 262K |
|---|---|---|---|---|---|
| **`27b-q4_K_M`** (기본) | **18 GB** | 18.7 ✅ | 20.2 ✅ | **26.2 ✅** | 34.2 ❌ |
| `27b-q8_0` | **30 GB** | ❌ | ❌ | ❌ | ❌ |
| `27b-bf16` | **56 GB** | ❌ | ❌ | ❌ | ❌ |

**결론: q4_K_M만 가능. 대신 128K 컨텍스트까지 도달 가능.**

### 태그 선택 가이드

| 태그 | 판단 |
|---|---|
| `qwen3.8:27b` = `27b-q4_K_M` | ✅ 기본 선택 |
| `27b-nvfp4` (18GB) | 🔶 5090은 Blackwell이라 **NVFP4 하드웨어 가속 대상**. Ollama/llama.cpp 지원 성숙도는 미확인 — 되면 이득, 안 되면 q4_K_M 복귀 |
| `27b-mtp-q4_K_M` (18GB) | 🔶 MTP(Multi-Token Prediction) 헤드 포함. 15단계 speculative decoding 계열. `27b-q4_K_M`과 속도 비교해볼 가치 있음 |
| `27b-q8_0`, `27b-bf16` | ❌ 32GB 초과 |
| `*-mlx-*`, `mxfp8` | ❌ Apple Silicon 전용 |

---

## ⚠️ 커리큘럼 진행 시 주의

**Qwen3.8-27B로는 3단계(양자화 비교) 실습이 성립하지 않습니다.**

3단계의 핵심은 "풀 모델 vs 양자화 정확도 비교"인데,
이 모델은 **BF16(56GB)도 Q8_0(30GB)도 32GB에 안 들어갑니다.**
Q4 하나만 돌아가므로 비교 대상이 없습니다.

추가로:
- **멀티모달 VLM** → 19단계 내용이 미리 등장
- **하이브리드 선형 어텐션** → 7단계에서 배울 표준 KV 캐시 공식의 예외 케이스.
  공식을 처음 익히는 단계에서 예외로 배우면 혼란

### 그래서 역할을 나눕니다

| 용도 | 모델 |
|---|---|
| 커리큘럼 2~3단계 실습 | **`qwen3:8b`** fp16 / q8_0 / q4_K_M (3종) |
| 실사용 · 코딩 에이전트 · VLM | **`qwen3.8:27b`** (q4_K_M) |

3단계를 8B로 완주한 뒤, 27B를 "최신 모델은 얼마나 다른가" 대조군으로 쓰면
학습 효과가 더 좋습니다.

---

## 검증 방법 — 계산값 vs 실측값

계산은 어디까지나 추정입니다. 반드시 대조하세요.

```bash
# 로드된 모델의 실제 VRAM / 컨텍스트 / GPU 비율
docker compose exec ollama ollama ps

# 호스트에서 실제 VRAM 점유
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

`ollama ps` 의 **`PROCESSOR` 컬럼이 가장 중요합니다:**

| 표시 | 의미 |
|---|---|
| `100% GPU` | 정상 ✅ |
| `48%/52% CPU/GPU` | **부분 오프로드 — 속도가 10배 느려집니다** ⚠️ |
| `100% CPU` | GPU 미사용 ❌ |

> Ollama는 VRAM이 부족하면 **경고 없이 레이어를 CPU로 내리고 그냥 느려집니다.**
> "로컬 LLM은 원래 느리구나"라고 오해하게 되는 지점입니다.
> 계산을 몰라도 이 한 줄만 확인하면 안전하게 진행할 수 있습니다.
