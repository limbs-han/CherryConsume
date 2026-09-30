"""Claude가 끝내기 전에 이번 차례의 답에 영어 문장이 섞였는지 본다. 섞였으면 exit 2로 한국어로 다시 쓰게 한다.

2026-09-30 사용자가 걸었다. 답을 영어로 쓰는 실수가 열 번 가까이 되풀이됐기 때문이다.
코드 블록, 인라인 코드, 주소는 빼고 본다. 한글이 한 글자도 없고 영어 낱말이 4개 이상인 줄을 영어 문장으로 본다.
화면의 영어 메뉴 이름이 섞인 한국어 문장은 한글이 있어 걸리지 않는다.
같은 줄로 두 번 막지 않는다. 막은 줄은 임시 파일에 적어 두고, 그 줄만 남았으면 통과시킨다.
"""

import hashlib
import json
import os
import re
import sys
import tempfile

sys.stderr.reconfigure(encoding="utf-8")

HANGUL = re.compile(r"[가-힣]")
WORD = re.compile(r"[A-Za-z]{2,}")
FENCE = re.compile(r"```.*?```", re.DOTALL)
INLINE = re.compile(r"`[^`\n]*`")
URL = re.compile(r"https?://\S+|\]\([^)]*\)")
MIN_WORDS = 4


def turn_texts(transcript: str) -> list[str]:
    """마지막 사용자 글 뒤로 Claude가 쓴 글. 도구 결과는 사용자 글로 치지 않는다."""
    texts: list[str] = []
    with open(transcript, encoding="utf-8") as f:
        for raw in f:
            try:
                entry = json.loads(raw)
            except json.JSONDecodeError:
                continue
            message = entry.get("message") or {}
            content = message.get("content")
            if entry.get("type") == "user":
                is_text = isinstance(content, str) or any(
                    isinstance(b, dict) and b.get("type") == "text"
                    for b in content or []
                )
                if is_text:
                    texts = []
            elif entry.get("type") == "assistant" and isinstance(content, list):
                texts += [
                    b.get("text", "")
                    for b in content
                    if isinstance(b, dict) and b.get("type") == "text"
                ]
    return texts


def english_lines(text: str) -> list[str]:
    text = URL.sub(" ", INLINE.sub(" ", FENCE.sub(" ", text)))
    return [
        line.strip()
        for line in text.splitlines()
        if not HANGUL.search(line) and len(WORD.findall(line)) >= MIN_WORDS
    ]


def main() -> int:
    data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
    transcript = data.get("transcript_path")
    if not transcript or not os.path.exists(transcript):
        return 0
    lines = [line for text in turn_texts(transcript) for line in english_lines(text)]
    if not lines:
        return 0
    state = os.path.join(
        tempfile.gettempdir(), f"korean_only_{data.get('session_id', 'x')}.txt"
    )
    digest = hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()
    try:
        with open(state, encoding="utf-8") as f:
            if f.read().strip() == digest:
                return 0  # 이미 한 번 막은 줄이다. 되풀이해 막지 않는다
    except OSError:
        pass
    with open(state, "w", encoding="utf-8") as f:
        f.write(digest)
    shown = "\n".join(f"- {line[:120]}" for line in lines[:5])
    print(
        "답에 영어 문장이 섞여 있어 끝낼 수 없다. 사용자는 한국어로만 읽는다.\n"
        "사과 한 줄 뒤, 같은 내용을 한국어로 다시 써서 보내라. 명령, 코드, 파일 이름, 화면의 영어 메뉴 이름만 그대로 둔다.\n"
        f"영어로 쓴 줄:\n{shown}",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
