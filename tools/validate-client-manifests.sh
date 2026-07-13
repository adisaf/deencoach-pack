#!/usr/bin/env bash
# Valide les manifests Ed25519 consommés par le client Flutter.
#
# Usage : ./tools/validate-client-manifests.sh [category] [pack]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED_DIR="${REPO_ROOT}/signed-manifests"
CATEGORY_FILTER="${1:-}"
PACK_FILTER="${2:-}"

command -v jq >/dev/null 2>&1 || {
  echo "Erreur : 'jq' est requis." >&2
  exit 1
}

pass_count=0
fail_count=0

validate_manifest() {
  local path="$1"
  local relative_path="${path#${REPO_ROOT}/}"

  if ! jq -e '
    (.packId | test("^[a-z0-9_]+$")) and
    (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.signingKeyId == "deencoach-pack-2026-07") and
    (.artifacts | type == "array" and length > 0) and
    (.artifacts as $artifacts |
      ([ $artifacts[].itemKey ] | unique | length == ($artifacts | length)) and
      ([ $artifacts[].fileName ] | unique | length == ($artifacts | length)) and
      ([ $artifacts[].relativePath ] | unique | length == ($artifacts | length))
    ) and
    ([.artifacts[] |
      (.itemKey | type == "string" and length > 0) and
      (.url | test("^https://github.com/adisaf/deencoach-pack/releases/download/")) and
      (.relativePath | test("^[a-z0-9_]+/[A-Za-z0-9_.-]+$")) and
      (.fileName | test("^[A-Za-z0-9_.-]+$")) and
      (. as $artifact | $artifact.relativePath | endswith("/" + $artifact.fileName)) and
      (.contentType | type == "string" and length > 0) and
      (.sha256 | test("^[a-f0-9]{64}$")) and
      (.expectedBytes | type == "number" and . > 0)
    ] | all) and
    (.provenance.sourceAuthority | type == "string" and length > 0) and
    (.provenance.sourceUrl | test("^https://")) and
    (.provenance.sourceVersion | type == "string" and length > 0) and
    (.provenance.retrievedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
    (.provenance.licenseUrl | test("^https://")) and
    (.provenance.licenseSnapshotSha256 | test("^[a-f0-9]{64}$")) and
    (.provenance.attribution | type == "string" and length > 0) and
    (.provenance.redistributionStatus == "allowed")
  ' "${path}" >/dev/null; then
    echo "[FAIL] ${relative_path} : contrat client invalide" >&2
    fail_count=$((fail_count + 1))
    return
  fi

  echo "[OK] ${relative_path}"
  pass_count=$((pass_count + 1))
}

for category_dir in "${SIGNED_DIR}"/*/; do
  category_name=$(basename "${category_dir}")
  if [[ -n "${CATEGORY_FILTER}" && "${category_name}" != "${CATEGORY_FILTER}" ]]; then
    continue
  fi
  for manifest in "${category_dir}"*.json; do
    [[ -e "${manifest}" ]] || continue
    pack_id=$(jq -r '.packId' "${manifest}")
    if [[ -n "${PACK_FILTER}" && "${pack_id}" != "${PACK_FILTER}" ]]; then
      continue
    fi
    validate_manifest "${manifest}"
  done
done

echo "====================================="
echo "Résumé : ${pass_count} valide(s), ${fail_count} invalide(s)"
[[ "${pass_count}" -gt 0 && "${fail_count}" -eq 0 ]]
