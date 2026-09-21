#!/usr/bin/env bash
# Construit l'archive déterministe unique de la catégorie `prayer_audio`.
#
#   adhan_sounds_hq.zip   les adhans intégraux et leurs amorces de notification
#
# Le pack avait été découpé en deux archives en v1.0.0, l'une requise et
# l'autre facultative, pour épargner vingt-deux mégaoctets à qui ne voulait
# qu'un son de notification. Le plafonnement des débits à 32 kbit/s ayant
# ramené les intégraux de 22,7 à 8,5 Mo, le propriétaire produit a choisi en
# v1.1.0 de revenir à une archive unique : un seul téléchargement, un seul
# digest, un seul installateur.
#
# Disposition :
#   <cle>.mp3                     l'adhan intégral, pour la pré-écoute
#   notification/<cle>_intro.caf  l'amorce iOS
#   notification/<cle>_intro.mp3  l'amorce Android
#   ATTRIBUTION.txt               le crédit, qui voyage avec les octets
#
# Les intégraux proviennent de `normalized/`, où les débits ont été plafonnés.
# Les amorces proviennent de `excerpts/`, découpées depuis les enregistrements
# d'origine et non depuis les versions ré-encodées : le son joué à l'heure de
# la prière ne subit aucune cascade de transcodage.
#
# Déterminisme : ordre des entrées trié, horodatage figé, aucun attribut
# externe. Deux exécutions sur les mêmes octets d'entrée produisent le même
# SHA-256, ce qui rend le digest publié reproductible par un tiers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

WORK_DIR="uploads/prayer-audio/adhan-notification-excerpts"
SOURCE_DIR="${WORK_DIR}/normalized"
EXCERPT_DIR="${WORK_DIR}/excerpts"
ATTRIBUTION_FILE="${WORK_DIR}/ATTRIBUTION.txt"
ARCHIVE_PATH="uploads/prayer-audio/adhan_sounds_hq.zip"
CUTS_FILE="provenance/prayer-audio-adhan-notification/excerpt_cuts.json"

# Horodatage figé des entrées. Toute autre valeur casserait la reproductibilité
# du SHA-256 publié sans rien apporter.
FIXED_TIMESTAMP="2026-09-21 00:00:00"

command -v python3 >/dev/null 2>&1 || {
  echo "Erreur : 'python3' est requis." >&2
  exit 69
}

for required in "${ATTRIBUTION_FILE}" "${CUTS_FILE}"; do
  [[ -f "${required}" ]] || {
    echo "Erreur : fichier requis absent (${required})." >&2
    exit 66
  }
done

python3 - "${SOURCE_DIR}" "${EXCERPT_DIR}" "${ATTRIBUTION_FILE}" \
  "${ARCHIVE_PATH}" "${CUTS_FILE}" "${FIXED_TIMESTAMP}" <<'PY'
import hashlib
import json
import sys
import zipfile
from datetime import datetime
from pathlib import Path

(source_dir, excerpt_dir, attribution_file, archive_path,
 cuts_file, fixed_timestamp) = (
    Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
    Path(sys.argv[4]), Path(sys.argv[5]), sys.argv[6],
)

moment = datetime.strptime(fixed_timestamp, "%Y-%m-%d %H:%M:%S")
date_time = (moment.year, moment.month, moment.day,
             moment.hour, moment.minute, moment.second)

with cuts_file.open(encoding="utf-8") as handle:
    item_keys = sorted(json.load(handle))

if not item_keys:
    raise SystemExit(f"Erreur : aucun point de coupe dans {cuts_file}.")

# Les clés sont l'unique référence : un intégral sans coupe enregistrée, ou une
# coupe sans intégral, est une incohérence qu'il vaut mieux voir ici qu'à
# l'installation.
entries = {"ATTRIBUTION.txt": attribution_file}
missing = []

for item_key in item_keys:
    full_length = source_dir / f"{item_key}.mp3"
    if not full_length.exists():
        missing.append(
            f"{item_key} : adhan integral absent de {source_dir}, "
            "lancez normalize-prayer-audio-sources.sh"
        )
        continue
    entries[full_length.name] = full_length
    for suffix in (".caf", ".mp3"):
        excerpt = excerpt_dir / f"{item_key}_intro{suffix}"
        if not excerpt.exists():
            missing.append(f"{item_key} : amorce {suffix} absente de {excerpt_dir}")
            continue
        entries[f"notification/{excerpt.name}"] = excerpt

stray = sorted(
    path.stem for path in source_dir.glob("*.mp3") if path.stem not in item_keys
)
for item_key in stray:
    missing.append(f"{item_key} : source sans point de coupe enregistre")

if missing:
    print("Erreur : contenu incomplet, aucune archive produite.", file=sys.stderr)
    for problem in missing:
        print(f"  - {problem}", file=sys.stderr)
    raise SystemExit(65)

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
print(f"muezzins          {len(item_keys)} adhans, {2 * len(item_keys)} amorces")
print(f"fileCount         {len(entries)}")
print(f"sizeCompressed    {archive_path.stat().st_size}")
print(f"sizeUncompressed  {uncompressed}")
print(f"sha256            {digest}")
PY
