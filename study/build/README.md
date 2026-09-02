# study/build — 스터디 자료 빌드 도구

`study/*.md` 를 **의존성 없는 단일 HTML 파일**로 변환합니다.
작성 규칙은 [`../GUIDE.md`](../GUIDE.md) 를 보세요. 이 문서는 **도구 사용법**만 다룹니다.

## 구성

| 파일 | 역할 |
|---|---|
| `build.sh` | 빌드 진입점. pandoc 을 호출합니다 |
| `template.html` | HTML 골격 (머리말 / 사이드바 목차 / 본문 / 테마 토글) + 목차 스크립트 |
| `style.css` | 공통 스타일. 라이트·다크 테마, 사이드바, 콜아웃, 표, SVG |
| `filter.lua` | pandoc Lua 필터. 표 스크롤 래핑, 깊이 배지 |

## 요구사항

```bash
pandoc --version    # 3.x 필요 (fenced_divs, raw_html 사용)
```

**Ubuntu 20.04 의 `apt install pandoc` 은 2.5 가 설치되어 쓸 수 없습니다.**
[pandoc 릴리스](https://github.com/jgm/pandoc/releases)에서 정적 바이너리를 받아 `PATH` 에 두세요.

```bash
curl -sL -o /tmp/pandoc.tar.gz \
  https://github.com/jgm/pandoc/releases/download/3.1.11.1/pandoc-3.1.11.1-linux-amd64.tar.gz
tar xzf /tmp/pandoc.tar.gz -C /tmp
install -m755 /tmp/pandoc-3.1.11.1/bin/pandoc ~/.local/bin/pandoc   # PATH 에 ~/.local/bin 이 있어야 합니다
```

## 사용법

```bash
cd study

./build/build.sh              # 모든 스터디 문서 빌드 (GUIDE.md 는 제외)
./build/build.sh 01-hardware  # 특정 문서만
```

산출물은 `study/01-hardware.html` 처럼 **같은 디렉터리에 같은 이름**으로 나옵니다.

## 산출물의 성질

- **완전 self-contained** — CSS 가 `<style>` 로 인라인됩니다. 외부 요청이 0건이므로
  네트워크 없이, 파일 하나만 복사해도 열립니다
- **사이드바 목차** — 왼쪽에 고정된 목차가 항상 떠 있고, 항목을 누르면 그 절로 이동합니다.
  스크롤에 따라 **지금 읽고 있는 절이 자동으로 표시**됩니다.
  화면이 1100px 보다 좁아지면 목차가 접히고 좌측 상단 `☰` 버튼으로 여닫습니다
- **테마 대응** — OS 의 라이트/다크 설정을 따르고, 우측 상단 버튼으로 수동 전환합니다
  (선택은 `localStorage` 에 기억됩니다)
- **반응형** — 넓은 표와 SVG 는 자기 영역 안에서만 가로 스크롤되고,
  페이지 본문은 가로로 밀리지 않습니다
- **인쇄 대응** — 목차·토글 버튼이 숨고, 표·코드블록이 페이지 경계에서 쪼개지지 않습니다

## 지원하는 마크다운 문법

표준 문법 외에 다음을 씁니다. 자세한 규칙은 `../GUIDE.md` 9절.

### 콜아웃 — pandoc fenced_divs

```markdown
::: note
개념 보충 내용
:::

::: {.quote data-label="원문 (1단계)"}
> 인용문
:::
```

사용 가능한 종류: `note` `key` `calc` `warn` `later` `quote` `quiz`
`data-label` 속성으로 머리 라벨을 개별 재정의할 수 있습니다.

### 목차 — 자동 생성

목차는 `build.sh` 의 `--toc --toc-depth=3` 이 **문서의 `##` / `###` 제목에서 자동으로 만듭니다.**
마크다운에 목차를 직접 쓰지 마세요. 문서 쪽에서 해야 할 일은 제목 계층을 지키는 것뿐입니다.

| 마크다운 | 목차에서 |
|---|---|
| `## 2.3 메모리 계층과 VRAM` | 굵은 상위 항목 |
| `### VRAM은 늘릴 수 없다` | 그 아래 들여쓴 항목 |
| `#### …` | 나오지 않음 (깊이 3 까지만) |

제목 옆 `#` 앵커와 목차의 현재 위치 표시는 `template.html` 의 스크립트가 붙입니다.
**Lua 필터로 제목에 앵커를 넣으면 안 됩니다** — pandoc 이 제목 내용을 목차에도 복사하므로
`<a>` 안에 `<a>` 가 중첩되어 브라우저가 목차 링크를 끊습니다.

### 깊이 배지

본문에 `[완전]` / `[씨앗]` 이라고 쓰면 필터가 배지로 바꿉니다.

### 다이어그램 — inline SVG

**반드시 pandoc raw attribute 펜스 안에 넣습니다.**

````markdown
```{=html}
<figure>
<div class="svg-scroll">
<svg viewBox="0 0 720 240" role="img" aria-label="설명">
  ...
</svg>
</div>
<figcaption>캡션</figcaption>
</figure>
```
````

> ⚠️ 펜스를 빼면 pandoc 이 `markdown_in_html_blocks` 규칙에 따라 SVG 내부를 마크다운으로
> 재파싱하면서 `<p>` / `</div>` 를 끼워 넣습니다. **빌드는 성공하는데 그림만 안 보입니다.**
> `marker id` 는 문서 전체에서 유일해야 합니다 (`ar1`, `ar2`, …).

색은 하드코딩하지 말고 다음 클래스를 쓰면 테마에 따라 자동으로 바뀝니다.

| 클래스 | 용도 |
|---|---|
| `s-fg` | 본문 색 텍스트 |
| `s-soft` | 보조 텍스트 |
| `s-faint` | 흐린 텍스트 |
| `s-line` | 선 / 화살표 (stroke) |
| `s-box` | 상자 (fill + stroke) |
| `s-accent` | 강조 |
| `mono` | 고정폭 글꼴 |

### YAML 머리말

```yaml
---
title:    문서 제목
subtitle: 한 줄 요약
eyebrow:  PHASE 0 · 1단계
meta:
  - 대상 장비 — RTX 5090 32GB × 1
  - 최종 수정 — 2026-09-01
footer:
  - 상위 커리큘럼 — ../README.md 1단계
---
```

## 문제가 생기면

| 증상 | 원인 / 조치 |
|---|---|
| `The extension ... is not supported` | pandoc 버전이 낮음. 3.x 로 올리세요 |
| 콜아웃이 그냥 문단으로 나옴 | `:::` 앞뒤로 **빈 줄**이 있어야 합니다 |
| 표가 깨짐 | 헤더 아래 구분선(`\|---\|---\|`)이 열 수와 맞는지 확인 |
| SVG 가 안 보임 | ` ```{=html} ` 펜스로 감쌌는지 확인. 펜스 없이 쓰면 조용히 깨집니다 |
| 화살표가 엉킴 | 여러 SVG 가 같은 `marker id` 를 씀. `ar1`, `ar2` 처럼 유일하게 |
| CSS 가 안 먹음 | `style.css` 를 고친 뒤 다시 빌드해야 반영됩니다 (HTML 에 복사되므로) |
| 목차가 비어 있음 | 문서에 `##` 제목이 없음. 제목 계층을 확인하세요 |
| 목차 항목이 링크로 안 잡힘 | 필터가 제목에 `<a>` 를 넣고 있는지 확인 (위 "목차 — 자동 생성") |
