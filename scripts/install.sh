#!/usr/bin/env bash
# Installe ou met à jour Mirage depuis la dernière release GitHub.
#   curl -fsSL https://raw.githubusercontent.com/sivelswhy/mirage/main/scripts/install.sh | bash
set -euo pipefail

REPO="sivelswhy/mirage"
TARGET="/Applications/Mirage.app"
API="https://api.github.com/repos/${REPO}/releases/latest"

say() { printf '\033[1m%s\033[0m\n' "$1"; }

say "Recherche de la dernière version…"
META=$(curl -fsSL -H "Accept: application/vnd.github+json" "$API")

TAG=$(printf '%s' "$META" | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')
URL=$(printf '%s' "$META" | /usr/bin/python3 -c '
import json, sys
assets = json.load(sys.stdin)["assets"]
print(next(a["browser_download_url"] for a in assets if a["name"].endswith(".dmg")))')

if [[ -d "$TARGET" ]]; then
  INSTALLED=$(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0")
  if [[ "v${INSTALLED}" == "$TAG" ]]; then
    say "Déjà à jour (${INSTALLED})."
    exit 0
  fi
  say "Mise à jour ${INSTALLED} vers ${TAG#v}"
fi

TMP=$(mktemp -d)
trap 'hdiutil detach "$TMP/mount" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

say "Téléchargement de ${TAG}…"
curl -fL --progress-bar "$URL" -o "$TMP/Mirage.dmg"

say "Vérification de la somme de contrôle…"
SUMS_URL="${URL%/*}/SHA256SUMS.txt"
if curl -fsSL "$SUMS_URL" -o "$TMP/SHA256SUMS.txt" 2>/dev/null; then
  EXPECTED=$(awk '{print $1}' "$TMP/SHA256SUMS.txt" | head -1)
  ACTUAL=$(shasum -a 256 "$TMP/Mirage.dmg" | awk '{print $1}')
  [[ "$EXPECTED" == "$ACTUAL" ]] || { echo "Somme de contrôle invalide." >&2; exit 1; }
fi

say "Installation…"
mkdir -p "$TMP/mount"
hdiutil attach "$TMP/Mirage.dmg" -mountpoint "$TMP/mount" -nobrowse -quiet

pkill -x Mirage 2>/dev/null || true
rm -rf "$TARGET"
cp -R "$TMP/mount/Mirage.app" "$TARGET"

# L'app n'étant pas notarisée, Gatekeeper la bloquerait sans cela.
xattr -dr com.apple.quarantine "$TARGET"

say "Mirage ${TAG#v} installé."
open "$TARGET"
