# Étape 3 du TP — image planning (Python FastAPI).
# Multi-stage : le venv est construit dans `build` puis copié tel quel dans
# `runtime`. Un pip install global polluerait l'image de tout l'outillage
# pip/setuptools et rendrait la copie sélective impossible.

# ---- Stage 1 : build / install des dépendances ----
FROM python:3.12.7-slim AS build

WORKDIR /app

COPY requirements.txt ./
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# ---- Stage 2 : runtime ----
FROM python:3.12.7-slim AS runtime

LABEL org.opencontainers.image.source="https://github.com/evanlefevre/devhub-campus"

WORKDIR /app

COPY --from=build /opt/venv /opt/venv
COPY --from=build /app/app ./app

# UID 1001 aligné avec le securityContext.runAsUser du chart Helm.
RUN groupadd -g 1001 app && useradd -u 1001 -g app -M app
USER 1001

ENV PORT=8080 \
    LOG_LEVEL=info \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
