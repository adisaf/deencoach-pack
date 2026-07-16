#!/usr/bin/env bash
#
# Vérifie la structure d'une copie verbatim Tanzil au format txt-2.
# Le fichier Tanzil contient 6 236 versets suivis de son avis de licence sous
# forme de commentaires. Les commentaires font partie de la copie autorisée et
# ne doivent pas être supprimés ou confondus avec le contenu coranique.
#
# Usage : ./tools/verify-quran-text-pack.sh <fichier.txt>

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage : $0 <fichier.txt>" >&2
  exit 64
fi

file_path="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QURAN_STRUCTURE="${REPO_ROOT}/tools/quran-structure.tsv"
if [[ ! -f "${file_path}" ]]; then
  echo "Erreur : fichier introuvable : ${file_path}" >&2
  exit 66
fi
if [[ ! -f "${QURAN_STRUCTURE}" ]]; then
  echo "Erreur : structure coranique introuvable : ${QURAN_STRUCTURE}" >&2
  exit 66
fi

awk -F'|' '
  NR == FNR {
    split($0, structureFields, /[[:space:]]+/)
    if (structureFields[1] ~ /^[1-9][0-9]*$/ && structureFields[2] ~ /^[1-9][0-9]*$/) {
      expected[structureFields[1]] = structureFields[2]
      expectedSurahs++
      expectedTotal += structureFields[2]
    }
    next
  }
  BEGIN { valid = 0; comments = 0; invalid = 0; first = ""; last = "" }
  /^$/ { next }
  /^#/ { comments++; next }
  NF != 3 || $1 !~ /^[1-9][0-9]*$/ || $2 !~ /^[1-9][0-9]*$/ || $3 == "" {
    invalid++
    next
  }
  {
    surah = $1 + 0
    ayah = $2 + 0
    key = surah "|" ayah
    if (!(surah in expected) || ayah < 1 || ayah > expected[surah]) invalid++
    if (seen[key]++) duplicates++
    if (valid > 0) {
      sameSurahSequence = surah == previousSurah && ayah == previousAyah + 1
      nextSurahSequence = surah == previousSurah + 1 && \
        previousAyah == expected[previousSurah] && ayah == 1
      if (!sameSurahSequence && !nextSurahSequence) outOfOrder++
    }
    if (first == "") first = key
    last = key
    perSurah[surah]++
    previousSurah = surah
    previousAyah = ayah
    valid++
  }
  END {
    incomplete = 0
    for (surah = 1; surah <= 114; surah++) {
      if (perSurah[surah] != expected[surah]) incomplete++
    }
    printf("versets=%d commentaires=%d invalides=%d doublons=%d ordre=%d sourates_incompletes=%d premier=%s dernier=%s\n", valid, comments, invalid, duplicates, outOfOrder, incomplete, first, last)
    if (expectedSurahs != 114 || expectedTotal != 6236 || valid != 6236 || comments == 0 || invalid != 0 || duplicates != 0 || outOfOrder != 0 || incomplete != 0 || first != "1|1" || last != "114|6") {
      exit 1
    }
  }
' "${QURAN_STRUCTURE}" "${file_path}"
