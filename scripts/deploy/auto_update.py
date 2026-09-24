#!/usr/bin/env python3
"""Déploiement automatique depuis les releases CI de `main`, sous le compte de service.

Lancé périodiquement (launchd) : si une release plus récente que la version déployée existe,
publie son APK aux membres, déploie le serveur au commit de la release avec son build web,
vérifie /health et revient à la version précédente en cas d'échec. Aucun secret imprimé."""

import argparse
import base64
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ASSETS = ("foyer-arm64.apk", "foyer-android.json", "foyer-web.tar.gz", "SHA256SUMS")
CI_AUTHOR = "github-actions[bot]"
API = os.environ.get("FOYER_GITHUB_API", "https://api.github.com")  # surchargé par les tests


def log(message):
    print(f"{datetime.now(timezone.utc):%Y-%m-%dT%H:%M:%SZ} {message}", flush=True)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    # Les fichiers de release redirigent vers un stockage signé : le jeton GitHub ne doit
    # jamais y être renvoyé, la redirection est donc suivie à part, sans en-tête d'autorisation.
    def redirect_request(self, *args, **kwargs):
        return None


class GitHub:
    def __init__(self, repo, token):
        self.repo, self.token = repo, token
        self.opener = urllib.request.build_opener(NoRedirect)

    def _open(self, url, accept):
        request = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": accept,
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "foyer-auto-update",
            },
        )
        try:
            return self.opener.open(request, timeout=60)
        except urllib.error.HTTPError as error:
            if error.code in (301, 302, 303, 307, 308) and error.headers.get("Location"):
                return urllib.request.urlopen(error.headers["Location"], timeout=120)  # nosec B310
            raise

    def json(self, path):
        with self._open(f"{API}/repos/{self.repo}{path}", "application/vnd.github+json") as r:
            return json.load(r)

    def download(self, asset, target):
        with self._open(asset["url"], "application/octet-stream") as r, target.open("wb") as f:
            shutil.copyfileobj(r, f)


def release_number(tag):
    match = re.fullmatch(r"ci-(\d+)", tag or "")
    return int(match[1]) if match else None


def choose(releases, deployed):
    """Release CI la plus récente, publiée par Actions, complète et plus récente que `deployed`."""
    candidates = []
    for r in releases:
        number = release_number(r.get("tag_name"))
        names = {a.get("name") for a in r.get("assets", [])}
        if (
            number is not None
            and number > deployed
            and not r.get("draft")
            and (r.get("author") or {}).get("login") == CI_AUTHOR
            and set(ASSETS) <= names
            and re.fullmatch(r"[0-9a-f]{40}", r.get("target_commitish") or "")
        ):
            candidates.append((number, r))
    return max(candidates, key=lambda c: c[0])[1] if candidates else None


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def verify(folder):
    sums = {}
    for line in (folder / "SHA256SUMS").read_text().splitlines():
        parts = line.split()
        if len(parts) == 2:
            sums[parts[1].lstrip("*")] = parts[0]
    for name in ("foyer-arm64.apk", "foyer-web.tar.gz"):
        if sums.get(name) != digest(folder / name):
            raise ValueError(f"Empreinte invalide : {name}")


def extract_web(archive, target):
    fresh = target.with_name(target.name + ".new")
    shutil.rmtree(fresh, ignore_errors=True)
    fresh.mkdir(parents=True)
    with tarfile.open(archive) as tar:
        tar.extractall(fresh, filter="data")
    if not (fresh / "index.html").is_file():
        raise ValueError("Build web incomplet : index.html absent.")
    old = target.with_name(target.name + ".old")
    shutil.rmtree(old, ignore_errors=True)
    if target.exists():
        target.rename(old)
    fresh.rename(target)


def restore_web(target):
    old = target.with_name(target.name + ".old")
    if old.exists():
        shutil.rmtree(target, ignore_errors=True)
        old.rename(target)


def healthy(url, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as r:  # nosec B310 (loopback)
                if r.status == 200 and json.load(r).get("status") == "ok":
                    return True
        except (OSError, ValueError):
            pass
        time.sleep(5)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="jmontenez/foyer")
    parser.add_argument("--app", required=True, help="Dépôt déployé (compose.yaml, .env)")
    parser.add_argument("--updates", required=True, help="FOYER_UPDATES_DIR")
    parser.add_argument("--token-file", required=True, help="Jeton GitHub lecture seule")
    parser.add_argument("--state", required=True, help="Fichier d'état du déploiement")
    parser.add_argument("--health", default="http://127.0.0.1:5080/health")
    parser.add_argument("--check", action="store_true", help="Afficher la release candidate, sans déployer")
    args = parser.parse_args()
    app, state_file = Path(args.app), Path(args.state)

    lock = open(state_file.with_suffix(".lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    token = Path(args.token_file).read_text().strip()
    github = GitHub(args.repo, token)

    # Dernière release réussie ou refusée : jamais de nouvel essai sur la même release.
    seen = max(state.get("deployed", 0), state.get("failed", 0))
    release = choose(github.json("/releases?per_page=20"), seen)
    if release is None:
        return
    tag, sha = release["tag_name"], release["target_commitish"]
    compare = github.json(f"/compare/{sha}...main")
    if compare.get("status") not in ("identical", "ahead"):
        log(f"{tag} ignorée : {sha[:7]} n'appartient pas à main.")
        state["failed"] = release_number(tag)
        state_file.write_text(json.dumps(state))
        return
    if args.check:
        log(f"Candidate : {tag} ({sha[:7]}), déployée : ci-{state.get('deployed', '?')}")
        return

    log(f"Déploiement de {tag} ({sha[:7]})")
    git_env = {
        **os.environ,
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "http.https://github.com/.extraheader",
        "GIT_CONFIG_VALUE_0": "AUTHORIZATION: basic "
        + base64.b64encode(f"x-access-token:{token}".encode()).decode(),
    }
    run = lambda *cmd, **kw: subprocess.run(cmd, cwd=app, check=True, **kw)  # noqa: E731
    previous = subprocess.run(["git", "rev-parse", "HEAD"], cwd=app, check=True, capture_output=True, text=True).stdout.strip()
    web = app / "client/build/web"
    with tempfile.TemporaryDirectory(prefix="foyer-release-") as tmp:
        folder = Path(tmp)
        try:
            for asset in release["assets"]:
                if asset["name"] in ASSETS:
                    github.download(asset, folder / asset["name"])
            verify(folder)
            run("git", "fetch", "--quiet", "origin", sha, env=git_env)
            run("git", "reset", "--quiet", "--hard", sha)
            extract_web(folder / "foyer-web.tar.gz", web)
            run("docker", "image", "tag", "foyer-api:latest", "foyer-api:rollback")
            run("docker", "compose", "build", "--quiet", "api")
            run("docker", "compose", "up", "-d", "--wait", "--wait-timeout", "180")
            if not healthy(args.health, 120):
                raise RuntimeError("/health ne répond pas après déploiement")
        except Exception as error:  # rollback puis mémorisation de l'échec
            log(f"Échec de {tag} : {type(error).__name__}: {error}. Retour à {previous[:7]}.")
            state["failed"] = release_number(tag)
            state_file.write_text(json.dumps(state))
            subprocess.run(["git", "reset", "--quiet", "--hard", previous], cwd=app)
            restore_web(web)
            subprocess.run(["docker", "image", "tag", "foyer-api:rollback", "foyer-api:latest"], cwd=app)
            subprocess.run(["docker", "compose", "up", "-d", "--no-build"], cwd=app)
            log("Version précédente " + ("rétablie." if healthy(args.health, 120) else "NON rétablie : intervention requise."))
            return 1
        # APK publié seulement une fois le serveur sain : jamais d'application plus récente
        # que l'API en cas de retour arrière.
        published = subprocess.run(
            [sys.executable, str(app / "scripts/android_update.py"), str(folder), args.updates]
        )
        if published.returncode != 0:
            log(f"{tag} : serveur déployé, APK non publié (voir ci-dessus).")
    state.update(deployed=release_number(tag), sha=sha, at=datetime.now(timezone.utc).isoformat())
    state_file.write_text(json.dumps(state))
    log(f"{tag} déployée et saine.")


if __name__ == "__main__":
    sys.exit(main())
