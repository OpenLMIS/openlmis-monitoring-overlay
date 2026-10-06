#!/usr/bin/env bash
# Copy this overlay into a soldevelo-monitoring checkout and reload Prometheus.
# Alertmanager fragments take effect on render-configs.sh + recreating the alertmanager container.
# Loki rules land in the ruler's tenant dir as overlay-*.yaml; Loki needs a restart to load them.
# Copies, not symlinks: the package bind-mounts the overlay dirs into containers
# and a symlink pointing outside the mount does not resolve there.
# Usage: bin/apply-overlay.sh [path/to/soldevelo-monitoring] [--no-reload]
set -euo pipefail
shopt -s nullglob
umask 022
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="${1:-${HERE}/../soldevelo-monitoring}"
[[ -f "${PKG}/stack/docker-compose.yml" ]] || { echo "not a soldevelo-monitoring checkout: ${PKG}" >&2; exit 1; }
for d in prometheus/targets/blackbox prometheus/rules/overlay grafana/dashboards/overlay alertmanager/overlay; do
  mkdir -p "${PKG}/${d}"
  for f in "${HERE}/${d}"/*.*; do
    cp "${f}" "${PKG}/${d}/" && chmod a+r "${PKG}/${d}/$(basename "${f}")"
  done
  chmod a+rX "${PKG}/${d}"
done
for f in "${HERE}"/loki/rules/*.yaml; do
  cp "${f}" "${PKG}/loki/rules/fake/overlay-$(basename "${f}")"
  chmod a+r "${PKG}/loki/rules/fake/overlay-$(basename "${f}")"
done
echo "overlay applied to ${PKG}"
if [[ "${2:-}" != "--no-reload" ]]; then
  curl -sf -X POST localhost:9090/-/reload && echo "prometheus reloaded" || echo "prometheus not reloaded (not running here?)"
fi
