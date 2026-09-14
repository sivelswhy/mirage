#!/usr/bin/env bash
# Prépare le projet pour un développement local.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v xcodegen >/dev/null || brew install xcodegen
./scripts/fetch-python.sh
xcodegen generate

echo "Prêt. Ouvre Mirage.xcodeproj"
