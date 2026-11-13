#!/usr/bin/env bash
# Renders the full Talos machine config for every node into rendered/<node>.yaml
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER_NAME=mycluster
ENDPOINT=https://192.168.178.66:6443
K8S_VERSION=1.35.0
TALOS_VERSION=v1.13

render() {
  local node=$1 type=$2
  talosctl gen config "$CLUSTER_NAME" "$ENDPOINT" \
    --with-secrets secrets.yaml \
    --kubernetes-version "$K8S_VERSION" \
    --talos-version "$TALOS_VERSION" \
    --with-docs=false --with-examples=false \
    --config-patch @cluster.yaml \
    --config-patch @longhorn.yaml \
    --config-patch-control-plane @controlplane.yaml \
    --config-patch "@nodes/$node.yaml" \
    --output-types "$type" \
    --output "rendered/$node.yaml" --force
  echo "✔ rendered/$node.yaml ($type)"
}

render chimchar controlplane
render piplup   worker
