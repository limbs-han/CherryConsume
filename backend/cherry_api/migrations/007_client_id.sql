-- 앱이 결제마다 만든 번호. 저장은 됐는데 답이 끊겨 다시 보낸 결제가 두 건이 되지 않게 한다. E24. 작업 005 설계 5i
ALTER TABLE transactions ADD COLUMN client_id uuid;
CREATE UNIQUE INDEX transactions_client ON transactions (user_id, client_id) WHERE client_id IS NOT NULL;
