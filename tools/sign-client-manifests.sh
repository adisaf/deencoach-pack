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
MANIFEST_VALIDITY_DAYS="${MANIFEST_VALIDITY_DAYS:-90}"
MAX_MANIFEST_VALIDITY_DAYS=90
PUBLIC_KEY_FILE="${REPO_ROOT}/keys/deencoach-pack-2026-07.pub.pem"
MANIFEST_REVISION="${MANIFEST_REVISION:-}"

[[ "${MANIFEST_REVISION}" =~ ^r[1-9][0-9]*$ ]] || {
  echo 'Erreur : MANIFEST_REVISION est obligatoire et doit respecter rN.' >&2
  exit 1
}

"${REPO_ROOT}/tools/validate-manifests.sh" \
  "${CATEGORY_FILTER}" "${PACK_FILTER}" --require-provenance

for command in cp dirname jq mkdir mv openssl rm security base64 mktemp python3; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

[[ "${MANIFEST_VALIDITY_DAYS}" =~ ^[1-9][0-9]*$ &&
  "${MANIFEST_VALIDITY_DAYS}" -le "${MAX_MANIFEST_VALIDITY_DAYS}" ]] || {
  echo 'Erreur : MANIFEST_VALIDITY_DAYS doit être un entier positif.' >&2
  exit 1
}

issued_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
expires_at=$(python3 - "${issued_at}" "${MANIFEST_VALIDITY_DAYS}" <<'PY'
from datetime import datetime, timedelta
import sys

issued_at = datetime.strptime(sys.argv[1], '%Y-%m-%dT%H:%M:%SZ')
expires_at = issued_at + timedelta(days=int(sys.argv[2]))
print(expires_at.strftime('%Y-%m-%dT%H:%M:%SZ'))
PY
)

private_key_file=$(mktemp /private/tmp/deencoach-pack-signing.XXXXXX)
staging_dir=$(mktemp -d "${REPO_ROOT}/.manifest-signing.XXXXXX")
backup_dir=$(mktemp -d "${REPO_ROOT}/.manifest-signing-backup.XXXXXX")
rollback_required=false
cleanup() {
  if [[ "${rollback_required}" == true ]] &&
      declare -F restore_backup >/dev/null; then
    if ! restore_backup; then
      echo 'CRITIQUE : restauration impossible, sauvegardes conservées.' >&2
      rm -f "${private_key_file}"
      rm -rf "${staging_dir}"
      return 1
    fi
  fi
  rm -f "${private_key_file}"
  rm -rf "${staging_dir}" "${backup_dir}"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
security find-generic-password -s "${KEYCHAIN_SERVICE}" -w |
  base64 --decode > "${private_key_file}"
chmod 600 "${private_key_file}"

manifest_relatives=()
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

    relative_path="${category_name}/${pack_id}-${MANIFEST_REVISION}.json"
    output_manifest="${OUTPUT_DIR}/${relative_path}"
    temporary_manifest="${staging_dir}/${relative_path}"
    temporary_signature="${temporary_manifest}.sig"
    mkdir -p "$(dirname "${temporary_manifest}")"
    [[ ! -e "${output_manifest}" && ! -e "${output_manifest}.sig" ]] || {
      echo "Erreur : révision immuable déjà présente : ${relative_path}." >&2
      exit 1
    }

    jq -S -c \
      --arg key_id "${KEY_ID}" \
      --arg issued_at "${issued_at}" \
      --arg expires_at "${expires_at}" '
      {
        packId: .id,
        version: .version,
        signingKeyId: $key_id,
        issuedAt: $issued_at,
        expiresAt: $expires_at,
        artifacts: [
          {
            itemKey: "bundle",
            url: .url,
            fallbackUrls: (.fallbackUrls // []),
            relativePath: (.id + "/" + (.url | split("/") | last)),
            fileName: (.url | split("/") | last),
            contentType: (.contentType // "application/octet-stream"),
            sha256: .sha256,
            expectedBytes: .sizeCompressed
          }
        ],
        provenance: .provenance
      }
    ' "${source_manifest}" > "${temporary_manifest}"

    openssl pkeyutl -sign -rawin \
      -inkey "${private_key_file}" \
      -in "${temporary_manifest}" \
      -out "${temporary_signature}"

    [[ "$(wc -c < "${temporary_signature}" | tr -d ' ')" = '64' ]] || {
      echo "Erreur : signature Ed25519 invalide pour ${pack_id}." >&2
      exit 1
    }
    openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
      -in "${temporary_manifest}" -sigfile "${temporary_signature}" >/dev/null
    manifest_relatives+=("${relative_path}")
    signed_count=$((signed_count + 1))
    echo "[OK] signed-manifests/${relative_path}"
  done
done

[[ "${signed_count}" -gt 0 ]] || {
  echo "Erreur : aucun manifest signé." >&2
  exit 1
}

SIGNED_DIR_OVERRIDE="${staging_dir}" \
  "${REPO_ROOT}/tools/verify-client-fallbacks.sh" \
  "${CATEGORY_FILTER}" "${PACK_FILTER}"

for relative_path in "${manifest_relatives[@]}"; do
  output_manifest="${OUTPUT_DIR}/${relative_path}"
  backup_manifest="${backup_dir}/${relative_path}"
  mkdir -p "$(dirname "${backup_manifest}")"
  if [[ -f "${output_manifest}" ]]; then
    cp "${output_manifest}" "${backup_manifest}"
    : > "${backup_manifest}.exists"
  fi
  if [[ -f "${output_manifest}.sig" ]]; then
    cp "${output_manifest}.sig" "${backup_manifest}.sig"
    : > "${backup_manifest}.sig.exists"
  fi
done
rollback_required=true

restore_backup() {
  for relative_path in "${manifest_relatives[@]}"; do
    output_manifest="${OUTPUT_DIR}/${relative_path}"
    backup_manifest="${backup_dir}/${relative_path}"
    if [[ -f "${backup_manifest}.exists" ]]; then
      cp "${backup_manifest}" "${output_manifest}"
    else
      rm -f "${output_manifest}"
    fi
    if [[ -f "${backup_manifest}.sig.exists" ]]; then
      cp "${backup_manifest}.sig" "${output_manifest}.sig"
    else
      rm -f "${output_manifest}.sig"
    fi
  done
}

for relative_path in "${manifest_relatives[@]}"; do
  output_manifest="${OUTPUT_DIR}/${relative_path}"
  temporary_manifest="${staging_dir}/${relative_path}"
  mkdir -p "$(dirname "${output_manifest}")"
  if ! mv "${temporary_manifest}" "${output_manifest}" ||
      ! mv "${temporary_manifest}.sig" "${output_manifest}.sig"; then
    echo 'Erreur : publication locale interrompue, restauration des manifests.' >&2
    restore_backup
    rollback_required=false
    exit 1
  fi
done

if ! "${REPO_ROOT}/tools/validate-client-manifests.sh" \
      "${CATEGORY_FILTER}" "${PACK_FILTER}" ||
    ! "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"; then
  echo 'Erreur : validation post-publication échouée, restauration des manifests.' >&2
  restore_backup
  rollback_required=false
  "${REPO_ROOT}/tools/validate-client-manifests.sh" \
    "${CATEGORY_FILTER}" "${PACK_FILTER}"
  "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"
  exit 1
fi
rollback_required=false
