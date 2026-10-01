-- 슬라이스 2. 결제 기록. 표 모양은 docs/erd.md, 작업 005 설계 5b절
-- 한 번 돌린 파일은 고치지 않는다. 바꿀 것은 새 번호로 더한다

-- 업종 code는 자식이면 "restaurant.general"처럼 부모 code를 붙인 값이다
CREATE TABLE categories (
    code text PRIMARY KEY,
    name_ko text NOT NULL,
    kakao_group_code text,
    parent_code text REFERENCES categories (code)
);

CREATE TABLE merchants (
    key text PRIMARY KEY,
    name text NOT NULL,
    category_code text NOT NULL REFERENCES categories (code),
    billing text NOT NULL
);

-- 별칭은 띄어쓰기를 빼고 소문자로 바꾼 값이다. 카탈로그 검사와 같다
CREATE TABLE merchant_aliases (
    alias text PRIMARY KEY,
    merchant_key text NOT NULL REFERENCES merchants (key)
);

CREATE TABLE payment_methods (
    key text PRIMARY KEY,
    name text NOT NULL,
    statement_names text[] NOT NULL DEFAULT '{}'
);

ALTER TABLE user_cards ADD FOREIGN KEY (last_payment_method) REFERENCES payment_methods (key);
-- 결제의 user_id가 그 보유 카드의 주인과 같게 DB가 막는다
ALTER TABLE user_cards ADD UNIQUE (id, user_id);

-- import_batch_id와 recommendation_request_id의 외래 키는 그 표가 생기는 슬라이스에서 건다
CREATE TABLE transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    user_card_id uuid NOT NULL REFERENCES user_cards (id) ON DELETE CASCADE,
    amount int NOT NULL CHECK (amount > 0),
    merchant_name text,
    merchant_key text REFERENCES merchants (key),
    category_code text REFERENCES categories (code),
    paid_at timestamptz NOT NULL,
    installment_months int NOT NULL DEFAULT 1 CHECK (installment_months >= 1),
    interest_free_installment boolean NOT NULL DEFAULT false,
    cancelled_amount int NOT NULL DEFAULT 0 CHECK (cancelled_amount >= 0 AND cancelled_amount <= amount),
    cancelled_at timestamptz,
    channel text NOT NULL DEFAULT 'offline' CHECK (channel IN ('online', 'offline')),
    region text NOT NULL DEFAULT 'domestic' CHECK (region IN ('domestic', 'overseas')),
    payment_method text REFERENCES payment_methods (key),
    billing text,
    card_revision_id bigint REFERENCES card_revisions (id),
    approval_no text,
    import_batch_id bigint,
    source text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'excel', 'notification')),
    recommendation_request_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CHECK (cancelled_amount = 0 OR cancelled_at IS NOT NULL),
    FOREIGN KEY (user_card_id, user_id) REFERENCES user_cards (id, user_id) ON DELETE CASCADE
);
-- 실적과 한도는 카드마다 결제 시각 순서로 읽는다. ERD 설계 메모의 핵심 인덱스
CREATE INDEX transactions_card_time ON transactions (user_card_id, paid_at);

-- 저장한 혜택은 다시 계산하지 않는다. E18. 예외는 E5, E48, E51, E52, E53
CREATE TABLE transaction_benefits (
    transaction_id uuid NOT NULL REFERENCES transactions (id) ON DELETE CASCADE,
    benefit_key text NOT NULL,
    amount int NOT NULL CHECK (amount >= 0),
    value int NOT NULL CHECK (value >= 0),
    base_amount int NOT NULL CHECK (base_amount >= 0),
    PRIMARY KEY (transaction_id, benefit_key)
);
