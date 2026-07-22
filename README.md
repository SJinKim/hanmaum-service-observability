# Hanmaum Observability

Shared observability platform for the Hetzner host and future Hanmaum services.
The DN server is the first connected application.

## Why Prometheus is included

Grafana visualizes data but does not collect or retain application metrics.

- **Prometheus** stores numeric time-series: CPU, RAM, disk, container usage,
  HTTP request rate, HTTP 5xx rate, JVM heap, database pools, and target health.
- **Loki** stores searchable log lines and exceptions.
- **Alloy** discovers opted-in Docker containers, redacts common sensitive
  values, and forwards their stdout/stderr to Loki.
- **Grafana** combines both data sources into dashboards.

## Architecture

```text
                                   +--> Prometheus --> Grafana
Spring / Keycloak metrics ---------+
node_exporter / cAdvisor metrics ---+

Opted-in Docker stdout --> Alloy --> Loki ---------> Grafana
                                                    |
                                             Caddy HTTPS
```

All components run once, independently of individual application deployments.
Future services join the same contracts instead of running another Grafana or
Prometheus instance.

## Included dashboards

- **Platform – Host & Containers**: Hetzner CPU/RAM/disk, Docker resources,
  and scrape health.
- **Platform – Logs & Errors**: log volume, warnings, exceptions, and filters
  by service/environment.
- **DN Server – Application Metrics**: availability, HTTP traffic/5xx,
  response time, JVM heap, HikariCP, and process CPU.
- **Hanmaum – Keycloak Auth Errors**: login/token failures and Keycloak server
  exceptions.

## Alerting

Grafana-managed alert rules are provisioned from version-controlled YAML files
under `grafana/provisioning/alerting/`. They use the existing Grafana contact
point named exactly **`Discord Hanmaum DEV`**. The Discord webhook remains in
Grafana's persistent database and is never stored in this repository.

Included rules:

- production or staging DN server unavailable for 2 minutes;
- DN server HTTP 5xx rate above 5% for 5 minutes, with at least 5 errors;
- more than 2 failed DN-server Keycloak Admin API calls in 5 minutes;
- any failed announcement notification fan-out;
- FCM failure rate above 20% for at least 10 messages in 10 minutes;
- any PII decryption failure;
- any failed scheduled cleanup job;
- Keycloak metrics endpoint unavailable for 2 minutes;
- more than 10 failed Keycloak login events in 5 minutes;
- node_exporter or cAdvisor scrape target unavailable;
- root disk usage above 85% (warning) or 95% (critical);
- host memory usage above 90% for 10 minutes;
- an expected application, database, proxy, or observability container missing
  from cAdvisor for 2 minutes.

Rules use pending periods and minimum event counts to reduce alert noise. They
route directly to the Discord contact point without replacing the notification
policy tree configured in Grafana. Provisioned rules are read-only in the UI;
change their YAML source and redeploy instead. A Grafana restart or provisioning
reload is required after changing alert files, which the Make target and deploy
workflow handle automatically.

Validate all alert files with the pinned Grafana version:

```bash
make validate-alerting
```

Self-hosted alerting cannot notify when the entire Hetzner host, its network, or
Grafana itself is unavailable. Keep a separate external uptime check for those
failure modes.

## One-time server setup

1. Create `grafana.<domain>` DNS pointing to the Hetzner server. Keep only
   ports 80/443 public; never expose 3000, 9090, 3100, 9100, or 12345.
2. Create the server-local directory and environment before deploying the
   Caddy mount, so Docker does not create the bind-mount directory as root:

   ```bash
   sudo mkdir -p /opt/hanmaum-service-observability
   sudo chown -R "$USER":"$USER" /opt/hanmaum-service-observability
   cd /opt/hanmaum-service-observability
   GRAFANA_PASSWORD="$(openssl rand -hex 32)"
   cat > .env <<EOF
   GRAFANA_DOMAIN=grafana.example.com
   GRAFANA_ADMIN_USER=admin
   GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
   EOF
   chmod 600 .env
   # Edit GRAFANA_DOMAIN and save GRAFANA_PASSWORD in a password manager.
   ```

3. Deploy the DN server's generic Caddy `conf.d` mount once. This repository
   owns and renders the Grafana route under `caddy/generated/`.
4. Start manually or configure the GitHub `production` environment and the
   `SERVER_HOST`, `SERVER_USER`, and `SSH_PRIVATE_KEY` secrets before running
   the manual deploy workflow:

   ```bash
   make config
   make up
   make ps
   ```

The local Grafana admin account remains available as break-glass access when
Keycloak itself is unavailable. The admin password environment variable only
initializes a new Grafana volume; rotate an existing account through Grafana's
admin CLI/UI.

## Connecting a service

### Logs

Add bounded Docker labels to the application container:

```yaml
labels:
  observability.logs.enabled: "true"
  observability.service: example-service
  observability.environment: production
logging:
  driver: local
  options:
    max-size: "20m"
    max-file: "3"
```

Do not emit PII, tokens, credentials, full JWTs, or session identifiers. Alloy
redaction is defense in depth, not permission to log sensitive data.

### Metrics

Join the external `observability` network and expose a private Prometheus-format
endpoint inside Docker. Do not publish the metrics port on the host.

```yaml
networks:
  - app-internal
  - observability

networks:
  observability:
    external: true
```

Add the target to the appropriate watched file under `prometheus/targets/`.
Prometheus applies valid target-file changes automatically; use
`make reload-prometheus` only after changing the main scrape configuration.

## DN server integration

The DN server repository provides only the application-side contract:

- Spring Boot Micrometer exposes `/actuator/prometheus` privately.
- Production and staging backends join `observability`.
- Keycloak exposes `/metrics` on its private management port `9000`.
- Backend, Keycloak, and Caddy logs use explicit service/environment labels.
- Caddy only provides a generic read-only `conf.d` mount; this repository owns
  the rendered Grafana route and reloads Caddy during deployment.
- Public Caddy continues to deny `/actuator/*` except health, so Prometheus
  metrics are not internet-accessible.

Targets are defined in:

- `prometheus/targets/spring/dn-server.json`
- `prometheus/targets/keycloak/dn-keycloak.json`

Failed-login panels depend on Keycloak's `jboss-logging` event listener. It is
already present in the DN realm exports; enable it explicitly for every future
realm (`Realm settings -> Events -> Event listeners`). Keycloak emits failed
authentication events at `WARN` by default, while Alloy removes common user,
session, email, and IP fields before Loki persists the log line.

## Security and retention

- Grafana is the only component on `caddy-proxy`; all other monitoring traffic
  uses internal/private Docker networks.
- Loki labels remain bounded. User IDs, IPs, request IDs, email addresses,
  tokens, and sessions are never indexed.
- Loki and Prometheus retain 30 days. Prometheus additionally caps its local
  TSDB at 8 GB.
- PostgreSQL logs are not collected by default because errors and statements
  can contain personal data.
- Alloy needs Docker API access to stream logs. It has no public port, runs with
  a read-only root filesystem, dropped capabilities, and `no-new-privileges`.
  A maintained Docker socket proxy allowing only container read/log endpoints
  is the next hardening step if the platform grows.
- cAdvisor requires privileged host access to inspect containers. It has no
  published port and is isolated on the internal monitoring network.

## Validation

Before deploying:

```bash
docker compose --env-file .env -f docker-compose.yml config -q
promtool check config prometheus/prometheus.yml
alloy fmt --test alloy/config.alloy
alloy validate alloy/config.alloy
loki -verify-config=true -config.file=loki/config.yml
```

Dashboard JSON and GitHub Actions workflows are also validated in review/CI.
