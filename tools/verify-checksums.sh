#!/usr/bin/env bash
#
# verify-checksums.sh
#
# Vérifie l'intégrité de tous les packs publiés en téléchargeant chaque
# ZIP depuis l'URL annoncée dans son manifest, puis en comparant le
# SHA-256 calculé au SHA-256 attendu dans le manifest.
#
# Usage :
#   ./tools/verify-checksums.sh                   # vérifie tous les manifests
#   ./tools/verify-checksums.sh mushaf-fonts      # vérifie une catégorie
#   ./tools/verify-checksums.sh mushaf-fonts qpc-v1   # vérifie un pack précis
#
# Pré-requis : curl, shasum (macOS) ou sha256sum (Linux), jq.
#
# Exit code : 0 si tout est OK, 1 si au moins une vérification échoue.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
TMP_DIR="$(mktemp -d -t deencoach-pack-verify-XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Détection de l'outil SHA-256 disponible
if command -v shasum >/dev/null 2>&1; then
  SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD="sha256sum"
else
  echo "Erreur : ni 'shasum' ni 'sha256sum' n'est disponible." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Erreur : 'jq' est requis. Installer via 'brew install jq' ou 'apt install jq'." >&2
  exit 1
fi

CATEGORY_FILTER="${1:-}"
PACK_FILTER="${2:-}"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILURES=()

verify_manifest() {
  local manifest_path="$1"
  local manifest_rel="${manifest_path#${REPO_ROOT}/}"

  local pack_id url expected_sha
  pack_id=$(jq -r '.id' "${manifest_path}")
  url=$(jq -r '.url' "${manifest_path}")
  expected_sha=$(jq -r '.sha256' "${manifest_path}")

  if [[ "${expected_sha}" == "TO_BE_FILLED_AFTER_RELEASE" ]]; then
    echo "[SKIP] ${manifest_rel} : SHA-256 placeholder (pack pas encore release)"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    return 0
  fi

  echo "[CHECK] ${manifest_rel}"
  echo "  → URL : ${url}"
  echo "  → expected SHA-256 : ${expected_sha}"

  local zip_path="${TMP_DIR}/${pack_id}.zip"
  if ! curl -fsSL -o "${zip_path}" "${url}"; then
    echo "  → ❌ FAIL : download échoué"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("${manifest_rel} (download failed)")
    return 0
  fi

  local actual_sha
  actual_sha=$(${SHA_CMD} "${zip_path}" | awk '{print $1}')
  echo "  → actual SHA-256   : ${actual_sha}"

  if [[ "${actual_sha}" == "${expected_sha}" ]]; then
    echo "  → ✅ OK"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  → ❌ FAIL : SHA-256 mismatch"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("${manifest_rel} (SHA-256 mismatch)")
  fi

  rm -f "${zip_path}"
  echo ""
}

# Itère sur tous les manifests, avec filtres optionnels
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

    verify_manifest "${manifest_file}"
  done
done

echo "====================================="
echo "Résumé :"
echo "  ✅ OK   : ${PASS_COUNT}"
echo "  ❌ FAIL : ${FAIL_COUNT}"
echo "  ⏭  SKIP : ${SKIP_COUNT}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo ""
  echo "Échecs :"
  for failure in "${FAILURES[@]}"; do
    echo "  - ${failure}"
  done
  exit 1
fi

exit 0
