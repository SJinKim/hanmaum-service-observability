# hanmaum-observability

Shared, self-hosted observability platform for Hanmaum services.

## Stack

- Grafana for dashboards and exploration
- Prometheus for metrics
- Loki for logs
- Grafana Alloy for Docker log collection
- node_exporter and cAdvisor for host/container metrics
- Docker Compose on the shared Hetzner host

## Rules

1. This repository owns shared observability infrastructure. Application
   repositories own only their integration labels, private metrics endpoints,
   and network attachment.
2. Never commit `.env`, credentials, webhook URLs, SMTP passwords, or tokens.
3. Pin every container image to an explicit version; no `latest` tags.
4. Do not publish Grafana, Prometheus, Loki, Alloy, exporter, or cAdvisor ports
   directly. Grafana is reachable only through the shared Caddy network.
5. Keep Loki labels low-cardinality. Never use user IDs, request IDs, IP
   addresses, email addresses, tokens, or session IDs as labels.
6. New services must provide an environment label and a stable service name.
7. Dashboards and data sources are file-provisioned and version-controlled.
8. Validate Compose, Prometheus, Loki, Alloy, dashboard JSON, and workflows
   before finishing a change.
9. Keep the single-node deployment simple until scale proves it insufficient.
10. Logs may contain operationally sensitive data. Retention and redaction
    changes require a security review.

## Layout

- `docker-compose.yml` — shared runtime
- `prometheus/` — scrape configuration and service target files
- `loki/` — log storage configuration
- `alloy/` — Docker discovery, labels, redaction, and Loki delivery
- `grafana/provisioning/` — data sources and dashboard providers
- `grafana/dashboards/` — platform and service dashboards
- `caddy/` — rendered Grafana route imported by the shared host proxy

## Service onboarding

1. Join the external Docker network `observability` when metrics are scraped.
2. Opt logs in with `observability.logs.enabled=true`.
3. Set `observability.service` and `observability.environment` labels.
4. Add a target under `prometheus/targets/` when the service exposes metrics.
5. Add/update dashboards and verify queries against real metric names.
