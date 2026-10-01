-- 슬라이스 1. 카드 등록과 홈. 표 모양은 docs/erd.md, 작업 005 설계 2절
-- 한 번 돌린 파일은 고치지 않는다. 바꿀 것은 새 번호로 더한다

CREATE TABLE issuers (
    code text PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE cards (
    id text PRIMARY KEY,
    issuer_code text NOT NULL REFERENCES issuers (code),
    name text NOT NULL,
    search_names text[] NOT NULL DEFAULT '{}',
    kind text NOT NULL CHECK (kind IN ('credit', 'check')),
    product_codes text[] NOT NULL DEFAULT '{}',
    status text NOT NULL CHECK (status IN ('on_sale', 'discontinued', 'closed')),
    status_since date,
    annual_fees jsonb NOT NULL DEFAULT '[]',
    sources jsonb NOT NULL DEFAULT '[]',
    checked_at date NOT NULL
);

CREATE TABLE card_revisions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    card_id text NOT NULL REFERENCES cards (id),
    effective_from date NOT NULL,
    effective_from_estimated boolean NOT NULL DEFAULT false,
    rules jsonb NOT NULL,
    rules_sha256 text NOT NULL,
    schema_version int NOT NULL,
    published_at timestamptz NOT NULL DEFAULT now(),
    -- 같은 날의 개정이 고쳐지면 새 행을 더한다. 결제가 가리키는 행은 그때 계산에 쓴 규칙 그대로 남는다. E18
    UNIQUE (card_id, effective_from, rules_sha256)
);

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

-- dev는 개발용 로그인이다. 개발용 로그인을 켠 서버에서만 생긴다. 작업 005 설계 3절
CREATE TABLE auth_identities (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    provider text NOT NULL CHECK (provider IN ('kakao', 'google', 'dev')),
    provider_uid text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_uid)
);

-- 토큰 원문은 두지 않고 SHA-256만 둔다
CREATE TABLE sessions (
    token_sha256 text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL
);
CREATE INDEX sessions_user ON sessions (user_id);

CREATE TABLE user_cards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    card_id text NOT NULL REFERENCES cards (id),
    nickname text,
    assumed_prev_month_spend int CHECK (assumed_prev_month_spend >= 0),
    started_on date,
    last_payment_method text,
    added_at timestamptz NOT NULL DEFAULT now(),
    removed_at timestamptz
);
-- 같은 사람이 같은 카드를 두 장 가지지 않는다. 가족카드도 한 장이다. E21
CREATE UNIQUE INDEX user_cards_one_active ON user_cards (user_id, card_id) WHERE removed_at IS NULL;
