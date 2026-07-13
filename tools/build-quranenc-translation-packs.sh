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
TERMS_URL="https://quranenc.com/ff/home/api"
RETRIEVED_AT="$(date -u +%F)"
PACK_VERSION="${RELEASE_TAG#quranenc-translations-v}"

[[ "${RELEASE_TAG}" == "quranenc-translations-v${PACK_VERSION}" &&
  "${PACK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Erreur : le tag doit respecter quranenc-translations-vX.Y.Z." >&2
  exit 1
}

for command in base64 curl date jq mktemp openssl security shasum wc; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

mkdir -p "${OUTPUT_DIR}" "${SIGNED_DIR}"
metadata_path="${OUTPUT_DIR}/quranenc-translations-list.json"
terms_path="${OUTPUT_DIR}/QURANENC_TERMS.html"
curl -fsSL 'https://quranenc.com/api/v1/translations/list/?localization=en' \
  -o "${metadata_path}"
curl -fsSL "${TERMS_URL}" -o "${terms_path}"
terms_sha=$(shasum -a 256 "${terms_path}" | awk '{print $1}')

private_key_file=$(mktemp /private/tmp/deencoach-quranenc-sign.XXXXXX)
trap 'rm -f "${private_key_file}"' EXIT
security find-generic-password -s "${KEYCHAIN_SERVICE}" -w |
  base64 --decode > "${private_key_file}"
chmod 600 "${private_key_file}"

build_pack() {
  local pack_id="$1"
  local translation_key="$2"
  local pack_dir="${OUTPUT_DIR}/${pack_id}"
  local manifest_path="${SIGNED_DIR}/${pack_id}.json"
  local signature_path="${manifest_path}.sig"
  local artifact_lines="${pack_dir}/.artifacts.ndjson"
  local artifacts_json="${pack_dir}/.artifacts.json"
  local metadata

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
    curl --fail --location --retry 3 --retry-all-errors \
      --connect-timeout 10 --max-time 120 --silent --show-error \
      "${response_url}" -o "${pack_dir}/${file}"
    jq -e --arg surah "${surah_number}" '
      (.result | type == "array" and length > 0) and
      ([.result[] | .sura == $surah] | all)
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
      --arg relative_path "${pack_id}/${file}" \
      --arg file_name "${file}" \
      --arg sha256 "${sha256}" \
      --argjson expected_bytes "${expected_bytes}" \
      '{
        itemKey: $item_key,
        url: $url,
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
  echo "[OK] ${pack_id}: 114 réponses QuranEnc source ${version}, pack ${PACK_VERSION}"
}

build_pack quran_translation_fr_noor french_montada
build_pack quran_translation_en_saheeh english_saheeh
build_pack quran_translation_en_hilali_khan english_hilali_khan
build_pack quran_translation_en_rwwad english_rwwad
build_pack quran_translation_fr_rashid french_rashid

"${REPO_ROOT}/tools/validate-client-manifests.sh" quran-translations
"${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"
echo "Lots QuranEnc construits dans ${OUTPUT_DIR}. Publication interdite avant revue."
