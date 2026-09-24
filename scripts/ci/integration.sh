#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p artifacts/ci
scripts/dev/run.sh > artifacts/ci/server.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
ready=false
for _ in {1..60}; do
  if curl --fail --silent http://localhost:5080/auth/config >/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo 'Le serveur de test a quitté prématurément.' >&2
    exit 1
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo 'Le serveur de test ne répond pas.' >&2
  exit 1
fi
python3 scripts/tests/integration.py
node scripts/tests/browser.cjs
node scripts/tests/appearance.cjs
