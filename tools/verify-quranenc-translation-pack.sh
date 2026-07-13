#!/usr/bin/env bash
# Vérifie chaque réponse QuranEnc locale contre le manifest signé généré.
# Usage : ./tools/verify-quranenc-translation-pack.sh <pack-id>

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACK_ID="${1:?Usage: verify-quranenc-translation-pack.sh <pack-id>}"
MANIFEST="${REPO_ROOT}/signed-manifests/quran-translations/${PACK_ID}.json"
PACK_DIR="${REPO_ROOT}/uploads/quranenc-translations/${PACK_ID}"

for command in jq shasum wc; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

[[ -f "${MANIFEST}" && -d "${PACK_DIR}" ]] || {
  echo "Erreur : manifest ou données absents pour ${PACK_ID}." >&2
  exit 1
}

artifact_count=$(jq '.artifacts | length' "${MANIFEST}")
[[ "${artifact_count}" = '114' ]] || {
  echo "Erreur : ${PACK_ID} doit contenir 114 sourates, trouvé ${artifact_count}." >&2
  exit 1
}

checked=0
while IFS=$'\t' read -r item_key file_name expected_sha expected_bytes; do
  file_path="${PACK_DIR}/${file_name}"
  [[ -f "${file_path}" ]] || {
    echo "Erreur : artefact absent : ${file_name}" >&2
    exit 1
  }
  actual_sha=$(shasum -a 256 "${file_path}" | awk '{print $1}')
  actual_bytes=$(wc -c < "${file_path}" | tr -d ' ')
  [[ "${actual_sha}" = "${expected_sha}" && "${actual_bytes}" = "${expected_bytes}" ]] || {
    echo "Erreur : intégrité invalide : ${file_name}" >&2
    exit 1
  }
  expected_surah=$((10#${item_key#surah_}))
  jq -e --arg surah "${expected_surah}" '
    (.result | type == "array" and length > 0) and
    ([.result[] | .sura == $surah] | all)
  ' "${file_path}" >/dev/null || {
    echo "Erreur : contenu QuranEnc incohérent : ${file_name}" >&2
    exit 1
  }
  checked=$((checked + 1))
done < <(
  jq -r '.artifacts[] | [.itemKey, .fileName, .sha256, (.expectedBytes | tostring)] | @tsv' \
    "${MANIFEST}"
)

echo "${PACK_ID}: ${checked}/114 sourates, SHA-256 et numéros vérifiés"
