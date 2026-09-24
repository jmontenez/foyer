#!/usr/bin/env bash
set -euo pipefail
# Instance de test sans données réelles, uniquement exposée sur loopback.
if ! docker --context "${DOCKER_CONTEXT:-colima-foyer}" inspect foyer-test-db >/dev/null 2>&1; then
  docker --context "${DOCKER_CONTEXT:-colima-foyer}" run -d --name foyer-test-db -p 127.0.0.1:55432:5432 -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=foyer_test postgres:17 >/dev/null
else
  docker --context "${DOCKER_CONTEXT:-colima-foyer}" start foyer-test-db >/dev/null
fi
for _ in {1..30}; do
  if docker --context "${DOCKER_CONTEXT:-colima-foyer}" exec foyer-test-db pg_isready -U postgres -d foyer_test >/dev/null; then exit 0; fi
  sleep 1
done
exit 1
