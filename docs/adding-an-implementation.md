# Adding an implementation

How to connect a new OpenLMIS implementation ("MyCountry") to
`olmis-monitoring.soldevelo.com`. Gambia is the reference: copy from
[`openlmis-gambia-deploy/monitoring/alloy`](https://github.com/gambiamoh/openlmis-gambia-deploy/tree/main/monitoring/alloy)
and from this repo's `gambia` files.

Two sides, two owners:

- **Implementation team** — the agent, app labels and DB role, in their own
  deploy and config repos (steps 1–4).
- **Host operators** — the overlay PR here and the host `.env` (steps 5–6).

## Before you start

Agree on these with the host operators:

| Item | Example | Note |
|---|---|---|
| `deployment` | `mycountry` | Lowercase, one word. Used in every label, rule and route. |
| `environment` per env | `uat`, `prod` | Must be one of `prod`, `uat`, `staging`, `dev`. Map your env names onto it. |
| `TARGET_NAME` per env | `mycountry-uat` | Becomes the agent's `host` label. Keep it stable. |
| Slack channel per env | `#notifications-mycountry-uat` | Plus an incoming webhook for each. |
| Ingest token | — | One per implementation, for all its envs. The host operators hand it over privately. |

Each implementation gets **its own ingest token**, so it can be revoked without
touching the others. It is not tied to a `deployment`: whoever holds it can
push metrics and logs under any label. Keep it in the private config repo only.

The host operators issue it before the first agent deploy (package ≥ 0.12.0):

```sh
cd ~/soldevelo-monitoring
echo "INGEST_TOKEN_MYCOUNTRY=$(openssl rand -hex 32)" >> .env
bin/render-configs.sh .env && bin/validate.sh .env \
  && docker compose --env-file .env -f stack/docker-compose.yml up -d --force-recreate caddy
```

Add the same line to the `.env` copy in `villagereach/openlmis-config`. To
revoke, delete the line and run the same render and recreate.

The app host needs Docker 20.10 or newer. Current Alloy images are OCI-only and
older engines reject them.

## 1. Agent

In your deploy repo, copy `monitoring/alloy/` from `openlmis-gambia-deploy`:

| File | Change |
|---|---|
| `config.alloy`, `PACKAGE_VERSION`, `sync-from-package.sh` | Nothing. `config.alloy` is the package file, vendored; never edit it. |
| `openlmis.alloy` | Nothing, unless your nginx log volume is not `<project>_nginx-log`. |
| `docker-compose.yml`, `Dockerfile` | Nothing. |
| `deploy_alloy.sh` | Paths to your config repo layout (`CONFIG_DIR`, the TLS certs dir). |
| `README.md`, `.env.example` | Your names. |

Then add per env, in your **private** config repo, an `alloy.env` based on
`.env.example`:

```env
DOCKER_HOST=tcp://uat.mycountry.example:2376
ALLOY_VERSION=v1.20.1
COMPOSE_PROJECT_NAME=soldevelo-monitoring-agents
APP=openlmis
DEPLOYMENT=mycountry
ENVIRONMENT=uat
TARGET_NAME=mycountry-uat
INGEST_METRICS_URL=https://olmis-monitoring.soldevelo.com/ingest/prometheus/api/v1/write
INGEST_LOGS_URL=https://olmis-monitoring.soldevelo.com/ingest/loki/loki/api/v1/push
INGEST_TOKEN=<INGEST_TOKEN_MYCOUNTRY from the host operators>
LOG_DROP_SERVICES=
COMPOSE_PROFILES=postgres
PG_EXPORTER_DSN=postgresql://olmis_monitoring:<password>@<db-host>:5432/open_lmis?sslmode=require
```

Keep these as they are:

- `network_mode: host`. On the app network, the agent container blocks the app
  deploy's `docker compose down` from removing `<env>_default`.
- `COMPOSE_PROJECT_NAME=soldevelo-monitoring-agents`. `config.alloy` drops the
  agent's own logs by that name.

Deploy with a manual Jenkins job that checks out both repos and runs
`monitoring/alloy/deploy_alloy.sh <env>` from the workspace root. It builds the
image on the env's Docker daemon and starts the agent as its own compose
project, so app deploys never touch it.

Host, container and log data start arriving as soon as the agent runs.

## 2. App metrics

Label each Java service that exposes `/actuator/prometheus` in your env's
`docker-compose.yml`:

```yaml
    labels:
      monitoring.scrape: "true"
      monitoring.port: "8080"
      monitoring.path: "/actuator/prometheus"
      monitoring.service: "requisition"
```

Core OpenLMIS releases already expose the endpoint without auth. Check your own
forks: a service without actuator gets no label (Gambia's `report` has none).
Labels take effect when the app containers are recreated, i.e. on the next app
deploy. Package details: [`java-app-setup.md`](https://github.com/SolDevelo/soldevelo-monitoring/blob/main/docs/java-app-setup.md).

## 3. Database

Create the read-only role that `postgres-exporter` logs in as:

```sql
CREATE ROLE olmis_monitoring LOGIN PASSWORD '...';
GRANT pg_monitor TO olmis_monitoring;
```

If an env's DB can be **replaced** (restore from another env's snapshot, or a
DB container wiped with its volume), the role disappears with it. Re-create it
in the restore flow, as Gambia's `shared/restore/after_restore.sh` does.
Without the role, the exporter fails to log in and the Postgres panels go empty.
Package details: [`postgresql-setup.md`](https://github.com/SolDevelo/soldevelo-monitoring/blob/main/docs/postgresql-setup.md).

## 4. Check the agent

In Grafana (Explore → Prometheus), after a deploy:

```promql
count by (job, service) (up{deployment="mycountry", environment="uat"})
```

You should see `job` values `agent`, `node`, `cadvisor`, and `app` with one
`service` per labelled container, `postgres` included. Logs: Explore → Loki,
`{deployment="mycountry"}`.

## 5. Overlay PR (this repo)

One PR, same shape as `gambia`:

- **`prometheus/targets/blackbox/mycountry.json`**: public URL per env.
  ```json
  [
    {
      "targets": ["https://uat.mycountry.example"],
      "labels": {"app": "openlmis", "deployment": "mycountry", "environment": "uat", "check": "public"}
    }
  ]
  ```
- **`prometheus/rules/overlay/mycountry.yml`**: one `AgentAbsent` stanza per
  agent, keyed on `host="<TARGET_NAME>"`. Copy `gambia.yml`. Add it only once
  the agent is up, or it fires straight away.
- **`alertmanager/overlay/routes.yml` + `receivers.yml`**: a route matching
  `deployment="mycountry"` + `environment="<env>"` and a `slack-mycountry-<env>`
  receiver using `${SLACK_WEBHOOK_URL_MYCOUNTRY_<ENV>}` and
  `${SLACK_CHANNEL_MYCOUNTRY_<ENV>}`. Without a route, alerts go to the
  per-environment default channels of the core deployment.
- **`README.md`**: a row in the deployments table.

## 6. Host (operators)

On `olmis-monitoring`:

1. The ingest token is already in `.env` (see [Before you start](#before-you-start)).
   Add the webhooks to `~/soldevelo-monitoring/.env` (and to its copy in
   `villagereach/openlmis-config`):
   ```env
   SLACK_WEBHOOK_URL_MYCOUNTRY_UAT=https://hooks.slack.com/services/...
   SLACK_CHANNEL_MYCOUNTRY_UAT=#notifications-mycountry-uat
   ```
   Do this **before** applying the overlay. A variable missing from `.env`
   stays a literal `${...}` in the rendered config and Alertmanager rejects it.
2. Apply:
   ```sh
   cd ~/openlmis-monitoring-overlay && git pull --ff-only
   bin/apply-overlay.sh ~/soldevelo-monitoring
   cd ~/soldevelo-monitoring && bin/render-configs.sh .env && bin/validate.sh .env \
     && curl -X POST localhost:9093/-/reload
   ```
3. Give the team Grafana access.

## 7. Done when

- `up{deployment="mycountry"}` has every expected `job`/`service` per env.
- Host, Containers, JVM and PostgreSQL dashboards show data when filtered to
  `mycountry`.
- `probe_success{deployment="mycountry"}` is 1.
- A test alert reaches each env's channel: stop the agent; `AgentAbsent` arrives
  after about 10 min (5 min staleness + `for: 5m`).

## Upgrades

The agent follows package tags. Bump `PACKAGE_VERSION`, run
`./sync-from-package.sh`, read the diff and the package CHANGELOG, commit,
redeploy. Watch the package CHANGELOG for label or rule changes that need the
agent and the host upgraded together.
