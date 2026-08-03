# ==========================
# Build Stage
# ==========================
FROM python:3.11-slim AS builder

WORKDIR /app

# Instala as dependências necessárias para build
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Instala as dependências em um diretório separado
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==========================
# Runtime Stage
# ==========================
FROM python:3.11-slim

WORKDIR /app

# Copia as dependências já instaladas
COPY --from=builder /install /usr/local

# Copia o código da aplicação
COPY app.py .
COPY db ./db

EXPOSE 8003

CMD ["gunicorn", "--bind", "0.0.0.0:8003", "app:app"]