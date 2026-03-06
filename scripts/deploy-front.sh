#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.frontend.yml"

echo "==> Rebuilding and deploying frontend..."
docker compose -f "$COMPOSE_FILE" up --build -d

echo "==> Frontend is running at http://localhost:8080"
