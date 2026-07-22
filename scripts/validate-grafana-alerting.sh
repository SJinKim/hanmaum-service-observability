#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_NAME="hanmaum-grafana-alerting-validation"
TMP_DIR="$(mktemp -d)"
ADMIN_PASSWORD="ci-alerting-validation"

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
cp -R "${ROOT_DIR}/grafana/provisioning" "${TMP_DIR}/provisioning"

# Production keeps the Discord webhook in Grafana's persistent database. CI
# provides only a non-routable placeholder so Grafana can validate that every
# rule references the existing contact point by its exact name.
cat > "${TMP_DIR}/provisioning/alerting/00-ci-contact-point.yml" <<'YAML'
apiVersion: 1

contactPoints:
  - orgId: 1
    name: Discord Hanmaum DEV
    receivers:
      - uid: ci-discord-placeholder
        type: discord
        disableResolveMessage: false
        settings:
          url: https://discord.com/api/webhooks/ci-placeholder/ci-placeholder
YAML

docker run --detach --name "${CONTAINER_NAME}" \
  --env GF_SECURITY_ADMIN_USER=admin \
  --env "GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWORD}" \
  --volume "${TMP_DIR}/provisioning:/etc/grafana/provisioning:ro" \
  grafana/grafana:13.1.1 >/dev/null

for _ in $(seq 1 30); do
  if docker exec "${CONTAINER_NAME}" \
    wget -q -O /dev/null http://localhost:3000/api/health; then
    break
  fi
  sleep 2
done

if ! docker exec "${CONTAINER_NAME}" \
  wget -q -O /dev/null http://localhost:3000/api/health; then
  docker logs "${CONTAINER_NAME}"
  echo "Grafana did not become healthy during alert provisioning validation" >&2
  exit 1
fi

if docker logs "${CONTAINER_NAME}" 2>&1 \
  | grep -E 'logger=provisioning\.alerting.*level=error'; then
  echo "Grafana reported an alerting provisioning error" >&2
  exit 1
fi

AUTH_HEADER="$(printf 'admin:%s' "${ADMIN_PASSWORD}" | base64 | tr -d '\n')"
ALERT_RULES="$(docker exec "${CONTAINER_NAME}" wget -qO- \
  --header="Authorization: Basic ${AUTH_HEADER}" \
  http://localhost:3000/api/v1/provisioning/alert-rules)"

EXPECTED_RULE_UIDS=(
  critical-container-missing
  dn-server-high-5xx
  dn-server-unavailable
  host-disk-space-critical
  host-disk-space-warning
  host-memory-high
  keycloak-login-failure-spike
  keycloak-unavailable
  platform-scrape-target-down
)

for uid in "${EXPECTED_RULE_UIDS[@]}"; do
  if ! grep -Eq "\"uid\"[[:space:]]*:[[:space:]]*\"${uid}\"" \
    <<<"${ALERT_RULES}"; then
    echo "Provisioned alert rule is missing: ${uid}" >&2
    exit 1
  fi
done

echo "Validated ${#EXPECTED_RULE_UIDS[@]} provisioned Grafana alert rules"
