#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED_ROOT="${REPO_ROOT}/signed-manifests"
PUBLIC_KEY_FILE="${REPO_ROOT}/keys/deencoach-pack-2026-07.pub.pem"
MANIFEST_INPUT="${1:?Usage: verify-signed-manifest-artifacts.sh <manifest>}"

for command_name in jq mktemp openssl python3 shasum tr wc; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Erreur : '${command_name}' est requis." >&2
    exit 69
  }
done

MANIFEST="$(python3 - "${SIGNED_ROOT}" "${MANIFEST_INPUT}" <<'PY'
from pathlib import Path
import os
import re
import sys

root = Path(sys.argv[1]).resolve()
candidate = Path(sys.argv[2])
if not candidate.is_absolute():
    candidate = Path.cwd() / candidate
candidate = candidate.resolve()
if os.path.commonpath((str(root), str(candidate))) != str(root):
    raise SystemExit('Erreur : manifest hors du registre signé.')
relative = candidate.relative_to(root).as_posix()
if re.fullmatch(r'(quran-text|quran-translations)/[a-z0-9_]+-r[1-9][0-9]*\.json', relative) is None:
    raise SystemExit('Erreur : chemin de manifest candidat invalide.')
print(candidate)
PY
)"

[[ -f "${MANIFEST}" && -f "${MANIFEST}.sig" ]] || {
  echo 'Erreur : manifest candidat ou signature absent.' >&2
  exit 66
}
openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
  -in "${MANIFEST}" -sigfile "${MANIFEST}.sig" >/dev/null || {
  echo 'Erreur : signature du manifest candidat invalide.' >&2
  exit 65
}
jq -e '
  (.packId | test("^[a-z0-9_]+$")) and
  (.artifacts | type == "array" and length > 0) and
  ([.artifacts[] |
    (.itemKey | type == "string" and length > 0) and
    (.url | test("^https://github.com/adisaf/deencoach-pack/releases/download/")) and
    (.sha256 | test("^[a-f0-9]{64}$")) and
    (.expectedBytes | type == "number" and . > 0 and floor == .)
  ] | all)
' "${MANIFEST}" >/dev/null || {
  echo 'Erreur : contrat des artefacts candidats invalide.' >&2
  exit 65
}

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/deencoach-pack-artifacts.XXXXXX")"
cleanup() {
  rm -rf "${temporary_dir}"
}
trap cleanup EXIT HUP INT TERM

verified_count=0
while IFS=$'\t' read -r url expected_bytes expected_sha; do
  artifact_path="${temporary_dir}/${verified_count}.artifact"
  "${REPO_ROOT}/tools/download-verified-https.sh" \
    "${url}" "${artifact_path}" "${expected_bytes}" \
    'github.com,objects.githubusercontent.com,release-assets.githubusercontent.com,github-releases.githubusercontent.com'
  actual_bytes="$(wc -c < "${artifact_path}" | tr -d ' ')"
  actual_sha="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
  [[ "${actual_bytes}" == "${expected_bytes}" &&
    "${actual_sha}" == "${expected_sha}" ]] || {
    echo "Erreur : artefact public incohérent : ${url}." >&2
    exit 65
  }
  verified_count=$((verified_count + 1))
done < <(
  jq -r '.artifacts[] | [.url, (.expectedBytes | tostring), .sha256] | @tsv' \
    "${MANIFEST}"
)

echo "[OK] ${verified_count} artefact(s) publics vérifiés avant activation."
