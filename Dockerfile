# syntax=docker/dockerfile:1

# =============================================================
# Étape 1 : installation des dépendances dans un virtualenv
# =============================================================
FROM python:3.12.16-slim-trixie AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
# --no-compile : pas de .pyc dans l'image ; pip est retiré du venv,
# il ne sert pas à l'exécution
RUN pip install --no-compile -r requirements.txt \
    && pip uninstall -y pip \
    && find /opt/venv -depth -type d -name "__pycache__" -exec rm -rf {} +

# =============================================================
# Étape 2 : image finale, uniquement le nécessaire à l'exécution
# =============================================================
FROM python:3.12.16-slim-trixie AS runtime

# Commit Git inscrit dans l'image, renvoyé par la route /version
# Build : docker build --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) .
ARG GIT_COMMIT=unknown
ARG APP_VERSION=1.4.0

LABEL org.opencontainers.image.title="fretly-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    GIT_COMMIT=${GIT_COMMIT} \
    APP_VERSION=${APP_VERSION} \
    APP_ENV=production

# Utilisateur non root dédié
RUN groupadd --system --gid 10001 fretly \
    && useradd --system --uid 10001 --gid fretly --no-create-home --shell /usr/sbin/nologin fretly

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
# Le code appartient à root (lecture seule pour l'application) ;
# seul le dossier /app est inscriptible (fichier SQLite si pas de DATABASE_URL)
COPY app/ ./app/
RUN chown fretly:fretly /app

USER fretly

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
