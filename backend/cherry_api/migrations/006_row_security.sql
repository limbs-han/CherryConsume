-- Supabase는 public 스키마의 표를 Data API로 공개한다. 안내서대로 끄지만, 다시 켜져도 아무 행도 보이지 않게
-- 행 단위 보안을 켠다. 정책이 없어 그 API의 역할은 행을 하나도 보지 못한다. 서버는 표 주인으로 붙어 영향이 없다.
-- 새 표를 만드는 마이그레이션은 그 표에도 켠다. 작업 005 설계 5h
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    END LOOP;
END
$$;
