#!/usr/bin/env bash
# Per-deployment copies of the package's Service availability dashboard, with no
# template variables, so each can be shared externally (no login).
# Usage: bin/stakeholder-dashboards.sh <package-checkout>
set -euo pipefail
pkg=${1:?usage: $0 <package-checkout>}
src=$pkg/grafana/dashboards/stakeholder.json
out=$(cd "$(dirname "$0")/.." && pwd)/grafana/dashboards/overlay

for dep in core gambia malawi; do
  name=$(tr '[:lower:]' '[:upper:]' <<<"${dep:0:1}")${dep:1}
  sed -e "s/\\\$deployment/$dep/g" -e 's/\$environment/.*/g' "$src" | jq \
    --arg uid "sdm-stakeholder-$dep" --arg title "Service availability — $name" '
      .uid = $uid | .title = $title | .templating.list = [] | .tags += ["overlay"]' \
    > "$out/stakeholder-$dep.json"
  echo "$out/stakeholder-$dep.json"
done
