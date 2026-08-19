#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-$ROOT/.env.example}"

model=$(docker compose \
  --env-file "$ENV_FILE" \
  --project-name hanmaum-observability-validation \
  --file "$ROOT/docker-compose.yml" \
  config --format json)

jq -e '
  .services.alloy.user == "473:473" and
  .services.alloy.read_only == true and
  (.services.alloy.cap_drop | index("ALL") != null) and
  (.services.alloy.group_add | length == 1) and
  (.services.alloy.group_add[0] | test("^[0-9]+$")) and
  (.services.alloy.volumes | any(
    .target == "/var/lib/alloy/data" and .type == "volume"
  )) and
  (.services.alloy.volumes | any(
    .source == "/var/run/docker.sock" and
    .target == "/var/run/docker.sock" and
    .read_only == true
  ))
' >/dev/null <<<"$model"

echo "Alloy runtime permission contract passed."
