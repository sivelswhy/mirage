#!/usr/bin/env bash
# Prépare le projet pour un développement local.
set -euo pipefail

command -v xcodegen >/dev/null || brew install xcodegen

if [[ ! -x Resources/backend/bin/python3 ]]; then
  echo "Téléchargement d'un interpréteur relocalisable…"
  ASSET=$(curl -fsSL \
    https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest \
    | python3 -c '
import json, sys
assets = json.load(sys.stdin)["assets"]
for version in ("cpython-3.12", "cpython-3.13", "cpython-3.11"):
    for a in assets:
        n = a["name"]
        if n.startswith(version) and n.endswith("aarch64-apple-darwin-install_only.tar.gz"):
            print(a["browser_download_url"]); sys.exit(0)
sys.exit("aucune distribution compatible trouvée")')

  curl -fsSL "$ASSET" -o /tmp/python.tar.gz
  rm -rf Resources/backend python
  mkdir -p Resources
  tar -xzf /tmp/python.tar.gz
  mv python Resources/backend
  Resources/backend/bin/python3 -m pip install --quiet --upgrade pip pymobiledevice3
fi

Resources/backend/bin/python3 -m pymobiledevice3 version
xcodegen generate
echo "Prêt. Ouvre Mirage.xcodeproj"
