#!/usr/bin/env python3
"""Exercice réel PostgreSQL + volumes + age, instances jetables sans identité externe."""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STAMP = str(int(time.time()))
WORK = ROOT / "artifacts" / ("migration-" + STAMP)
WORK.mkdir(parents=True, mode=0o700)
ENV = dict(
    os.environ,
    DOCKER_CONTEXT="colima-foyer",
    FOYER_COMPOSE_FILE=str(ROOT / "scripts/tests/compose.migration.yaml"),
)
SCRIPT = str(ROOT / "scripts/migration/foyer.py")
source = "foyer-export-" + STAMP
target = "foyer-restore-" + STAMP


def run(args, **kwargs):
    return subprocess.run(args, check=True, env=ENV, **kwargs)


def dc(project, *args, **kwargs):
    return run(
        ["docker", "compose", "-f", ENV["FOYER_COMPOSE_FILE"], "-p", project, *args],
        **kwargs
    )


def migration(project, *args, ok=True):
    p = subprocess.run(
        [sys.executable, SCRIPT, *args],
        env=dict(ENV, FOYER_PROJECT=project),
        check=False,
    )
    assert (p.returncode == 0) == ok


identity = WORK / "test-identity.agekey"
# Ephemeral test key stays on disk; it is never displayed or embedded in source.
run(["age-keygen", "-o", str(identity)], stderr=subprocess.DEVNULL)
recipient = (
    run(["age-keygen", "-y", str(identity)], capture_output=True)
    .stdout.decode()
    .strip()
)
try:
    dc(source, "up", "-d", "--wait", "db")
    with (WORK / "seed.dump").open("wb") as dump:
        run(
            [
                "docker",
                "exec",
                "foyer-test-db",
                "pg_dump",
                "-U",
                "postgres",
                "-d",
                "foyer_test",
                "-Fc",
                "--no-owner",
            ],
            stdout=dump,
        )
    with (WORK / "seed.dump").open("rb") as seed_input:
        dc(
            source,
            "exec",
            "-T",
            "db",
            "pg_restore",
            "-U",
            "foyer",
            "-d",
            "foyer",
            "--no-owner",
            stdin=seed_input,
        )
    dc(source, "create", "api")
    dc(source, "cp", str(ROOT / "artifacts/test-images") + "/.", "api:/data/images")
    dc(
        source,
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
    dc(source, "start", "api")
    archive = str(WORK / "snapshot.age")
    outage_start = time.monotonic()
    migration(
        source,
        "export",
        "--recipient",
        recipient,
        "--output",
        archive,
        "--keep-maintenance",
    )
    migration(source, "verify", "--identity", str(identity), "--archive", archive)
    migration(target, "restore", "--identity", str(identity), "--archive", archive)
    # Same ciphertext cannot be restored over a populated target.
    migration(
        target, "restore", "--identity", str(identity), "--archive", archive, ok=False
    )
    dc(target, "start", "api")
    time.sleep(3)
    dc(target, "exec", "-T", "api", "/app/Foyer.Api", "--healthcheck")
    report = dc(
        target,
        "exec",
        "-T",
        "db",
        "psql",
        "-U",
        "foyer",
        "-d",
        "foyer",
        "-Atc",
        "SELECT json_build_object('tickets',jsonb_array_length(data->'tickets'),'sessions',jsonb_array_length(data->'sessions'),'devices',jsonb_array_length(data->'devices'),'pending', (SELECT count(*) FROM jsonb_array_elements(data->'notifications') n WHERE n->>'finished'='false')) FROM foyer_state",
        capture_output=True,
    ).stdout.decode()
    counts = json.loads(report)
    assert (
        counts["tickets"] > 0
        and counts["sessions"] == counts["devices"] == counts["pending"] == 0
    )
    (WORK / "report.json").write_text(json.dumps(counts, indent=2))
    dc(target, "stop", "api")
    migration(source, "resume-source")
    time.sleep(2)
    dc(source, "exec", "-T", "api", "/app/Foyer.Api", "--healthcheck")
    counts["sourceInterruptionSeconds"] = round(time.monotonic() - outage_start, 2)
    (WORK / "report.json").write_text(json.dumps(counts, indent=2))
    # Authentication tag rejects a corrupted export.
    corrupted = WORK / "corrupted.age"
    data = bytearray(Path(archive).read_bytes())
    data[-10] ^= 1
    corrupted.write_bytes(data)
    migration(
        source,
        "verify",
        "--identity",
        str(identity),
        "--archive",
        str(corrupted),
        ok=False,
    )
    print(
        "PASS : export chiffré, intégrité, restauration vierge, refus écrasement, API cible, sessions révoquées, aucun push, retour arrière, archive corrompue rejetée."
    )
finally:
    dc(source, "stop")
    dc(target, "stop")
    print("Instances de test arrêtées, volumes conservés :", source, target)
