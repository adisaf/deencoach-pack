#!/usr/bin/env bash
#
# Construit les deux artefacts texte Tanzil autorisés pour Deen Coach.
#
# Aucun contenu n'est modifié : le script télécharge les copies verbatim,
# archive l'avis de licence et génère les manifests avec les vrais SHA-256.
# Les artefacts restent dans uploads/ et ne sont publiés qu'après revue.
#
# Usage : ./tools/build-tanzil-text-packs.sh [release-tag]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/uploads/quran-text"
MANIFEST_DIR="${REPO_ROOT}/manifests/quran-text"
RELEASE_TAG="${1:-quran-text-v1.0.0}"
RELEASE_BASE="https://github.com/adisaf/deencoach-pack/releases/download/${RELEASE_TAG}"
PACK_VERSION="${RELEASE_TAG#quran-text-v}"
LICENSE_URL="https://tanzil.net/docs/Text_License"
UTHMANI_URL="https://tanzil.net/pub/download/index.php?marks=true&sajdah=true&tatweel=true&quranType=uthmani&outType=txt-2&agree=true"
SIMPLE_URL="https://tanzil.net/pub/download/index.php?marks=false&sajdah=false&tatweel=false&quranType=simple-clean&outType=txt-2&agree=true"
ATTRIBUTION="Tanzil Quran Text, Copyright (C) 2007-2021 Tanzil Project"
RETRIEVED_AT="$(date -u +%F)"

[[ "${RELEASE_TAG}" == "quran-text-v${PACK_VERSION}" &&
  "${PACK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Erreur : le tag doit respecter quran-text-vX.Y.Z." >&2
  exit 1
}

for command in curl date jq shasum wc; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

mkdir -p "${OUTPUT_DIR}" "${MANIFEST_DIR}"

license_path="${OUTPUT_DIR}/TANZIL_TEXT_LICENSE.txt"
curl -fsSL "${LICENSE_URL}" -o "${license_path}"
license_sha=$(shasum -a 256 "${license_path}" | awk '{print $1}')

build_pack() {
  local id="$1"
  local source_url="$2"
  local filename="$3"
  local display_fr="$4"
  local display_en="$5"
  local display_ar="$6"
  local description_fr="$7"
  local description_en="$8"
  local description_ar="$9"

  local artifact_path="${OUTPUT_DIR}/${filename}"
  local manifest_path="${MANIFEST_DIR}/${id}.json"
  curl -fsSL "${source_url}" -o "${artifact_path}"

  local artifact_sha size_bytes
  artifact_sha=$(shasum -a 256 "${artifact_path}" | awk '{print $1}')
  size_bytes=$(wc -c < "${artifact_path}" | tr -d ' ')

  jq -n \
    --arg id "${id}" \
    --arg pack_version "${PACK_VERSION}" \
    --arg url "${RELEASE_BASE}/${filename}" \
    --arg sha "${artifact_sha}" \
    --argjson size "${size_bytes}" \
    --arg license_sha "${license_sha}" \
    --arg source_url "${source_url}" \
    --arg display_fr "${display_fr}" \
    --arg display_en "${display_en}" \
    --arg display_ar "${display_ar}" \
    --arg description_fr "${description_fr}" \
    --arg description_en "${description_en}" \
    --arg description_ar "${description_ar}" \
    --arg attribution "${ATTRIBUTION}" \
    --arg retrieved_at "${RETRIEVED_AT}" \
    '{
      "$schema": "../../schemas/pack-manifest.schema.json",
      id: $id,
      category: "quran_text",
      version: $pack_version,
      displayName: {fr: $display_fr, en: $display_en, ar: $display_ar},
      description: {fr: $description_fr, en: $description_en, ar: $description_ar},
      url: $url,
      artifactFormat: "raw",
      contentType: "text/plain; charset=utf-8",
      sizeCompressed: $size,
      sizeUncompressed: $size,
      sha256: $sha,
      fileCount: 1,
      transmission: "Hafs an Asim via al-Shatibiyya",
      license: "Tanzil Quran Text License, CC BY 3.0 with verbatim-copy conditions",
      minAppVersion: "1.0.1+10",
      provenance: {
        sourceAuthority: "Tanzil Project",
        sourceUrl: $source_url,
        sourceVersion: "1.1",
        retrievedAt: $retrieved_at,
        licenseUrl: "https://tanzil.net/docs/Text_License",
        licenseSnapshotSha256: $license_sha,
        attribution: $attribution,
        redistributionStatus: "allowed"
      }
    }' > "${manifest_path}"
}

build_pack \
  "quran_text_uthmani_hafs" \
  "${UTHMANI_URL}" \
  "quran-uthmani-hafs.txt" \
  "Texte coranique Uthmani Hafs" \
  "Uthmani Hafs Quran text" \
  "نص القرآن العثماني برواية حفص" \
  "Copie verbatim du texte Uthmani Tanzil, avec attribution obligatoire." \
  "Verbatim Tanzil Uthmani text with required attribution." \
  "نسخة حرفية من نص تنزيل العثماني مع الإسناد المطلوب."

build_pack \
  "quran_text_simple_search" \
  "${SIMPLE_URL}" \
  "quran-simple-clean.txt" \
  "Texte coranique Simple Clean pour la recherche" \
  "Simple Clean Quran text for search" \
  "نص القرآن المبسط للبحث" \
  "Copie verbatim Simple Clean Tanzil destinée à l'indexation et à la recherche." \
  "Verbatim Tanzil Simple Clean text for indexing and search." \
  "نسخة حرفية من نص تنزيل المبسط للفهرسة والبحث."

"${REPO_ROOT}/tools/validate-manifests.sh" quran-text '' --require-provenance
"${REPO_ROOT}/tools/verify-quran-text-pack.sh" "${OUTPUT_DIR}/quran-uthmani-hafs.txt"
"${REPO_ROOT}/tools/verify-quran-text-pack.sh" "${OUTPUT_DIR}/quran-simple-clean.txt"
echo "Artefacts construits dans ${OUTPUT_DIR}. Publication interdite avant revue."
