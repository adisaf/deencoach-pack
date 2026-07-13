#!/usr/bin/env bash
# Renouvelle la fenêtre de validité puis re-signe les manifests déjà publiés.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED_DIR="${REPO_ROOT}/signed-manifests"
KEYCHAIN_SERVICE="deencoach-pack-ed25519-2026-07"
MANIFEST_VALIDITY_DAYS="${MANIFEST_VALIDITY_DAYS:-90}"
MAX_MANIFEST_VALIDITY_DAYS=90
PUBLIC_KEY_FILE="${REPO_ROOT}/keys/deencoach-pack-2026-07.pub.pem"

for command in base64 cp date dirname find jq mkdir mktemp mv openssl python3 rm security; do
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

# Le renouvellement accepte uniquement un état déjà signé par la clé de
# production. Cela permet de corriger une ancienne fenêtre de validité trop
# longue sans accepter un manifeste local non authentifié. Le contrat complet
# est ensuite validé après la ré-signature atomique de tous les manifests.
"${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"

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
staging_dir=$(mktemp -d "${REPO_ROOT}/.manifest-refresh.XXXXXX")
backup_dir=$(mktemp -d "${REPO_ROOT}/.manifest-refresh-backup.XXXXXX")
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
count=0
while IFS= read -r manifest; do
  relative_path="${manifest#${SIGNED_DIR}/}"
  temporary_manifest="${staging_dir}/${relative_path}"
  temporary_signature="${temporary_manifest}.sig"
  mkdir -p "$(dirname "${temporary_manifest}")"
  jq -S -c \
    --arg issued_at "${issued_at}" \
    --arg expires_at "${expires_at}" \
    '. + {issuedAt: $issued_at, expiresAt: $expires_at}' \
    "${manifest}" > "${temporary_manifest}"
  openssl pkeyutl -sign -rawin \
    -inkey "${private_key_file}" \
    -in "${temporary_manifest}" \
    -out "${temporary_signature}"
  openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
    -in "${temporary_manifest}" -sigfile "${temporary_signature}" >/dev/null
  manifest_relatives+=("${relative_path}")
  count=$((count + 1))
done < <(find "${SIGNED_DIR}" -type f -name '*.json' | sort)

[[ "${count}" -gt 0 ]] || {
  echo 'Erreur : aucun manifest signé trouvé.' >&2
  exit 1
}

for relative_path in "${manifest_relatives[@]}"; do
  mkdir -p "$(dirname "${backup_dir}/${relative_path}")"
  cp "${SIGNED_DIR}/${relative_path}" "${backup_dir}/${relative_path}"
  cp "${SIGNED_DIR}/${relative_path}.sig" "${backup_dir}/${relative_path}.sig"
done
rollback_required=true

restore_backup() {
  for relative_path in "${manifest_relatives[@]}"; do
    cp "${backup_dir}/${relative_path}" "${SIGNED_DIR}/${relative_path}"
    cp "${backup_dir}/${relative_path}.sig" "${SIGNED_DIR}/${relative_path}.sig"
  done
}

for relative_path in "${manifest_relatives[@]}"; do
  manifest="${SIGNED_DIR}/${relative_path}"
  temporary_manifest="${staging_dir}/${relative_path}"
  if ! mv "${temporary_manifest}" "${manifest}" ||
      ! mv "${temporary_manifest}.sig" "${manifest}.sig"; then
    echo "Erreur : publication locale interrompue, restauration des manifests." >&2
    restore_backup
    rollback_required=false
    exit 1
  fi
  echo "[OK] ${manifest#${REPO_ROOT}/}"
done

if ! "${REPO_ROOT}/tools/validate-client-manifests.sh" ||
    ! "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"; then
  echo 'Erreur : validation post-publication échouée, restauration des manifests.' >&2
  restore_backup
  rollback_required=false
  "${REPO_ROOT}/tools/validate-client-manifests.sh"
  "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"
  exit 1
fi
rollback_required=false
