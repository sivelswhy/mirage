#!/usr/bin/env bash
# Installe un interpréteur Python relocalisable dans Resources/backend
# et y ajoute pymobiledevice3.
#
# Un venv classique encode des chemins absolus vers la machine qui l'a créé :
# il casse dès que le bundle change d'ordinateur. python-build-standalone est
# conçu pour être déplacé n'importe où.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/Resources/backend"
API="https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"

if [[ -x "$TARGET/bin/python3" && "${FORCE:-0}" != "1" ]]; then
  echo "Backend déjà présent."
  "$TARGET/bin/python3" -m pymobiledevice3 version
  exit 0
fi

ARCH=$(uname -m)
case "$ARCH" in
  arm64)  SUFFIX="aarch64-apple-darwin-install_only.tar.gz" ;;
  x86_64) SUFFIX="x86_64-apple-darwin-install_only.tar.gz" ;;
  *)      echo "Architecture non gérée : $ARCH" >&2; exit 1 ;;
esac

echo "Recherche d'une distribution $SUFFIX…"
ASSET=$(curl -fsSL "$API" | "$ROOT/scripts/pick-python-asset.py" "$SUFFIX")

echo "Téléchargement : ${ASSET##*/}"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

curl -fsSL "$ASSET" -o "$STAGE/python.tar.gz"
tar -xzf "$STAGE/python.tar.gz" -C "$STAGE"

rm -rf "$TARGET"
mkdir -p "$ROOT/Resources"
mv "$STAGE/python" "$TARGET"

"$TARGET/bin/python3" -m pip install --quiet --upgrade pip
"$TARGET/bin/python3" -m pip install --quiet pymobiledevice3

# Allège le bundle : caches et en-têtes de compilation inutiles à l'exécution.
find "$TARGET" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "$TARGET/include" "$TARGET/share" 2>/dev/null || true

"$TARGET/bin/python3" -m pymobiledevice3 version
echo "Backend installé dans Resources/backend"
