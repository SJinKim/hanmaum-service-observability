#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$ROOT/.github/workflows/deploy.yml"
MAKEFILE="$ROOT/Makefile"

grep -q 'docker network inspect caddy-proxy' "$DEPLOY"
grep -q 'graceops.edge.owner' "$DEPLOY"
grep -q 'docker network inspect caddy-proxy' "$MAKEFILE"

if grep -Eq 'source:.*caddy|caddy reload|docker network create caddy-proxy' "$DEPLOY"; then
  echo "Observability deployment must not mutate the shared edge." >&2
  exit 1
fi

if awk '/^up:/{capture=1; next} /^[[:alnum:]_-]+:/{capture=0} capture' "$MAKEFILE" \
  | grep -Eq 'render.*caddy|caddy reload|docker network create caddy-proxy'; then
  echo "make up must not mutate the shared edge." >&2
  exit 1
fi

echo "Shared edge ownership contract passed."
