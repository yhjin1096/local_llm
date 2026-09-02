-- ============================================================
-- 스터디 자료용 pandoc Lua 필터
--
--  ① 표를 가로 스크롤 컨테이너로 감쌈
--     → 넓은 표가 있어도 페이지 본문이 가로로 밀리지 않게
--  ② [완전] / [씨앗] 표기를 배지로 변환
--     → 깊이 규칙(GUIDE.md 3절)을 시각적으로 구분
--
-- 제목 앵커(#)는 여기서 붙이지 않고 template.html 의 스크립트가 붙입니다.
-- 필터로 제목 내용에 <a> 를 넣으면 pandoc 이 그 내용을 목차에도 그대로 복사해
-- 목차 링크가 <a> 안에 <a> 인 구조가 되고, 브라우저가 이를 끊어 목차가 깨집니다.
-- 다이어그램(<figure> + <svg>)은 필터가 손대지 않습니다.
-- 마크다운에서 ```{=html} 펜스로 감싸 원문 그대로 통과시키고,
-- 가로 스크롤 컨테이너(<div class="svg-scroll">)도 원문에 직접 씁니다.
-- (raw HTML 블록으로 두면 pandoc 이 markdown_in_html_blocks 규칙에 따라
--  내부를 마크다운으로 재파싱하면서 SVG 중간에 <p>/</div> 를 끼워 넣습니다.)
-- ============================================================

-- ① 표 감싸기
function Table(el)
  return {
    pandoc.RawBlock('html', '<div class="table-scroll">'),
    el,
    pandoc.RawBlock('html', '</div>')
  }
end

-- ② 깊이 배지: 본문의 [완전] / [씨앗] 을 배지 span 으로
function Str(el)
  if el.text == '[완전]' then
    return pandoc.RawInline('html', '<span class="badge full">완전</span>')
  elseif el.text == '[씨앗]' then
    return pandoc.RawInline('html', '<span class="badge seed">씨앗</span>')
  end
  return el
end
