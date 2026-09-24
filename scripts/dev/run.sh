#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export ASPNETCORE_ENVIRONMENT=Development
export ASPNETCORE_URLS=http://127.0.0.1:5080
export PublicOrigin=http://localhost:5080
export ConnectionStrings__Database='Host=127.0.0.1;Port=55432;Database=foyer_test;Username=postgres'
export AllowedEmails='camille@example.invalid,alex@example.invalid'
export DemoMode=true
export WorkersEnabled=false
export ImagesPath="$PWD/artifacts/test-images"
exec "${DOTNET_BIN:-dotnet}" run --project server/Foyer.Api --no-launch-profile
