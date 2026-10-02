# 서버 이미지. 저장소 맨 위에서 만든다. 서버 코드, 엔진, 카탈로그만 넣는다. 작업 005 설계 5h
# Cloud Build가 Docker Hub 받기 횟수 제한에 걸리지 않게 Google의 사본에서 받는다
FROM mirror.gcr.io/library/python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /bin/uv
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 UV_COMPILE_BYTECODE=1 PATH=/app/backend/.venv/bin:$PATH
WORKDIR /app/backend
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-default-groups --group api --no-install-project
COPY backend/cherry_core cherry_core
COPY backend/cherry_api cherry_api
# 서버는 cherry_api의 두 단계 위에서 catalog/를 찾는다
COPY catalog /app/catalog
USER nobody
# Cloud Run이 PORT를 준다. 요청 주소는 Cloud Run이 이미 남겨 uvicorn은 다시 남기지 않는다
CMD exec uvicorn cherry_api.main:create_app --factory --host 0.0.0.0 --port ${PORT:-8080} --no-access-log
