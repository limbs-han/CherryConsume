-- 슬라이스 5. 모르는 값 묻기. 표 모양은 docs/erd.md, 작업 005 설계 5e절
-- 답마다 바꾼 날을 남긴다. 처음 답은 원래 그랬던 것이라 0001-01-01부터다. 2026-10-02 사용자가 정했다
-- 한 번 돌린 파일은 고치지 않는다. 바꿀 것은 새 번호로 더한다

CREATE TABLE user_card_options (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_card_id uuid NOT NULL REFERENCES user_cards (id) ON DELETE CASCADE,
    option_key text NOT NULL,
    choice_key text NOT NULL,
    effective_from date NOT NULL,
    answered_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_card_id, option_key, effective_from)
);

-- 사람 사실. 생일 달, 현역병 여부처럼 그 사람의 모든 카드에 쓴다
CREATE TABLE user_facts (
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    key text NOT NULL,
    effective_from date NOT NULL,
    value text NOT NULL,
    answered_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, key, effective_from)
);

-- 카드 사실. 급여이체, 마이태그 등록처럼 그 카드에만 쓴다
CREATE TABLE user_card_facts (
    user_card_id uuid NOT NULL REFERENCES user_cards (id) ON DELETE CASCADE,
    key text NOT NULL,
    effective_from date NOT NULL,
    value text NOT NULL,
    answered_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_card_id, key, effective_from)
);
