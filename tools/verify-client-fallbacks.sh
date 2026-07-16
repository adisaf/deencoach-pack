#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED_DIR="${SIGNED_DIR_OVERRIDE:-${REPO_ROOT}/signed-manifests}"
CATEGORY_FILTER="${1:-}"
PACK_FILTER="${2:-}"

for command in curl find jq mktemp rm shasum sort tr wc; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

SIGNED_DIR_OVERRIDE="${SIGNED_DIR}" \
  "${REPO_ROOT}/tools/validate-client-manifests.sh" \
  "${CATEGORY_FILTER}" "${PACK_FILTER}"
SIGNED_DIR_OVERRIDE="${SIGNED_DIR}" \
  "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/deencoach-pack-fallbacks-verify.XXXXXX")
cleanup() {
  rm -rf "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

verified_count=0
manifest_count=0
while IFS= read -r manifest; do
  category=$(basename "$(dirname "${manifest}")")
  pack_id=$(jq -r '.packId' "${manifest}")
  if [[ -n "${CATEGORY_FILTER}" && "${category}" != "${CATEGORY_FILTER}" ]]; then
    continue
  fi
  if [[ -n "${PACK_FILTER}" && "${pack_id}" != "${PACK_FILTER}" ]]; then
    continue
  fi
  manifest_count=$((manifest_count + 1))

  while IFS=$'\t' read -r item_key expected_sha expected_bytes fallback_url; do
    [[ -n "${fallback_url}" ]] || continue
    target="${temporary_dir}/${pack_id}-${item_key}-${verified_count}"
    bash "${REPO_ROOT}/tools/download-verified-https.sh" \
      "${fallback_url}" "${target}" "${expected_bytes}"
    actual_bytes=$(wc -c < "${target}" | tr -d ' ')
    [[ "${actual_bytes}" == "${expected_bytes}" ]] || {
      echo "Erreur : taille fallback invalide pour ${pack_id}/${item_key}." >&2
      exit 1
    }
    actual_sha=$(shasum -a 256 "${target}" | awk '{print $1}')
    [[ "${actual_sha}" == "${expected_sha}" ]] || {
      echo "Erreur : fallback non identique pour ${pack_id}/${item_key}." >&2
      exit 1
    }
    rm -f "${target}"
    verified_count=$((verified_count + 1))
  done < <(
    jq -r '.artifacts[] | .itemKey as $item_key | .sha256 as $sha |
      .expectedBytes as $bytes | (.fallbackUrls // [])[] |
      [$item_key, $sha, $bytes, .] | @tsv' "${manifest}"
  )
done < <(find "${SIGNED_DIR}" -type f -name '*.json' \
  ! -name 'active-revisions.json' | sort)

[[ "${manifest_count}" -gt 0 ]] || {
  echo 'Erreur : aucun manifest ne correspond aux filtres.' >&2
  exit 1
}
[[ "${verified_count}" -gt 0 ]] || {
  echo 'Erreur : aucun fallback ne correspond aux filtres.' >&2
  exit 1
}

echo "[OK] ${verified_count} fallback(s) vérifié(s) contre leur SHA-256 signé."
