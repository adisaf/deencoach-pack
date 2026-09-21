#!/usr/bin/env bash
# Plafonne le débit des adhans intégraux avant leur mise en archive.
#
# Usage : ./tools/normalize-prayer-audio-sources.sh
#
# Les enregistrements reçus d'Assabile vont de 16 à 192 kbit/s, en mono comme
# en stéréo, sans logique apparente : le plus lourd pèse huit fois le plus
# léger pour une durée plus courte. Ce script ramène au plafond ceux qui le
# dépassent, et ne touche PAS ceux qui sont déjà en dessous.
#
# Le plafond est une limite haute, jamais une cible. Ré-encoder un fichier
# déjà à 16 kbit/s vers 32 le ferait grossir du double sans restaurer la
# moindre information perdue : ce serait payer deux fois, en octets et en
# qualité.
#
# La stéréo est ramenée au mono : un adhan est une voix seule, écoutée sur un
# téléphone, et le second canal ne porte rien.
#
# Ce ré-encodage est un transcodage en cascade, donc une perte. Il est assumé
# pour l'archive de pré-écoute, qui est facultative et n'a pas à imposer
# vingt-deux mégaoctets. Les amorces de notification, elles, restent découpées
# depuis les enregistrements d'origine : elles ne passent jamais par ici.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

WORK_DIR="uploads/prayer-audio/adhan-notification-excerpts"
SOURCE_DIR="${WORK_DIR}/sources"
OUTPUT_DIR="${WORK_DIR}/normalized"

BITRATE_CAP_KBPS=32
SAMPLE_RATE=22050

for command_name in ffmpeg ffprobe python3; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Erreur : '${command_name}' est requis." >&2
    exit 69
  }
done

[[ -d "${SOURCE_DIR}" ]] || {
  echo "Erreur : repertoire source absent (${SOURCE_DIR})." >&2
  exit 66
}

mkdir -p "${OUTPUT_DIR}"

kept=0
recoded=0

for source_path in "${SOURCE_DIR}"/*.mp3; do
  [[ -e "${source_path}" ]] || continue
  item_key="$(basename "${source_path}" .mp3)"
  output_path="${OUTPUT_DIR}/${item_key}.mp3"

  bitrate="$(ffprobe -v error -select_streams a:0 \
    -show_entries stream=bit_rate \
    -of default=noprint_wrappers=1:nokey=1 "${source_path}")"
  bitrate_kbps=$((bitrate / 1000))

  if [[ "${bitrate_kbps}" -le "${BITRATE_CAP_KBPS}" ]]; then
    # Déjà sous le plafond : copie des octets d'origine, sans transcodage.
    cp "${source_path}" "${output_path}"
    kept=$((kept + 1))
    printf '%-30s %4s kbit/s  conserve tel quel\n' "${item_key}" "${bitrate_kbps}"
    continue
  fi

  # `-fflags +bitexact` écarte la balise `encoder` qui porte la version de
  # ffmpeg : sans elle, deux machines produiraient des octets différents et le
  # digest publié cesserait d'être reproductible par un tiers.
  ffmpeg -hide_banner -loglevel error -y \
    -i "${source_path}" \
    -map 0:a:0 \
    -map_metadata -1 \
    -fflags +bitexact \
    -ac 1 \
    -ar "${SAMPLE_RATE}" \
    -codec:a libmp3lame \
    -b:a "${BITRATE_CAP_KBPS}k" \
    "${output_path}"

  recoded=$((recoded + 1))
  printf '%-30s %4s kbit/s  -> %s kbit/s mono, %s o -> %s o\n' \
    "${item_key}" "${bitrate_kbps}" "${BITRATE_CAP_KBPS}" \
    "$(stat -f%z "${source_path}")" "$(stat -f%z "${output_path}")"
done

# Une source disparue laisserait sa version normalisee derriere elle, et
# l'archive porterait un muezzin retire du catalogue.
for output_path in "${OUTPUT_DIR}"/*.mp3; do
  [[ -e "${output_path}" ]] || continue
  item_key="$(basename "${output_path}" .mp3)"
  [[ -f "${SOURCE_DIR}/${item_key}.mp3" ]] || {
    echo "Erreur : ${item_key}.mp3 n'a plus de source, retirez-le de ${OUTPUT_DIR}." >&2
    exit 65
  }
done

echo
printf 'normalize-prayer-audio-sources: %s reencodes, %s conserves, total %s o\n' \
  "${recoded}" "${kept}" \
  "$(python3 -c "
import pathlib
print(sum(p.stat().st_size for p in pathlib.Path('${OUTPUT_DIR}').glob('*.mp3')))
")"
