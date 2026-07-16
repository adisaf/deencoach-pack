#!/usr/bin/env bash
#
# Construit des copies byte-for-byte des réponses QuranEnc par sourate puis
# signe les manifests clients. Aucun champ religieux n'est réécrit, filtré ou
# normalisé. Les lots restent locaux dans uploads/ tant qu'une release GitHub
# n'a pas été expressément autorisée.
#
# Seules les traductions dont l'API officielle expose une version sont admises.
# Usage : ./tools/build-quranenc-translation-packs.sh [release-tag]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/uploads/quranenc-translations"
SIGNED_DIR="${REPO_ROOT}/signed-manifests/quran-translations"
RELEASE_TAG="${1:-quranenc-translations-v1.0.0}"
RELEASE_BASE="https://github.com/adisaf/deencoach-pack/releases/download/${RELEASE_TAG}"
KEYCHAIN_SERVICE="deencoach-pack-ed25519-2026-07"
KEY_ID="deencoach-pack-2026-07"
PUBLIC_KEY_FILE="${REPO_ROOT}/keys/deencoach-pack-2026-07.pub.pem"
MANIFEST_REVISION="${MANIFEST_REVISION:-}"
TERMS_URL="https://quranenc.com/ff/home/api"
RETRIEVED_AT="$(date -u +%F)"
PACK_VERSION="${RELEASE_TAG#quranenc-translations-v}"
MANIFEST_VALIDITY_DAYS="${MANIFEST_VALIDITY_DAYS:-90}"
MAX_MANIFEST_VALIDITY_DAYS=90
DOWNLOAD_TOOL="${REPO_ROOT}/tools/download-verified-https.sh"
QURAN_STRUCTURE="${REPO_ROOT}/tools/quran-structure.tsv"

[[ "${RELEASE_TAG}" == "quranenc-translations-v${PACK_VERSION}" &&
  "${PACK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Erreur : le tag doit respecter quranenc-translations-vX.Y.Z." >&2
  exit 1
}

[[ "${MANIFEST_REVISION}" =~ ^r[1-9][0-9]*$ ]] || {
  echo 'Erreur : MANIFEST_REVISION est obligatoire et doit respecter rN.' >&2
  exit 1
}

for command in awk base64 bash cp curl date dirname jq mkdir mktemp mv openssl python3 rm security shasum wc; do
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

mkdir -p "${OUTPUT_DIR}" "${SIGNED_DIR}"
metadata_path="${OUTPUT_DIR}/quranenc-translations-list.json"
terms_path="${OUTPUT_DIR}/QURANENC_TERMS.html"
bash "${DOWNLOAD_TOOL}" \
  'https://quranenc.com/api/v1/translations/list/?localization=en' \
  "${metadata_path}" 5242880 quranenc.com
bash "${DOWNLOAD_TOOL}" "${TERMS_URL}" "${terms_path}" 5242880 quranenc.com
terms_sha=$(shasum -a 256 "${terms_path}" | awk '{print $1}')

private_key_file=$(mktemp /private/tmp/deencoach-quranenc-sign.XXXXXX)
staging_dir=$(mktemp -d "${REPO_ROOT}/.quranenc-manifest-staging.XXXXXX")
backup_dir=$(mktemp -d "${REPO_ROOT}/.quranenc-manifest-backup.XXXXXX")
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

manifest_names=()
build_pack() {
  local pack_id="$1"
  local translation_key="$2"
  local pack_dir="${OUTPUT_DIR}/${pack_id}"
  local manifest_path="${staging_dir}/${pack_id}-${MANIFEST_REVISION}.json"
  local signature_path="${manifest_path}.sig"
  local artifact_lines="${pack_dir}/.artifacts.ndjson"
  local artifacts_json="${pack_dir}/.artifacts.json"
  local metadata

  [[ ! -e "${SIGNED_DIR}/${pack_id}-${MANIFEST_REVISION}.json" &&
    ! -e "${SIGNED_DIR}/${pack_id}-${MANIFEST_REVISION}.json.sig" ]] || {
    echo "Erreur : révision immuable déjà présente pour ${pack_id}-${MANIFEST_REVISION}." >&2
    return 1
  }

  metadata=$(jq -c --arg key "${translation_key}" \
    '.translations[] | select(.key == $key)' "${metadata_path}")
  [[ -n "${metadata}" ]] || {
    echo "Erreur : version officielle absente pour ${translation_key}." >&2
    return 1
  }

  local version title description
  version=$(jq -r '.version' <<<"${metadata}")
  title=$(jq -r '.title' <<<"${metadata}")
  description=$(jq -r '.description' <<<"${metadata}")
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Erreur : version QuranEnc invalide pour ${translation_key}." >&2
    return 1
  }

  mkdir -p "${pack_dir}"
  : > "${artifact_lines}"
  for surah_number in $(seq 1 114); do
    local padded file response_url
    padded=$(printf '%03d' "${surah_number}")
    file="${translation_key}_${padded}.json"
    response_url="https://quranenc.com/api/v1/translation/sura/${translation_key}/${surah_number}"
    # Re-télécharger chaque réponse rend `retrievedAt` exact et évite de
    # republier silencieusement un cache dont la version source a évolué.
    bash "${DOWNLOAD_TOOL}" "${response_url}" "${pack_dir}/${file}" \
      2097152 quranenc.com
    local expected_ayah_count
    expected_ayah_count=$(awk -v surah="${surah_number}" \
      '$1 == surah { print $2 }' "${QURAN_STRUCTURE}")
    [[ -n "${expected_ayah_count}" ]] || {
      echo "Erreur : structure coranique absente pour la sourate ${surah_number}." >&2
      return 1
    }
    jq -e --arg surah "${surah_number}" \
      --argjson expected_count "${expected_ayah_count}" '
      (.result | type == "array" and length == $expected_count) and
      ([.result[] | (.sura | tostring) == $surah] | all) and
      ([.result[] | (.aya | tonumber)] == [range(1; $expected_count + 1)]) and
      ([.result[] | (.translation | type == "string" and length > 0)] | all)
    ' "${pack_dir}/${file}" >/dev/null || {
      echo "Erreur : réponse invalide pour ${translation_key}/${surah_number}." >&2
      return 1
    }
    local sha256 expected_bytes
    sha256=$(shasum -a 256 "${pack_dir}/${file}" | awk '{print $1}')
    expected_bytes=$(wc -c < "${pack_dir}/${file}" | tr -d ' ')
    jq -n -c \
      --arg item_key "surah_${padded}" \
      --arg url "${RELEASE_BASE}/${file}" \
      --arg fallback_url "${response_url}" \
      --arg relative_path "${pack_id}/${file}" \
      --arg file_name "${file}" \
      --arg sha256 "${sha256}" \
      --argjson expected_bytes "${expected_bytes}" \
      '{
        itemKey: $item_key,
        url: $url,
        fallbackUrls: [$fallback_url],
        relativePath: $relative_path,
        fileName: $file_name,
        contentType: "application/json",
        sha256: $sha256,
        expectedBytes: $expected_bytes
      }' >> "${artifact_lines}"
  done

  jq -s '.' "${artifact_lines}" > "${artifacts_json}"

  jq -n -S -c \
    --arg pack_version "${PACK_VERSION}" \
    --arg pack_id "${pack_id}" \
    --arg version "${version}" \
    --arg key_id "${KEY_ID}" \
    --arg issued_at "${issued_at}" \
    --arg expires_at "${expires_at}" \
    --arg source_url "https://quranenc.com/en/browse/${translation_key}" \
    --arg title "${title}" \
    --arg description "${description}" \
    --arg terms_sha "${terms_sha}" \
    --arg retrieved_at "${RETRIEVED_AT}" \
    --arg terms_url "${TERMS_URL}" \
    --slurpfile artifacts "${artifacts_json}" \
    '
      {
        packId: $pack_id,
        version: $pack_version,
        signingKeyId: $key_id,
        issuedAt: $issued_at,
        expiresAt: $expires_at,
        artifacts: $artifacts[0],
        provenance: {
          sourceAuthority: "QuranEnc.com",
          sourceUrl: $source_url,
          sourceVersion: $version,
          retrievedAt: $retrieved_at,
          licenseUrl: $terms_url,
          licenseSnapshotSha256: $terms_sha,
          attribution: ($title + ". " + $description + " Source: QuranEnc.com."),
          redistributionStatus: "allowed"
        }
      }
    ' > "${manifest_path}"
  rm -f "${artifact_lines}" "${artifacts_json}"

  jq -e '([.artifacts[] | .sha256 | test("^[a-f0-9]{64}$")] | all) and ([.artifacts[] | .expectedBytes | type == "number"] | all)' \
    "${manifest_path}" >/dev/null || {
    echo "Erreur : manifeste incomplet pour ${pack_id}." >&2
    return 1
  }
  openssl pkeyutl -sign -rawin -inkey "${private_key_file}" \
    -in "${manifest_path}" -out "${signature_path}"
  [[ "$(wc -c < "${signature_path}" | tr -d ' ')" = '64' ]] || {
    echo "Erreur : signature invalide pour ${pack_id}." >&2
    return 1
  }
  openssl pkeyutl -verify -rawin -pubin -inkey "${PUBLIC_KEY_FILE}" \
    -in "${manifest_path}" -sigfile "${signature_path}" >/dev/null
  manifest_names+=("${pack_id}")
  echo "[OK] ${pack_id}: 114 réponses QuranEnc source ${version}, pack ${PACK_VERSION}"
}

build_pack quran_translation_fr_noor french_montada
build_pack quran_translation_en_saheeh english_saheeh
build_pack quran_translation_en_hilali_khan english_hilali_khan
build_pack quran_translation_en_rwwad english_rwwad
build_pack quran_translation_fr_rashid french_rashid

SIGNED_DIR_OVERRIDE="${staging_dir}" \
  "${REPO_ROOT}/tools/verify-client-fallbacks.sh" quran-translations

for pack_id in "${manifest_names[@]}"; do
  final_manifest="${SIGNED_DIR}/${pack_id}-${MANIFEST_REVISION}.json"
  backup_manifest="${backup_dir}/${pack_id}-${MANIFEST_REVISION}.json"
  if [[ -f "${final_manifest}" ]]; then
    cp "${final_manifest}" "${backup_manifest}"
    : > "${backup_manifest}.exists"
  fi
  if [[ -f "${final_manifest}.sig" ]]; then
    cp "${final_manifest}.sig" "${backup_manifest}.sig"
    : > "${backup_manifest}.sig.exists"
  fi
done
rollback_required=true

restore_backup() {
  for pack_id in "${manifest_names[@]}"; do
    final_manifest="${SIGNED_DIR}/${pack_id}-${MANIFEST_REVISION}.json"
    backup_manifest="${backup_dir}/${pack_id}-${MANIFEST_REVISION}.json"
    if [[ -f "${backup_manifest}.exists" ]]; then
      cp "${backup_manifest}" "${final_manifest}"
    else
      rm -f "${final_manifest}"
    fi
    if [[ -f "${backup_manifest}.sig.exists" ]]; then
      cp "${backup_manifest}.sig" "${final_manifest}.sig"
    else
      rm -f "${final_manifest}.sig"
    fi
  done
}

for pack_id in "${manifest_names[@]}"; do
  final_manifest="${SIGNED_DIR}/${pack_id}-${MANIFEST_REVISION}.json"
  staged_manifest="${staging_dir}/${pack_id}-${MANIFEST_REVISION}.json"
  if ! mv "${staged_manifest}" "${final_manifest}" ||
      ! mv "${staged_manifest}.sig" "${final_manifest}.sig"; then
    echo 'Erreur : publication locale interrompue, restauration des manifests.' >&2
    restore_backup
    rollback_required=false
    exit 1
  fi
done

if ! "${REPO_ROOT}/tools/validate-client-manifests.sh" quran-translations ||
    ! "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"; then
  echo 'Erreur : validation post-publication échouée, restauration des manifests.' >&2
  restore_backup
  rollback_required=false
  "${REPO_ROOT}/tools/validate-client-manifests.sh" quran-translations
  "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"
  exit 1
fi
rollback_required=false
echo "Lots QuranEnc construits dans ${OUTPUT_DIR}. Publication interdite avant revue."
