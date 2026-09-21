#!/usr/bin/env bash
# Vérifie que les deux archives `prayer_audio` se reconstruisent à l'identique.
#
# Usage : ./tools/verify-prayer-audio-reproducible.sh
#
# Le déterminisme du script de construction n'était jusqu'ici qu'une propriété
# observée : deux exécutions avaient donné le même digest. Une propriété
# mesurée une fois n'est pas une propriété garantie, et celle-ci porte deux
# usages qui la supposent acquise. Un tiers doit pouvoir reconstruire une
# archive publiée et retrouver son empreinte sans nous croire sur parole. Et
# l'application développe son installateur contre des archives rebâties
# localement, en comparant leur digest au nôtre : sans reproductibilité, elle
# ne saurait plus si elle teste les octets qui seront réellement publiés.
#
# Ce script relève les empreintes en place, relance la construction, et refuse
# si l'une d'elles a bougé. Il n'altère rien : si les archives sont bien
# déterministes, elles sont réécrites à l'identique.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ARCHIVES=(
  "uploads/prayer-audio/adhan_notification_sounds.zip"
  "uploads/prayer-audio/adhan_sounds_hq.zip"
)

command -v shasum >/dev/null 2>&1 || {
  echo "Erreur : 'shasum' est requis." >&2
  exit 69
}

for archive in "${ARCHIVES[@]}"; do
  [[ -f "${archive}" ]] || {
    echo "Erreur : archive absente (${archive}). Construisez-la d'abord." >&2
    exit 66
  }
done

before=()
for archive in "${ARCHIVES[@]}"; do
  before+=("$(shasum -a 256 "${archive}" | cut -d' ' -f1)")
done

"${REPO_ROOT}/tools/build-prayer-audio-pack.sh" >/dev/null

problems=()
index=0
for archive in "${ARCHIVES[@]}"; do
  after="$(shasum -a 256 "${archive}" | cut -d' ' -f1)"
  if [[ "${after}" != "${before[${index}]}" ]]; then
    problems+=("$(basename "${archive}") : ${before[${index}]} devenu ${after}")
  fi
  index=$((index + 1))
done

if [[ "${#problems[@]}" -gt 0 ]]; then
  echo 'verify-prayer-audio-reproducible: la construction n est pas deterministe' >&2
  for problem in "${problems[@]}"; do
    echo "  - ${problem}" >&2
  done
  exit 1
fi

echo "verify-prayer-audio-reproducible: OK, ${#ARCHIVES[@]} archives reconstruites a l identique"
