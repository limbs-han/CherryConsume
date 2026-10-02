-- 슬라이스 6. 엑셀 가져오기. 표 모양은 docs/erd.md, 작업 005 설계 5f절
-- 한 번 돌린 파일은 고치지 않는다. 바꿀 것은 새 번호로 더한다

-- 엑셀에 날짜만 있으면 그날 12시로 두고 시각을 모른다고 적는다. 시각 조건이 모름이 된다. E57
ALTER TABLE transactions ADD COLUMN time_known boolean NOT NULL DEFAULT true;

-- 가져오기 한 번이 한 행이다. 묶음 단위로 되돌린다. E34
-- 파일 이름은 남기지 않는다. 이름과 카드번호 끝자리가 들어 있을 수 있다
CREATE TABLE import_batches (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- 카드사 코드나 toss, banksalad. 카드사별 매핑 표가 생기기 전에는 비어 있다
    source text,
    -- 앱이 보낸 행 수다. 겹쳐 버린 행은 앱이 보내지 않는다
    row_count int NOT NULL CHECK (row_count >= 0),
    imported_count int NOT NULL CHECK (imported_count >= 0),
    duplicate_count int NOT NULL CHECK (duplicate_count >= 0),
    cancel_count int NOT NULL CHECK (cancel_count >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    undone_at timestamptz
);

ALTER TABLE transactions
    ADD CONSTRAINT transactions_import_batch_id_fkey FOREIGN KEY (import_batch_id) REFERENCES import_batches (id);
CREATE INDEX transactions_import_batch ON transactions (import_batch_id) WHERE import_batch_id IS NOT NULL;

-- 같은 카드의 같은 승인번호는 한 번만 들어간다. 지운 결제는 다시 넣을 수 있다. E31, ERD 메모
CREATE UNIQUE INDEX transactions_card_approval ON transactions (user_card_id, approval_no)
    WHERE approval_no IS NOT NULL AND deleted_at IS NULL;

-- 가져오기가 붙인 취소 한 줄마다 한 행이다. 같은 파일을 다시 올렸을 때 겹친 취소를 알아보고, 되돌릴 때 이 묶음의
-- 취소만 뺀다. 결제의 cancelled_amount는 이 행들과 앱에서 적은 취소의 합이다. E32, E34
CREATE TABLE import_cancels (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    import_batch_id bigint NOT NULL REFERENCES import_batches (id) ON DELETE CASCADE,
    transaction_id uuid NOT NULL REFERENCES transactions (id) ON DELETE CASCADE,
    amount int NOT NULL CHECK (amount > 0),
    cancelled_at timestamptz NOT NULL
);
CREATE INDEX import_cancels_transaction ON import_cancels (transaction_id);

-- 사용자가 짝지은 열. 머리 줄 모양의 해시마다 하나다. 열 이름 대신 열 번호만 남긴다. E30
CREATE TABLE import_mappings (
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    signature text NOT NULL,
    mapping jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, signature)
);
