#!/usr/bin/env bash
# Vérifie le contenu d'une archive `prayer_audio` avant publication.
#
# Usage : ./tools/verify-prayer-audio-pack.sh <archive.zip>
#
# Un SHA-256 prouve que l'archive n'a pas été altérée ; il ne prouve pas que
# son contenu est jouable. Ce script contrôle ce que le digest ignore : que
# chaque muezzin a bien son adhan intégral et ses deux amorces, que les
# amorces respectent les formats exigés par les plateformes, et qu'aucune
# n'atteint la limite de 30 secondes au-delà de laquelle iOS ignore un son de
# notification en silence.
#
# Ce script ne porte aucun jugement sur ce qui est entendu. La règle de coupe
# de l'ADR TICKET-191, une unité de sens complète arrêtée sur un silence, ne
# se vérifie qu'à l'oreille humaine.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-}"

SAMPLE_RATE=22050
MAX_SECONDS=30
ATTRIBUTION_ENTRY="ATTRIBUTION.txt"

[[ -n "${ARCHIVE_PATH}" ]] || {
  echo 'Usage : verify-prayer-audio-pack.sh <archive.zip>' >&2
  exit 64
}
[[ -f "${ARCHIVE_PATH}" ]] || {
  echo "Erreur : archive absente : ${ARCHIVE_PATH}" >&2
  exit 66
}

for command_name in afinfo ffprobe python3 unzip; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Erreur : '${command_name}' est requis." >&2
    exit 69
  }
done

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT HUP INT TERM

unzip -q "${ARCHIVE_PATH}" -d "${work_dir}"

problems=()

[[ -f "${work_dir}/${ATTRIBUTION_ENTRY}" ]] || {
  problems+=("${ATTRIBUTION_ENTRY} absent : l'attribution voyage avec l'archive")
}

full_length_count=0
for source_path in "${work_dir}"/adhan_*.mp3; do
  [[ -e "${source_path}" ]] || continue
  full_length_count=$((full_length_count + 1))
  item_key="$(basename "${source_path}" .mp3)"

  mp3_excerpt="${work_dir}/notification/${item_key}_intro.mp3"
  caf_excerpt="${work_dir}/notification/${item_key}_intro.caf"

  if [[ ! -f "${mp3_excerpt}" ]]; then
    problems+=("${item_key} : amorce Android absente")
  else
    mp3_duration="$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "${mp3_excerpt}")"
    python3 -c "
import sys
duration = float(sys.argv[1])
if duration >= ${MAX_SECONDS}:
    print(f'${item_key} : amorce mp3 de {duration:.2f}s, la limite est ${MAX_SECONDS}s')
" "${mp3_duration}" >> "${work_dir}/problems" || true
  fi

  if [[ ! -f "${caf_excerpt}" ]]; then
    problems+=("${item_key} : amorce iOS absente")
  else
    # `ffprobe` n'ouvre pas l'ima4 et rendrait une durée nulle : seul `afinfo`
    # lit correctement un CAF encodé ainsi.
    afinfo "${caf_excerpt}" | python3 -c "
import re, sys
text = sys.stdin.read()
duration = re.search(r'estimated duration:\s*([\d.]+)\s*sec', text)
data_format = re.search(r'Data format:\s*(\d+)\s*ch,\s*(\d+)\s*Hz,\s*(\S+)', text)
if duration is None or data_format is None:
    print('${item_key} : sortie afinfo illisible pour l\'amorce caf')
    raise SystemExit(0)
channels, sample_rate, codec = int(data_format.group(1)), int(data_format.group(2)), data_format.group(3)
if codec != 'ima4':
    print(f'${item_key} : codec caf {codec}, attendu ima4')
if channels != 1:
    print(f'${item_key} : {channels} canaux dans le caf, attendu 1')
if sample_rate != ${SAMPLE_RATE}:
    print(f'${item_key} : {sample_rate} Hz dans le caf, attendu ${SAMPLE_RATE}')
if float(duration.group(1)) >= ${MAX_SECONDS}:
    print(f'${item_key} : amorce caf de {float(duration.group(1)):.2f}s, la limite est ${MAX_SECONDS}s')
" >> "${work_dir}/problems" || true
  fi
done

[[ "${full_length_count}" -gt 0 ]] || {
  problems+=("aucun adhan intégral à la racine de l'archive")
}

excerpt_count=0
if [[ -d "${work_dir}/notification" ]]; then
  excerpt_count="$(find "${work_dir}/notification" -type f \
    \( -name '*.caf' -o -name '*.mp3' \) | wc -l | tr -d ' ')"
fi
expected_excerpts=$((full_length_count * 2))
[[ "${excerpt_count}" -eq "${expected_excerpts}" ]] || {
  problems+=("${excerpt_count} amorces pour ${full_length_count} adhans, ${expected_excerpts} attendues")
}

if [[ -s "${work_dir}/problems" ]]; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] && problems+=("${line}")
  done < "${work_dir}/problems"
fi

if [[ "${#problems[@]}" -gt 0 ]]; then
  echo "verify-prayer-audio-pack: ${ARCHIVE_PATH}" >&2
  for problem in "${problems[@]}"; do
    echo "  - ${problem}" >&2
  done
  exit 1
fi

echo "verify-prayer-audio-pack: OK, ${full_length_count} adhans et ${excerpt_count} amorces conformes"
echo "L'écoute humaine de chaque amorce reste due : aucun contrôle ici ne porte sur ce qui est entendu."
