
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt \
    && groupadd --system app \
    && useradd --system --gid app --home-dir /app app

COPY app ./app
COPY migrations ./migrations
COPY schema.sql .
COPY bootstrap_owner.py .

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import os,urllib.request; p=os.environ.get('PORT','8000'); urllib.request.urlopen('http://127.0.0.1:'+p+'/health/ready',timeout=3)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
