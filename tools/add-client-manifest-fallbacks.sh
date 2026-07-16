#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED_DIR="${REPO_ROOT}/signed-manifests"
KEYCHAIN_SERVICE="deencoach-pack-ed25519-2026-07"
PUBLIC_KEY_FILE="${REPO_ROOT}/keys/deencoach-pack-2026-07.pub.pem"
MANIFEST_REVISION="${MANIFEST_REVISION:-r2}"
MANIFEST_VALIDITY_DAYS="${MANIFEST_VALIDITY_DAYS:-90}"

[[ "${MANIFEST_REVISION}" =~ ^r[1-9][0-9]*$ ]] || {
  echo 'Erreur : MANIFEST_REVISION doit respecter rN.' >&2
  exit 1
}

for command in base64 chmod date find jq mkdir mktemp mv openssl python3 rm security sort; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

[[ "${MANIFEST_VALIDITY_DAYS}" =~ ^[1-9][0-9]*$ &&
  "${MANIFEST_VALIDITY_DAYS}" -le 90 ]] || {
  echo 'Erreur : MANIFEST_VALIDITY_DAYS doit être compris entre 1 et 90.' >&2
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

private_key_file=$(mktemp /private/tmp/deencoach-pack-fallback-sign.XXXXXX)
staging_dir=$(mktemp -d /private/tmp/deencoach-pack-fallbacks.XXXXXX)
rollback_required=false
published_paths=()
cleanup() {
  if [[ "${rollback_required}" == true ]]; then
    for published_path in "${published_paths[@]}"; do
      rm -f "${published_path}" "${published_path}.sig"
    done
  fi
  rm -f "${private_key_file}"
  rm -rf "${staging_dir}"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

security find-generic-password -s "${KEYCHAIN_SERVICE}" -w |
  base64 --decode > "${private_key_file}"
chmod 600 "${private_key_file}"

add_fallbacks() {
  local source_path="$1"
  local category pack_id relative_path target_path final_path
  category=$(basename "$(dirname "${source_path}")")
  pack_id=$(jq -r '.packId' "${source_path}")
  relative_path="${category}/${pack_id}-${MANIFEST_REVISION}.json"
  target_path="${staging_dir}/${relative_path}"
  final_path="${SIGNED_DIR}/${relative_path}"

  [[ ! -e "${final_path}" && ! -e "${final_path}.sig" ]] || {
    echo "Erreur : révision immuable déjà présente : ${relative_path}." >&2
    return 1
  }
  mkdir -p "$(dirname "${target_path}")"

  jq -S -c --arg issued_at "${issued_at}" --arg expires_at "${expires_at}" '
    .issuedAt = $issued_at |
    .expiresAt = $expires_at |
    .provenance.sourceAuthority as $authority |
    .artifacts |= map(
      if $authority == "QuranEnc.com" then
        (.fileName | capture("^(?<key>.+)_(?<surah>[0-9]{3})\\.json$")) as $parts |
        .fallbackUrls = [
          "https://quranenc.com/api/v1/translation/sura/\($parts.key)/\($parts.surah | tonumber)"
        ]
      elif $authority == "Tanzil Project" then
        .fallbackUrls = [$source_path]
      else
        error("Autorité sans stratégie de fallback explicite")
      end
    )
  ' --arg source_path "$(jq -r '.provenance.sourceUrl' "${source_path}")" \
    "${source_path}" > "${target_path}"

  openssl pkeyutl -sign -rawin -inkey "${private_key_file}" \
    -in "${target_path}" -out "${target_path}.sig"
  openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
    -in "${target_path}" -sigfile "${target_path}.sig" >/dev/null
}

while IFS= read -r manifest; do
  add_fallbacks "${manifest}"
done < <(find "${SIGNED_DIR}/quran-text" "${SIGNED_DIR}/quran-translations" \
  -type f -name '*.json' ! -name '*-r[0-9]*.json' | sort)

SIGNED_DIR_OVERRIDE="${staging_dir}" \
  "${REPO_ROOT}/tools/verify-client-fallbacks.sh"

rollback_required=true
while IFS= read -r manifest; do
  relative_path="${manifest#${staging_dir}/}"
  final_path="${SIGNED_DIR}/${relative_path}"
  mkdir -p "$(dirname "${final_path}")"
  published_paths+=("${final_path}")
  mv "${manifest}" "${final_path}"
  mv "${manifest}.sig" "${final_path}.sig"
done < <(find "${staging_dir}" -type f -name '*.json' | sort)
rollback_required=false

echo "Révision ${MANIFEST_REVISION} signée et vérifiée sans modifier les manifests existants."
