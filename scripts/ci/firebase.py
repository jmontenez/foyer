#!/usr/bin/env python3
"""Prépare la configuration de compilation du client Android (canal + Firebase public)."""

import json
import os
from pathlib import Path

channel = os.environ.get("FOYER_CHANNEL", "stable")

if channel == "beta":
    # Canal beta : app « Foyer β » installable à côté de l'app principale,
    # pointée sur l'instance de validation. Sans google-services.json, le plugin
    # Gradle n'est pas appliqué (build.gradle.kts) : pas de Firebase ni de push.
    api_url = os.environ.get("FOYER_BETA_API_URL", "")
    if not api_url:
        raise SystemExit(
            "Configurer la variable Actions FOYER_BETA_API_URL pour le canal beta."
        )
    Path("client/android/app/google-services.json").unlink(missing_ok=True)
    config = {
        "CHANNEL": "beta",
        "FIREBASE_ENABLED": False,
        "API_URL": api_url,
    }
else:
    raw = os.environ.get("FIREBASE_ANDROID_JSON", "")
    if not raw:
        raise SystemExit(
            "Configurer la variable Actions FIREBASE_ANDROID_JSON avant le build Android."
        )
    data = json.loads(raw)
    if "private_key" in data or data.get("type") == "service_account":
        raise SystemExit("Credentials serveur interdits dans la configuration Android.")
    project = data["project_info"]
    if project["project_id"] != "foyer-d02dc":
        raise SystemExit("Projet Firebase inattendu.")
    client = next(
        c
        for c in data["client"]
        if c["client_info"]["android_client_info"]["package_name"] == "fr.foyer.foyer"
    )
    Path("client/android/app/google-services.json").write_text(raw)
    config = {
        "CHANNEL": "stable",
        "FIREBASE_ENABLED": True,
        "FIREBASE_PROJECT_ID": project["project_id"],
        "FIREBASE_SENDER_ID": project["project_number"],
        "FIREBASE_APP_ID": client["client_info"]["mobilesdk_app_id"],
        "FIREBASE_API_KEY": client["api_key"][0]["current_key"],
    }
    if os.environ.get("FOYER_API_URL"):
        config["API_URL"] = os.environ["FOYER_API_URL"]

Path("client/.config").mkdir(exist_ok=True)
Path("client/.config/android.json").write_text(json.dumps(config))
print(f"Configuration cliente générée (canal {channel}).")
