# Étape 3 du TP — image planning (Python FastAPI).
# Base Alpine : fastapi + uvicorn (sans [standard]) sont du pur Python, et
# pydantic-core dispose de wheels musllinux → aucune compilation, image légère.
# Multi-stage : le venv est construit dans `build` puis copié tel quel dans
# `runtime`. Un pip install global polluerait l'image de tout l'outillage pip.

# ---- Stage 1 : build / install des dépendances ----
FROM python:3.12.7-alpine AS build

WORKDIR /app

COPY requirements.txt ./
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt \
    && /opt/venv/bin/pip uninstall -y pip setuptools 2>/dev/null || true \
    && find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf {} +

COPY app/ ./app/

# ---- Stage 2 : runtime ----
FROM python:3.12.7-alpine AS runtime

LABEL org.opencontainers.image.source="https://github.com/evanlefevre/devhub-campus"

WORKDIR /app

COPY --from=build /opt/venv /opt/venv
COPY --from=build /app/app ./app

# UID 1001 aligné avec le securityContext.runAsUser du chart Helm.
RUN addgroup -g 1001 app && adduser -D -u 1001 -G app app
USER 1001

ENV PORT=8080 \
    LOG_LEVEL=info \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
