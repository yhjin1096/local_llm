#!/usr/bin/env bash
# ============================================================
# 스터디 자료 빌드: study/*.md → study/*.html
#
# 사용법:
#   ./build/build.sh              # study/ 의 모든 스터디 문서 빌드
#   ./build/build.sh 01-hardware  # 특정 문서만 빌드
#
#   (study/ 디렉터리에서 실행해도 되고 저장소 루트에서 실행해도 됩니다)
#
# 요구사항: pandoc 3.x
#   설치 확인:  pandoc --version
# ============================================================

set -euo pipefail

BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY_DIR="$(dirname "$BUILD_DIR")"

# GUIDE.md 는 작성 기준 문서이므로 HTML 로 변환하지 않습니다.
EXCLUDE_REGEX='^(GUIDE)$'

if ! command -v pandoc >/dev/null 2>&1; then
  echo "✗ pandoc 이 없습니다.  sudo apt install pandoc" >&2
  exit 1
fi

# style.css 를 <style> 로 감싼 임시 헤더 파일.
#   --css 는 <link> 를 만들 뿐이라 self-contained 가 되지 않으므로
#   --include-in-header 로 원문 그대로 삽입합니다 (템플릿 변수는 HTML 이스케이프됨).
STYLE_HEADER="$(mktemp -t study-style-XXXXXX.html)"
trap 'rm -f "$STYLE_HEADER"' EXIT
{ echo '<style>'; cat "$BUILD_DIR/style.css"; echo '</style>'; } > "$STYLE_HEADER"

build_one() {
  local stem="$1"
  local src="$STUDY_DIR/$stem.md"
  local out="$STUDY_DIR/$stem.html"

  if [[ ! -f "$src" ]]; then
    echo "✗ 없는 파일: $src" >&2
    return 1
  fi

  pandoc "$src" \
    --from=markdown+pipe_tables+fenced_divs+raw_html+raw_attribute+auto_identifiers+header_attributes+bracketed_spans+fenced_code_attributes \
    --to=html5 \
    --standalone \
    --embed-resources \
    --template="$BUILD_DIR/template.html" \
    --lua-filter="$BUILD_DIR/filter.lua" \
    --include-in-header="$STYLE_HEADER" \
    --toc --toc-depth=3 \
    --highlight-style=tango \
    --wrap=preserve \
    --output="$out"

  local size
  size=$(du -h "$out" | cut -f1)
  echo "✓ $stem.md → $stem.html  ($size)"
}

if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    build_one "${arg%.md}"
  done
else
  found=0
  for src in "$STUDY_DIR"/*.md; do
    [[ -e "$src" ]] || continue
    stem="$(basename "$src" .md)"
    if [[ "$stem" =~ $EXCLUDE_REGEX ]]; then
      echo "· $stem.md — 건너뜀 (작성 기준 문서)"
      continue
    fi
    build_one "$stem"
    found=1
  done
  [[ $found -eq 1 ]] || echo "· 빌드할 스터디 문서가 없습니다."
fi
