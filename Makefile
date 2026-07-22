DC = docker compose --env-file .env --project-name hanmaum-observability -f docker-compose.yml

.PHONY: config render-caddy up down pull logs ps reload-prometheus

config:
	$(DC) config -q

render-caddy:
	set -a; . ./.env; set +a; mkdir -p caddy/generated; sed "s|__GRAFANA_DOMAIN__|$${GRAFANA_DOMAIN}|g" caddy/grafana.caddy.template > caddy/generated/grafana.caddy

up: render-caddy
	docker network inspect observability >/dev/null 2>&1 || docker network create observability
	docker network inspect caddy-proxy >/dev/null 2>&1 || docker network create caddy-proxy
	$(DC) up -d
	docker exec hanmaum-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

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
