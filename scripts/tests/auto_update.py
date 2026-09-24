#!/usr/bin/env python3
"""Recette du déploiement automatique sur un faux GitHub, un vrai dépôt git et un faux Docker."""

import hashlib
import http.server
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/deploy/auto_update.py"
tmp = Path(tempfile.mkdtemp(prefix="foyer-auto-update-"))
releases, files, compare = [], {}, {}
leaked = []  # requêtes vers le stockage signé portant encore le jeton


class Fake(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, status, body=b"", headers=None):
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path
        if path == "/health":
            return self.send(200, b'{"status":"ok"}')
        if path.startswith("/repos/o/r/releases"):
            assert self.headers["Authorization"] == "Bearer jeton-test"
            return self.send(200, json.dumps(releases).encode())
        if path.startswith("/repos/o/r/compare/"):
            sha = path.split("/")[-1].split("...")[0]
            return self.send(200, json.dumps({"status": compare.get(sha, "identical")}).encode())
        if path.startswith("/assets/"):
            assert self.headers["Authorization"] == "Bearer jeton-test"
            return self.send(302, headers={"Location": f"{BASE}/s3/{path[8:]}"})
        if path.startswith("/s3/"):
            if self.headers.get("Authorization"):
                leaked.append(path)
            return self.send(200, files[path[4:]])
        self.send(404)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=server.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{server.server_port}"


def git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


# Origine : deux commits sur main, contenant le vrai script de publication APK.
work, origin, app = tmp / "work", tmp / "origin.git", tmp / "app"
(work / "scripts").mkdir(parents=True)
shutil.copy(ROOT / "scripts/android_update.py", work / "scripts/")
(work / ".gitignore").write_text("client/build/\n")
git("init", "-q", "-b", "main", cwd=work)
git("config", "user.email", "ci@example.invalid", cwd=work)
git("config", "user.name", "CI", cwd=work)
commits = []
for version in ("A", "B", "C"):
    (work / "VERSION").write_text(version)
    git("add", "-A", cwd=work)
    git("commit", "-qm", version, cwd=work)
    commits.append(git("rev-parse", "HEAD", cwd=work))
git("clone", "-q", "--bare", str(work), str(origin), cwd=tmp)
git("clone", "-q", str(origin), str(app), cwd=tmp)
git("reset", "-q", "--hard", commits[0], cwd=app)
(app / "client/build/web").mkdir(parents=True)
(app / "client/build/web/index.html").write_text("web A")

# Faux docker : journalise, échoue au build si FAKE_DOCKER_FAIL existe.
bin_dir = tmp / "bin"
bin_dir.mkdir()
(bin_dir / "docker").write_text(
    f'#!/bin/sh\necho "$@" >> {tmp}/docker.log\n'
    f'[ "$2" = build ] && [ -f {tmp}/FAKE_DOCKER_FAIL ] && exit 1\nexit 0\n'
)
(bin_dir / "docker").chmod(0o755)


def release(number, sha, web="web", apk=b"", tamper=False, author="github-actions[bot]"):
    apk = apk or os.urandom(2048)
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        data = web.encode()
        info = tarfile.TarInfo("./index.html")
        info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
    web_tar = buffer.getvalue()
    sha_apk = hashlib.sha256(apk).hexdigest()
    manifest = {"versionCode": 2100 + number, "versionName": "1.0.0", "sha256": sha_apk, "size": len(apk)}
    sums = f"{'0' * 64 if tamper else sha_apk}  foyer-arm64.apk\n{hashlib.sha256(web_tar).hexdigest()}  foyer-web.tar.gz\n"
    content = {
        "foyer-arm64.apk": apk,
        "foyer-android.json": json.dumps(manifest).encode(),
        "foyer-web.tar.gz": web_tar,
        "SHA256SUMS": sums.encode(),
    }
    assets = []
    for name, body in content.items():
        files[f"{number}/{name}"] = body
        assets.append({"name": name, "url": f"{BASE}/assets/{number}/{name}"})
    releases.insert(0, {"tag_name": f"ci-{number}", "target_commitish": sha, "draft": False, "author": {"login": author}, "assets": assets})


token, state, updates = tmp / "token", tmp / "state.json", tmp / "updates"
token.write_text("jeton-test\n")
env = {**os.environ, "FOYER_GITHUB_API": BASE, "PATH": f"{bin_dir}:{os.environ['PATH']}"}


def deploy():
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--repo", "o/r", "--app", str(app), "--updates", str(updates),
         "--token-file", str(token), "--state", str(state), "--health", f"{BASE}/health"],
        env=env, capture_output=True, text=True,
    )


def docker_calls():
    log = tmp / "docker.log"
    return log.read_text().splitlines() if log.exists() else []


def head():
    return git("rev-parse", "HEAD", cwd=app)


def served_version():
    return json.loads((updates / "foyer-android.json").read_text())["versionCode"]


checks = 0

# 1. Release valide : serveur au commit de la release, web remplacé, APK publié ensuite.
release(12, commits[1], web="web B")
r = deploy()
assert r.returncode == 0, r.stdout + r.stderr
assert head() == commits[1]
assert (app / "client/build/web/index.html").read_text() == "web B"
assert served_version() == 2112
assert json.loads(state.read_text())["deployed"] == 12
assert any(c.startswith("compose build") for c in docker_calls())
assert any(c.startswith("image tag foyer-api:latest foyer-api:rollback") for c in docker_calls())
assert not leaked, f"jeton transmis au stockage : {leaked}"
checks += 1

# 2. Rien de nouveau : aucune action.
before = len(docker_calls())
assert deploy().returncode == 0 and len(docker_calls()) == before
checks += 1

# 3. Échec du build : retour au commit, au web et à l'image précédents ; APK inchangé.
(tmp / "FAKE_DOCKER_FAIL").touch()
release(13, commits[2], web="web C")
r = deploy()
assert r.returncode == 1, r.stdout
assert head() == commits[1] and (app / "client/build/web/index.html").read_text() == "web B"
assert served_version() == 2112, "APK publié malgré l'échec serveur"
assert "image tag foyer-api:rollback foyer-api:latest" in docker_calls()
assert json.loads(state.read_text())["failed"] == 13
before = len(docker_calls())
assert deploy().returncode == 0 and len(docker_calls()) == before, "release en échec retentée"
(tmp / "FAKE_DOCKER_FAIL").unlink()
checks += 1

# 4. Empreinte falsifiée : refus avant tout changement.
release(14, commits[2], tamper=True)
before = len(docker_calls())
assert deploy().returncode == 1
assert head() == commits[1] and served_version() == 2112
assert not any(c.startswith("compose build") for c in docker_calls()[before:])
checks += 1

# 5. Commit absent de main : ignoré.
release(15, commits[2])
compare[commits[2]] = "diverged"
assert deploy().returncode == 0
assert head() == commits[1] and json.loads(state.read_text())["failed"] == 15
checks += 1

# 6. Release non publiée par la CI : ignorée, état inchangé.
compare.pop(commits[2])
release(16, commits[2], author="quelquun")
saved = state.read_text()
assert deploy().returncode == 0 and state.read_text() == saved and head() == commits[1]
checks += 1

# 7. Release suivante valide : déployée normalement après les refus.
release(17, commits[2], web="web C")
r = deploy()
assert r.returncode == 0, r.stdout + r.stderr
assert head() == commits[2] and served_version() == 2117
assert json.loads(state.read_text())["deployed"] == 17
checks += 1

server.shutdown()
shutil.rmtree(tmp)
print(f"PASS : déploiement automatique, {checks} scénarios (succès, rien à faire, rollback, empreinte, hors main, auteur, reprise).")
