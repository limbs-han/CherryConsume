-- 골드의 카드 개정 한 줄에서 근거 원문 파일까지 따라간다. 작업 003 과제 22, 설계 1절 8단계
-- SQL 편집기에서 돌린다. rev의 카드 id를 따라갈 카드로 바꾼다. 운영 이름이다. 개발용은 스키마 앞에 dev_<이름>_을 붙인다
-- 2026-10-02 매개변수 :card_id는 편집기에 따라 칸이 생기지 않아 UNBOUND_SQL_PARAMETER로 멈췄다. 그래서 글자로 적는다
-- 개정 한 줄이 원문에 닿는 길은 셋이다
--   검수 앱 승인: 검수 기록의 초안이 읽은 원문 silver.drafts.doc_paths. 과제 20부터 생긴다
--   첫 적재 initial: 카드 파일을 대조한 첫 수집 원문 silver.golden.sources
--   손 승인: 첫 적재와 같은 원문에 사람이 올린 incoming 폴더 이름 silver.reviews.source를 더해 보인다
-- 원문 경로는 bronze.fetches와 silver.documents가 같은 값을 쓴다. 볼륨 cherry.bronze.raw 안의 경로다
-- 끝은 silver.documents다. 사람 계정에는 bronze 표를 읽는 권한을 주지 않았다. 2026-10-02. 원문 주소는 카드 파일 sources에 있다
-- 삼성, 롯데, IBK 다섯 장의 첫 적재 개정은 그때 자동 수집 원문이 없어 원문 칸이 빈 줄 하나로 나온다. 계보가 검수 기록에서 끝난다
-- 2026-10-05부터 집 PC 러너가 이 다섯 장의 원문도 받아 다음 개정부터는 원문이 붙는다
WITH rev AS (
  SELECT card_id, effective_from, source, review_id
  FROM cherry.gold.card_revisions
  WHERE card_id IN ('samsung-id-on', 'kb-easy-all-titanium')
),
via_app AS (
  SELECT r.card_id, r.effective_from, r.review_id, '검수 앱 승인' AS way, v.source AS uploaded,
         explode(d.doc_paths) AS doc_path
  FROM rev r
  JOIN cherry.silver.reviews v ON v.review_id = r.review_id AND v.draft_id IS NOT NULL
  JOIN cherry.silver.drafts d ON d.draft_id = v.draft_id
),
via_first AS (
  SELECT r.card_id, r.effective_from, r.review_id,
         CASE WHEN r.review_id = 'initial' THEN '첫 적재' ELSE '손 승인' END AS way,
         v.source AS uploaded, explode_outer(map_values(g.sources)) AS doc_path
  FROM rev r
  LEFT JOIN cherry.silver.reviews v ON v.review_id = r.review_id
  LEFT JOIN cherry.silver.golden g ON g.card_id = r.card_id
  WHERE v.draft_id IS NULL
)
SELECT x.card_id, x.effective_from, x.review_id, x.way, x.uploaded, x.doc_path, d.source_id, d.fetched_at, d.sha256
FROM (SELECT * FROM via_app UNION ALL SELECT * FROM via_first) x
LEFT JOIN cherry.silver.documents d ON d.path = x.doc_path
ORDER BY x.card_id, x.effective_from, x.doc_path;
