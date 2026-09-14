#!/usr/bin/env bash
set -euo pipefail

# 1. Génère le projet Xcode à partir de project.yml
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

# 2. Embarque pymobiledevice3 dans le bundle
python3 -m venv Resources/backend
Resources/backend/bin/pip install --quiet --upgrade pip pymobiledevice3

echo "Prêt. Ouvre Mirage.xcodeproj"
