#!/usr/bin/env python3
"""Publie aux membres l'APK d'une release CI (foyer-arm64.apk, foyer-android.json, SHA256SUMS).

Vérifie empreinte et taille, refuse un retour en arrière, puis remplace les fichiers
servis par l'API sans jamais exposer de copie partielle."""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path

APK = "foyer-arm64.apk"
MANIFEST = "foyer-android.json"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", help="Dossier des fichiers téléchargés depuis la release")
parser.add_argument("updates", help="Répertoire servi par l'API (FOYER_UPDATES_DIR)")
parser.add_argument(
    "--allow-downgrade", action="store_true", help="Republier une version plus ancienne"
)
args = parser.parse_args()
source, updates = Path(args.source), Path(args.updates)


def fail(message):
    raise SystemExit(f"Refusé : {message}")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


try:
    manifest = json.loads((source / MANIFEST).read_text())
except (OSError, ValueError):
    fail(f"{MANIFEST} absent ou illisible dans {source}.")
apk = source / APK
if not apk.is_file():
    fail(f"{APK} absent dans {source}.")
code, name = manifest.get("versionCode"), manifest.get("versionName")
sha, size = manifest.get("sha256"), manifest.get("size")
if not isinstance(code, int) or code <= 0 or not isinstance(name, str) or not name:
    fail("version invalide dans le manifeste.")
if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{64}", sha):
    fail("empreinte invalide dans le manifeste.")
if size != apk.stat().st_size or digest(apk) != sha:
    fail("l'APK ne correspond pas à son manifeste (taille ou SHA-256).")
sums = source / "SHA256SUMS"
if sums.is_file() and f"{sha}  {APK}" not in sums.read_text().splitlines():
    fail("SHA256SUMS ne confirme pas l'empreinte de l'APK.")

updates.mkdir(parents=True, exist_ok=True)
try:
    current = json.loads((updates / MANIFEST).read_text()).get("versionCode", 0)
except (OSError, ValueError):
    current = 0
if code < current and not args.allow_downgrade:
    fail(f"version {code} plus ancienne que la version publiée {current}.")

# APK puis manifeste : l'API ne propose une version que si les deux concordent.
for filename in (APK, MANIFEST):
    temporary = updates / f".{filename}.tmp"
    shutil.copyfile(source / filename, temporary)
    os.chmod(temporary, 0o644)
    os.replace(temporary, updates / filename)
print(f"Publié : Foyer {name} (versionCode {code}), {size} octets, SHA-256 {sha[:12]}…", file=sys.stderr)
