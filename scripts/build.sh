#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_bin="${FLUTTER_BIN:-flutter}"
"$flutter_bin" pub get --directory client
(cd client && "$flutter_bin" build web --release --no-web-resources-cdn)
mkdir -p server/Foyer.Api/wwwroot
cp -R client/build/web/. server/Foyer.Api/wwwroot/
"${DOTNET_BIN:-dotnet}" build server/Foyer.Api --configuration Release
