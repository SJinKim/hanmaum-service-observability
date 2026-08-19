DC = docker compose --env-file .env --project-name hanmaum-observability -f docker-compose.yml
DOCKER_SOCKET_GID ?= $(shell stat -c '%g' /var/run/docker.sock 2>/dev/null || stat -f '%g' /var/run/docker.sock)
export DOCKER_SOCKET_GID

.PHONY: config render-legacy-caddy up down pull logs ps reload-prometheus validate-alerting validate-alloy

config:
	$(DC) config -q

# Rollback-only helper. graceops-edge owns the active Grafana route.
render-legacy-caddy:
	set -a; . ./.env; set +a; mkdir -p caddy/generated; sed "s|__GRAFANA_DOMAIN__|$${GRAFANA_DOMAIN}|g" caddy/grafana.caddy.template > caddy/generated/grafana.caddy

up:
	docker network inspect observability >/dev/null 2>&1 || docker network create observability
	docker network inspect caddy-proxy >/dev/null
	docker inspect --format='{{.State.Running}}' hanmaum-caddy | grep -q true
	$(DC) up -d
	$(DC) restart grafana

down:
	$(DC) down

pull:
	$(DC) pull

logs:
	$(DC) logs -f

ps:
	$(DC) ps

reload-prometheus:
	docker kill --signal=SIGHUP hanmaum-prometheus

validate-alerting:
	./scripts/validate-grafana-alerting.sh

validate-alloy:
	./scripts/validate-alloy-runtime.sh
