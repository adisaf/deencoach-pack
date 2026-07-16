#!/usr/bin/env bash
# Met à jour les métadonnées du registre actif et signe ses octets Ed25519.
# La clé privée reste dans le trousseau macOS et n'est jamais écrite dans Git.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ACTIVE_INDEX="${REPO_ROOT}/signed-manifests/active-revisions.json"
readonly ACTIVE_SIGNATURE="${ACTIVE_INDEX}.sig"
readonly KEYCHAIN_SERVICE='deencoach-pack-ed25519-2026-07'
readonly KEY_ID='deencoach-pack-2026-07'
readonly PUBLIC_KEY_FILE="${REPO_ROOT}/keys/deencoach-pack-2026-07.pub.pem"
readonly INDEX_VALIDITY_DAYS="${INDEX_VALIDITY_DAYS:-90}"
readonly MAXIMUM_VALIDITY_DAYS=90

for command_name in base64 chmod cmp cp date git jq mktemp mv openssl python3 rm security tr wc; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Erreur : '${command_name}' est requis." >&2
    exit 1
  }
done

[[ -f "${ACTIVE_INDEX}" ]] || {
  echo 'Erreur : registre actif absent.' >&2
  exit 1
}
[[ "${INDEX_VALIDITY_DAYS}" =~ ^[1-9][0-9]*$ &&
  "${INDEX_VALIDITY_DAYS}" -le "${MAXIMUM_VALIDITY_DAYS}" ]] || {
  echo 'Erreur : INDEX_VALIDITY_DAYS doit être compris entre 1 et 90.' >&2
  exit 1
}

git fetch --quiet origin main
remote_index=$(mktemp "${REPO_ROOT}/.active-revisions-origin.XXXXXX")
remote_signature="${remote_index}.sig"
if git cat-file -e 'origin/main:signed-manifests/active-revisions.json'; then
  git show 'origin/main:signed-manifests/active-revisions.json' > "${remote_index}"
else
  printf '{"revisions":[],"sequence":0}\n' > "${remote_index}"
fi
remote_sequence=$(jq -r '.sequence // 0' "${remote_index}")
[[ "${remote_sequence}" =~ ^[0-9]+$ ]] || {
  echo 'Erreur : séquence origin/main invalide.' >&2
  rm -f "${remote_index}"
  exit 1
}
if git cat-file -e 'origin/main:signed-manifests/active-revisions.json.sig'; then
  git show 'origin/main:signed-manifests/active-revisions.json.sig' > \
    "${remote_signature}"
  openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
    -in "${remote_index}" -sigfile "${remote_signature}" >/dev/null || {
    echo 'Erreur : signature du registre origin/main invalide.' >&2
    rm -f "${remote_index}" "${remote_signature}"
    exit 1
  }
elif [[ "${remote_sequence}" -gt 0 ]]; then
  echo 'Erreur : registre origin/main signé sans signature disponible.' >&2
  rm -f "${remote_index}"
  exit 1
else
  : > "${remote_signature}"
fi

issued_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
expires_at=$(python3 - "${issued_at}" "${INDEX_VALIDITY_DAYS}" <<'PY'
from datetime import datetime, timedelta
import sys

issued_at = datetime.strptime(sys.argv[1], '%Y-%m-%dT%H:%M:%SZ')
expires_at = issued_at + timedelta(days=int(sys.argv[2]))
print(expires_at.strftime('%Y-%m-%dT%H:%M:%SZ'))
PY
)

current_sequence=$(jq -r '.sequence // 0' "${ACTIVE_INDEX}")
[[ "${current_sequence}" =~ ^[0-9]+$ ]] || {
  echo 'Erreur : séquence active invalide.' >&2
  exit 1
}
[[ "${current_sequence}" = "${remote_sequence}" ]] || {
  echo "Erreur : séquence locale ${current_sequence} différente de origin/main ${remote_sequence}." >&2
  rm -f "${remote_index}"
  exit 1
}
if ! changed_manifests="$(python3 - \
  "${ACTIVE_INDEX}" "${remote_index}" "${REPO_ROOT}/signed-manifests" <<'PY'
import json
from pathlib import Path
import re
import sys

with open(sys.argv[1], encoding='utf-8') as handle:
    local = json.load(handle)
with open(sys.argv[2], encoding='utf-8') as handle:
    remote = json.load(handle)
signed_root = Path(sys.argv[3])

local_revisions = {entry['packId']: entry for entry in local.get('revisions', [])}
remote_revisions = {entry['packId']: entry for entry in remote.get('revisions', [])}

def revision_number(path):
    match = re.search(r'-r([1-9][0-9]*)\.json$', path)
    if match is None:
        raise SystemExit('manifest revision suffix is missing')
    return int(match.group(1))

def manifest_version(path):
    with (signed_root / path).open(encoding='utf-8') as handle:
        value = json.load(handle).get('version', '')
    match = re.fullmatch(r'([0-9]+)\.([0-9]+)\.([0-9]+)', value)
    if match is None:
        raise SystemExit(f'invalid manifest version: {path}')
    return tuple(int(part) for part in match.groups())

for pack_id, previous in remote_revisions.items():
    current = local_revisions.get(pack_id)
    if current is None:
        raise SystemExit(f'active pack removed: {pack_id}')
    if current.get('category') != previous.get('category'):
        raise SystemExit(f'active category changed: {pack_id}')
    previous_revision = revision_number(previous['manifest'])
    current_revision = revision_number(current['manifest'])
    if current_revision < previous_revision:
        raise SystemExit(f'active revision rolled back: {pack_id}')
    if current['manifest'] != previous['manifest'] and current_revision <= previous_revision:
        raise SystemExit(f'active revision did not increase: {pack_id}')
    if manifest_version(current['manifest']) < manifest_version(previous['manifest']):
        raise SystemExit(f'active semantic version rolled back: {pack_id}')

for pack_id, current in local_revisions.items():
    previous = remote_revisions.get(pack_id)
    if previous is None or current['manifest'] != previous['manifest']:
        print(current['manifest'])
PY
)"; then
  echo 'Erreur : évolution locale des révisions actives invalide.' >&2
  rm -f "${remote_index}"
  exit 1
fi

if [[ -n "${changed_manifests}" ]]; then
  while IFS= read -r relative_manifest; do
    local_manifest="${REPO_ROOT}/signed-manifests/${relative_manifest}"
    for published_path in "${relative_manifest}" "${relative_manifest}.sig"; do
      git cat-file -e "origin/main:signed-manifests/${published_path}" || {
        echo "Erreur : candidat absent de origin/main : ${published_path}." >&2
        rm -f "${remote_index}" "${remote_signature}"
        exit 1
      }
    done
    git show "origin/main:signed-manifests/${relative_manifest}" |
      cmp -s - "${local_manifest}" || {
      echo "Erreur : manifest candidat local différent de origin/main : ${relative_manifest}." >&2
      exit 1
    }
    git show "origin/main:signed-manifests/${relative_manifest}.sig" |
      cmp -s - "${local_manifest}.sig" || {
      echo "Erreur : signature candidate locale différente de origin/main : ${relative_manifest}." >&2
      exit 1
    }
    "${REPO_ROOT}/tools/verify-signed-manifest-artifacts.sh" \
      "${local_manifest}"
  done <<< "${changed_manifests}"
fi
next_sequence=$((current_sequence + 1))

private_key_file=$(mktemp "${TMPDIR:-/tmp}/deencoach-pack-index-signing.XXXXXX")
staged_index=$(mktemp "${REPO_ROOT}/.active-revisions.XXXXXX")
staged_signature="${staged_index}.sig"
backup_index=$(mktemp "${REPO_ROOT}/.active-revisions-backup.XXXXXX")
backup_signature="${backup_index}.sig"
cp "${ACTIVE_INDEX}" "${backup_index}"
if [[ -f "${ACTIVE_SIGNATURE}" ]]; then
  cp "${ACTIVE_SIGNATURE}" "${backup_signature}"
fi
rollback_required=false
restore_backup() {
  cp "${backup_index}" "${ACTIVE_INDEX}"
  if [[ -f "${backup_signature}" ]]; then
    cp "${backup_signature}" "${ACTIVE_SIGNATURE}"
  else
    rm -f "${ACTIVE_SIGNATURE}"
  fi
}
cleanup() {
  if [[ "${rollback_required}" == true ]]; then
    if ! restore_backup; then
      echo 'CRITIQUE : restauration du registre actif impossible.' >&2
      return 1
    fi
  fi
  rm -f \
    "${private_key_file}" \
    "${staged_index}" \
    "${staged_signature}" \
    "${backup_index}" \
    "${backup_signature}" \
    "${remote_index}" \
    "${remote_signature}"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

security find-generic-password -s "${KEYCHAIN_SERVICE}" -w |
  base64 --decode > "${private_key_file}"
chmod 600 "${private_key_file}"

jq -S \
  --argjson sequence "${next_sequence}" \
  --arg key_id "${KEY_ID}" \
  --arg issued_at "${issued_at}" \
  --arg expires_at "${expires_at}" '
  {
    schemaVersion: 1,
    sequence: $sequence,
    signingKeyId: $key_id,
    issuedAt: $issued_at,
    expiresAt: $expires_at,
    revisions: .revisions
  }
' "${ACTIVE_INDEX}" > "${staged_index}"

openssl pkeyutl -sign -rawin \
  -inkey "${private_key_file}" \
  -in "${staged_index}" \
  -out "${staged_signature}"
[[ "$(wc -c < "${staged_signature}" | tr -d ' ')" = '64' ]] || {
  echo 'Erreur : signature du registre actif invalide.' >&2
  exit 1
}
openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
  -in "${staged_index}" -sigfile "${staged_signature}" >/dev/null

# Optimistic concurrency: refuse promotion if origin/main changed while the
# new index was being validated and signed.
git fetch --quiet origin main
latest_remote_index=$(mktemp "${REPO_ROOT}/.active-revisions-origin-latest.XXXXXX")
latest_remote_signature="${latest_remote_index}.sig"
if git cat-file -e 'origin/main:signed-manifests/active-revisions.json'; then
  git show 'origin/main:signed-manifests/active-revisions.json' > "${latest_remote_index}"
else
  printf '{"revisions":[],"sequence":0}\n' > "${latest_remote_index}"
fi
latest_remote_sequence=$(jq -r '.sequence // 0' "${latest_remote_index}")
if git cat-file -e 'origin/main:signed-manifests/active-revisions.json.sig'; then
  git show 'origin/main:signed-manifests/active-revisions.json.sig' > \
    "${latest_remote_signature}"
  openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
    -in "${latest_remote_index}" -sigfile "${latest_remote_signature}" \
    >/dev/null || {
    rm -f "${latest_remote_index}" "${latest_remote_signature}"
    echo 'Erreur : nouvelle signature origin/main invalide.' >&2
    exit 1
  }
elif [[ "${latest_remote_sequence}" -gt 0 ]]; then
  rm -f "${latest_remote_index}"
  echo 'Erreur : nouvelle révision origin/main non signée.' >&2
  exit 1
else
  : > "${latest_remote_signature}"
fi
if ! cmp -s "${remote_index}" "${latest_remote_index}" ||
  ! cmp -s "${remote_signature}" "${latest_remote_signature}"; then
  rm -f "${latest_remote_index}" "${latest_remote_signature}"
  echo 'Erreur : origin/main a changé pendant la signature, recommencez.' >&2
  exit 1
fi
rm -f "${latest_remote_index}" "${latest_remote_signature}"

rollback_required=true
if ! mv "${staged_index}" "${ACTIVE_INDEX}" ||
  ! mv "${staged_signature}" "${ACTIVE_SIGNATURE}"; then
  echo 'Erreur : publication locale interrompue, restauration du registre.' >&2
  restore_backup
  rollback_required=false
  exit 1
fi

if ! "${REPO_ROOT}/tools/validate-client-manifests.sh" ||
  ! "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"; then
  echo 'Erreur : validation post-signature échouée, restauration du registre.' >&2
  restore_backup
  rollback_required=false
  MINIMUM_REMAINING_DAYS=0 \
    "${REPO_ROOT}/tools/validate-client-manifests.sh"
  "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"
  exit 1
fi
rollback_required=false
echo "[OK] registre actif signé avec la séquence ${next_sequence}."
