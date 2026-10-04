"""검수 앱 cherry_review. 작업 003 과제 20, 설계 4절 5번.

표는 읽기만 한다. 승인은 고친 카드 파일을 incoming 볼륨에 올리고 작업 cherry_approve를 draft_id와 함께 돌린다.
반려도 같은 작업이 decision reject로 적는다. 검사는 그 작업이 한다. 오류가 있으면 아무것도 쓰지 않고 실패로 끝난다.
앱의 기본 Python은 3.11이라 3.12 이상인 cherry_core를 깔지 않는다. 미리 깔린 streamlit, databricks-sdk,
databricks-sql-connector만 쓴다. 켜져 있는 동안 요금이 나와 검수가 끝나면 끈다. docs/databricks.md "검수 앱"
"""

import difflib
import io
import os
import re
import time
from datetime import UTC, datetime

import streamlit as st
from databricks import sql
from databricks.sdk import WorkspaceClient
from databricks.sdk.core import Config

SILVER, GOLD = os.environ["CHERRY_SILVER"], os.environ["CHERRY_GOLD"]
JOB_ID = int(os.environ["APPROVE_JOB_ID"])
DONE = {"TERMINATED", "SKIPPED", "INTERNAL_ERROR"}
cfg = Config()
w = WorkspaceClient()


@st.cache_resource
def connection():
    return sql.connect(
        server_hostname=cfg.host,
        http_path=f"/sql/1.0/warehouses/{os.environ['DATABRICKS_WAREHOUSE_ID']}",
        credentials_provider=lambda: cfg.authenticate,
    )


def query(text: str, **params) -> list[dict]:
    with connection().cursor() as cur:
        cur.execute(text, params)
        return [r.asDict() for r in cur.fetchall()]


def listed(value) -> list:
    """배열 칸. SQL 연결 라이브러리는 배열을 numpy 배열로 줄 수 있어 `or []`를 쓰지 않는다. 2026-10-02 위험 검토"""
    return [] if value is None else list(value)


def run_approve(params: dict) -> None:
    """cherry_approve를 돌리고 끝날 때까지 기다려 출력을 보인다. 작업은 한 번에 하나만 돈다."""
    run_id = w.jobs.run_now(job_id=JOB_ID, job_parameters=params).response.run_id
    with st.spinner("cherry_approve를 돌리는 중이다. 몇 분 걸린다"):
        for _ in range(240):
            run = w.jobs.get_run(run_id)
            if run.state.life_cycle_state.value in DONE:
                break
            time.sleep(5)
    result = (
        run.state.result_state.value
        if run.state.result_state
        else run.state.life_cycle_state.value
    )
    out = w.jobs.get_run_output(run.tasks[0].run_id)
    (st.success if result == "SUCCESS" else st.error)(
        f"cherry_approve {result}. 실행 {run.run_page_url}"
    )
    st.code(out.logs or out.error or "출력 없음")


st.set_page_config(page_title="체리컨슘 검수", layout="wide")
st.title("검수 대기")
reviewer = st.context.headers.get("X-Forwarded-Email", "")
if not reviewer:
    st.error("로그인한 사람의 메일을 받지 못했다. 승인과 반려를 할 수 없다")

items = query(
    f"SELECT kind, issuer, card_id, subject, source_path, created_at, draft_id FROM cherry.{SILVER}.queue "
    "WHERE status = 'open' ORDER BY created_at"
)
if not items:
    st.info("열린 검수 대기 건이 없다")
    st.stop()
pick = st.selectbox(
    f"열린 건 {len(items)}개",
    range(len(items)),
    format_func=lambda i: (
        f"{items[i]['created_at']:%m-%d %H:%M} {items[i]['kind']} "
        f"{items[i]['card_id'] or items[i]['issuer']} {items[i]['subject']}"
    ),
)
item = items[pick]
if not item["draft_id"]:
    # 새 카드와 사라진 카드는 보여 주기만 한다. 새 카드는 card-researcher로 조사해 손 승인으로 넣는다. 설계 4절 5번
    st.write(f"{item['issuer']} 상품 목록에서 찾았다: {item['subject']}")
    st.caption(
        f"원문 {item['source_path']}. 새 카드는 카드 조사 에이전트로 조사해 손 승인으로 넣는다"
    )
    st.stop()

draft = query(
    f"SELECT * FROM cherry.{SILVER}.drafts WHERE draft_id = :id", id=item["draft_id"]
)[0]
new_card = draft["mode"] == "new_card"
if new_card:
    # 카탈로그에 없는 카드의 새 초안이라 골드에 파일이 없다. 승인할 때 카드 파일의 id로 경로를 정한다. 작업 008 11단계
    path, now = None, ""
else:
    gold = query(
        # LIKE의 밑줄은 한 글자 와일드카드라 파일 이름은 정확히 맞춘다
        f"SELECT path, yaml FROM cherry.{GOLD}.catalog_files "
        "WHERE path LIKE 'cards/%' AND substring_index(path, '/', -1) = :name",
        name=f"{draft['card_id']}.yaml",
    )
    if len(gold) != 1:
        st.error(f"골드에서 카드 파일 {draft['card_id']}을 하나로 찾지 못했다")
        st.stop()
    path, now = gold[0]["path"], gold[0]["yaml"]

st.subheader(f"{draft['card_id']} {draft['status']}")
st.caption(
    f"초안 {draft['draft_id']}, 모델 {draft['model']}, 프롬프트 판 {draft['prompt_version']}"
)
if new_card:
    st.info(
        f"새 카드 초안이다. 승인하면 cards/{draft['issuer']}/<id>.yaml로 들어간다. "
        "id를 바꾸면 그 이름으로 들어가고 색인도 따라 바뀐다. 확인 필요 항목을 원문과 맞춰 보고 연회비와 짧은 이름을 채운다"
    )
    if not draft["draft_yaml"]:
        st.warning("초안이 없다. 카드 파일을 직접 쓰거나 반려한다")
if draft["reason"]:
    st.warning(draft["reason"])
if draft.get("retry_reason"):
    st.caption(f"형식 오류로 한 번 더 물었다. 처음 까닭: {draft['retry_reason']}")
for problem in listed(draft["problems"]):
    (st.error if problem.startswith("error") else st.warning)(problem)

# 목록 매개변수는 SQL 연결 라이브러리 판에 따라 받지 못해 경로마다 이름 붙인 매개변수로 넘긴다
paths = {f"p{i}": p for i, p in enumerate(listed(draft["change_paths"]))}
changes = (
    query(
        f"SELECT source_id, removed, added FROM cherry.{SILVER}.changes "
        f"WHERE new_path IN ({', '.join(':' + k for k in paths)})",
        **paths,
    )
    if paths
    else []
)
for c in changes:
    lines = [f"- {x}" for x in listed(c["removed"])] + [
        f"+ {x}" for x in listed(c["added"])
    ]
    st.markdown(f"**바뀐 원문 줄 {c['source_id']}**")
    st.code("\n".join(lines) or "바뀐 줄 없음", language="diff")

text = (
    draft["draft_yaml"] or now
)  # 사람이 정할 것은 초안이 없어 지금 골드 파일을 고친다
st.markdown("**지금 골드 파일과 초안의 차이**")
diff = difflib.unified_diff(
    now.splitlines(), text.splitlines(), "지금 골드", "초안", lineterm=""
)
st.code("\n".join(diff) or "차이 없음", language="diff")
edited = st.text_area(
    "승인할 카드 파일. 고쳐서 승인할 수 있다",
    value=text,
    height=480,
    key=item["draft_id"],
)
note = st.text_input("근거와 까닭")

left, right = st.columns(2)
if left.button("승인", type="primary", disabled=not reviewer):
    if new_card:
        # 앱은 cherry_core와 YAML 읽기를 깔지 않아 저장 형식 카드 파일의 맨 위 id 줄로 경로를 정한다
        found = re.search(
            r"^id: ([a-z0-9-]+)$", edited.replace("\r\n", "\n"), re.MULTILINE
        )
        if not found:
            st.error("카드 파일에서 id 줄을 찾지 못했다")
            st.stop()
        path = f"cards/{draft['issuer']}/{found.group(1)}.yaml"
    name = f"app-{datetime.now(UTC):%Y%m%dT%H%M%S}-{draft['draft_id'][:8]}"
    w.files.upload(
        f"/Volumes/cherry/{GOLD}/incoming/{name}/catalog/{path}",
        io.BytesIO(edited.replace("\r\n", "\n").encode("utf-8")),
        overwrite=False,
    )
    run_approve(
        {
            "incoming": name,
            "draft_id": draft["draft_id"],
            "decision": "approve",
            "reviewer": reviewer,
            "note": note,
        }
    )
if right.button("반려", disabled=not reviewer):
    run_approve(
        {
            "draft_id": draft["draft_id"],
            "decision": "reject",
            "reviewer": reviewer,
            "note": note,
        }
    )
