#!/usr/bin/env bash
# Vérifie le contenu des deux archives `prayer_audio` avant publication.
#
# Usage : ./tools/verify-prayer-audio-pack.sh <notification.zip> <full-length.zip>
#
# Les deux sont exigées ensemble, bien qu'elles soient publiées et téléchargées
# séparément : le contrôle de provenance compare chaque amorce à son adhan
# intégral, et il perdrait tout son sens sur une archive isolée.
#
# Un SHA-256 prouve qu'une archive n'a pas été altérée ; il ne prouve pas que
# son contenu est jouable, ni qu'il est bien celui qu'il prétend être. Ce
# script contrôle ce que le digest ignore.
#
# Ce script ne porte aucun jugement sur ce qui est entendu. La règle de coupe
# de l'ADR TICKET-191, une unité de sens complète arrêtée sur un silence, et la
# formule de l'adhan elle-même ne se vérifient qu'à l'oreille humaine.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFICATION_ARCHIVE="${1:-}"
FULL_LENGTH_ARCHIVE="${2:-}"

SAMPLE_RATE=22050
MAX_SECONDS=30
DURATION_TOLERANCE=0.15
ATTRIBUTION_ENTRY="ATTRIBUTION.txt"
# Liste de reference des muezzins attendus et de leur point de coupe. Sans
# elle, une archive amputee d'un muezzin resterait coherente avec elle-meme et
# passerait le controle alors qu'elle casserait le son de ce muezzin dans
# l'application.
CUTS_FILE="${REPO_ROOT}/provenance/prayer-audio-adhan-notification/excerpt_cuts.json"

[[ -n "${NOTIFICATION_ARCHIVE}" && -n "${FULL_LENGTH_ARCHIVE}" ]] || {
  echo 'Usage : verify-prayer-audio-pack.sh <notification.zip> <full-length.zip>' >&2
  exit 64
}
for archive in "${NOTIFICATION_ARCHIVE}" "${FULL_LENGTH_ARCHIVE}"; do
  [[ -f "${archive}" ]] || {
    echo "Erreur : archive absente : ${archive}" >&2
    exit 66
  }
done
[[ -f "${CUTS_FILE}" ]] || {
  echo "Erreur : liste de reference absente : ${CUTS_FILE}" >&2
  exit 66
}

for command_name in afconvert afinfo ffmpeg ffprobe python3 unzip; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Erreur : '${command_name}' est requis." >&2
    exit 69
  }
done

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT HUP INT TERM

problems=()

# Chaque archive porte sa propre attribution : distribuee seule, elle reste
# creditee. L'absence dans l'une des deux est un defaut a part entiere.
# Pas de tube ici : `grep -q` ferme le tube des la premiere correspondance,
# `unzip` recoit un SIGPIPE, et `pipefail` transforme le succes en echec.
for archive in "${NOTIFICATION_ARCHIVE}" "${FULL_LENGTH_ARCHIVE}"; do
  archive_entries="$(unzip -Z1 "${archive}")"
  case "${archive_entries}" in
    *"${ATTRIBUTION_ENTRY}"*) ;;
    *) problems+=("$(basename "${archive}") : ${ATTRIBUTION_ENTRY} absent") ;;
  esac
done

# Un texte peut se perimer a chaque evolution du pack sans qu'aucun controle
# d'octets ne s'en apercoive : c'est ainsi que l'attribution a decrit pendant
# un temps un repertoire `notification/` disparu au decoupage. On ne peut pas
# verifier qu'une phrase est vraie, mais on peut verifier que les noms qu'elle
# cite existent, et qu'aucun muezzin livre n'est passe sous silence.
attribution_text="$(unzip -p "${NOTIFICATION_ARCHIVE}" "${ATTRIBUTION_ENTRY}")"

# Les deux archives portent le meme texte, et l'application compte sur cette
# identite pour n'en exposer qu'un seul exemplaire. Une divergence afficherait
# un credit different de celui reellement distribue avec les octets non
# exposes : la verifier ici est le seul endroit ou elle se voit.
full_length_attribution="$(unzip -p "${FULL_LENGTH_ARCHIVE}" "${ATTRIBUTION_ENTRY}")"
[[ "${attribution_text}" == "${full_length_attribution}" ]] || {
  problems+=("${ATTRIBUTION_ENTRY} differe entre les deux archives")
}

for archive in "${NOTIFICATION_ARCHIVE}" "${FULL_LENGTH_ARCHIVE}"; do
  archive_name="$(basename "${archive}")"
  case "${attribution_text}" in
    *"${archive_name}"*) ;;
    *) problems+=("${ATTRIBUTION_ENTRY} ne cite pas l'archive ${archive_name}") ;;
  esac
done

# Les noms ne collident pas entre les deux archives : `<cle>.mp3` pour
# l'integral, `<cle>_intro.*` pour les amorces. Une extraction commune permet
# les controles croises.
unzip -qo "${FULL_LENGTH_ARCHIVE}" -d "${work_dir}"
unzip -qo "${NOTIFICATION_ARCHIVE}" -d "${work_dir}"

expected_keys=()
while IFS= read -r expected_key; do
  expected_keys+=("${expected_key}")
done < <(python3 -c "
import json
with open('${CUTS_FILE}', encoding='utf-8') as handle:
    for key in sorted(json.load(handle)):
        print(key)
")

full_length_count=0
excerpt_count=0

for item_key in "${expected_keys[@]}"; do
  source_path="${work_dir}/${item_key}.mp3"
  if [[ ! -f "${source_path}" ]]; then
    problems+=("${item_key} : adhan integral absent de l'archive")
    continue
  fi
  full_length_count=$((full_length_count + 1))
  expected_cut="$(python3 -c "
import json
with open('${CUTS_FILE}', encoding='utf-8') as handle:
    print(json.load(handle)['${item_key}']['cutSeconds'])
")"

  mp3_excerpt="${work_dir}/${item_key}_intro.mp3"
  caf_excerpt="${work_dir}/${item_key}_intro.caf"

  if [[ ! -f "${mp3_excerpt}" ]]; then
    problems+=("${item_key} : amorce Android absente")
  else
    excerpt_count=$((excerpt_count + 1))
    mp3_duration="$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "${mp3_excerpt}")"
    python3 -c "
import sys
duration, expected = float(sys.argv[1]), float(sys.argv[2])
if duration >= ${MAX_SECONDS}:
    print(f'${item_key} : amorce mp3 de {duration:.2f}s, la limite est ${MAX_SECONDS}s')
if abs(duration - expected) > ${DURATION_TOLERANCE}:
    print(f'${item_key} : amorce mp3 de {duration:.2f}s, coupe enregistree {expected:.2f}s')
" "${mp3_duration}" "${expected_cut}" >> "${work_dir}/problems" || true
  fi

  if [[ ! -f "${caf_excerpt}" ]]; then
    problems+=("${item_key} : amorce iOS absente")
  else
    excerpt_count=$((excerpt_count + 1))
    # `ffprobe` n'ouvre pas l'ima4 : seul `afinfo` lit correctement un CAF
    # encode ainsi, et rendrait une duree nulle si on l'interrogeait autrement.
    afinfo "${caf_excerpt}" | python3 -c "
import re, sys
text = sys.stdin.read()
duration = re.search(r'estimated duration:\s*([\d.]+)\s*sec', text)
data_format = re.search(r'Data format:\s*(\d+)\s*ch,\s*(\d+)\s*Hz,\s*(\S+)', text)
if duration is None or data_format is None:
    print('${item_key} : sortie afinfo illisible pour l\'amorce caf')
    raise SystemExit(0)
channels, sample_rate, codec = int(data_format.group(1)), int(data_format.group(2)), data_format.group(3)
if codec != 'ima4':
    print(f'${item_key} : codec caf {codec}, attendu ima4')
if channels != 1:
    print(f'${item_key} : {channels} canaux dans le caf, attendu 1')
if sample_rate != ${SAMPLE_RATE}:
    print(f'${item_key} : {sample_rate} Hz dans le caf, attendu ${SAMPLE_RATE}')
measured = float(duration.group(1))
if measured >= ${MAX_SECONDS}:
    print(f'${item_key} : amorce caf de {measured:.2f}s, la limite est ${MAX_SECONDS}s')
if abs(measured - ${expected_cut}) > ${DURATION_TOLERANCE}:
    print(f'${item_key} : amorce caf de {measured:.2f}s, coupe enregistree ${expected_cut}s')
" >> "${work_dir}/problems" || true
  fi
done

# Chaque muezzin livre doit etre credite nommement, et l'attribution ne doit
# pas citer de cle absente des archives.
for item_key in "${expected_keys[@]}"; do
  case "${attribution_text}" in
    *"${item_key}"*) ;;
    *) problems+=("${item_key} : absent de ${ATTRIBUTION_ENTRY}, muezzin non credite") ;;
  esac
done
while IFS= read -r cited_key; do
  case " ${expected_keys[*]} " in
    *" ${cited_key} "*) ;;
    *) problems+=("${ATTRIBUTION_ENTRY} cite ${cited_key}, absent des archives") ;;
  esac
done < <(printf '%s\n' "${attribution_text}" \
  | sed -n 's/^ *\(adhan_[a-z0-9_]*\) .*/\1/p' | sort -u)

# Les amorces ne doivent porter AUCUNE metadonnee. Les integraux d'Assabile
# arrivent avec des balises ID3 qui nomment un site tiers, un logiciel de
# montage et un titre arabe ; les recopier reviendrait a distribuer tout cela
# dans un son de notification. C'est aussi ce qui rend l'encodage
# reproductible : une balise de date ou d'encodeur suffit a faire diverger
# deux sorties issues du meme flux audio. Verifier l'absence ici protege
# l'artefact quel que soit l'outil qui l'a produit, sans dependre d'un autre
# depot.
for item_key in "${expected_keys[@]}"; do
  excerpt="${work_dir}/${item_key}_intro.mp3"
  [[ -f "${excerpt}" ]] || continue
  excerpt_tags="$(ffprobe -v error -show_entries format_tags \
    -of default=noprint_wrappers=1 "${excerpt}")"
  [[ -z "${excerpt_tags}" ]] || {
    problems+=("${item_key} : l'amorce mp3 porte des metadonnees, attendu aucune")
  }
done

[[ "${full_length_count}" -eq "${#expected_keys[@]}" ]] || {
  problems+=("${full_length_count} adhans integraux pour ${#expected_keys[@]} attendus")
}

# Une entree inattendue signale une archive construite autrement que par le
# script versionne.
while IFS= read -r stray_path; do
  stray_key="$(basename "${stray_path}" .mp3)"
  [[ "${stray_key}" == *_intro ]] && continue
  case " ${expected_keys[*]} " in
    *" ${stray_key} "*) ;;
    *) problems+=("${stray_key}.mp3 : fichier inattendu dans les archives") ;;
  esac
done < <(find "${work_dir}" -maxdepth 1 -type f -name 'adhan_*.mp3')

# Format et provenance sont deux proprietes distinctes. Une amorce decoupee
# depuis le mauvais fichier source porterait le bon nom, le bon codec, le bon
# nombre de canaux, la bonne frequence et la bonne duree, et donnerait la voix
# d'un autre muezzin sous le nom affiche. Rien de ce qui precede ne le voit.
# On compare donc l'enveloppe d'energie de chaque amorce au debut de son
# integral homonyme : meme enregistrement, la correlation vaut 1 ; deux
# muezzins differents, elle s'effondre.
python3 - "${work_dir}" "${CUTS_FILE}" >> "${work_dir}/problems" <<'PYTHON' || true
import array
import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

work_dir, cuts_file = Path(sys.argv[1]), Path(sys.argv[2])

SAMPLE_RATE = 8000
WINDOW_SAMPLES = SAMPLE_RATE // 20  # fenêtres de 50 ms
SAME_RECORDING_FLOOR = 0.95


def decode(path, seconds):
    """Rend les `seconds` premières secondes en PCM mono 8 kHz signé 16 bits."""
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-t", f"{seconds}",
         "-map", "0:a:0", "-ac", "1", "-ar", str(SAMPLE_RATE),
         "-f", "s16le", "-"],
        capture_output=True, check=True,
    )
    samples = array.array("h")
    samples.frombytes(result.stdout[: len(result.stdout) // 2 * 2])
    return samples


def decode_caf(path, seconds):
    """Même chose pour un CAF/ima4, qu'ffmpeg refuse d'ouvrir entièrement.

    `afconvert` est le seul chemin sur macOS : il ne sait pas tronquer, donc
    la troncature se fait sur les échantillons rendus.
    """
    with tempfile.TemporaryDirectory() as temporary_dir:
        wave_path = Path(temporary_dir) / "decoded.wav"
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", f"LEI16@{SAMPLE_RATE}", "-c", "1",
             str(path), str(wave_path)],
            capture_output=True, check=True,
        )
        with wave.open(str(wave_path), "rb") as handle:
            frames = handle.readframes(int(seconds * SAMPLE_RATE))
    samples = array.array("h")
    samples.frombytes(frames[: len(frames) // 2 * 2])
    return samples


def energy_envelope(samples):
    windows = len(samples) // WINDOW_SAMPLES
    return [
        sum(value * value for value in samples[index * WINDOW_SAMPLES:(index + 1) * WINDOW_SAMPLES])
        / WINDOW_SAMPLES
        for index in range(windows)
    ]


def correlation(left, right):
    length = min(len(left), len(right))
    if length < 2:
        return None
    left, right = left[:length], right[:length]
    mean_left, mean_right = sum(left) / length, sum(right) / length
    covariance = sum((a - mean_left) * (b - mean_right) for a, b in zip(left, right))
    variance_left = sum((a - mean_left) ** 2 for a in left)
    variance_right = sum((b - mean_right) ** 2 for b in right)
    if variance_left <= 0 or variance_right <= 0:
        return None
    return covariance / (variance_left * variance_right) ** 0.5


with cuts_file.open(encoding="utf-8") as handle:
    cuts = json.load(handle)

for item_key in sorted(cuts):
    full_length = work_dir / f"{item_key}.mp3"
    if not full_length.exists():
        continue
    cut_seconds = cuts[item_key]["cutSeconds"]
    try:
        reference = energy_envelope(decode(full_length, cut_seconds))
    except subprocess.CalledProcessError:
        print(f"{item_key} : integral indecodable pour le controle de provenance")
        continue

    # Les deux amorces sont contrôlées séparément : elles sortent de deux
    # invocations ffmpeg indépendantes, donc l'une peut diverger sans l'autre.
    # Le .caf est le fichier qu'iOS joue réellement.
    for suffix, decoder in ((".mp3", decode), (".caf", decode_caf)):
        excerpt = work_dir / f"{item_key}_intro{suffix}"
        if not excerpt.exists():
            continue
        try:
            measured = correlation(energy_envelope(decoder(excerpt, cut_seconds)), reference)
        except subprocess.CalledProcessError:
            print(f"{item_key} : amorce {suffix} indecodable pour le controle de provenance")
            continue
        if measured is None:
            print(f"{item_key} : enveloppe d'energie inexploitable pour l'amorce {suffix}")
        elif measured < SAME_RECORDING_FLOOR:
            print(
                f"{item_key} : l'amorce {suffix} ne provient pas de l'integral homonyme "
                f"(correlation {measured:.4f}, plancher {SAME_RECORDING_FLOOR})"
            )
PYTHON

if [[ -s "${work_dir}/problems" ]]; then
  while IFS= read -r line; do
    [[ -n "${line}" ]] && problems+=("${line}")
  done < "${work_dir}/problems"
fi

if [[ "${#problems[@]}" -gt 0 ]]; then
  echo "verify-prayer-audio-pack: defauts" >&2
  for problem in "${problems[@]}"; do
    echo "  - ${problem}" >&2
  done
  exit 1
fi

echo "verify-prayer-audio-pack: OK, ${full_length_count} adhans et ${excerpt_count} amorces conformes"
echo "L'ecoute humaine reste due : la coupe s'entend sur l'amorce, la formule sur l'integral."
