#!/usr/bin/env bash
#
# Génère les manifests consommés par le client Flutter et leurs signatures
# Ed25519. La clé privée reste dans le trousseau macOS et n'est jamais écrite
# dans le dépôt. Toute nouvelle clé doit d'abord être livrée dans l'application.
#
# Usage : ./tools/sign-client-manifests.sh [category] [pack]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="${REPO_ROOT}/manifests"
OUTPUT_DIR="${REPO_ROOT}/signed-manifests"
KEYCHAIN_SERVICE="deencoach-pack-ed25519-2026-07"
KEY_ID="deencoach-pack-2026-07"
CATEGORY_FILTER="${1:-}"
PACK_FILTER="${2:-}"

"${REPO_ROOT}/tools/validate-manifests.sh" \
  "${CATEGORY_FILTER}" "${PACK_FILTER}" --require-provenance

for command in jq openssl security base64 mktemp; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

private_key_file=$(mktemp /private/tmp/deencoach-pack-signing.XXXXXX)
trap 'rm -f "${private_key_file}"' EXIT
security find-generic-password -s "${KEYCHAIN_SERVICE}" -w |
  base64 --decode > "${private_key_file}"
chmod 600 "${private_key_file}"

signed_count=0
for category_dir in "${MANIFESTS_DIR}"/*/; do
  category_name=$(basename "${category_dir}")
  if [[ -n "${CATEGORY_FILTER}" && "${category_name}" != "${CATEGORY_FILTER}" ]]; then
    continue
  fi

  for source_manifest in "${category_dir}"*.json; do
    [[ -e "${source_manifest}" ]] || continue
    pack_id=$(jq -r '.id' "${source_manifest}")
    if [[ -n "${PACK_FILTER}" && "${pack_id}" != "${PACK_FILTER}" ]]; then
      continue
    fi

    output_category="${OUTPUT_DIR}/${category_name}"
    output_manifest="${output_category}/${pack_id}.json"
    output_signature="${output_manifest}.sig"
    mkdir -p "${output_category}"

    jq -S -c --arg key_id "${KEY_ID}" '
      {
        packId: .id,
        version: .version,
        signingKeyId: $key_id,
        artifacts: [
          {
            itemKey: "bundle",
            url: .url,
            relativePath: (.id + "/" + (.url | split("/") | last)),
            fileName: (.url | split("/") | last),
            contentType: (.contentType // "application/octet-stream"),
            sha256: .sha256,
            expectedBytes: .sizeUncompressed
          }
        ],
        provenance: .provenance
      }
    ' "${source_manifest}" > "${output_manifest}"

    openssl pkeyutl -sign -rawin \
      -inkey "${private_key_file}" \
      -in "${output_manifest}" \
      -out "${output_signature}"

    [[ "$(wc -c < "${output_signature}" | tr -d ' ')" = '64' ]] || {
      echo "Erreur : signature Ed25519 invalide pour ${pack_id}." >&2
      exit 1
    }
    signed_count=$((signed_count + 1))
    echo "[OK] signed-manifests/${category_name}/${pack_id}.json"
  done
done

[[ "${signed_count}" -gt 0 ]] || {
  echo "Erreur : aucun manifest signé." >&2
  exit 1
}
