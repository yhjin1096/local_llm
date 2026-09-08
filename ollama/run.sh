#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Phase 1 (커리큘럼 2~3단계) 기동 스크립트
#
#   ./run.sh                       기본 모델(qwen3.8:27b) 준비까지
#   ./run.sh qwen3:8b              다른 모델 지정
#   ./run.sh qwen3.8:27b --chat    준비 후 바로 대화 진입
#
# 하는 일:
#   사전 점검 → .env 정합성 → 컨테이너 기동 → GPU 인식 확인
#   → 모델 pull → VRAM 점유 확인
#
# 여러 번 실행해도 안전합니다. 이미 떠 있으면 그대로 쓰고,
# 이미 받은 모델은 다시 받지 않습니다.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

DEFAULT_MODEL="qwen3.8:27b"
NEED_DISK_GB=25          # 18GB 모델 + 여유
WAIT_SECONDS=90          # 서버 응답 대기 상한

# ── 도움말 ───────────────────────────────────────────────────
usage() {
cat <<'HELP'
run.sh — Phase 1 (커리큘럼 2~3단계) 기동 스크립트

사용법
  ./run.sh                       기본 모델(qwen3.8:27b) 준비까지
  ./run.sh qwen3:8b              다른 모델 지정
  ./run.sh qwen3.8:27b --chat    준비 후 바로 대화 진입
  ./run.sh --help                이 도움말

  여러 번 실행해도 안전합니다. 이미 떠 있으면 그대로 쓰고,
  이미 받은 모델은 다시 받지 않습니다.

하는 일 (순서대로)
  1. 사전 점검      docker / compose / GPU / 디스크 여유
  2. .env 정합성    OLLAMA_MAX_LOADED_MODELS 를 1로 고정
                    (18GB 모델을 2개 올리면 32GB를 넘김. 고치면 .env.bak 백업)
  3. 컨테이너 기동  docker compose up -d ollama
                    .env 를 고쳤을 때만 --force-recreate 를 붙임
  4. 응답 대기      ollama list 가 성공할 때까지 최대 90초 폴링
  5. GPU 인식 확인  로그에서 "inference compute" 를 찾음
  6. 모델 pull      이미 있으면 건너뜀
  7. VRAM 확인      짧은 호출로 로드를 유도한 뒤 ollama ps

  수동 명령과 다른 곳
    docker compose logs -f  → 폴링 + 로그 grep  (-f 는 Ctrl+C 로만 끝나서
                                                 스크립트가 멈춤)
    ollama ps 바로 호출     → 로드 유도 후 호출  (pull 만으로는 VRAM 에
                                                 올라가지 않아 빈 표가 나옴)
    ollama run (대화형)     → 기본은 안내만, --chat 일 때만 진입

docker compose 명령 빠른 참고
  docker compose ps                            컨테이너 상태
  docker compose logs -f ollama                로그 (Ctrl+C 로 나옴)
  docker compose exec -it ollama ollama run M  대화 (/bye 로 나옴)
  docker compose exec -T ollama ollama ps      로드된 모델
  docker compose stop ollama                   정지 (컨테이너는 남음)
  docker compose down                          컨테이너 삭제
  docker compose pull ollama                   이미지 갱신

  ※ exec 의 두 번째 ollama 는 컨테이너 속 CLI 이고,
    첫 번째는 docker-compose.yml 의 서비스 이름입니다.

설정을 바꿀 때
  .env (컨텍스트, KV 타입 등)   docker compose up -d --force-recreate ollama
  docker-compose.yml (구조)     docker compose up -d ollama
  eval/requirements.txt         docker compose build eval

  환경변수는 컨테이너를 만들 때 주입되므로 restart 로는 반영되지 않습니다.

데이터는 어디 남는가
  ./models        받아둔 모델      bind mount — 컨테이너를 지워도 남습니다
  ./results       측정 결과        bind mount — 남습니다
  ./eval/scripts  평가 스크립트    bind mount — 남습니다
  hf_cache        데이터셋 캐시    named volume — 남습니다 (down -v 는 지움)

  컨테이너 안에서 apt/pip install 한 것은 컨테이너를 지우면 사라집니다.
  남아야 하는 것은 Dockerfile 이나 requirements.txt 에 적으세요.

자주 나는 오류
  no kernel image is available    Blackwell(sm_120) 미지원 이미지
                                  → docker compose pull ollama
  GPU 대신 CPU 로 추론 (매우 느림) → docker compose logs ollama | grep -i gpu
  컨텍스트가 4096 으로 고정        → .env 수정 후 --force-recreate
  VRAM OOM                        → ollama ps 로 상주 모델 확인

자세한 설명은 README.md, VRAM 예산 계산은 ../study/01-hardware.md 2.5절.
HELP
}

# ── 인수 파싱 ────────────────────────────────────────────────
MODEL=""
CHAT=0
for arg in "$@"; do
  case "$arg" in
    --chat)     CHAT=1 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "알 수 없는 옵션: $arg" >&2
                echo "도움말: ./run.sh --help" >&2; exit 1 ;;
    *)          MODEL="$arg" ;;
  esac
done
MODEL="${MODEL:-$DEFAULT_MODEL}"

# 스크립트가 놓인 디렉터리(= docker-compose.yml 자리)로 이동
cd "$(dirname "$(readlink -f "$0")")"

# ── 출력 헬퍼 ────────────────────────────────────────────────
if [ -t 1 ]; then
  C_STEP=$'\033[1;36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
  C_ERR=$'\033[31m';    C_DIM=$'\033[2m';  C_OFF=$'\033[0m'
else
  C_STEP=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi
step() { printf '\n%s▶ %s%s\n' "$C_STEP" "$1" "$C_OFF"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$1"; }
info() { printf '    %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
die()  { printf '  %s✗%s %s\n' "$C_ERR" "$C_OFF" "$1" >&2; exit 1; }

# ── 1. 사전 점검 ─────────────────────────────────────────────
step "사전 점검"

command -v docker >/dev/null 2>&1 || die "docker 가 없습니다"
docker compose version >/dev/null 2>&1 \
  || die "docker compose v2 가 필요합니다 (docker-compose 구버전은 지원하지 않습니다)"
[ -f docker-compose.yml ] || die "docker-compose.yml 이 없습니다 — ollama/ 안에서 실행하세요"
[ -f .env ]               || die ".env 가 없습니다"
docker info >/dev/null 2>&1 || die "docker 데몬에 접속할 수 없습니다 (권한 또는 서비스 상태 확인)"
ok "docker / compose 준비됨"

if command -v nvidia-smi >/dev/null 2>&1; then
  ok "GPU: $(nvidia-smi --query-gpu=name,memory.total,driver_version \
             --format=csv,noheader | head -1)"
else
  warn "nvidia-smi 가 없습니다 — GPU 없이 뜨면 추론이 매우 느립니다"
fi

avail_gb=$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -dc '0-9')
if [ -n "$avail_gb" ] && [ "$avail_gb" -lt "$NEED_DISK_GB" ]; then
  warn "디스크 여유 ${avail_gb}GB — 권장 ${NEED_DISK_GB}GB 미만입니다"
else
  ok "디스크 여유 ${avail_gb:-?}GB"
fi

# ── 2. .env 정합성 ───────────────────────────────────────────
# 18GB 모델을 동시에 2개 올리면 32GB를 넘기므로 1로 고정합니다.
step ".env 정합성"

recreate=0
read_env() { sed -n "s/^$1=\([^ #]*\).*/\1/p" .env | head -1; }

cur_loaded=$(read_env OLLAMA_MAX_LOADED_MODELS)
if [ "${cur_loaded:-2}" != "1" ]; then
  cp .env .env.bak
  if grep -q '^OLLAMA_MAX_LOADED_MODELS=' .env; then
    sed -i 's/^OLLAMA_MAX_LOADED_MODELS=.*/OLLAMA_MAX_LOADED_MODELS=1/' .env
  else
    printf '\nOLLAMA_MAX_LOADED_MODELS=1\n' >> .env
  fi
  ok "OLLAMA_MAX_LOADED_MODELS ${cur_loaded:-미설정} → 1  (백업: .env.bak)"
  recreate=1
else
  ok "OLLAMA_MAX_LOADED_MODELS=1"
fi

ctx=$(read_env OLLAMA_CONTEXT_LENGTH)
ok "OLLAMA_CONTEXT_LENGTH=${ctx:-8192}"
ok "OLLAMA_KV_CACHE_TYPE=$(read_env OLLAMA_KV_CACHE_TYPE)"
ok "OLLAMA_KEEP_ALIVE=$(read_env OLLAMA_KEEP_ALIVE)  (-1 = 언로드 안 함)"

# ── 3. 컨테이너 기동 ─────────────────────────────────────────
# .env 를 고쳤으면 재시작만으로는 반영되지 않습니다. 컨테이너를 다시 만듭니다.
step "컨테이너 기동"
if [ "$recreate" = "1" ]; then
  info ".env 가 바뀌어 컨테이너를 다시 만듭니다 (--force-recreate)"
  docker compose up -d --force-recreate ollama
else
  docker compose up -d ollama
fi

# ── 4. 서버 응답 대기 ────────────────────────────────────────
step "서버 준비 대기"
ready=0
for i in $(seq 1 "$WAIT_SECONDS"); do
  if docker compose exec -T ollama ollama list >/dev/null 2>&1; then
    ok "응답함 (${i}초)"
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" = "0" ]; then
  printf '\n%s--- 마지막 로그 30줄 ---%s\n' "$C_DIM" "$C_OFF"
  docker compose logs --tail 30 ollama || true
  die "${WAIT_SECONDS}초 동안 응답이 없습니다"
fi

# ── 5. GPU 인식 확인 ─────────────────────────────────────────
step "GPU 인식 확인"
logs=$(docker compose logs ollama 2>&1 || true)

if grep -q "no kernel image is available" <<<"$logs"; then
  die "이미지가 Blackwell(sm_120)을 지원하지 않습니다 — 'docker compose pull' 후 다시 실행하세요"
fi

compute_line=$(grep -i "inference compute" <<<"$logs" | tail -1 || true)
if [ -n "$compute_line" ]; then
  ok "컨테이너가 GPU를 인식했습니다"
  info "$compute_line"
elif grep -qiE "no compatible gpus|looking for compatible gpus" <<<"$logs"; then
  warn "GPU를 찾지 못한 흔적이 있습니다 — CPU 추론으로 떨어졌을 수 있습니다"
  info "확인: docker compose logs ollama | grep -i gpu"
else
  warn "GPU 인식 로그를 찾지 못했습니다 (모델을 처음 올릴 때 나올 수도 있습니다)"
fi

# ── 6. 모델 준비 ─────────────────────────────────────────────
step "모델 준비: $MODEL"
if docker compose exec -T ollama ollama list 2>/dev/null \
     | awk 'NR>1 {print $1}' | grep -qx "$MODEL"; then
  ok "이미 받아둔 모델입니다 — pull 건너뜀"
else
  info "내려받는 중입니다. 회선에 따라 5~30분 걸립니다"
  docker compose exec -T ollama ollama pull "$MODEL" \
    || die "pull 실패 — 태그 이름을 확인하세요 (https://ollama.com/library)"
  ok "받기 완료"
fi
info "디스크 사용량: $(du -sh ./models 2>/dev/null | cut -f1 || echo '확인 불가')"

# ── 7. VRAM 점유 확인 ────────────────────────────────────────
# pull 만으로는 VRAM에 올라가지 않습니다. 짧은 호출로 로드를 유도합니다.
step "VRAM 점유 확인"
info "모델을 올리는 중 (첫 로드는 수십 초 걸릴 수 있습니다)"
docker compose exec -T ollama ollama run "$MODEL" "hi" >/dev/null 2>&1 || true

echo
docker compose exec -T ollama ollama ps || true
echo
if command -v nvidia-smi >/dev/null 2>&1; then
  printf '  호스트 기준: %s\n' \
    "$(nvidia-smi --query-gpu=memory.used,memory.total,temperature.gpu,power.draw \
        --format=csv,noheader | head -1)"
fi

cat <<EOF

${C_STEP}▶ 다음${C_OFF}
  대화 시작   : docker compose exec -it ollama ollama run $MODEL     ($C_DIM/bye 로 나옴$C_OFF)
  API 호출    : curl http://localhost:${OLLAMA_PORT:-11434}/v1/chat/completions \\
                  -H 'Content-Type: application/json' \\
                  -d '{"model":"$MODEL","messages":[{"role":"user","content":"안녕"}]}'
  로그 보기   : docker compose logs -f ollama                        ($C_DIM Ctrl+C 로 나옴$C_OFF)
  정지        : docker compose stop ollama

  ${C_DIM}위 'ollama ps' 의 SIZE 를 study/01-hardware.md 2.5절 예산 계산과 대조해 보세요.${C_OFF}
EOF

if [ "$CHAT" = "1" ]; then
  step "대화 진입 (/bye 로 나옴)"
  exec docker compose exec -it ollama ollama run "$MODEL"
fi
