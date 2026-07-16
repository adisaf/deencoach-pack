#!/usr/bin/env bash
#
# validate-manifests.sh
#
# Valide les invariants de publication sans télécharger d'artefact : JSON
# parseable, SHA-256 publié, URL HTTPS et métadonnées obligatoires.
#
# Usage : ./tools/validate-manifests.sh [category] [pack] [--require-provenance|--allow-quarantined]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
CATEGORY_FILTER="${1:-}"
PACK_FILTER="${2:-}"
VALIDATION_MODE="${3:-}"

if [[ -n "${VALIDATION_MODE}" &&
    "${VALIDATION_MODE}" != "--require-provenance" &&
    "${VALIDATION_MODE}" != "--allow-quarantined" ]]; then
  echo "Erreur : troisième argument invalide : ${VALIDATION_MODE}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Erreur : 'jq' est requis." >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

validate_manifest() {
  local manifest_path="$1"
  local manifest_rel="${manifest_path#${REPO_ROOT}/}"

  if ! jq -e '
    (.id | test("^[a-z0-9_]+$")) and
    (.category | type == "string" and length > 0) and
    (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.url | test("^https://")) and
    ((.fallbackUrls // []) as $fallbacks |
      ($fallbacks | type == "array" and length <= 3) and
      (($fallbacks | unique | length) == ($fallbacks | length)) and
      ($fallbacks | all(
        type == "string" and
        test("^https://[^@/#]+(:443)?/[^#]*$")
      ))) and
    (.sha256 | test("^[a-f0-9]{64}$")) and
    (.sizeCompressed | type == "number" and . > 0) and
    (.sizeUncompressed | type == "number" and . > 0) and
    (.fileCount | type == "number" and . > 0) and
    (.publicationStatus == "active" or .publicationStatus == "quarantined") and
    (.minAppVersion | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+$")) and
    ([.displayName.fr, .displayName.en, .displayName.ar,
      .description.fr, .description.en, .description.ar,
      .license] | all(type == "string" and length > 0))
  ' "${manifest_path}" >/dev/null; then
    echo "[FAIL] ${manifest_rel} : contrat de publication invalide"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  if [[ "${VALIDATION_MODE}" != "--allow-quarantined" ]] &&
      [[ "$(jq -r '.publicationStatus' "${manifest_path}")" != "active" ]]; then
    echo "[FAIL] ${manifest_rel} : statut de publication non admissible"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  if [[ "${VALIDATION_MODE}" == "--require-provenance" ]] && ! jq -e '
    (.provenance.sourceAuthority | type == "string" and length > 0) and
    (.provenance.sourceUrl | test("^https://")) and
    (.provenance.sourceVersion | type == "string" and length > 0) and
    (.provenance.retrievedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
    (.provenance.licenseUrl | test("^https://")) and
    (.provenance.licenseSnapshotSha256 | test("^[a-f0-9]{64}$")) and
    (.provenance.attribution | type == "string" and length > 0) and
    (.provenance.redistributionStatus == "allowed")
  ' "${manifest_path}" >/dev/null; then
    echo "[FAIL] ${manifest_rel} : provenance publiable invalide"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  echo "[OK] ${manifest_rel}"
  PASS_COUNT=$((PASS_COUNT + 1))
}

for category_dir in "${MANIFESTS_DIR}"/*/; do
  category_name=$(basename "${category_dir}")
  if [[ -n "${CATEGORY_FILTER}" && "${category_name}" != "${CATEGORY_FILTER}" ]]; then
    continue
  fi

  for manifest_file in "${category_dir}"*.json; do
    [[ -e "${manifest_file}" ]] || continue
    pack_basename=$(basename "${manifest_file}" .json)
    if [[ -n "${PACK_FILTER}" && "${pack_basename}" != "${PACK_FILTER}" ]]; then
      continue
    fi
    validate_manifest "${manifest_file}"
  done
done

echo "====================================="
echo "Résumé : ${PASS_COUNT} valide(s), ${FAIL_COUNT} invalide(s)"
[[ "${FAIL_COUNT}" -eq 0 ]]
