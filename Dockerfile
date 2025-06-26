FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml /app/pyproject.toml
COPY uv.lock /app/uv.lock
RUN pip install --no-cache-dir uv && \
    uv sync

COPY src /app/src

CMD ["/app/.venv/bin/python", "src/main.py"]
