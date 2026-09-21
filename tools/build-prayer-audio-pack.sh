#!/usr/bin/env bash
# Construit les deux archives déterministes de la catégorie `prayer_audio`.
#
#   adhan_notification_sounds.zip   les amorces aux deux formats
#   adhan_sounds_hq.zip             les adhans intégraux
#
# Le découpage suit l'usage, pas la plateforme. Tout le monde a besoin des
# amorces, qui servent de son de notification et pèsent quelques mégaoctets.
# Les adhans intégraux ne servent qu'à la pré-écoute au moment de choisir un
# muezzin, pèsent le reste, et n'ont donc pas à être imposés à chacun.
# Séparer par plateforme aurait économisé moins d'un dixième du poids en
# doublant la chaîne de vérification : le gisement est ici.
#
# Chaque archive porte son propre `ATTRIBUTION.txt`. L'obligation de crédit
# suit les octets : une archive distribuée seule reste créditée.
#
# Déterminisme : ordre des entrées trié, horodatage figé, aucun attribut
# externe. Deux exécutions sur les mêmes octets d'entrée produisent le même
# SHA-256, ce qui rend chaque digest publié reproductible par un tiers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

WORK_DIR="uploads/prayer-audio/adhan-notification-excerpts"
SOURCE_DIR="${WORK_DIR}/sources"
EXCERPT_DIR="${WORK_DIR}/excerpts"
ATTRIBUTION_FILE="${WORK_DIR}/ATTRIBUTION.txt"
NOTIFICATION_ARCHIVE="uploads/prayer-audio/adhan_notification_sounds.zip"
FULL_LENGTH_ARCHIVE="uploads/prayer-audio/adhan_sounds_hq.zip"
CUTS_FILE="provenance/prayer-audio-adhan-notification/excerpt_cuts.json"

# Horodatage figé des entrées. Toute autre valeur casserait la reproductibilité
# des SHA-256 publiés sans rien apporter.
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
  "${NOTIFICATION_ARCHIVE}" "${FULL_LENGTH_ARCHIVE}" "${CUTS_FILE}" \
  "${FIXED_TIMESTAMP}" <<'PY'
import hashlib
import json
import sys
import zipfile
from datetime import datetime
from pathlib import Path

(source_dir, excerpt_dir, attribution_file, notification_archive,
 full_length_archive, cuts_file, fixed_timestamp) = (
    Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
    Path(sys.argv[4]), Path(sys.argv[5]), Path(sys.argv[6]), sys.argv[7],
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
notification_entries = {"ATTRIBUTION.txt": attribution_file}
full_length_entries = {"ATTRIBUTION.txt": attribution_file}
missing = []

for item_key in item_keys:
    full_length = source_dir / f"{item_key}.mp3"
    if not full_length.exists():
        missing.append(f"{item_key} : adhan integral absent de {source_dir}")
        continue
    full_length_entries[full_length.name] = full_length
    for suffix in (".caf", ".mp3"):
        excerpt = excerpt_dir / f"{item_key}_intro{suffix}"
        if not excerpt.exists():
            missing.append(f"{item_key} : amorce {suffix} absente de {excerpt_dir}")
            continue
        notification_entries[excerpt.name] = excerpt

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


def build(archive_path, entries, label):
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
    print(f"=== {label} ===")
    print(f"archive           {archive_path}")
    print(f"fileCount         {len(entries)}")
    print(f"sizeCompressed    {archive_path.stat().st_size}")
    print(f"sizeUncompressed  {uncompressed}")
    print(f"sha256            {digest}")


build(notification_archive, notification_entries, "sons de notification, requis")
build(full_length_archive, full_length_entries, "adhans integraux, optionnel")
PY
