# Phase 1 — Ollama + 평가 환경 (커리큘럼 2~3단계)

상위 커리큘럼: [`../README.md`](../README.md)

## 이 환경의 목표

커리큘럼 2~3단계를 돌리기 위한 최소 구성입니다.

1. **2단계** — 모델을 돌리고, **측정 도구(MMLU Pro / HumanEval)를 손에 쥔다**
2. **3단계** — 같은 모델의 양자화 버전들을 **같은 자로 재서 정확도 붕괴를 체감한다**

> 3단계의 비교표를 채우는 것이 Phase 1의 산출물입니다.
> 이 표가 이후 4·16·20단계에서 계속 기준선으로 쓰입니다.

## 구성

| 서비스 | 이미지 | 역할 | GPU |
|---|---|---|---|
| `ollama` | `ollama/ollama:latest` (공식) | 모델 서빙. **Dockerfile 없음** — 빌드할 것이 없습니다 | ✅ |
| `eval` | `./eval/Dockerfile` | 평가 하네스 (HTTP API만 호출) | ❌ |
| `open-webui` | `ghcr.io/open-webui/open-webui:main` | 브라우저 채팅 UI. **기본으로 뜨지 않습니다** | ❌ |

```
ollama/
├── docker-compose.yml
├── .env                  ← 튜닝 값 (컨텍스트, KEEP_ALIVE, WEBUI_PORT 등)
├── run.sh                ← 기동 스크립트 (./run.sh --help)
├── eval/
│   ├── Dockerfile        ← Dockerfile 이 필요한 유일한 자리
│   ├── requirements.txt
│   └── scripts/          ← 직접 작성한 평가 스크립트
├── models/               ← 모델 저장 (bind mount, gitignore)
├── mount/                ← 컨테이너에 넘길 파일 (이미지 등) → /root/mount
└── results/              ← 측정 결과 (gitignore)
```

### 서비스는 따로 뜹니다

compose 명령에 **서비스명을 명시**하므로 서로 간섭하지 않습니다.

| 명령 | 뜨는 것 |
|---|---|
| `./run.sh` | `ollama` 만 |
| `./run.sh --ui` | `ollama` + `open-webui` |
| `docker compose up -d open-webui` | `open-webui` (의존성으로 `ollama` 도 함께) |
| `docker compose stop open-webui` | UI 만 정지. **`ollama` 는 계속 돕니다** |
| `docker compose up -d` | 서비스명을 빼면 **전부** 뜹니다 |

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

## docker compose 기초 (처음 쓰는 경우)

`docker-compose.yml` 은 **"어떤 컨테이너를 어떤 설정으로 띄울지" 적어둔 명세서**입니다.
`docker compose` 명령은 **항상 이 파일이 있는 디렉터리에서** 실행합니다.

### `image:` 와 `build:` 의 차이

**두 서비스 모두 compose 가 관리합니다.** 차이는 compose 를 쓰는지 여부가 아니라
**이미지를 어디서 얻는지**입니다.

```
docker compose            ← 무엇을 어떤 설정으로 띄울지 (상위 명세)
    │
    ├── ollama 서비스 ──→ image: ollama/ollama:latest
    │                      Docker Hub 에서 완성품을 받아옴
    │
    └── eval 서비스 ────→ build: ./eval
                           eval/Dockerfile 로 직접 만듦
                                   │
                          Dockerfile → 이미지 → 컨테이너
```

`Dockerfile` 은 **이미지를 만드는 단계**의 도구이고, compose 는 **그렇게 얻은 이미지를
어떻게 띄울지** 기술합니다. 층위가 다르므로 서로 대체하는 관계가 아닙니다.
compose 없이 Dockerfile 만 쓸 수도 있고, Dockerfile 없이 compose 만 쓸 수도 있습니다
(`ollama` 서비스가 그 경우입니다).

| 서비스 | 방식 | 뜻 |
|---|---|---|
| `ollama` | `image: ollama/ollama:latest` | **남이 만든 이미지를 그대로 받아 씁니다.** 빌드할 것이 없습니다 |
| `eval` | `build: context: ./eval` | **`eval/Dockerfile` 로 직접 이미지를 만듭니다.** 원하는 패키지 조합의 공개 이미지가 없기 때문입니다 |

> 📌 Dockerfile 은 원래 알던 그대로 **이미지를 만드는 레시피**입니다. compose가 그 용도를 바꾸지는 않습니다.
> 달라지는 것은 **누가 빌드를 호출하는가**뿐입니다. `docker build` 를 손으로 치는 대신
> `docker compose build eval` 이 `build:` 항목을 보고 대신 빌드합니다.

### 왜 ollama 는 받아 쓰고 eval 은 만드는가

**ollama 를 직접 만들지 않는 이유**

| 이유 | 설명 |
|---|---|
| 이미 완성돼 있음 | 공식 이미지에 ollama 바이너리 + CUDA 런타임 + 모델 관리가 다 들어 있습니다 |
| 만들면 손해 | 직접 짜면 CUDA 버전 맞추기와 ollama 빌드를 떠안는데, 얻는 게 없습니다 |
| **업스트림 갱신을 그냥 받을 수 있음** | Blackwell(sm_120) 지원이 계속 개선되는 중입니다. `docker compose pull` 한 줄로 따라갑니다 |

세 번째가 실질적으로 가장 큽니다. `no kernel image is available` 의 1차 처방이
`docker compose pull` 인 것도 이 구조 덕분입니다.

**eval 을 직접 만드는 이유**

| 이유 | 설명 |
|---|---|
| 그런 이미지가 없음 | `lm-eval[api]` + `evalplus` + `pandas` + **CPU 전용 torch** 조합의 공개 이미지가 없습니다 |
| **재현성이 결과의 전제** | 3단계 양자화 비교는 "같은 자로 재기"가 핵심입니다. 패키지 버전이 흔들리면 16·20단계에서 기준선으로 못 씁니다 |
| 크기 최적화가 필요 | `eval` 은 HTTP API 만 호출하므로 GPU 가 불필요합니다. torch 를 CPU 휠로 받아 수 GB 를 아낍니다 |

**판단 기준으로 일반화하면**

| 상황 | 선택 |
|---|---|
| 필요한 것이 공개 이미지에 이미 다 있다 | `image:` — 받아 씁니다 |
| 내가 고른 패키지 조합을 고정해야 한다 | `build:` + Dockerfile |
| 업스트림이 활발히 갱신되고 그걸 따라가고 싶다 | `image:` |
| 측정·실험의 재현성이 결과의 전제다 | `build:` |

> 💡 둘은 배타적이지 않습니다. `FROM ollama/ollama` 로 시작하는 Dockerfile 을 써서
> 공식 이미지에 뭔가 얹을 수도 있습니다. 지금은 얹을 게 없어서 안 하는 것뿐입니다.
>
> 이 구도는 곧 바뀝니다. **커리큘럼 5단계가 "vLLM 소스 빌드"** 입니다.
> 컴파일 플래그와 CUDA 아키텍처(`sm_120`)를 직접 지정해야 하므로 `image:` 로는 안 되고,
> 서빙 엔진 쪽에도 Dockerfile 이 필요해집니다.
> 지금 `ollama` 가 `image:` 인 것은 **"2~3단계에서는 엔진 내부를 건드리지 않는다"**
> 는 커리큘럼 설계와 맞물린 선택입니다.

### 명령에 `ollama` 가 두 번 나오는 이유

가장 헷갈리는 지점입니다. 같은 단어가 다른 것을 가리킵니다.

```
docker compose exec   ollama   ollama pull qwen3:8b
└──────┬──────┘ └─┬┘   └──┬─┘   └────────┬───────┘
   compose 도구   무엇을  어느 서비스     그 안에서 실행할 명령
                  할지    (yml 의 이름)  (컨테이너 속 ollama CLI)
```

앞의 것은 **명세서에 적힌 서비스 이름**이고, 뒤의 것은 **그 컨테이너 안에 들어 있는 프로그램**입니다.

### 명령별 역할

| 명령 | 하는 일 | 알아둘 것 |
|---|---|---|
| `up -d <서비스>` | 이미지 받고 컨테이너 만들고 시작 | `-d` 는 백그라운드. 없으면 터미널이 로그에 묶입니다. 서비스명을 빼면 `eval` 까지 함께 뜹니다 |
| `logs -f <서비스>` | 로그를 실시간으로 따라가기 | **`Ctrl+C` 로 나옵니다.** 로그 보기만 끝나고 컨테이너는 계속 돕니다 |
| `exec <서비스> <명령>` | **이미 돌고 있는** 컨테이너 안에서 명령 실행 | `up` 이 먼저 와야 합니다 |
| `exec -it <서비스> <명령>` | 대화형으로 실행 | `-i` 는 입력 받기, `-t` 는 터미널 흉내. 채팅에 필요합니다 |
| `run --rm <서비스> <명령>` | **새 컨테이너를 만들어** 실행하고 끝나면 삭제 | `eval` 처럼 필요할 때만 쓰는 서비스에 적합 |
| `ps` | 컨테이너 상태 확인 | `ollama ps`(로드된 모델)와 **다른 명령**입니다 |
| `build <서비스>` | `Dockerfile` 로 이미지 다시 만들기 | `build:` 를 쓰는 `eval` 에만 해당 |
| `pull <서비스>` | 이미지를 최신으로 갱신 | Blackwell 문제의 1차 처방 |

### `up` 을 여러 번 실행해도 안전합니다

compose는 컨테이너에 **설정 해시를 라벨로 붙여둡니다.** `up` 을 다시 하면
`docker-compose.yml` + `.env` 로 계산한 해시를 기존 컨테이너의 것과 비교합니다.

| 상태 | compose 의 판단 |
|---|---|
| 컨테이너 없음 | 만들고 시작 |
| 실행 중 + 설정 일치 | **그대로 둡니다** (아무 일도 일어나지 않음) |
| 정지됨 + 설정 일치 | 시작만 함 |
| 설정이 달라짐 | **자동으로 지우고 다시 만듭니다** |

`docker run` 은 이 비교를 못 합니다. 어떤 옵션으로 띄웠는지가 셸 히스토리에만 남기 때문입니다.
**명세서를 파일로 고정한다**는 것이 compose 를 쓰는 첫 번째 이유입니다.

---

## 환경을 바꾸거나 컨테이너를 다시 만들 때

### 무엇을 바꾸느냐에 따라 명령이 다릅니다

| 바꾸는 것 | 고칠 파일 | 명령 |
|---|---|---|
| 컨텍스트 길이, KV 타입 등 환경변수 | `.env` | `docker compose up -d --force-recreate ollama` |
| 포트, 볼륨, GPU 할당 등 구조 | `docker-compose.yml` | `docker compose up -d ollama` (변경을 자동 감지) |
| 이미지 버전 | — | `docker compose pull ollama && docker compose up -d ollama` |
| 평가 환경의 파이썬 패키지 | `eval/requirements.txt` | `docker compose build eval` |

> ⚠️ `.env` 만 예외적으로 `--force-recreate` 가 필요합니다.
> 환경변수는 컨테이너를 **만들 때** 주입되므로 `restart` 로는 반영되지 않고,
> compose 가 `.env` 변경을 항상 감지하지도 못합니다.

### 컨테이너를 지워도 사라지지 않는 것

컨테이너에는 **writable layer** 가 하나 붙습니다. 컨테이너 안에서 만든 파일과
`apt install` 한 패키지가 전부 거기 쌓이고, **컨테이너를 삭제하면 그 레이어도 함께 사라집니다.**

이 문제를 해결하는 것은 compose 가 아니라 **volume 설계**입니다.
`docker-compose.yml` 의 `volumes:` 항목이 남아야 할 것을 전부 컨테이너 밖으로 빼놓습니다.

| 데이터 | 어디에 | 컨테이너를 지워도 |
|---|---|---|
| 받아둔 모델 | bind mount `./models` | ✅ 남습니다 |
| 측정 결과 | bind mount `./results` | ✅ 남습니다 |
| 직접 쓴 평가 스크립트 | bind mount `./eval/scripts` | ✅ 남습니다 |
| 벤치마크 데이터셋 캐시 | named volume `hf_cache` | ✅ 남습니다 |
| 컨테이너 안에서 `apt install` 한 것 | writable layer | ❌ 사라집니다 |
| 마운트되지 않은 경로에 만든 파일 | writable layer | ❌ 사라집니다 |

bind mount 는 호스트 디렉터리를 그대로 연결한 것이라 `ls` 와 `du` 로 직접 볼 수 있습니다.
모델을 `./models` 에 둔 덕분에 컨테이너를 몇 번 다시 만들어도 수십 GB를 다시 받지 않습니다.

> 📌 **원칙**: 컨테이너 안에서 직접 설치하지 마세요.
> `Dockerfile` 이나 `requirements.txt` 에 적고 `build` 하세요.
> 그러면 컨테이너를 언제 버려도 같은 환경이 재현됩니다.

### `down` 계열의 위험도

| 명령 | 컨테이너 | bind mount | named volume |
|---|---|---|---|
| `docker compose stop` | 정지만 | 안전 | 안전 |
| `docker compose down` | 삭제 | 안전 | 안전 |
| `docker compose down -v` | 삭제 | 안전 | ❌ **삭제됩니다** |
| `docker compose down --rmi all` | 삭제 (이미지까지) | 안전 | 안전 |

`-v` 하나만 조심하면 됩니다. bind mount 는 `down -v` 로도 지워지지 않습니다.

> 💡 프로젝트 이름이나 볼륨 방식을 바꾸면 **고아 볼륨**이 남습니다.
> `docker volume ls` 로 확인하고, 참조하지 않는 것은 `docker volume rm <이름>` 으로 지웁니다.
> 사용 중인 볼륨은 docker 가 삭제를 거부하므로 실수로 지울 위험은 없습니다.

---

## eval 의 Dockerfile 과 requirements.txt

`eval` 은 이 프로젝트에서 **Dockerfile 이 필요한 유일한 자리**입니다.
`lm-eval` + `evalplus` + CPU 전용 torch 조합의 공개 이미지가 없어서 직접 만듭니다.

### 두 파일의 역할 분담

| 파일 | 역할 |
|---|---|
| `eval/Dockerfile` | **이미지를 만드는 순서서.** 베이스 이미지, OS 패키지, 작업 디렉터리, 실행할 기본 명령 |
| `eval/requirements.txt` | **파이썬 패키지 목록.** Dockerfile 이 `pip install -r` 로 읽어들이는 재료 |

### Dockerfile 을 한 줄씩 보면

```dockerfile
FROM python:3.12-slim          # ① 출발점이 되는 이미지
RUN apt-get install -y git build-essential curl   # ② OS 패키지
WORKDIR /work                  # ③ 이후 명령의 기준 디렉터리
COPY requirements.txt .        # ④ 목록만 먼저 복사
RUN pip install -r requirements.txt               # ⑤ 그 목록대로 설치
CMD ["bash"]                   # ⑥ 컨테이너가 뜰 때 실행할 기본 명령
```

- **②** HumanEval 은 생성된 코드를 **실제로 실행해서** 채점하므로 컴파일 도구가 필요합니다
- **④와 ⑤를 나눈 이유** — Docker 는 명령 한 줄을 **레이어** 하나로 캐시합니다.
  소스 전체를 먼저 복사하면 파일 하나만 고쳐도 `pip install` 이 처음부터 다시 돕니다.
  목록만 먼저 복사하면 `requirements.txt` 가 그대로인 한 설치 레이어를 재사용합니다
- **torch CPU 휠** — `--extra-index-url .../whl/cpu` 로 CPU 버전을 받습니다.
  `eval` 은 Ollama 의 HTTP API 만 호출하므로 GPU 가 필요 없고, GPU 휠은 수 GB 입니다

> ⚠️ `Dockerfile` 의 `CMD ["bash"]` 는 실제로는 쓰이지 않습니다.
> `docker-compose.yml` 이 `entrypoint: ["sleep", "infinity"]` 로 덮어쓰기 때문입니다
> (평가 컨테이너가 바로 종료되지 않게 하려는 설정).
> 그래서 진입할 때 `docker compose run --rm eval bash` 처럼 **`bash` 를 명시**합니다.

### 패키지를 추가하고 싶으면

```bash
# ① eval/requirements.txt 에 한 줄 추가
# ② 이미지 다시 만들기
docker compose build eval
```

컨테이너 안에서 `pip install` 하면 그 컨테이너를 지울 때 함께 사라집니다.
`requirements.txt` 에 적는 것이 3단계·16단계에서 같은 측정을 재현하는 유일한 방법입니다.

---

## 웹 UI (open-webui)

브라우저에서 ChatGPT처럼 쓰는 인터페이스입니다. **Ollama 자체에는 웹 UI가 없습니다.**
`localhost:11434` 를 브라우저로 열면 `Ollama is running` 한 줄만 나옵니다. 그 포트는
사람이 보는 화면이 아니라 API 엔드포인트입니다.

```bash
./run.sh --ui                        # 모델 준비 + 웹 UI 까지
docker compose up -d open-webui      # UI 만 (ollama 는 의존성으로 함께 뜸)
```

브라우저에서 `http://localhost:3000` 을 엽니다. 포트는 `.env` 의 `WEBUI_PORT` 로 바꿉니다.

### 터미널과 비교하면

| | 터미널 (`ollama run`) | 웹 UI |
|---|---|---|
| **이미지 입력** | 컨테이너 경로 필요 (`mount/` 활용) | **드래그앤드롭** |
| 대화 기록 | 세션이 끝나면 사라짐 | 저장되고 검색됨 |
| 여러 모델 비교 | 각각 다시 실행 | 드롭다운 전환, 나란히 비교 |
| thinking 표시 | 텍스트로 섞여 나옴 | 접었다 펼 수 있음 |
| 마크다운·코드 | 원문 그대로 | 렌더링 |

### 설정에서 짚어둘 것

| 설정 | 이유 |
|---|---|
| `OLLAMA_BASE_URL: http://ollama:11434` | 컨테이너끼리는 `localhost` 가 아니라 **서비스명**으로 부릅니다 |
| `webui_data:/app/backend/data` | named volume. **이게 없으면 컨테이너를 다시 만들 때 대화 기록이 전부 사라집니다** |
| `ports: "3000:8080"` | 컨테이너 내부는 8080, 호스트에서는 3000 |
| `depends_on` + `service_healthy` | `ollama` 가 healthy 가 된 뒤에 뜹니다 |
| GPU 설정 없음 | HTTP 만 호출하므로 **VRAM 을 쓰지 않습니다** (실측으로 확인) |

> ⚠️ `WEBUI_AUTH=false` 는 **브라우저 로그인만** 건너뜁니다.
> `/ollama/api/...` 같은 API 엔드포인트는 여전히 토큰을 요구합니다
> (`{"detail":"Not authenticated"}`).
> 외부에 노출할 때는 반드시 `.env` 에서 `WEBUI_AUTH=true` 로 바꾸세요.

> 💡 `docker compose down -v` 는 `webui_data` 를 지웁니다. 대화 기록이 날아갑니다.
> 컨테이너만 정리할 때는 `-v` 를 빼세요.

---

## 실행

> 💡 아래 ①~⑤ 를 한 번에 처리하는 `./run.sh` 가 있습니다.
> 자세한 설명은 `./run.sh --help` 로 볼 수 있습니다.

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
| 웹 UI 에 모델이 안 보임 | `OLLAMA_BASE_URL` 이 `http://ollama:11434` 인지 확인. `localhost` 면 컨테이너 자신을 가리켜 실패합니다 |
| 웹 UI 포트 충돌 | `.env` 의 `WEBUI_PORT` 를 바꾸고 `docker compose up -d --force-recreate open-webui` |
| 웹 UI 대화 기록이 사라짐 | `webui_data` 볼륨이 지워진 것입니다 (`down -v` 등) |
| 컨테이너를 다시 만들었더니 작업이 사라짐 | 마운트되지 않은 경로에 있던 파일입니다. 남아야 할 것은 `Dockerfile` · `requirements.txt` · bind mount 경로에 두세요 (위 [환경 변경](#환경을-바꾸거나-컨테이너를-다시-만들-때) 절) |
| 쓰지 않는 볼륨이 디스크를 먹음 | 프로젝트명이나 볼륨 방식을 바꿀 때 생기는 고아 볼륨입니다. `docker volume ls` 로 확인 후 `docker volume rm <이름>` |
| 포트 11434 가 이미 사용 중 | 다른 방식으로 띄운 Ollama 가 있습니다. `docker ps -a --filter name=ollama` 와 `ss -tlnp \| grep 11434` 로 확인 |
| `pip install` 한 패키지가 사라짐 | 컨테이너 안에서 설치했기 때문입니다. `eval/requirements.txt` 에 적고 `docker compose build eval` |

## 다음 단계

Phase 1이 끝나면 **4단계에서 Ollama를 버리고 vLLM으로 갑니다.**
그때는 `vllm/` 디렉터리를 새로 만들고, 이 환경의 `results/` 를 기준선으로 삼아
**엔진이 바뀌어도 같은 정확도가 재현되는지** 확인합니다.
