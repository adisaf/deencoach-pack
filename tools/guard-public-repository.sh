#!/usr/bin/env bash
# Refuse la publication si un secret ou une clé privée semble suivi par Git.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_PATTERN='-----BEGIN [A-Z ]*PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9]{20,}'

cd "${REPO_ROOT}"

tracked_env_paths="$(git ls-files | grep -E '(^|/)\.env(rc)?($|\.)' | grep -Ev '(^|/)\.env(rc)?\.example$' || true)"
if [[ -n "${tracked_env_paths}" ]]; then
  echo 'Erreur : un fichier .env est suivi par Git.' >&2
  printf '%s\n' "${tracked_env_paths}" >&2
  exit 1
fi

if git grep -IlE -e "${SECRET_PATTERN}" -- . >/dev/null; then
  echo 'Erreur : un secret ou une clé privée potentielle est suivi par Git.' >&2
  git grep -IlE -e "${SECRET_PATTERN}" -- . >&2
  exit 1
fi

echo 'guard-public-repository: OK'
