#!/usr/bin/env bash
# Construit l'archive déterministe du pack `adhan_sounds_hq`.
#
# Contenu : les huit adhans intégraux, les seize amorces de notification
# produites par `tools/build-adhan-notification-excerpts.sh`, et le fichier
# d'attribution obligatoire.
#
# Déterminisme : ordre des entrées trié, horodatage figé, aucun attribut
# externe. Deux exécutions sur les mêmes octets d'entrée produisent le même
# SHA-256, ce qui rend le digest publié reproductible par un tiers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

WORK_DIR="uploads/prayer-audio/adhan-notification-excerpts"
SOURCE_DIR="${WORK_DIR}/sources"
EXCERPT_DIR="${WORK_DIR}/excerpts"
ATTRIBUTION_FILE="${WORK_DIR}/ATTRIBUTION.txt"
ARCHIVE_PATH="uploads/prayer-audio/adhan_sounds_hq.zip"

# Horodatage figé des entrées de l'archive. Toute autre valeur casserait la
# reproductibilité du SHA-256 publié sans rien apporter.
FIXED_TIMESTAMP="2026-09-21 00:00:00"

command -v python3 >/dev/null 2>&1 || {
  echo "Erreur : 'python3' est requis." >&2
  exit 69
}

[[ -f "${ATTRIBUTION_FILE}" ]] || {
  echo "Erreur : fichier d'attribution absent (${ATTRIBUTION_FILE})." >&2
  exit 66
}

python3 - "${SOURCE_DIR}" "${EXCERPT_DIR}" "${ATTRIBUTION_FILE}" "${ARCHIVE_PATH}" "${FIXED_TIMESTAMP}" <<'PY'
import hashlib
import sys
import zipfile
from datetime import datetime
from pathlib import Path

source_dir, excerpt_dir, attribution_file, archive_path, fixed_timestamp = (
    Path(sys.argv[1]),
    Path(sys.argv[2]),
    Path(sys.argv[3]),
    Path(sys.argv[4]),
    sys.argv[5],
)

moment = datetime.strptime(fixed_timestamp, "%Y-%m-%d %H:%M:%S")
date_time = (moment.year, moment.month, moment.day, moment.hour, moment.minute, moment.second)

# `entries` associe le chemin dans l'archive au fichier sur disque. La
# disposition suit `docs/CATEGORIES.md` pour la catégorie `prayer_audio` :
# les intégraux à la racine, les amorces de notification dans `notification/`.
entries: dict[str, Path] = {"ATTRIBUTION.txt": attribution_file}

full_length = sorted(source_dir.glob("*.mp3"))
if not full_length:
    raise SystemExit(f"Erreur : aucun adhan intégral dans {source_dir}.")
for path in full_length:
    entries[path.name] = path

for path in sorted(excerpt_dir.iterdir()):
    if path.suffix not in {".caf", ".mp3"}:
        continue
    entries[f"notification/{path.name}"] = path

expected = 2 * len(full_length)
produced = sum(1 for name in entries if name.startswith("notification/"))
if produced != expected:
    raise SystemExit(
        f"Erreur : {produced} amorces pour {len(full_length)} adhans intégraux, "
        f"{expected} attendues. Relancez build-adhan-notification-excerpts.sh."
    )

archive_path.parent.mkdir(parents=True, exist_ok=True)
uncompressed = 0
with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(entries):
        payload = entries[name].read_bytes()
        uncompressed += len(payload)
        info = zipfile.ZipInfo(name, date_time=date_time)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info, payload)

digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
print(f"archive           {archive_path}")
print(f"fileCount         {len(entries)}")
print(f"sizeCompressed    {archive_path.stat().st_size}")
print(f"sizeUncompressed  {uncompressed}")
print(f"sha256            {digest}")
PY
