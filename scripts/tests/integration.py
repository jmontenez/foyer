#!/usr/bin/env python3
"""Tests sur une instance de démonstration locale, données fictives exclusivement."""

import concurrent.futures
import json
import os
import struct
import urllib.error
import urllib.request
import uuid
import zlib

BASE = os.environ.get("FOYER_TEST_URL", "http://localhost:5080")
assert BASE.startswith(
    ("http://localhost:", "http://127.0.0.1:")
), "Instance locale uniquement"
checks = 0


def call(
    method,
    path,
    body=None,
    token=None,
    expected=200,
    csrf=True,
    origin=BASE,
    raw=None,
    content="application/json",
    extra_headers=None,
):
    global checks
    headers = {"Content-Type": content}
    if extra_headers:
        headers.update(extra_headers)
    if csrf:
        headers["X-Foyer-CSRF"] = "1"
    if origin:
        headers["Origin"] = origin
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(
        BASE + path,
        data=(
            raw
            if raw is not None
            else (
                json.dumps(body).encode()
                if body is not None
                else (b"" if method == "POST" else None)
            )
        ),
        headers=headers,
        method=method,
    )
    try:
        # URL is restricted to HTTP loopback by the test configuration above.
        response = urllib.request.urlopen(req)  # nosec B310
    except urllib.error.HTTPError as error:
        response = error
    status = response.status
    data = response.read()
    assert (
        status == expected
    ), f"{method} {path}: {status}, attendu {expected}; {data[:200]}"
    checks += 1
    return (
        json.loads(data)
        if data and "json" in response.headers.get("Content-Type", "")
        else data
    )


call("GET", "/api/v1/state", expected=401)
call("GET", "/api/v1/images/nope", expected=401)
call("GET", "/api/v1/app/android", expected=401)
call("GET", "/api/v1/app/android.apk", expected=401)
call("POST", "/auth/demo/0", origin="https://intrus.invalid", expected=403)
a = call("POST", "/auth/demo/0")["token"]
b = call("POST", "/auth/demo/1")["token"]
state = call("GET", "/api/v1/state", token=a)
# Aucune mise à jour Android publiée sur l’instance de test : 404, jamais d’APK.
call("GET", "/api/v1/app/android", token=a, expected=404)
call("GET", "/api/v1/app/android.apk", token=a, expected=404)
assert "sessions" not in state and "devices" not in state
# Appareil Android : version déclarée optionnelle (anciennes versions), jamais négative.
device_token = "fcm-" + "x" * 40
call("POST", "/api/v1/devices", {"token": device_token}, token=a, expected=204)
call("POST", "/api/v1/devices", {"token": device_token, "appVersion": 2116}, token=a, expected=204)
call("POST", "/api/v1/devices", {"token": device_token, "appVersion": -1}, token=a, expected=400)
assert all("email" not in m and "subject" not in m for m in state["members"])
original_palette = state["me"]["paletteId"]
other_palette = call("GET", "/api/v1/state", token=b)["me"]["paletteId"]
updated = call("PUT", "/api/v1/appearance", {"paletteId": "sky-orange"}, a)
assert updated["paletteId"] == "sky-orange"
assert updated["digestTime"] == state["me"]["digestTime"]
assert updated["digestEnabled"] == state["me"]["digestEnabled"]
call("PUT", "/api/v1/appearance", {"paletteId": "unknown"}, a, expected=400)
assert call("GET", "/api/v1/state", token=b)["me"]["paletteId"] == other_palette
second_session = call("POST", "/auth/demo/0")["token"]
assert (
    call("GET", "/api/v1/state", token=second_session)["me"]["paletteId"]
    == "sky-orange"
)
call("POST", "/api/v1/logout", token=second_session, expected=204)
call("PUT", "/api/v1/appearance", {"paletteId": original_palette}, a)
ma = state["me"]["id"]
mb = call("GET", "/api/v1/state", token=b)["me"]["id"]
fields = {
    "title": "Test étagère " + uuid.uuid4().hex[:6],
    "description": "Un projet fictif",
    "kind": "obligation",
    "priority": "high",
    "stageId": "backlog",
    "startDate": None,
    "dueDate": None,
    "assignees": [ma, mb],
    "performers": [],
    "tagIds": [],
    "checklist": [{"id": "item1", "text": "Mesurer", "done": False}],
    "version": 0,
}
call("POST", "/api/v1/tickets", fields, a, expected=403, csrf=False)
call(
    "POST", "/api/v1/tickets", fields, a, expected=403, origin="https://intrus.invalid"
)
ticket = call("POST", "/api/v1/tickets", fields, a)
path = "/api/v1/tickets/" + ticket["id"]
assert ticket["stageId"] == "backlog"
fields.update(version=ticket["version"], stageId="done")
call("PUT", path, fields, a, expected=400)
fields.update(performers=[mb])
done = call("PUT", path, fields, a)
assert done["performers"] == [mb]
call("PUT", path, fields, b, expected=409)
call("POST", path + "/comments", {"text": "Mesures terminées."}, b)
latest = next(
    t
    for t in call("GET", "/api/v1/state", token=a)["tickets"]
    if t["id"] == ticket["id"]
)
assert latest["comments"][-1]["authorId"] == mb
fields.update(version=latest["version"], stageId="doing")
reopened = call("PUT", path, fields, a)
assert reopened["performers"] == [] and reopened["closedAt"] is None
fields["version"] = reopened["version"]


# Competing writes must not silently overwrite one another.
def compete(_):
    try:
        call("PUT", path, fields, a)
        return "ok"
    except AssertionError as e:
        assert ": 409," in str(e)
        return "conflict"


with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    assert sorted(pool.map(compete, range(2))) == ["conflict", "ok"]
call("POST", "/api/v1/tickets", dict(fields, assignees=None), a, expected=400)


# Actual decoding/re-encoding, private read, and malformed image refusal.
def chunk(kind, data):
    return (
        struct.pack("!I", len(data))
        + kind
        + data
        + struct.pack("!I", zlib.crc32(kind + data))
    )


png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack("!IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00"))
    + chunk(b"IEND", b"")
)

boundary = "foyer-test-boundary"


def multipart(payload):
    return (
        f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="test.png"\r\nContent-Type: image/png\r\n\r\n'.encode()
        + payload
        + f"\r\n--{boundary}--\r\n".encode()
    )


upload = call(
    "POST",
    path + "/images",
    token=a,
    raw=multipart(png),
    content="multipart/form-data; boundary=" + boundary,
)
image = upload["images"][-1]["id"]
assert call("GET", "/api/v1/images/" + image, token=b).startswith(b"\xff\xd8")
call("GET", "/api/v1/images/" + image, expected=401)
call(
    "POST",
    path + "/images",
    token=a,
    raw=multipart(b"not an image"),
    content="multipart/form-data; boundary=" + boundary,
    expected=400,
)
call(
    "PUT",
    "/api/v1/preferences",
    {"digestTime": "25:80", "digestEnabled": True},
    b,
    expected=400,
)
call("PUT", "/api/v1/preferences", {"digestTime": "09:15", "digestEnabled": True}, b)
sessions = call("GET", "/api/v1/sessions", token=a)
current = next(s for s in sessions if s["current"])
call("DELETE", "/api/v1/sessions/" + current["id"], token=a, expected=204)
call("GET", "/api/v1/state", token=a, expected=401)
call("GET", "/api/v1/state", token=b)


# En-têtes de sécurité et absence de cache sur les réponses privées,
# indispensables devant le cache Cloudflare.
def response_headers(path, token=None):
    global checks
    headers = {"Authorization": "Bearer " + token} if token else {}
    req = urllib.request.Request(BASE + path, headers=headers)
    try:
        response = urllib.request.urlopen(req)  # nosec B310
    except urllib.error.HTTPError as error:
        response = error
    response.read()
    checks += 1
    return response.headers


for private_path in ("/auth/config", "/api/v1/state", "/api/v1/app/android"):
    got = response_headers(private_path, token=b if "api" in private_path else None)
    assert got["Cache-Control"] == "no-store", f"{private_path}: {got['Cache-Control']}"
    assert got["X-Content-Type-Options"] == "nosniff"
    assert got["X-Frame-Options"] == "DENY"

# Derrière le tunnel, chaque visiteur doit être limité sur sa propre adresse
# CF-Connecting-IP, pas sur celle, partagée, du connecteur.
visitor = {"CF-Connecting-IP": "203.0.113.10"}
for _ in range(30):
    call("GET", "/auth/config", extra_headers=visitor)
call("GET", "/auth/config", extra_headers=visitor, expected=429)
# Un autre visiteur et le trafic local (sans en-tête) gardent leur propre budget.
call("GET", "/auth/config", extra_headers={"CF-Connecting-IP": "203.0.113.11"})
call("GET", "/auth/config")
# Une valeur non parsable retombe sur le pair réseau au lieu d'ouvrir
# une partition arbitraire par requête.
call("GET", "/auth/config", extra_headers={"CF-Connecting-IP": "pas-une-adresse"})
# L'en-tête visiteur n'influence pas le contrôle « démo locale uniquement »,
# qui repose sur le pair réseau réel.
call(
    "POST",
    "/auth/demo/0",
    extra_headers={"CF-Connecting-IP": "203.0.113.12"},
)
print(
    f"{checks} requêtes validées : contrôle d’accès, CSRF, concurrence, clôture, "
    "commentaires, images, préférences, révocation, en-têtes de cache et "
    "limitation par visiteur derrière le tunnel."
)
