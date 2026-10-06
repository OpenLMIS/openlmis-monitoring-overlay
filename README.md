# openlmis-monitoring-overlay

Per-deployment overlay for the `olmis-monitoring.soldevelo.com` stack — the
central monitoring host for OpenLMIS implementations. The base package is
[`soldevelo-monitoring`](https://github.com/SolDevelo/soldevelo-monitoring);
this repo holds only what the base deliberately leaves to the deployment.

**Built against package tag `v0.9.0`.** Bump this line when the host moves.

## Deployments

| deployment | environment | OpenLMIS env | URL | Slack |
|---|---|---|---|---|
| `core` | `staging` | Test | https://test.openlmis.org | `#notifications-core-test` |
| `core` | `uat` | UAT | https://uat.openlmis.org | `#notifications-core-uat` |
| `core` | `prod` | Demo | https://demo-v3.openlmis.org | `#notifications-core-demo` |

`environment` is the package's fixed enum (`prod|uat|staging|dev`), so the core
environments are mapped onto it. Alerts with no `environment` (the stack's own
`meta-*` jobs) go to the default webhook, set to the demo channel.

| Path | What |
|---|---|
| `prometheus/targets/blackbox/*.json` | HTTP probe targets per deployment |
| `prometheus/rules/overlay/*.yml` | `AgentAbsent` host inventory — added with each agent |
| `grafana/dashboards/overlay/*.json` | Deployment-specific dashboards |
| `loki/rules/*.yaml` | Deployment-specific log alerts |
| `bin/apply-overlay.sh` | Copies the above into a package checkout and reloads Prometheus |

Secrets are never here. The host's `.env` lives on the host, with a copy in
`villagereach/openlmis-config`.

## Applying on the monitoring host

```sh
cd ~/openlmis-monitoring-overlay && git pull --ff-only
bin/apply-overlay.sh ~/soldevelo-monitoring       # copies + chmod + prometheus reload
```

Dashboards and blackbox targets are picked up within 30 s; Prometheus rules on
the reload the script performs. Loki rules need `docker restart` of the Loki
container.

The agents that report here live in
[`openlmis-deployment/monitoring/alloy`](https://github.com/OpenLMIS/openlmis-deployment/tree/master/monitoring/alloy).
