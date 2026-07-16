#!/usr/bin/env bash
# Vérifie chaque réponse QuranEnc locale contre le manifest signé généré.
# Usage : ./tools/verify-quranenc-translation-pack.sh <pack-id> [manifest-candidat]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACK_ID="${1:?Usage: verify-quranenc-translation-pack.sh <pack-id>}"
MANIFEST_OVERRIDE="${2:-}"
ACTIVE_INDEX="${REPO_ROOT}/signed-manifests/active-revisions.json"
SIGNED_ROOT="${REPO_ROOT}/signed-manifests"
PACK_DIR="${REPO_ROOT}/uploads/quranenc-translations/${PACK_ID}"
QURAN_STRUCTURE="${REPO_ROOT}/tools/quran-structure.tsv"

for command in awk jq python3 shasum wc; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

[[ -d "${PACK_DIR}" && -f "${QURAN_STRUCTURE}" ]] || {
  echo "Erreur : données absentes pour ${PACK_ID}." >&2
  exit 1
}
if [[ -n "${MANIFEST_OVERRIDE}" ]]; then
  MANIFEST="$(python3 - "${SIGNED_ROOT}" "${MANIFEST_OVERRIDE}" <<'PY'
from pathlib import Path
import os
import sys

root = Path(sys.argv[1]).resolve()
candidate = Path(sys.argv[2])
if not candidate.is_absolute():
    candidate = Path.cwd() / candidate
candidate = candidate.resolve()
if os.path.commonpath((str(root), str(candidate))) != str(root):
    raise SystemExit('Erreur : manifest candidat hors du registre signé.')
print(candidate)
PY
  )"
else
  [[ -f "${ACTIVE_INDEX}" ]] || {
    echo 'Erreur : registre actif absent.' >&2
    exit 1
  }
  manifest_relative_path=$(jq -r --arg pack_id "${PACK_ID}" \
    '.revisions[] | select(.packId == $pack_id) | .manifest' \
    "${ACTIVE_INDEX}")
  [[ -n "${manifest_relative_path}" ]] || {
    echo "Erreur : aucune révision active pour ${PACK_ID}." >&2
    exit 1
  }
  MANIFEST="${SIGNED_ROOT}/${manifest_relative_path}"
fi
[[ -f "${MANIFEST}" ]] || {
  echo "Erreur : manifest absent pour ${PACK_ID}." >&2
  exit 1
}
jq -e --arg pack_id "${PACK_ID}" '.packId == $pack_id' "${MANIFEST}" \
  >/dev/null || {
  echo "Erreur : manifest incohérent pour ${PACK_ID}." >&2
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
  expected_ayah_count=$(awk -v surah="${expected_surah}" \
    '$1 == surah { print $2 }' "${QURAN_STRUCTURE}")
  [[ -n "${expected_ayah_count}" ]] || {
    echo "Erreur : structure coranique absente pour la sourate ${expected_surah}." >&2
    exit 1
  }
  jq -e --arg surah "${expected_surah}" \
    --argjson expected_count "${expected_ayah_count}" '
    (.result | type == "array" and length == $expected_count) and
    ([.result[] | (.sura | tostring) == $surah] | all) and
    ([.result[] | (.aya | tonumber)] == [range(1; $expected_count + 1)]) and
    ([.result[] | (.aya | tonumber)] | sort == [range(1; $expected_count + 1)]) and
    ([.result[] | (.translation | type == "string" and length > 0)] | all)
  ' "${file_path}" >/dev/null || {
    echo "Erreur : contenu QuranEnc incohérent : ${file_name}" >&2
    exit 1
  }
  checked=$((checked + 1))
done < <(
  jq -r '.artifacts[] | [.itemKey, .fileName, .sha256, (.expectedBytes | tostring)] | @tsv' \
    "${MANIFEST}"
)

echo "${PACK_ID}: ${checked}/114 sourates, SHA-256 et couverture canonique vérifiés"
