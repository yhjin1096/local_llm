-- ============================================================
-- 스터디 자료용 pandoc Lua 필터
--
--  ① 표를 가로 스크롤 컨테이너로 감쌈
--     → 넓은 표가 있어도 페이지 본문이 가로로 밀리지 않게
--  ② h2 / h3 에 앵커 링크(#) 추가
--     → 특정 절을 링크로 공유할 수 있게
--  ③ [완전] / [씨앗] 표기를 배지로 변환
--     → 깊이 규칙(GUIDE.md 3절)을 시각적으로 구분
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

-- ② 제목 앵커
function Header(el)
  if (el.level == 2 or el.level == 3) and el.identifier ~= '' then
    local anchor = pandoc.RawInline('html',
      '<a class="anchor" href="#' .. el.identifier .. '" aria-hidden="true">#</a>')
    table.insert(el.content, 1, anchor)
  end
  return el
end

-- ③ 깊이 배지: 본문의 [완전] / [씨앗] 을 배지 span 으로
function Str(el)
  if el.text == '[완전]' then
    return pandoc.RawInline('html', '<span class="badge full">완전</span>')
  elseif el.text == '[씨앗]' then
    return pandoc.RawInline('html', '<span class="badge seed">씨앗</span>')
  end
  return el
end
