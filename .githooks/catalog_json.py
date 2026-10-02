"""폰이 받는 app/assets/catalog.json이 catalog/로 다시 만든 것과 같은지 본다. 커밋 훅과 푸시 훅이 쓴다.

앱은 규칙을 다시 검사하지 않는다. 손으로 합친 파일이나 git이 글자 단위로 합친 파일이 master에 오르면 그대로 모든 폰에
간다. 작업 006 설계 2절, 2026-10-02 단계 3 위험 검토
"""

import io
import os
import subprocess
import tempfile
import zipfile

COMMAND = [
    "uv",
    "run",
    "--project",
    "backend",
    "python",
    "-m",
    "cherry_core.catalog",
    "json",
]
FIX = "uv run --project backend python -m cherry_core.catalog json 으로 만들어 함께 커밋한다"


def run(args: list[str], root: str, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=root, capture_output=True, check=False, **kw)


def errors(root: str, rev: str | None = None) -> list[str]:
    """rev가 없으면 stage한 것을, 있으면 그 커밋을 본다. 같으면 빈 목록이다"""
    where = "stage한 것" if rev is None else f"커밋 {rev[:10]}"
    with tempfile.TemporaryDirectory() as d:
        if rev is None:
            # 파일 목록은 0바이트로 나눠 넘긴다. Windows에서 글자로 넘기면 줄 끝이 바뀌어 파일을 못 꺼낸다
            names = run(["git", "ls-files", "-z", "catalog"], root).stdout
            got = run(
                ["git", "checkout-index", "-z", "--stdin", f"--prefix={d}/"],
                root,
                input=names,
            )
            committed = ":app/assets/catalog.json"
        else:
            got = run(["git", "archive", "--format=zip", rev, "catalog"], root)
            if got.returncode == 0:
                zipfile.ZipFile(io.BytesIO(got.stdout)).extractall(d)
            committed = f"{rev}:app/assets/catalog.json"
        if got.returncode != 0:
            return [
                f"{where}의 catalog/를 꺼내지 못했다: {got.stderr.decode(errors='replace').strip()}"
            ]
        out = os.path.join(d, "catalog.json")
        r = run([*COMMAND, "--root", os.path.join(d, "catalog"), "--out", out], root)
        if r.returncode != 0:
            detail = (
                (r.stdout + r.stderr)
                .decode(errors="replace")
                .strip()
                .replace("\n", "\n  ")
            )
            return [f"{where}의 catalog/로 앱 JSON을 만들지 못했다\n  {detail}"]
        with open(out, "rb") as f:
            made = f.read()
        if made != run(["git", "show", committed], root).stdout:
            return [
                f"{where}의 app/assets/catalog.json이 catalog/로 다시 만든 것과 다르다. {FIX}"
            ]
    return []
