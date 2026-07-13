#!/usr/bin/env bash
# Publie une catégorie de packs dont les manifests sont vérifiés par le client.
# Usage : ./tools/release-signed-pack-category.sh <verify|tag|publish|verify-published> <category> <release-tag>

set -euo pipefail

readonly EXPECTED_REPOSITORY='adisaf/deencoach-pack'
readonly EXPECTED_GITHUB_LOGIN='adisaf'
readonly EXPECTED_GIT_AUTHOR_NAME='Fawaz ADISA'
readonly EXPECTED_GIT_AUTHOR_EMAIL='adisaf@programmer.net'
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SIGNED_MANIFESTS_DIR="${REPO_ROOT}/signed-manifests"
readonly PUBLIC_KEY_PATH='keys/deencoach-pack-2026-07.pub.pem'

ACTION="${1:-}"
CATEGORY="${2:-}"
RELEASE_TAG="${3:-}"
PACK_VERSION=''
MANIFESTS=()
ASSETS=()
TEMPORARY_PATHS=()

cleanup() {
  local temporary_path
  for temporary_path in "${TEMPORARY_PATHS[@]}"; do
    rm -rf "${temporary_path}"
  done
}

trap cleanup EXIT

fail() {
  echo "Erreur : $*" >&2
  exit 1
}

require_commands() {
  local command_name
  for command_name in cmp curl find gh git jq shasum sort uniq wc; do
    command -v "${command_name}" >/dev/null 2>&1 || {
      fail "'${command_name}' est requis."
    }
  done
}

validate_arguments() {
  case "${ACTION}" in
    verify|tag|publish|verify-published) ;;
    *) fail 'action attendue : verify, tag, publish ou verify-published.' ;;
  esac

  [[ "${RELEASE_TAG}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    fail "tag de release invalide : ${RELEASE_TAG:-absent}."
  }

  case "${CATEGORY}" in
    quran-text)
      PACK_VERSION="${RELEASE_TAG#quran-text-v}"
      ;;
    quran-translations)
      PACK_VERSION="${RELEASE_TAG#quranenc-translations-v}"
      ;;
    *) fail "catégorie non publiable par ce runbook : ${CATEGORY:-absente}." ;;
  esac

  [[ "${PACK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    fail "le tag ${RELEASE_TAG} ne correspond pas à la version attendue pour ${CATEGORY}."
  }
}

collect_manifests() {
  local manifest
  local category_dir="${SIGNED_MANIFESTS_DIR}/${CATEGORY}"

  [[ -d "${category_dir}" ]] || fail "manifests absents pour ${CATEGORY}."
  while IFS= read -r manifest; do
    MANIFESTS+=("${manifest}")
  done < <(find "${category_dir}" -maxdepth 1 -type f -name '*.json' | sort)

  [[ "${#MANIFESTS[@]}" -gt 0 ]] || {
    fail "aucun manifest signé pour ${CATEGORY}."
  }
}

validate_manifest_urls() {
  local manifest="$1"
  local expected_prefix="https://github.com/${EXPECTED_REPOSITORY}/releases/download/${RELEASE_TAG}/"

  jq -e --arg expected_prefix "${expected_prefix}" --arg pack_version "${PACK_VERSION}" '
    .packId as $pack_id |
    (.version == $pack_version) and
    (.signingKeyId == "deencoach-pack-2026-07") and
    ([.artifacts[] |
      (.url == ($expected_prefix + .fileName)) and
      (.relativePath == ($pack_id + "/" + .fileName))
    ] | all)
  ' "${manifest}" >/dev/null || {
    fail "les URLs du manifest ${manifest#${REPO_ROOT}/} ne correspondent pas au tag ${RELEASE_TAG}."
  }
}

resolve_asset_path() {
  local pack_id="$1"
  local file_name="$2"

  case "${CATEGORY}" in
    quran-text) echo "${REPO_ROOT}/uploads/quran-text/${file_name}" ;;
    quran-translations)
      echo "${REPO_ROOT}/uploads/quranenc-translations/${pack_id}/${file_name}"
      ;;
  esac
}

collect_and_verify_assets() {
  local manifest pack_id file_name expected_sha expected_bytes
  local asset_path actual_sha actual_bytes
  local asset_names_file

  asset_names_file="$(mktemp)"
  TEMPORARY_PATHS+=("${asset_names_file}")

  for manifest in "${MANIFESTS[@]}"; do
    validate_manifest_urls "${manifest}"
    while IFS=$'\t' read -r pack_id file_name expected_sha expected_bytes; do
      asset_path="$(resolve_asset_path "${pack_id}" "${file_name}")"
      [[ -f "${asset_path}" ]] || fail "artefact local absent : ${asset_path#${REPO_ROOT}/}."

      actual_sha="$(shasum -a 256 "${asset_path}" | awk '{print $1}')"
      actual_bytes="$(wc -c < "${asset_path}" | tr -d ' ')"
      [[ "${actual_sha}" == "${expected_sha}" ]] || {
        fail "SHA-256 local invalide : ${asset_path#${REPO_ROOT}/}."
      }
      [[ "${actual_bytes}" == "${expected_bytes}" ]] || {
        fail "taille locale invalide : ${asset_path#${REPO_ROOT}/}."
      }

      ASSETS+=("${asset_path}")
      printf '%s\n' "${file_name}" >> "${asset_names_file}"
    done < <(
      jq -r '.packId as $pack_id | .artifacts[] |
        [$pack_id, .fileName, .sha256, (.expectedBytes | tostring)] | @tsv' "${manifest}"
    )
  done

  [[ "${#ASSETS[@]}" -gt 0 ]] || fail 'aucun artefact à publier.'
  if sort "${asset_names_file}" | uniq -d | grep -q .; then
    fail 'des noms de fichiers d’artefacts sont dupliqués dans la même release.'
  fi
}

validate_signed_manifests() {
  "${REPO_ROOT}/tools/validate-client-manifests.sh" "${CATEGORY}"
  "${REPO_ROOT}/tools/verify-client-manifest-signatures.sh"
}

validate_local_contract() {
  local manifest

  "${REPO_ROOT}/tools/guard-public-repository.sh"
  validate_signed_manifests
  collect_and_verify_assets

  for manifest in "${MANIFESTS[@]}"; do
    if [[ "${CATEGORY}" == 'quran-text' ]]; then
      "${REPO_ROOT}/tools/verify-quran-text-pack.sh" \
        "$(resolve_asset_path "$(jq -r '.packId' "${manifest}")" "$(jq -r '.artifacts[0].fileName' "${manifest}")")"
    else
      "${REPO_ROOT}/tools/verify-quranenc-translation-pack.sh" \
        "$(jq -r '.packId' "${manifest}")"
    fi
  done
}

verify_published_manifest_sources() {
  local file_path relative_path

  git fetch --quiet origin main
  for file_path in "${MANIFESTS[@]}" "${PUBLIC_KEY_PATH/#/${REPO_ROOT}/}"; do
    for file_path in "${file_path}" "${file_path}.sig"; do
      [[ "${file_path}" == *.sig && ! -f "${file_path}" ]] && continue
      relative_path="${file_path#${REPO_ROOT}/}"
      git cat-file -e "origin/main:${relative_path}" || {
        fail "${relative_path} n’est pas encore publié sur origin/main."
      }
      git show "origin/main:${relative_path}" | cmp -s - "${file_path}" || {
        fail "${relative_path} local diffère de la version sur origin/main."
      }
    done
  done
}

verify_github_target() {
  local actual_repository actual_login

  actual_repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" || {
    fail 'impossible de vérifier le dépôt GitHub ciblé.'
  }
  [[ "${actual_repository}" == "${EXPECTED_REPOSITORY}" ]] || {
    fail "dépôt GitHub inattendu : ${actual_repository}."
  }
  actual_login="$(gh api user --jq '.login')" || {
    fail 'impossible de vérifier le compte GitHub opérateur.'
  }
  [[ "${actual_login}" == "${EXPECTED_GITHUB_LOGIN}" ]] || {
    fail "compte GitHub inattendu : ${actual_login}."
  }
}

assert_git_identity() {
  local author_name author_email

  author_name="$(git config user.name)"
  author_email="$(git config user.email)"
  [[ "${author_name}" == "${EXPECTED_GIT_AUTHOR_NAME}" ]] || {
    fail "auteur Git inattendu : ${author_name}."
  }
  [[ "${author_email}" == "${EXPECTED_GIT_AUTHOR_EMAIL}" ]] || {
    fail "email Git inattendu : ${author_email}."
  }
}

assert_remote_tag_absent() {
  if git ls-remote --exit-code --tags origin "refs/tags/${RELEASE_TAG}" \
    >/dev/null 2>&1; then
    fail "le tag ${RELEASE_TAG} existe déjà."
  fi
}

assert_published_annotated_tag() {
  local tag_commit main_commit

  git fetch --quiet origin "refs/tags/${RELEASE_TAG}:refs/tags/${RELEASE_TAG}"
  [[ "$(git cat-file -t "${RELEASE_TAG}")" == 'tag' ]] || {
    fail "${RELEASE_TAG} doit être un tag annoté publié."
  }
  tag_commit="$(git rev-list -n1 "${RELEASE_TAG}")"
  main_commit="$(git rev-parse origin/main)"
  [[ "${tag_commit}" == "${main_commit}" ]] || {
    fail "${RELEASE_TAG} doit pointer exactement sur origin/main."
  }
}

create_annotated_tag() {
  local release_target

  assert_git_identity
  assert_remote_tag_absent
  release_target="$(git rev-parse origin/main)"
  git tag -a "${RELEASE_TAG}" "${release_target}" \
    -m "Deen Coach pack release ${RELEASE_TAG}"
  git push origin "refs/tags/${RELEASE_TAG}"
  assert_published_annotated_tag
}

assert_release_absent() {
  local release_tags

  release_tags="$(gh release list --repo "${EXPECTED_REPOSITORY}" --limit 1000 --json tagName --jq '.[].tagName')" || {
    fail 'impossible de vérifier les releases GitHub existantes.'
  }
  if printf '%s\n' "${release_tags}" | grep -Fxq "${RELEASE_TAG}"; then
    fail "la release ${RELEASE_TAG} existe déjà : une release de packs est immuable."
  fi
}

write_release_notes() {
  local notes_file="$1"
  local manifest

  {
    printf '# Deen Coach pack release %s\n\n' "${RELEASE_TAG}"
    printf 'Les manifests joints au dépôt sont signés Ed25519 et vérifiés par le client Deen Coach avant tout téléchargement.\n\n'
    printf '## Packs\n\n'
    for manifest in "${MANIFESTS[@]}"; do
      jq -r '"- `\(.packId)` v\(.version) : \(.provenance.attribution)\n  - Source : \(.provenance.sourceAuthority), \(.provenance.sourceUrl)\n  - Licence : \(.provenance.licenseUrl)\n  - Version source : \(.provenance.sourceVersion)"' \
        "${manifest}"
    done
    printf '\n## Vérification\n\n'
    printf 'Chaque artefact a été contrôlé localement puis après publication contre le SHA-256 et la taille déclarés dans son manifest signé.\n'
  } > "${notes_file}"
}

verify_remote_assets() {
  local manifest pack_id file_name expected_sha expected_bytes url
  local temporary_dir downloaded_path actual_sha actual_bytes verified_count=0

  temporary_dir="$(mktemp -d)"
  TEMPORARY_PATHS+=("${temporary_dir}")

  for manifest in "${MANIFESTS[@]}"; do
    while IFS=$'\t' read -r pack_id file_name expected_sha expected_bytes url; do
      downloaded_path="${temporary_dir}/${pack_id}-${file_name}"
      curl --fail --location --retry 3 --retry-all-errors \
        --connect-timeout 10 --max-time 120 --silent --show-error \
        "${url}" --output "${downloaded_path}" || {
        fail "téléchargement public échoué : ${url}."
      }
      actual_sha="$(shasum -a 256 "${downloaded_path}" | awk '{print $1}')"
      actual_bytes="$(wc -c < "${downloaded_path}" | tr -d ' ')"
      [[ "${actual_sha}" == "${expected_sha}" ]] || {
        fail "SHA-256 public invalide : ${url}."
      }
      [[ "${actual_bytes}" == "${expected_bytes}" ]] || {
        fail "taille publique invalide : ${url}."
      }
      verified_count=$((verified_count + 1))
    done < <(
      jq -r '.packId as $pack_id | .artifacts[] |
        [$pack_id, .fileName, .sha256, (.expectedBytes | tostring), .url] | @tsv' "${manifest}"
    )
  done

  echo "[OK] ${verified_count} artefact(s) publics vérifiés."
}

publish_release() {
  local notes_file

  notes_file="$(mktemp)"
  TEMPORARY_PATHS+=("${notes_file}")
  write_release_notes "${notes_file}"

  gh release create "${RELEASE_TAG}" \
    --repo "${EXPECTED_REPOSITORY}" \
    --verify-tag \
    --title "Deen Coach packs ${RELEASE_TAG}" \
    --notes-file "${notes_file}" \
    "${ASSETS[@]}"
}

main() {
  cd "${REPO_ROOT}"
  require_commands
  validate_arguments
  collect_manifests
  "${REPO_ROOT}/tools/guard-public-repository.sh"

  case "${ACTION}" in
    verify)
      validate_local_contract
      verify_published_manifest_sources
      verify_github_target
      echo "[OK] pré-vérification réussie : ${CATEGORY} est publiable sous ${RELEASE_TAG}."
      ;;
    tag)
      validate_local_contract
      verify_published_manifest_sources
      verify_github_target
      create_annotated_tag
      echo "[OK] tag annoté ${RELEASE_TAG} publié."
      ;;
    publish)
      validate_local_contract
      verify_published_manifest_sources
      verify_github_target
      assert_release_absent
      assert_published_annotated_tag
      publish_release
      verify_remote_assets
      echo "[OK] release ${RELEASE_TAG} publiée et vérifiée."
      ;;
    verify-published)
      validate_signed_manifests
      verify_published_manifest_sources
      for manifest in "${MANIFESTS[@]}"; do
        validate_manifest_urls "${manifest}"
      done
      verify_github_target
      verify_remote_assets
      ;;
  esac
}

main "$@"
