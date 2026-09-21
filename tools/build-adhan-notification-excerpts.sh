#!/usr/bin/env bash
# Encode les amorces de notification du pack `adhan_sounds_hq` aux deux formats
# imposés par les plateformes, à partir de points de coupe déjà arrêtés.
#
# Ce script n'analyse AUCUN silence et ne propose AUCUNE coupe. Les points de
# coupe sont une donnée d'entrée figée, versionnée dans
# `provenance/prayer-audio-adhan-notification/excerpt_cuts.json`, produite en
# amont par `tools/adhan/build_notification_excerpts.py` du dépôt applicatif.
# Recalculer une coupe ici créerait une seconde autorité sur une décision
# religieuse déjà tranchée et déjà écoutée.
#
# Règle de coupe (ADR TICKET-191, décision 2) : l'amorce s'arrête sur une unité
# de sens complète, le takbir d'ouverture, sur un silence, jamais en plein mot.
# Ce script ne peut pas vérifier cette règle. L'écoute humaine reste due.
#
# Contrainte iOS : un son de notification doit être `.caf`, `.aiff` ou `.wav` et
# durer moins de 30 secondes. Un MP3, ou un fichier plus long, est ignoré en
# silence et l'appareil joue le son par défaut.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

WORK_DIR="uploads/prayer-audio/adhan-notification-excerpts"
SOURCE_DIR="${WORK_DIR}/sources"
OUTPUT_DIR="${WORK_DIR}/excerpts"
CUTS_FILE="provenance/prayer-audio-adhan-notification/excerpt_cuts.json"

SAMPLE_RATE=22050
MP3_BITRATE=64k
MAX_SECONDS=30
DURATION_TOLERANCE=0.15

for command_name in ffmpeg ffprobe afconvert afinfo python3 shasum; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Erreur : '${command_name}' est requis." >&2
    exit 69
  }
done

[[ -f "${CUTS_FILE}" ]] || {
  echo "Erreur : points de coupe absents (${CUTS_FILE})." >&2
  exit 66
}

# `mapfile` n'existe pas dans le bash 3.2 livré par macOS.
item_keys=()
while IFS= read -r item_key; do
  item_keys+=("${item_key}")
done < <(python3 -c "
import json
with open('${CUTS_FILE}', encoding='utf-8') as handle:
    for key in sorted(json.load(handle)):
        print(key)
")

[[ "${#item_keys[@]}" -gt 0 ]] || {
  echo "Erreur : aucun point de coupe dans ${CUTS_FILE}." >&2
  exit 65
}

mkdir -p "${OUTPUT_DIR}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT HUP INT TERM

read_cut_seconds() {
  python3 -c "
import json, sys
with open('${CUTS_FILE}', encoding='utf-8') as handle:
    print(json.load(handle)['$1']['cutSeconds'])
"
}

assert_within_tolerance() {
  python3 -c "
import sys
measured, expected, tolerance, label = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
if abs(measured - expected) > tolerance:
    raise SystemExit(f'{label} : durée mesurée {measured:.2f}s, coupe attendue {expected:.2f}s')
if measured >= ${MAX_SECONDS}:
    raise SystemExit(f'{label} : durée {measured:.2f}s, la limite iOS est ${MAX_SECONDS}s')
" "$1" "$2" "${DURATION_TOLERANCE}" "$3"
}

for item_key in "${item_keys[@]}"; do
  source_path="${SOURCE_DIR}/${item_key}.mp3"
  [[ -f "${source_path}" ]] || {
    echo "Erreur : source intégrale absente (${source_path})." >&2
    exit 66
  }

  cut_seconds="$(read_cut_seconds "${item_key}")"
  python3 -c "
cut = float('${cut_seconds}')
if not 0 < cut < ${MAX_SECONDS}:
    raise SystemExit('${item_key} : cutSeconds=${cut_seconds} hors de ]0, ${MAX_SECONDS}[')
"

  mp3_path="${OUTPUT_DIR}/${item_key}_intro.mp3"
  caf_path="${OUTPUT_DIR}/${item_key}_intro.caf"
  wav_path="${temporary_dir}/${item_key}_intro.wav"

  # Android : MP3 mono 22050 Hz 64 kbit/s. `-map_metadata -1` écarte les
  # balises ID3 de la source, qui n'ont pas à voyager dans le pack : elles
  # nomment un site tiers, un logiciel de montage et un titre arabe.
  # `-fflags +bitexact` écarte en plus la balise `encoder` que ffmpeg inscrit
  # de lui-même, et qui porte son numéro de version : sans cela, deux machines
  # aux versions différentes produiraient des octets différents à partir du
  # même flux audio, et le digest publié cesserait d'être reproductible par un
  # tiers.
  ffmpeg -hide_banner -loglevel error -y \
    -i "${source_path}" \
    -map 0:a:0 \
    -t "${cut_seconds}" \
    -map_metadata -1 \
    -fflags +bitexact \
    -ac 1 \
    -ar "${SAMPLE_RATE}" \
    -codec:a libmp3lame \
    -b:a "${MP3_BITRATE}" \
    "${mp3_path}"

  # iOS : CAF/ima4 mono 22050 Hz, via un WAV intermédiaire car `afconvert`
  # n'ouvre pas directement le MP3 source.
  ffmpeg -hide_banner -loglevel error -y \
    -i "${source_path}" \
    -map 0:a:0 \
    -t "${cut_seconds}" \
    -map_metadata -1 \
    -fflags +bitexact \
    -ac 1 \
    -ar "${SAMPLE_RATE}" \
    "${wav_path}"
  afconvert -f caff -d ima4 -c 1 "${wav_path}" "${caf_path}"
  rm -f "${wav_path}"

  mp3_duration="$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "${mp3_path}")"
  assert_within_tolerance "${mp3_duration}" "${cut_seconds}" "${item_key} mp3"

  caf_info="$(afinfo "${caf_path}")"
  python3 -c "
import re, sys
text = sys.stdin.read()
duration = re.search(r'estimated duration:\s*([\d.]+)\s*sec', text)
data_format = re.search(r'Data format:\s*(\d+)\s*ch,\s*(\d+)\s*Hz,\s*(\S+)', text)
if duration is None or data_format is None:
    raise SystemExit('${item_key} caf : sortie afinfo illisible')
channels, sample_rate, codec = int(data_format.group(1)), int(data_format.group(2)), data_format.group(3)
if codec != 'ima4':
    raise SystemExit(f'${item_key} caf : codec {codec}, attendu ima4')
if channels != 1:
    raise SystemExit(f'${item_key} caf : {channels} canaux, attendu 1')
if sample_rate != ${SAMPLE_RATE}:
    raise SystemExit(f'${item_key} caf : {sample_rate} Hz, attendu ${SAMPLE_RATE}')
print(duration.group(1))
" <<< "${caf_info}" > "${temporary_dir}/caf_duration"
  assert_within_tolerance "$(cat "${temporary_dir}/caf_duration")" "${cut_seconds}" "${item_key} caf"

  printf '%-24s coupe %6.2fs  mp3 %7s o  caf %7s o\n' \
    "${item_key}" "${cut_seconds}" \
    "$(stat -f%z "${mp3_path}")" "$(stat -f%z "${caf_path}")"
done

echo
echo "build-adhan-notification-excerpts: ${#item_keys[@]} amorces produites aux deux formats dans ${OUTPUT_DIR}"
echo "L'écoute humaine de chaque amorce reste due avant toute publication."
