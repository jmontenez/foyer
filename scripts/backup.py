#!/usr/bin/env python3
"""Sauvegarde quotidienne ; conserve les 7 derniers jours et 4 semaines distinctes."""

import argparse
import re
import subprocess
import sys
from datetime import date as Date
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--destination", required=True, help="Dossier dédié, idéalement hors Mac"
)
parser.add_argument(
    "--recipient", required=True, help="Clé publique age, jamais la clé privée"
)
args = parser.parse_args()
folder = Path(args.destination).resolve()
if not folder.is_dir():
    raise SystemExit("La destination doit exister et être montée avant la sauvegarde.")
now = datetime.now(timezone.utc)
output = folder / now.strftime("foyer-%Y%m%dT%H%M%SZ.age")
script = Path(__file__).resolve().parent / "migration/foyer.py"
subprocess.run(
    [
        sys.executable,
        str(script),
        "export",
        "--recipient",
        args.recipient,
        "--output",
        str(output),
    ],
    check=True,
)
# Only application-owned, timestamped archives are eligible; no glob-wide cleanup.
archives = sorted(
    (
        p
        for p in folder.iterdir()
        if p.is_file()
        and not p.is_symlink()
        and re.fullmatch(r"foyer-\d{8}T\d{6}Z\.age", p.name)
    ),
    reverse=True,
)
keep = set()
days: set[Date] = set()
weeks: set[tuple[int, int]] = set()
for p in archives:
    date = datetime.strptime(p.name, "foyer-%Y%m%dT%H%M%SZ.age").replace(
        tzinfo=timezone.utc
    )
    day = date.date()
    week = date.isocalendar()[:2]
    if day not in days and len(days) < 7:
        keep.add(p)
        days.add(day)
    if week not in weeks and len(weeks) < 4:
        keep.add(p)
        weeks.add(week)
for p in archives:
    if p not in keep:
        p.unlink()
print(
    f"Sauvegarde terminée ; {len(keep)} archives conservées. Tester régulièrement leur restauration."
)
