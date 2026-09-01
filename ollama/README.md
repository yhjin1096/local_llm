# Phase 1 — Ollama + 평가 환경 (커리큘럼 2~3단계)

상위 커리큘럼: [`../README.md`](../README.md)

## 이 환경의 목표

커리큘럼 2~3단계를 돌리기 위한 최소 구성입니다.

1. **2단계** — 모델을 돌리고, **측정 도구(MMLU Pro / HumanEval)를 손에 쥔다**
2. **3단계** — 같은 모델의 양자화 버전들을 **같은 자로 재서 정확도 붕괴를 체감한다**

> 3단계의 비교표를 채우는 것이 Phase 1의 산출물입니다.
> 이 표가 이후 4·16·20단계에서 계속 기준선으로 쓰입니다.

## 구성

| 서비스 | 이미지 | 역할 |
|---|---|---|
| `ollama` | `ollama/ollama:latest` (공식) | 모델 서빙. **Dockerfile 없음** — 빌드할 것이 없습니다 |
| `eval` | `./eval/Dockerfile` | 평가 하네스. GPU 불필요 (HTTP API만 호출) |

```
ollama/
├── docker-compose.yml
├── .env                  ← 튜닝 값 (컨텍스트, KEEP_ALIVE 등)
├── eval/
│   ├── Dockerfile        ← Dockerfile 이 필요한 유일한 자리
│   ├── requirements.txt
│   └── scripts/          ← 직접 작성한 평가 스크립트
├── models/               ← 모델 저장 (bind mount, gitignore)
└── results/              ← 측정 결과 (gitignore)
```

## 이 환경의 하드웨어 전제

| 항목 | 값 |
|---|---|
| GPU | RTX 5090 32GB × 1 |
| 아키텍처 | **Blackwell (sm_120)** |
| 드라이버 | 580.173.02 |

> ⚠️ **Blackwell 주의사항**: sm_120은 CUDA 12.8+ 를 요구합니다.
> 구버전 컨테이너 이미지는 `no kernel image is available for execution` 로 죽습니다.
> 문제가 생기면 먼저 `docker compose pull` 로 이미지를 갱신하세요.

> 📌 **커리큘럼과 다른 점**
> - **9단계(Tensor/Pipeline Parallel)는 GPU 1대라 불가능합니다.** 나머지 20단계는 모두 가능.
> - 반대로 **3090(Ampere)에 없는 FP8/NVFP4 하드웨어 가속이 있습니다.**
>   3단계의 NVFP4 비교, 16단계의 FP8 레시피를 실제 가속으로 실습할 수 있습니다.
> - 32GB면 **8B BF16(16GB) 원본을 여유롭게 돌릴 수 있습니다** → 3단계 비교의 기준선 확보 가능.

---

## 실행

```bash
cd ollama

# ① 서버 기동
docker compose up -d ollama
docker compose logs -f ollama          # GPU 인식 확인

# ② GPU가 잡혔는지 확인 (로그에 "inference compute" + 5090 이 보여야 함)
docker compose exec ollama nvidia-smi

# ③ 모델 받기
docker compose exec ollama ollama pull qwen3:8b
docker compose exec ollama ollama list

# ④ 대화 테스트
docker compose exec -it ollama ollama run qwen3:8b

# ⑤ API 테스트 (호스트에서 — opencode 등이 붙는 경로와 동일)
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3:8b","messages":[{"role":"user","content":"안녕"}]}'
```

### 실제 컨텍스트 길이 확인 (중요)

`.env`의 `OLLAMA_CONTEXT_LENGTH`가 반영됐는지 반드시 확인하세요.
**Ollama 기본값 4096은 커리큘럼 8단계와 에이전트 사용 모두를 망칩니다.**

```bash
docker compose exec ollama ollama show qwen3:8b        # 모델이 지원하는 길이
docker compose exec ollama ollama ps                  # 로드된 모델의 실제 컨텍스트/VRAM
```

`.env`를 수정한 뒤에는 **컨테이너 재생성이 필요합니다** (재시작만으로는 반영 안 됨):

```bash
docker compose up -d --force-recreate ollama
```

---

## 2단계 — 평가 도구 쥐기

```bash
# 평가 컨테이너 빌드 & 진입
docker compose build eval
docker compose run --rm eval bash
```

컨테이너 안에서:

```bash
# MMLU Pro — Ollama 를 OpenAI 호환 엔드포인트로 호출
lm_eval --model local-chat-completions \
        --model_args model=qwen3:8b,base_url=http://ollama:11434/v1,num_concurrent=4 \
        --tasks mmlu_pro \
        --limit 200 \
        --output_path results/mmlu_pro_qwen3-8b.json

# HumanEval+ (생성된 코드를 실제 실행해 채점)
evalplus.evaluate --model qwen3:8b \
                  --dataset humaneval \
                  --backend openai \
                  --base-url http://ollama:11434/v1
```

> 💡 `--limit 200` 으로 시작하세요. MMLU Pro 전체는 12,000문항이라 로컬 8B로는 오래 걸립니다.
> **중요한 것은 절대 점수가 아니라 "같은 조건에서 모델 간 비교"** 입니다.
> 단, 3단계 비교 시 `--limit` 값과 시드를 **모든 실행에서 동일하게** 유지해야 합니다.

> 💡 원문 저자의 권장대로 LLM에게 평가 스크립트를 직접 짜게 해보는 것도 좋습니다.
> 평가 루프의 구조(프롬프트 포맷 → 응답 파싱 → 채점)를 한 번 손으로 만들어보면
> 3단계·16단계에서 계속 쓰입니다. `eval/scripts/` 에 두면 컨테이너에 마운트됩니다.

---

## 3단계 — 양자화 비교

같은 모델의 여러 양자화 버전을 받아 **동일 스크립트로** 측정합니다.

```bash
# 사용 가능한 태그 확인 (모델마다 제공되는 양자화가 다릅니다)
#   → https://ollama.com/library/qwen3/tags
docker compose exec ollama ollama pull qwen3:8b-fp16     # 원본급 ~16GB
docker compose exec ollama ollama pull qwen3:8b-q8_0     # 8bit  ~8.5GB
docker compose exec ollama ollama pull qwen3:8b-q4_K_M   # 4bit  ~5GB

du -sh ./models        # 디스크 사용량 추적
```

> ⚠️ `OLLAMA_MAX_LOADED_MODELS=2` 이고 fp16이 16GB이므로, fp16 + 다른 모델을 동시에
> 올리면 32GB를 넘길 수 있습니다. 측정은 **한 번에 하나씩** 하고
> `ollama ps` 로 실제 상주 상태를 확인하세요.

### 채울 표 (Phase 1 산출물)

| 양자화 | 파일 크기 | VRAM (`ollama ps`) | MMLU Pro | HumanEval+ | tok/s |
|---|---|---|---|---|---|
| fp16 | | | | | |
| q8_0 | | | | | |
| q4_K_M | | | | | |
| q3_K_S | | | | | |

**관찰 포인트:**
- 어느 비트 수부터 급격히 무너지는가 (보통 3~4bit 경계)
- 양자화 손상은 **작은 모델일수록, 추론이 긴 과제일수록** 심합니다
  → 여유가 되면 1.7B / 8B / 14B 를 같은 q4로 비교해보세요.
  "파라미터 수가 손상 여유(redundancy)"라는 감각이 생깁니다
- 측정 중 `OLLAMA_KEEP_ALIVE=-1` 이어야 언로드로 인한 오염이 없습니다

---

## 트러블슈팅

| 증상 | 원인 / 조치 |
|---|---|
| `no kernel image is available` | Blackwell 미지원 구버전 이미지 → `docker compose pull` |
| GPU 대신 CPU로 추론 (매우 느림) | `docker compose logs ollama` 에서 GPU 감지 여부 확인. `nvidia-ctk` 런타임 등록 상태 점검 |
| 컨텍스트가 4096으로 고정 | `.env` 수정 후 `--force-recreate` 필요 |
| 벤치마크 중간에 속도가 급변 | 모델 언로드/재로드. `OLLAMA_KEEP_ALIVE=-1` 확인 |
| `eval` 에서 ollama 연결 실패 | 컨테이너 내부에서는 `localhost` 가 아니라 **`http://ollama:11434`** |
| VRAM OOM | `ollama ps` 로 상주 모델 확인 → `OLLAMA_MAX_LOADED_MODELS=1` 로 낮추기 |

## 다음 단계

Phase 1이 끝나면 **4단계에서 Ollama를 버리고 vLLM으로 갑니다.**
그때는 `vllm/` 디렉터리를 새로 만들고, 이 환경의 `results/` 를 기준선으로 삼아
**엔진이 바뀌어도 같은 정확도가 재현되는지** 확인합니다.
