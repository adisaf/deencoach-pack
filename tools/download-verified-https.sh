#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 3 || "$#" -gt 4 ]]; then
  echo 'Usage : download-verified-https.sh <url> <destination> <max-bytes> [allowed-hosts]' >&2
  exit 64
fi

url="$1"
destination="$2"
maximum_bytes="$3"
allowed_hosts="${4:-}"

[[ "${maximum_bytes}" =~ ^[1-9][0-9]*$ ]] || {
  echo 'Erreur : la taille maximale doit être un entier positif.' >&2
  exit 64
}

for command_name in curl mktemp mv python3 rm sed tr wc; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Erreur : '${command_name}' est requis." >&2
    exit 69
  }
done

temporary_path=$(mktemp "${destination}.download.XXXXXX")
cleanup() {
  rm -f "${temporary_path}"
}
trap cleanup EXIT HUP INT TERM

validate_endpoint() {
  python3 - "$1" "${url}" "${allowed_hosts}" <<'PY'
from urllib.parse import urlparse
import sys

candidate = urlparse(sys.argv[1])
requested = urlparse(sys.argv[2])
configured = {host.strip().lower() for host in sys.argv[3].split(',') if host.strip()}
allowed = configured or {requested.hostname.lower() if requested.hostname else ''}

if (
    requested.scheme != 'https'
    or candidate.scheme != 'https'
    or candidate.username is not None
    or candidate.password is not None
    or candidate.fragment
    or candidate.port not in (None, 443)
    or not candidate.hostname
    or candidate.hostname.lower() not in allowed
):
    raise SystemExit('Erreur : endpoint HTTPS non autorisé.')
PY
}

current_url="${url}"
for redirect_count in 0 1 2 3; do
  validate_endpoint "${current_url}"
  response_metadata=$(curl --fail --retry 3 --retry-all-errors \
    --proto '=https' --connect-timeout 10 --max-time 120 \
    --silent --show-error --max-filesize "${maximum_bytes}" \
    --output "${temporary_path}" --write-out '%{http_code}\n%{redirect_url}' \
    "${current_url}")
  status_code=$(printf '%s\n' "${response_metadata}" | sed -n '1p')
  redirect_url=$(printf '%s\n' "${response_metadata}" | sed -n '2p')

  if [[ "${status_code}" =~ ^2[0-9][0-9]$ ]]; then
    break
  fi
  if [[ "${status_code}" =~ ^30[12378]$ && -n "${redirect_url}" ]]; then
    [[ "${redirect_count}" -lt 3 ]] || {
      echo 'Erreur : limite de redirections HTTPS dépassée.' >&2
      exit 65
    }
    validate_endpoint "${redirect_url}"
    current_url="${redirect_url}"
    continue
  fi
  echo "Erreur : statut HTTP inattendu ${status_code}." >&2
  exit 65
done

actual_bytes=$(wc -c < "${temporary_path}" | tr -d ' ')
[[ "${actual_bytes}" -le "${maximum_bytes}" ]] || {
  echo "Erreur : ressource trop volumineuse (${actual_bytes} octets)." >&2
  exit 65
}

mv "${temporary_path}" "${destination}"
trap - EXIT HUP INT TERM
