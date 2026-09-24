#!/usr/bin/env python3
"""Sauvegarde chiffrée et restauration isolée. Aucun secret n'est imprimé."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPOSE = [
    "docker",
    "compose",
    "-f",
    os.environ.get("FOYER_COMPOSE_FILE", str(ROOT / "compose.yaml")),
]
if os.environ.get("FOYER_PROJECT"):
    COMPOSE += ["-p", os.environ["FOYER_PROJECT"]]


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def dc(*args, **kwargs):
    return run(COMPOSE + list(args), **kwargs)


def sql(query):
    return (
        dc(
            "exec",
            "-T",
            "db",
            "psql",
            "-U",
            "foyer",
            "-d",
            "foyer",
            "-v",
            "ON_ERROR_STOP=1",
            "-Atc",
            query,
            capture_output=True,
        )
        .stdout.decode()
        .strip()
    )


def maintenance(enabled):
    query = (
        "UPDATE foyer_state SET data=jsonb_set(jsonb_set(data,'{maintenance}','true'),'{revision}',to_jsonb((data->>'revision')::bigint+1)) WHERE id=1"
        if enabled
        else "UPDATE foyer_state SET data=jsonb_set(jsonb_set(data,'{maintenance}','false'),'{revision}',to_jsonb((data->>'revision')::bigint+1)) WHERE id=1"
    )
    sql(query)


def sha(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def validate_relations(images):
    # Data stays local; only counts are reported, never ticket content or identities.
    h = json.loads(
        sql(
            "SELECT (data - 'sessions' - 'devices' - 'notifications')::text FROM foyer_state WHERE id=1"
        )
    )
    members = {m["id"] for m in h["members"]}
    tags = {t["id"] for t in h["tags"]}
    stages = {s["id"] for s in h["stages"]} | {"backlog", "done", "abandoned"}
    ids = [t["id"] for t in h["tickets"]]
    if len(ids) != len(set(ids)) or len(members) > 2:
        raise ValueError("Identifiants ou nombre de membres invalides.")
    for ticket in h["tickets"]:
        if (
            not set(ticket["assignees"] + ticket["performers"]) <= members
            or not set(ticket["tagIds"]) <= tags
            or ticket["stageId"] not in stages
        ):
            raise ValueError("Référence métier invalide dans un ticket.")
        if ticket["stageId"] == "done" and not ticket["performers"]:
            raise ValueError("Ticket terminé sans réalisateur.")
        if any(c["authorId"] not in members for c in ticket["comments"]):
            raise ValueError("Auteur de commentaire inconnu.")
        for attachment in ticket["images"]:
            name = attachment["fileName"]
            if Path(name).name != name or name in (".", ".."):
                raise ValueError("Chemin image invalide.")
            file = images / name
            if (
                not file.is_file()
                or sha(file).upper() != attachment["sha256"].upper()
                or file.stat().st_size != attachment["bytes"]
            ):
                raise ValueError("Image référencée absente ou altérée.")
    return len(h["tickets"])


def unpack(archive, identity, folder):
    plain = folder / "snapshot.tar"
    with plain.open("xb") as out:
        run(["age", "--decrypt", "-i", identity, archive], stdout=out)
    target = folder / "snapshot"
    target.mkdir()
    with tarfile.open(plain) as tar:
        for member in tar.getmembers():
            p = Path(member.name)
            if (
                not member.isfile()
                or p.is_absolute()
                or ".." in p.parts
                or not (
                    member.name in ("manifest.json", "database.dump")
                    or (len(p.parts) == 2 and p.parts[0] == "images")
                )
            ):
                raise ValueError("Archive contenant un chemin non autorisé.")
        tar.extractall(target, filter="data")
    manifest = json.loads((target / "manifest.json").read_text())
    if (
        manifest["format"] != 1
        or manifest["schema"] != 1
        or manifest.get("postgresMajor") != 17
    ):
        raise ValueError("Format/schema non pris en charge.")
    actual = {
        str(p.relative_to(target)): sha(p)
        for p in target.rglob("*")
        if p.is_file() and p.name != "manifest.json"
    }
    if actual != manifest["sha256"]:
        raise ValueError("Intégrité de la sauvegarde invalide.")
    return target, manifest


def export(args):
    if int(sql("SHOW server_version_num")) // 10000 != 17:
        raise ValueError("PostgreSQL 17 requis pour cet export.")
    output = Path(args.output).resolve()
    if output.exists():
        raise ValueError("Le fichier de destination existe déjà.")
    output.parent.mkdir(parents=True, exist_ok=True)
    running = (
        dc("ps", "--status", "running", "--services", capture_output=True)
        .stdout.decode()
        .splitlines()
    )
    if "api" not in running:
        raise ValueError(
            "L'API doit être démarrée avant l'export (état de départ explicite)."
        )
    acquired = sql(
        "UPDATE foyer_state SET data=jsonb_set(data,'{maintenance}','true') WHERE id=1 AND data->>'maintenance'='false' RETURNING id"
    )
    if acquired != "1\nUPDATE 1" and not acquired.startswith("1\n"):
        raise ValueError(
            "Maintenance déjà active : terminer ou annuler cette opération auparavant."
        )
    try:
        # Drain all requests and stop scheduling/delivery before taking either snapshot.
        dc("stop", "-t", "45", "api")
        with tempfile.TemporaryDirectory(prefix="foyer-export-") as tmp:
            folder = Path(tmp)
            (folder / "images").mkdir()
            with (folder / "database.dump").open("xb") as dump:
                dc(
                    "exec",
                    "-T",
                    "db",
                    "pg_dump",
                    "-U",
                    "foyer",
                    "-d",
                    "foyer",
                    "-Fc",
                    "--no-owner",
                    "--no-acl",
                    stdout=dump,
                )
            dc("cp", "api:/data/images/.", str(folder / "images"))
            validate_relations(folder / "images")
            state = json.loads(
                sql(
                    "SELECT json_build_object('schema',data->'schemaVersion','tickets',jsonb_array_length(data->'tickets'),'members',jsonb_array_length(data->'members')) FROM foyer_state WHERE id=1"
                )
            )
            if state["schema"] != 1:
                raise ValueError("Version du schéma non prise en charge.")
            manifest = dict(
                format=1,
                createdAt=datetime.now(timezone.utc).isoformat(),
                appVersion="0.1.0",
                postgresMajor=17,
                **state,
            )
            files = sorted(p for p in folder.rglob("*") if p.is_file())
            manifest["sha256"] = {str(p.relative_to(folder)): sha(p) for p in files}
            (folder / "manifest.json").write_text(json.dumps(manifest, indent=2))
            plain = folder / "snapshot.tar"
            with tarfile.open(plain, "w") as tar:
                for p in files + [folder / "manifest.json"]:
                    tar.add(p, arcname=str(p.relative_to(folder)), recursive=False)
            # age refuses an existing destination; never overwrite an earlier export.
            run(["age", "-r", args.recipient, "-o", str(output), str(plain)])
            output.chmod(0o600)
            print(f'Sauvegarde chiffrée créée : {output}; {state["tickets"]} tickets.')
    except BaseException:
        maintenance(False)
        dc("start", "api")
        raise
    if not args.keep_maintenance:
        maintenance(False)
        dc("start", "api")
    else:
        print(
            "Source conservée en maintenance, API arrêtée. Ne pas la redémarrer avant arbitrage de la bascule."
        )


def restore(args):
    config = json.loads(dc("config", "--format", "json", capture_output=True).stdout)
    if (
        str(
            config["services"]["api"].get("environment", {}).get("WorkersEnabled", "")
        ).lower()
        != "false"
    ):
        raise ValueError(
            "WORKERS_ENABLED=false obligatoire sur la cible de restauration."
        )
    running = (
        dc("ps", "--status", "running", "--services", capture_output=True)
        .stdout.decode()
        .splitlines()
    )
    if "api" in running:
        raise ValueError("L'API cible doit être arrêtée et la cible doit être neuve.")
    with tempfile.TemporaryDirectory(prefix="foyer-restore-") as tmp:
        folder, manifest = unpack(args.archive, args.identity, Path(tmp))
        dc("up", "-d", "--wait", "db")
        exists = sql("SELECT COALESCE(to_regclass('public.foyer_state')::text,'')")
        if exists and sql("SELECT count(*) FROM foyer_state") != "0":
            raise ValueError(
                "Refus de remplacer une base contenant un foyer. Utiliser un nouveau projet Compose."
            )
        # Check before any database import; do not replace existing images.
        dc(
            "run",
            "--rm",
            "--no-deps",
            "--entrypoint",
            "sh",
            "api",
            "-c",
            'test -z "$(ls -A /data/images)"',
        )
        if exists:
            raise ValueError(
                "Une table existe déjà. Utiliser une base entièrement neuve."
            )
        with (folder / "database.dump").open("rb") as dump:
            dc(
                "exec",
                "-T",
                "db",
                "pg_restore",
                "-U",
                "foyer",
                "-d",
                "foyer",
                "--no-owner",
                "--no-acl",
                "--exit-on-error",
                "--single-transaction",
                stdin=dump,
            )
        # Force new authentication and prevent replay of restored push jobs/devices.
        sql(
            'UPDATE foyer_state SET data=data || \'{"sessions":[],"devices":[],"maintenance":false}\'::jsonb'
        )
        sql(
            "UPDATE foyer_state SET data=jsonb_set(data,'{notifications}',COALESCE((SELECT jsonb_agg(n || '{\"finished\":true}'::jsonb) FROM jsonb_array_elements(data->'notifications') n),'[]'::jsonb))"
        )
        dc("create", "api")
        if (folder / "images").exists():
            dc("cp", str(folder / "images") + "/.", "api:/data/images")
        dc(
            "run",
            "--rm",
            "--no-deps",
            "--user",
            "root",
            "--entrypoint",
            "chown",
            "api",
            "-R",
            "app:app",
            "/data/images",
        )
        restored = Path(tmp) / "restored-images"
        restored.mkdir()
        dc("cp", "api:/data/images/.", str(restored))
        count = validate_relations(restored)
        if count != manifest["tickets"]:
            raise ValueError("Nombre de tickets restaurés incorrect.")
        print(
            f"Restauration vérifiée : {count} tickets. API arrêtée, notifications désactivées. Démarrer et contrôler avant bascule."
        )


def main():
    if sys.version_info < (3, 12):
        raise ValueError(
            "Python 3.12 ou supérieur requis ; sélectionner PYTHON_BIN dans les wrappers."
        )
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="action", required=True)
    subs.add_parser("preflight")
    e = subs.add_parser("export")
    e.add_argument("--recipient", required=True)
    e.add_argument("--output", required=True)
    e.add_argument("--keep-maintenance", action="store_true")
    for name in ("verify", "restore"):
        p = subs.add_parser(name)
        p.add_argument("--archive", required=True)
        p.add_argument("--identity", required=True)
    subs.add_parser("resume-source")
    args = parser.parse_args()
    for binary in ("docker", "age"):
        if not shutil.which(binary):
            raise ValueError(f"Prérequis absent : {binary}")
    if args.action == "preflight":
        dc("version")
        dc("config", "--quiet")
        run(
            [
                "docker",
                "info",
                "--format",
                "Docker {{.ServerVersion}} / {{.Architecture}} / {{.OSType}}",
            ]
        )
        free = shutil.disk_usage(ROOT).free // (1024**3)
        if free < 5:
            raise ValueError("Moins de 5 Gio disponibles sur le volume de travail.")
        print(
            f"Espace hôte disponible : {free} Gio. Vérifier aussi le disque de la VM Docker et la destination des archives."
        )
        print(
            "Configuration Compose valide. Vérifier espace libre, HTTPS Tailscale, secrets et destination hors Mac dans le guide."
        )
    elif args.action == "export":
        export(args)
    elif args.action == "restore":
        restore(args)
    elif args.action == "verify":
        with tempfile.TemporaryDirectory(prefix="foyer-verify-") as tmp:
            _, manifest = unpack(args.archive, args.identity, Path(tmp))
            print(
                f'Archive authentifiée et empreintes vérifiées : {manifest["tickets"]} tickets. Tester aussi une restauration isolée.'
            )
    else:
        maintenance(False)
        dc("start", "api")
        print(
            "Source réactivée. Vérifier que la cible est arrêtée pour éviter deux sources de vérité."
        )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, OSError, KeyError) as error:
        # Do not print SQL payloads, configuration or credentials.
        print(
            f"Échec ({type(error).__name__}) : "
            + (
                str(error)
                if isinstance(error, ValueError)
                else "voir la sortie de la commande; cible conservée pour diagnostic."
            )
        )
        raise SystemExit(1)
