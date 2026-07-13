#!/usr/bin/env bash
# Vérifie les signatures Ed25519 des manifests destinés au client Flutter.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED_DIR="${REPO_ROOT}/signed-manifests"
PUBLIC_KEY_FILE="${REPO_ROOT}/keys/deencoach-pack-2026-07.pub.pem"

for command in openssl find; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

[[ -f "${PUBLIC_KEY_FILE}" ]] || {
  echo "Erreur : clé publique absente : ${PUBLIC_KEY_FILE}" >&2
  exit 1
}

count=0
while IFS= read -r manifest; do
  signature="${manifest}.sig"
  [[ -f "${signature}" ]] || {
    echo "[FAIL] signature absente : ${manifest#${REPO_ROOT}/}" >&2
    exit 1
  }
  openssl pkeyutl -verify -rawin \
    -pubin -inkey "${PUBLIC_KEY_FILE}" \
    -in "${manifest}" -sigfile "${signature}" >/dev/null
  echo "[OK] ${manifest#${REPO_ROOT}/}"
  count=$((count + 1))
done < <(find "${SIGNED_DIR}" -type f -name '*.json' | sort)

[[ "${count}" -gt 0 ]] || {
  echo "Erreur : aucun manifest signé trouvé." >&2
  exit 1
}
