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
if [[ ! -f "${file_path}" ]]; then
  echo "Erreur : fichier introuvable : ${file_path}" >&2
  exit 66
fi

awk -F'|' '
  BEGIN { valid = 0; comments = 0; invalid = 0; first = ""; last = "" }
  /^$/ { next }
  /^#/ { comments++; next }
  NF != 3 || $1 !~ /^[1-9][0-9]*$/ || $2 !~ /^[1-9][0-9]*$/ || $3 == "" {
    invalid++
    next
  }
  {
    key = $1 "|" $2
    if (seen[key]++) duplicates++
    if (first == "") first = key
    last = key
    valid++
  }
  END {
    printf("versets=%d commentaires=%d invalides=%d doublons=%d premier=%s dernier=%s\n", valid, comments, invalid, duplicates, first, last)
    if (valid != 6236 || comments == 0 || invalid != 0 || duplicates != 0 || first != "1|1" || last != "114|6") {
      exit 1
    }
  }
' "${file_path}"
