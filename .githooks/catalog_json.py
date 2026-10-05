"""폰이 받는 app/assets/catalog/의 목록 파일과 카드별 규칙 파일이 catalog/로 다시 만든 것과 같은지 본다. 커밋 훅과
푸시 훅이 쓴다.

앱은 규칙을 다시 검사하지 않는다. 손으로 합친 파일이나 git이 글자 단위로 합친 파일이 master에 오르면 그대로 모든 폰에
간다. 작업 006 설계 2절, 2026-10-02 단계 3 위험 검토. 작업 014 설계 5절부터 폴더다
"""

import io
import os
import subprocess
import tempfile
import zipfile

# 생성기는 이 훅이 든 저장소의 backend다. 임시 저장소로 훅을 시험할 때도 같은 생성기를 쓴다
COMMAND = [
    "uv",
    "run",
    "--project",
    os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"
    ),
    "python",
    "-m",
    "cherry_core.catalog",
    "json",
]
FIX = "uv run --project backend python -m cherry_core.catalog json 으로 만들어 함께 커밋한다"
APP = "app/assets/catalog"


def run(args: list[str], root: str, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=root, capture_output=True, check=False, **kw)


def files_in(top: str) -> dict[str, bytes]:
    """폴더 아래 파일의 상대 경로와 바이트"""
    out = {}
    for d, _, names in os.walk(top):
        for n in names:
            path = os.path.join(d, n)
            with open(path, "rb") as f:
                out[os.path.relpath(path, top).replace(os.sep, "/")] = f.read()
    return out


def errors(root: str, rev: str | None = None) -> list[str]:
    """rev가 없으면 stage한 것을, 있으면 그 커밋을 본다. 같으면 빈 목록이다"""
    where = "stage한 것" if rev is None else f"커밋 {rev[:10]}"
    with tempfile.TemporaryDirectory() as d:
        if rev is None:
            # 파일 목록은 0바이트로 나눠 넘긴다. Windows에서 글자로 넘기면 줄 끝이 바뀌어 파일을 못 꺼낸다
            names = run(["git", "ls-files", "-z", "catalog", APP], root).stdout
            got = run(
                ["git", "checkout-index", "-z", "--stdin", f"--prefix={d}/"],
                root,
                input=names,
            )
        else:
            got = run(["git", "archive", "--format=zip", rev, "catalog", APP], root)
            if got.returncode == 0:
                zipfile.ZipFile(io.BytesIO(got.stdout)).extractall(d)
        if got.returncode != 0:
            detail = got.stderr.decode(errors="replace").strip()
            return [
                f"{where}의 catalog/나 {APP}/를 꺼내지 못했다. {APP}/를 함께 커밋했는지 본다: {detail}"
            ]
        out = os.path.join(d, "made")
        r = run([*COMMAND, "--root", os.path.join(d, "catalog"), "--split", out], root)
        if r.returncode != 0:
            detail = (
                (r.stdout + r.stderr)
                .decode(errors="replace")
                .strip()
                .replace("\n", "\n  ")
            )
            return [f"{where}의 catalog/로 앱 JSON을 만들지 못했다\n  {detail}"]
        if files_in(out) != files_in(os.path.join(d, APP)):
            return [f"{where}의 {APP}/가 catalog/로 다시 만든 것과 다르다. {FIX}"]
    return []
