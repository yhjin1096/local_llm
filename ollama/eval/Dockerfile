# ─────────────────────────────────────────────────────────────
# 평가 하네스 (커리큘럼 2단계: "측정 도구를 먼저 손에 쥔다")
#
# 여기가 이 프로젝트에서 Dockerfile 이 필요한 유일한 자리입니다.
#   - Ollama 는 공식 이미지로 충분 (빌드할 것이 없음)
#   - 평가 환경은 재현성이 중요하므로 고정해둡니다
#
# GPU 불필요: Ollama 의 HTTP API 만 호출합니다.
#   → torch 를 CPU 휠로 받아 이미지 크기를 크게 줄입니다.
# ─────────────────────────────────────────────────────────────
FROM python:3.12-slim

# HumanEval 은 생성된 코드를 "실제로 실행"해서 채점합니다.
# git: 일부 패키지가 소스 설치를 요구
# build-essential: 네이티브 확장 빌드용
RUN apt-get update && apt-get install -y --no-install-recommends \
        git build-essential curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# torch CPU 휠을 먼저 받아 GPU 버전(수 GB)이 끌려오는 것을 방지합니다.
COPY requirements.txt .
RUN pip install --no-cache-dir \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        -r requirements.txt

RUN mkdir -p /work/results /work/scripts

# 사용 예시는 README.md 참고.
CMD ["bash"]
