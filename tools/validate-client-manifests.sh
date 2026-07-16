#!/usr/bin/env bash
# Valide les manifests Ed25519 consommés par le client Flutter.
#
# Usage : ./tools/validate-client-manifests.sh [category] [pack]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED_DIR="${SIGNED_DIR_OVERRIDE:-${REPO_ROOT}/signed-manifests}"
CATEGORY_FILTER="${1:-}"
PACK_FILTER="${2:-}"
MINIMUM_REMAINING_DAYS="${MINIMUM_REMAINING_DAYS:-14}"
ACTIVE_REVISIONS_FILE="${SIGNED_DIR}/active-revisions.json"

for command in date find jq sort; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Erreur : '${command}' est requis." >&2
    exit 1
  }
done

[[ "${MINIMUM_REMAINING_DAYS}" =~ ^[0-9]+$ ]] || {
  echo 'Erreur : MINIMUM_REMAINING_DAYS doit être un entier positif ou nul.' >&2
  exit 1
}
minimum_remaining_seconds=$((MINIMUM_REMAINING_DAYS * 24 * 60 * 60))
current_epoch=$(date -u +%s)

if [[ -f "${ACTIVE_REVISIONS_FILE}" ]]; then
  jq -e '
    .schemaVersion == 1 and
    (.revisions as $revisions |
      ($revisions | type == "array" and length > 0) and
      ([$revisions[].packId] | unique | length == ($revisions | length)) and
      ([$revisions[].manifest] | unique | length == ($revisions | length)) and
      ([$revisions[] |
      (.packId | test("^[a-z0-9_]+$")) and
      (.category == "quran-text" or .category == "quran-translations") and
      (.manifest | test("^(quran-text|quran-translations)/[a-z0-9_]+-r[1-9][0-9]*\\.json$"))
      ] | all)
    )
  ' "${ACTIVE_REVISIONS_FILE}" >/dev/null || {
    echo 'Erreur : registre des révisions actives invalide.' >&2
    exit 1
  }
  while IFS=$'\t' read -r pack_id category relative_path; do
    active_path="${SIGNED_DIR}/${relative_path}"
    [[ -f "${active_path}" && -f "${active_path}.sig" ]] || {
      echo "Erreur : révision active absente : ${relative_path}." >&2
      exit 1
    }
    jq -e --arg pack_id "${pack_id}" '.packId == $pack_id' \
      "${active_path}" >/dev/null || {
      echo "Erreur : packId actif incohérent : ${relative_path}." >&2
      exit 1
    }
    [[ "${relative_path}" =~ /${pack_id}-r[1-9][0-9]*\.json$ ]] || {
      echo "Erreur : nom de révision actif incohérent : ${relative_path}." >&2
      exit 1
    }
    [[ "${relative_path}" == "${category}/"* ]] || {
      echo "Erreur : catégorie active incohérente : ${relative_path}." >&2
      exit 1
    }
  done < <(jq -r '.revisions[] | [.packId, .category, .manifest] | @tsv' \
    "${ACTIVE_REVISIONS_FILE}")

  while IFS= read -r manifest; do
    manifest_pack_id=$(jq -r '.packId' "${manifest}")
    jq -e --arg pack_id "${manifest_pack_id}" \
      '.revisions[] | select(.packId == $pack_id)' \
      "${ACTIVE_REVISIONS_FILE}" >/dev/null || {
      echo "Erreur : aucune révision active pour ${manifest_pack_id}." >&2
      exit 1
    }
  done < <(find "${SIGNED_DIR}" -type f -name '*.json' \
    ! -name 'active-revisions.json' | sort)
fi

pass_count=0
fail_count=0

validate_manifest() {
  local path="$1"
  local relative_path="${path#${REPO_ROOT}/}"
  local signed_relative_path="${path#${SIGNED_DIR}/}"
  local require_freshness=true
  if [[ -f "${ACTIVE_REVISIONS_FILE}" ]] &&
      ! jq -e --arg path "${signed_relative_path}" \
        '.revisions[] | select(.manifest == $path)' \
        "${ACTIVE_REVISIONS_FILE}" >/dev/null; then
    require_freshness=false
  fi

  if ! jq -e \
    --argjson current_epoch "${current_epoch}" \
    --argjson minimum_remaining_seconds "${minimum_remaining_seconds}" \
    --argjson require_freshness "${require_freshness}" '
    (.packId | test("^[a-z0-9_]+$")) and
    (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.signingKeyId == "deencoach-pack-2026-07") and
    (.issuedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.expiresAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    ((.issuedAt | fromdateiso8601) < (.expiresAt | fromdateiso8601)) and
    (((.expiresAt | fromdateiso8601) - (.issuedAt | fromdateiso8601)) <= (90 * 24 * 60 * 60)) and
    (($require_freshness | not) or
      ((.expiresAt | fromdateiso8601) > ($current_epoch + $minimum_remaining_seconds))) and
    (.artifacts | type == "array" and length > 0) and
    (.artifacts as $artifacts |
      ([ $artifacts[].itemKey ] | unique | length == ($artifacts | length)) and
      ([ $artifacts[].fileName ] | unique | length == ($artifacts | length)) and
      ([ $artifacts[].relativePath ] | unique | length == ($artifacts | length))
    ) and
    ([.artifacts[] |
      (.itemKey | type == "string" and length > 0) and
      (.url | test("^https://github.com/adisaf/deencoach-pack/releases/download/")) and
      ((.fallbackUrls // []) | type == "array" and length <= 3) and
      (. as $artifact |
        (($artifact.fallbackUrls // []) | unique | length) ==
        (($artifact.fallbackUrls // []) | length)) and
      (. as $artifact | [($artifact.fallbackUrls // [])[] |
        (type == "string") and
        test("^https://(quranenc\\.com|tanzil\\.net)(:443)?/[^#]*$") and
        (contains("@") | not) and
        (. != $artifact.url)
      ] | all) and
      (.relativePath | test("^[a-z0-9_]+/[A-Za-z0-9_.-]+$")) and
      (.fileName | test("^[A-Za-z0-9_.-]+$")) and
      (. as $artifact | $artifact.relativePath | endswith("/" + $artifact.fileName)) and
      (.contentType | type == "string" and length > 0) and
      (.sha256 | test("^[a-f0-9]{64}$")) and
      (.expectedBytes | type == "number" and . > 0)
    ] | all) and
    (.provenance.sourceAuthority | type == "string" and length > 0) and
    (.provenance.sourceUrl | test("^https://")) and
    (.provenance.sourceVersion | type == "string" and length > 0) and
    (.provenance.retrievedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
    (.provenance.licenseUrl | test("^https://")) and
    (.provenance.licenseSnapshotSha256 | test("^[a-f0-9]{64}$")) and
    (.provenance.attribution | type == "string" and length > 0) and
    (.provenance.redistributionStatus == "allowed")
  ' "${path}" >/dev/null; then
    echo "[FAIL] ${relative_path} : contrat client invalide" >&2
    fail_count=$((fail_count + 1))
    return
  fi

  echo "[OK] ${relative_path}"
  pass_count=$((pass_count + 1))
}

for category_dir in "${SIGNED_DIR}"/*/; do
  category_name=$(basename "${category_dir}")
  if [[ -n "${CATEGORY_FILTER}" && "${category_name}" != "${CATEGORY_FILTER}" ]]; then
    continue
  fi
  for manifest in "${category_dir}"*.json; do
    [[ -e "${manifest}" ]] || continue
    pack_id=$(jq -r '.packId' "${manifest}")
    if [[ -n "${PACK_FILTER}" && "${pack_id}" != "${PACK_FILTER}" ]]; then
      continue
    fi
    validate_manifest "${manifest}"
  done
done

echo "====================================="
echo "Résumé : ${pass_count} valide(s), ${fail_count} invalide(s)"
[[ "${pass_count}" -gt 0 && "${fail_count}" -eq 0 ]]
