#!/usr/bin/env bash
# Refuse la publication si un secret ou une clé privée semble suivi par Git.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_PATTERN='-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9]{20,}'

cd "${REPO_ROOT}"

command -v rg >/dev/null 2>&1 || {
  echo "Erreur : 'rg' est requis pour contrôler les fichiers suivis." >&2
  exit 1
}

tracked_env_paths="$(git ls-files | rg '(^|/)\.env($|\.)' | rg -v '(^|/)\.env\.example$' || true)"
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
