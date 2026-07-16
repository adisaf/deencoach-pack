#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TANZIL_ARCHIVE="${REPO_ROOT}/provenance/licenses/TANZIL_TEXT_LICENSE.txt.gz"
QURANENC_ARCHIVE="${REPO_ROOT}/provenance/licenses/QURANENC_TERMS.html.gz"
EXPECTED_TANZIL_SHA='665c0e48132115892b1ed4445903468b785917040d29802d750d0956a28a30f2'
EXPECTED_QURANENC_SHA='851663275ce2b0d335f6607e023c79ad2777268557f6e066a78bfb62ed0cbb4e'

for command_name in awk find gzip jq shasum; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "verify-license-snapshots: '${command_name}' est requis." >&2
    exit 69
  }
done

fail() {
  printf 'verify-license-snapshots: %s\n' "$1" >&2
  exit 1
}

verify_archive() {
  local archive_path="$1"
  local expected_sha="$2"
  local actual_sha

  [[ -f "${archive_path}" ]] || fail "archive absente: ${archive_path}"
  gzip -t "${archive_path}"
  actual_sha="$(gzip -dc "${archive_path}" | shasum -a 256 | awk '{print $1}')"
  [[ "${actual_sha}" == "${expected_sha}" ]] || \
    fail "digest décompressé inattendu pour ${archive_path}"
}

verify_manifest_authority() {
  local authority="$1"
  local expected_sha="$2"
  local matched_count=0
  local manifest_path
  local manifest_authority
  local manifest_sha

  while IFS= read -r -d '' manifest_path; do
    manifest_authority="$(jq -r '.provenance.sourceAuthority // empty' "${manifest_path}")"
    [[ "${manifest_authority}" == "${authority}" ]] || continue
    matched_count=$((matched_count + 1))
    manifest_sha="$(jq -r '.provenance.licenseSnapshotSha256' "${manifest_path}")"
    [[ "${manifest_sha}" == "${expected_sha}" ]] || \
      fail "digest de licence incohérent dans ${manifest_path}"
  done < <(find "${REPO_ROOT}/signed-manifests" -type f -name '*.json' -print0)
  [[ "${matched_count}" -gt 0 ]] || \
    fail "aucun manifest trouvé pour l'autorité ${authority}"
}

verify_archive "${TANZIL_ARCHIVE}" "${EXPECTED_TANZIL_SHA}"
verify_archive "${QURANENC_ARCHIVE}" "${EXPECTED_QURANENC_SHA}"
verify_manifest_authority 'Tanzil Project' "${EXPECTED_TANZIL_SHA}"
verify_manifest_authority 'QuranEnc.com' "${EXPECTED_QURANENC_SHA}"

echo 'verify-license-snapshots: OK'
