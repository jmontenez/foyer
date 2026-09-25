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
# Jetons de design : validés ensemble, conservés quand ils sont omis.
tokens = call("PUT", "/api/v1/appearance", {"paletteId": "ember-night", "fontId": "grotesk", "listStyle": "rows", "density": "compact", "corners": "sharp"}, a)
assert (tokens["fontId"], tokens["listStyle"], tokens["density"], tokens["corners"]) == ("grotesk", "rows", "compact", "sharp"), tokens
call("PUT", "/api/v1/appearance", {"fontId": "comic-sans"}, a, expected=400)
kept = call("PUT", "/api/v1/appearance", {"paletteId": "sky-orange"}, a)
assert (kept["fontId"], kept["density"]) == ("grotesk", "compact"), kept
call("PUT", "/api/v1/appearance", {"fontId": "system", "listStyle": "cards", "density": "comfortable", "corners": "soft"}, a)
assert call("GET", "/api/v1/state", token=b)["me"]["paletteId"] == other_palette
# Raccourcis : exemples pré-chargés, lancement, gestion, lien depuis une création étoffée.
shortcuts = call("GET", "/api/v1/state", token=a)["shortcuts"]
assert len(shortcuts) == 8 and shortcuts[0]["title"] == "Faire une lessive", shortcuts[:1]
launched = call("POST", f"/api/v1/shortcuts/{shortcuts[0]['id']}/launch", token=a)
assert launched["stageId"] == "todo" and launched["shortcutId"] == shortcuts[0]["id"] and len(launched["checklist"]) == 4, launched
again = call("GET", "/api/v1/state", token=a)["shortcuts"][0]
assert again["openTicketId"] == launched["id"] and again["uses"] == 1, again
custom = call("POST", "/api/v1/shortcuts", {"title": "Nourrir le chat", "description": "", "kind": "obligation", "priority": "normal", "tagIds": [], "checklist": [], "dueInDays": None, "assign": "rotation", "assigneeId": None}, a)
call("POST", "/api/v1/shortcuts", {"title": "", "description": "", "kind": "obligation", "priority": "normal", "tagIds": [], "checklist": [], "dueInDays": 0, "assign": "launcher", "assigneeId": None}, a, expected=400)
edited = call("PUT", f"/api/v1/shortcuts/{custom['id']}", {"title": "Nourrir le chat", "description": "Croquettes", "kind": "obligation", "priority": "high", "tagIds": [], "checklist": ["Gamelle"], "dueInDays": 1, "assign": "rotation", "assigneeId": None}, a)
assert edited["priority"] == "high" and edited["checklist"] == ["Gamelle"], edited
ids = [x["id"] for x in call("GET", "/api/v1/state", token=a)["shortcuts"]]
call("PUT", "/api/v1/shortcuts-order", [ids[-1], *ids[:-1]], a, expected=204)
assert call("GET", "/api/v1/state", token=a)["shortcuts"][0]["id"] == custom["id"]
call("PUT", "/api/v1/shortcuts-order", ids[:-1], a, expected=400)
detailed = call("POST", "/api/v1/tickets", {"title": "Nourrir le chat (vétérinaire)", "description": "", "kind": "obligation", "priority": "normal", "stageId": "todo", "startDate": None, "dueDate": None, "assignees": [], "performers": [], "tagIds": [], "checklist": [], "shortcutId": custom["id"]}, a)
assert detailed["shortcutId"] == custom["id"], detailed
# Répétition : validée, aperçu de la prochaine date ; « passer » réservé aux occurrences répétées.
body = {"title": "Nourrir le chat", "description": "", "kind": "obligation", "priority": "normal", "tagIds": [], "checklist": [], "dueInDays": 0, "assign": "rotation", "assigneeId": None}
call("PUT", f"/api/v1/shortcuts/{custom['id']}", {**body, "repeat": {"mode": "weekly", "every": 1, "days": [], "monthDay": 1, "active": True}}, a, expected=400)
# Raccourci neuf (sans occurrence ouverte) : l’aperçu donne la prochaine échéance mensuelle.
rent = call("POST", "/api/v1/shortcuts", {**body, "title": "Payer le loyer", "repeat": {"mode": "monthly", "every": 1, "days": [], "monthDay": 5, "active": False}}, a)
assert rent["repeat"]["mode"] == "monthly" and rent["nextDate"].endswith("-05"), rent
call("DELETE", f"/api/v1/shortcuts/{rent['id']}", token=a, expected=204)
laundry = next(x for x in call("GET", "/api/v1/state", token=a)["shortcuts"] if x["seedKey"] == "laundry")
assert laundry["repeat"]["mode"] == "after" and laundry["repeat"]["every"] == 3 and not laundry["repeat"]["active"], laundry["repeat"]
call("POST", f"/api/v1/tickets/{detailed['id']}/skip", token=a, expected=409)
call("DELETE", f"/api/v1/shortcuts/{custom['id']}", token=a, expected=204)
kept = [t for t in call("GET", "/api/v1/state", token=a)["tickets"] if t["id"] == detailed["id"]]
assert kept and kept[0]["shortcutId"] is None, "la tâche doit rester, sans lien"
call("POST", f"/api/v1/shortcuts/{custom['id']}/launch", token=a, expected=404)
# Courses : brouillon, catalogue, rayons, programmation et lancement du raccourci avec la liste.
shopping = call("GET", "/api/v1/state", token=a)["shopping"]
assert shopping["lists"][-1]["id"] == "draft" and len(shopping["ingredients"]) >= 30 and len(shopping["aisles"]) == 11, shopping["aisles"]
milk = call("POST", "/api/v1/shopping/items", {"list": "draft", "name": "lait", "qty": "2 L", "aisle": None}, a)
assert milk["text"] == "Lait" and milk["aisle"] == "dairy" and milk["qty"] == "2 L", milk
call("POST", "/api/v1/shopping/items", {"list": "draft", "name": "Frites", "qty": None, "aisle": "frozen"}, b)
call("POST", "/api/v1/shopping/items", {"list": "draft", "name": "x", "qty": None, "aisle": "inconnu"}, a, expected=400)
call("PATCH", f"/api/v1/shopping/items/draft/{milk['id']}", {"done": True, "qty": None, "aisle": None}, b)
call("POST", "/api/v1/shopping/draft/clear-done", token=a, expected=204)
draft = call("GET", "/api/v1/state", token=a)["shopping"]["lists"][-1]["items"]
assert [x["text"] for x in draft] == ["Frites"], draft
aisles = [x["id"] for x in shopping["aisles"]]
call("PUT", "/api/v1/shopping/aisle-order", [*aisles[1:], aisles[0]], a, expected=204)
assert call("GET", "/api/v1/state", token=a)["shopping"]["aisles"][-1]["id"] == aisles[0]
call("PUT", "/api/v1/shopping/aisle-order", aisles[1:], a, expected=400)
renamed = call("PUT", "/api/v1/shopping/ingredients/Frites", {"name": "Frites au four", "aisle": "frozen", "qty": "1 sac"}, a)
assert renamed["name"] == "Frites au four" and renamed["lastQty"] == "1 sac", renamed
call("PUT", "/api/v1/shopping/ingredients/Frites%20au%20four", {"name": "Lait", "aisle": None, "qty": None}, a, expected=409)
draft = call("GET", "/api/v1/state", token=a)["shopping"]["lists"][-1]["items"]
assert [x["text"] for x in draft] == ["Frites au four"], draft
call("PUT", "/api/v1/shopping/ingredients/Frites%20au%20four", {"name": "Frites", "aisle": "frozen", "qty": None}, a)
call("DELETE", "/api/v1/shopping/ingredients/Frites", token=a, expected=204)
call("POST", "/api/v1/shopping/schedule", {"date": "2000-01-01", "mode": "new", "targetId": None}, a, expected=400)
today = call("GET", "/api/v1/state", token=a)["today"]
groceries = call("POST", "/api/v1/shopping/schedule", {"date": today, "mode": "new", "targetId": None}, a)
assert groceries["shopping"] and groceries["stageId"] == "todo" and [x["text"] for x in groceries["checklist"]] == ["Frites"], groceries
call("POST", "/api/v1/shopping/items", {"list": groceries["id"], "name": "Pain", "qty": "1", "aisle": None}, b)
call("POST", "/api/v1/shopping/items", {"list": "draft", "name": "Café", "qty": None, "aisle": None}, a)
call("POST", "/api/v1/shopping/schedule", {"date": today, "mode": "append", "targetId": groceries["id"]}, a)
lists = call("GET", "/api/v1/state", token=a)["shopping"]["lists"]
assert lists[0]["id"] == groceries["id"] and len(lists[0]["items"]) == 3 and not lists[-1]["items"], lists
call("POST", "/api/v1/shopping/items", {"list": "draft", "name": "Sucre", "qty": None, "aisle": None}, a)
grocery_shortcut = next(x for x in call("GET", "/api/v1/state", token=a)["shortcuts"] if x["seedKey"] == "groceries")
second = call("POST", f"/api/v1/shortcuts/{grocery_shortcut['id']}/launch?withList=true", token=a)
assert second["shopping"] and [x["text"] for x in second["checklist"]] == ["Sucre"], second
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
