#!/usr/bin/env bash

# Lint and render every chart with the values files of each of its environments, like ArgoCD does
# SOPS values can't be decrypted here (no AGE key)
# Use .github/ci/<chart>-sops-placeholders.yaml to replace them

set -euo pipefail

cd "$(dirname "$0")/../.."

render() {
  local name=$1 namespace=$2
  shift 2
  echo "::group::$name ($namespace)"
  helm lint "charts/$name" --namespace "$namespace" "$@"
  helm template "$name" "charts/$name" --namespace "$namespace" "$@" > /dev/null
  echo "::endgroup::"
}

for chart in charts/*/; do
  name=$(basename "$chart")

  # Only the InterOPS applications and api-relay are deployed per environment (integration and production)
  if [[ ! -f $chart/values-integration.yaml ]]; then
    render "$name" "$name"
    continue
  fi

  for environment in integration production; do
    values=(-f "$chart/values-$environment.yaml")
    if [[ -f $chart/values-$environment.enc.yaml ]]; then
      values+=(-f ".github/ci/$name-sops-placeholders.yaml")
    fi
    render "$name" "interops-$environment" "${values[@]}"
  done
done
