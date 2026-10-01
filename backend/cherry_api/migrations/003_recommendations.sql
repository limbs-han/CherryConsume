-- 슬라이스 3. 추천. 표 모양은 docs/erd.md, 작업 005 설계 5c절
-- 추천을 따랐는지는 결제의 recommendation_request_id로 본다. 설계 문서 4.1
-- 한 번 돌린 파일은 고치지 않는다. 바꿀 것은 새 번호로 더한다

CREATE TABLE recommendation_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    merchant_name text,
    merchant_key text REFERENCES merchants (key),
    category_code text REFERENCES categories (code),
    -- 비우면 1만 원 기준으로 계산했다. E11
    amount int CHECK (amount > 0),
    channel text CHECK (channel IN ('online', 'offline')),
    region text CHECK (region IN ('domestic', 'overseas')),
    payment_method text REFERENCES payment_methods (key),
    requested_at timestamptz NOT NULL
);
CREATE INDEX recommendation_requests_user ON recommendation_requests (user_id, requested_at);
-- 결제가 같은 사용자의 요청만 가리키게 한다
ALTER TABLE recommendation_requests ADD UNIQUE (id, user_id);

CREATE TABLE recommendation_results (
    request_id uuid NOT NULL REFERENCES recommendation_requests (id) ON DELETE CASCADE,
    rank int NOT NULL CHECK (rank >= 1),
    user_card_id uuid NOT NULL REFERENCES user_cards (id) ON DELETE CASCADE,
    expected_benefit int NOT NULL CHECK (expected_benefit >= 0),
    applied jsonb NOT NULL DEFAULT '[]',
    conditional jsonb NOT NULL DEFAULT '[]',
    warnings text[] NOT NULL DEFAULT '{}',
    PRIMARY KEY (request_id, rank)
);

ALTER TABLE transactions
    ADD FOREIGN KEY (recommendation_request_id, user_id) REFERENCES recommendation_requests (id, user_id);

-- 최근 간 가게는 사용자의 결제를 최근 순으로 읽는다
CREATE INDEX transactions_user_time ON transactions (user_id, paid_at);
