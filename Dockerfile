FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app/src \
    NEKOSAMA_DATA_DIR=/app/data

WORKDIR /app

RUN pip install --no-cache-dir "discord.py>=2.4" "openai>=1.91"

COPY src ./src

CMD ["python", "-m", "nekosama"]
