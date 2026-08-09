# Webhook server for TradingView → Binance Futures (Cloud Run ready)
FROM python:3.11-slim

WORKDIR /app

# libgomp1 is needed by lightgbm/xgboost
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt flask gunicorn

COPY . .

ENV PORT=8080
# Single worker keeps one consistent trading state; threads handle concurrent alerts.
CMD exec gunicorn --bind :$PORT --workers 1 --threads 4 --timeout 60 webhook_server:app
