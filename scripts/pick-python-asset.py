#!/usr/bin/env python3
"""Choisit l'archive python-build-standalone correspondant à l'architecture.

Lit le JSON de l'API GitHub sur l'entrée standard, écrit une URL sur la sortie.
"""
import json
import sys

SERIES = ("cpython-3.12", "cpython-3.13", "cpython-3.11")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: pick-python-asset.py <suffixe>", file=sys.stderr)
        return 2

    suffix = sys.argv[1]
    assets = json.load(sys.stdin).get("assets", [])

    for series in SERIES:
        for asset in assets:
            name = asset["name"]
            if name.startswith(series) and name.endswith(suffix):
                print(asset["browser_download_url"])
                return 0

    print(f"aucune distribution {suffix} trouvée", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
