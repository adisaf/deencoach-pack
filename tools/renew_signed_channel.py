"""Prepare an atomic signed-channel renewal, without publishing anything.

The source checkout is read-only. Its committed HEAD must equal public main.
All old immutable bytes stay intact; the output contains new revisions and one
new signed index. The current client security policy is never changed.
"""

import argparse
import base64
import copy
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

REMOTE = 'https://github.com/adisaf/deencoach-pack.git'
KEY_ID = 'deencoach-pack-2026-07'
KEYCHAIN_SERVICE = 'deencoach-pack-ed25519-2026-07'
INDEX = 'active-revisions.json'


class RenewalError(ValueError):
    """A channel invariant prevents preparing a valid renewal."""


def command(*arguments, **kwargs):
    return subprocess.check_output(arguments, stderr=subprocess.PIPE, **kwargs)


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def timestamp(value):
    return value.strftime('%Y-%m-%dT%H:%M:%SZ')


def plan_renewal(signed_root, now, validity_days=90):
    """Pure metadata renewal: preserve every artifact and provenance field."""
    if not 15 <= validity_days <= 90:
        raise RenewalError('Validity must remain between 15 and 90 days')
    index = json.loads((signed_root / INDEX).read_bytes())
    if index.get('signingKeyId') != KEY_ID or index.get('schemaVersion') != 1:
        raise RenewalError('Unsupported signing identity or index schema')
    sequence = index.get('sequence')
    if type(sequence) is not int or sequence < 1:
        raise RenewalError('Invalid previous sequence')
    entries = index.get('revisions', [])
    if not entries or len({entry['packId'] for entry in entries}) != len(entries):
        raise RenewalError('Missing or duplicate active packs')
    renewed = copy.deepcopy(index)
    renewed.update(sequence=sequence + 1, issuedAt=timestamp(now),
                   expiresAt=timestamp(now + dt.timedelta(days=validity_days)))
    candidates = {}
    for entry in renewed['revisions']:
        pack_id, category, previous_path = (
            entry['packId'], entry['category'], entry['manifest'])
        pattern = rf'{re.escape(category)}/{re.escape(pack_id)}-r([1-9][0-9]*)\.json'
        if (category not in ('quran-text', 'quran-translations') or
                not re.fullmatch('[a-z0-9_]+', pack_id) or
                not re.fullmatch(pattern, previous_path)):
            raise RenewalError('Invalid active manifest path')
        previous = json.loads((signed_root / previous_path).read_bytes())
        if previous.get('packId') != pack_id or previous.get('signingKeyId') != KEY_ID:
            raise RenewalError('Active manifest identity mismatch')
        revisions = [int(match.group(1))
                     for path in signed_root.rglob('*.json')
                     if (match := re.fullmatch(pattern, path.relative_to(signed_root).as_posix()))]
        next_path = f'{category}/{pack_id}-r{max(revisions) + 1}.json'
        if (signed_root / (next_path + '.sig')).exists():
            raise RenewalError('An orphan signature occupies the next immutable revision')
        candidate = copy.deepcopy(previous)
        candidate.update(issuedAt=renewed['issuedAt'], expiresAt=renewed['expiresAt'])
        candidates[next_path] = canonical(candidate)
        entry['manifest'] = next_path
    candidates[INDEX] = canonical(renewed)
    return candidates


def public_head():
    response = command('git', 'ls-remote', REMOTE, 'refs/heads/main', text=True)
    fields = response.split()
    if len(fields) != 2 or not re.fullmatch('[a-f0-9]{40}', fields[0]):
        raise RenewalError('Cannot establish public main identity')
    return fields[0]


def extract_committed_source(source, destination):
    archive = command('git', '-C', str(source), 'archive', 'HEAD',
                      'signed-manifests', 'keys', 'tools')
    with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
        for member in contents.getmembers():
            if (member.issym() or member.islnk() or
                    Path(member.name).is_absolute() or '..' in Path(member.name).parts):
                raise RenewalError('Unsafe source archive entry')
        contents.extractall(destination, filter='data')


def sign_candidates(stage, candidates):
    """Use the existing local signing identity; never emit or retain its key."""
    signed = stage / 'signed-manifests'
    public_key = stage / 'keys' / f'{KEY_ID}.pub.pem'
    with tempfile.TemporaryDirectory(prefix='deen-channel-key-') as directory:
        private_key = Path(directory) / 'signing.pem'
        encoded = command('security', 'find-generic-password', '-s', KEYCHAIN_SERVICE, '-w')
        with open(private_key, 'xb', opener=lambda path, flags: os.open(path, flags, 0o600)) as handle:
            handle.write(base64.b64decode(encoded.strip(), validate=True))
        del encoded
        derived = command('openssl', 'pkey', '-in', str(private_key), '-pubout')
        if derived.strip() != public_key.read_bytes().strip():
            raise RenewalError('Keychain signing identity differs from trusted public key')
        for relative, payload in candidates.items():
            path = signed / relative
            if relative != INDEX and path.exists():
                raise RenewalError('Immutable revision collision')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
            command('openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(private_key),
                    '-in', str(path), '-out', str(path) + '.sig')


def validate_bundle(stage, candidates):
    environment = dict(os.environ, SIGNED_DIR_OVERRIDE=str(stage / 'signed-manifests'))
    for script in ('validate-client-manifests.sh', 'verify-client-manifest-signatures.sh'):
        command('bash', str(stage / 'tools' / script), env=environment, cwd=stage)
    for relative in candidates:
        if relative != INDEX:
            command('bash', str(stage / 'tools/verify-signed-manifest-artifacts.sh'),
                    str(stage / 'signed-manifests' / relative), env=environment, cwd=stage)


def prepare(source, output, validity_days):
    if output.exists() or not output.parent.is_dir():
        raise RenewalError('Output must be new and its parent must exist')
    baseline = public_head()
    local_head = command('git', '-C', str(source), 'rev-parse', 'HEAD', text=True).strip()
    if local_head != baseline:
        raise RenewalError('Source HEAD differs from public main; refresh a separate checkout')
    with tempfile.TemporaryDirectory(dir=output.parent, prefix='.channel-renewal-') as temporary:
        work = Path(temporary)
        stage = work / 'repository'
        stage.mkdir()
        extract_committed_source(source, stage)
        # Existing validators fetch origin/main. Their owning repository must
        # be this disposable public checkout, never the caller's working tree.
        command('git', 'init', '--quiet', str(stage))
        command('git', '-C', str(stage), 'remote', 'add', 'origin', REMOTE)
        command('bash', str(stage / 'tools/verify-client-manifest-signatures.sh'), cwd=stage)
        old_index = (stage / 'signed-manifests' / INDEX).read_bytes()
        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
        candidates = plan_renewal(stage / 'signed-manifests', now, validity_days)
        sign_candidates(stage, candidates)
        validate_bundle(stage, candidates)
        if public_head() != baseline:
            raise RenewalError('Public main changed during preparation; discard and retry')
        shutil.rmtree(stage / '.git')
        identities = {relative: hashlib.sha256((stage / 'signed-manifests' / relative).read_bytes()).hexdigest()
                      for path in candidates for relative in (path, path + '.sig')}
        report = {'preparedAt': timestamp(now), 'sourceCommit': baseline,
                  'previousIndexSha256': hashlib.sha256(old_index).hexdigest(),
                  'previousSequence': json.loads(old_index)['sequence'],
                  'nextSequence': json.loads(candidates[INDEX])['sequence'],
                  'expiresAt': json.loads(candidates[INDEX])['expiresAt'],
                  'renewBefore': timestamp(now + dt.timedelta(days=validity_days - 30)),
                  'verifiedPublicPacks': len(candidates) - 1,
                  'verifiedPublicArtifacts': sum(
                      len(json.loads(payload)['artifacts'])
                      for path, payload in candidates.items() if path != INDEX),
                  'files': identities, 'published': False}
        (work / 'renewal-identity.json').write_bytes(canonical(report))
        # Rename exposes only a fully signed and validated bundle.
        os.rename(work, output)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--validity-days', type=int, default=90)
    arguments = parser.parse_args()
    try:
        report = prepare(arguments.source_root.resolve(), arguments.output.resolve(), arguments.validity_days)
    except (RenewalError, OSError, subprocess.CalledProcessError, ValueError) as error:
        # Never print child-process stdout: security's stdout contains key bytes.
        detail = error.stderr.decode(errors='replace') if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        raise SystemExit(f'Renewal preparation failed: {detail}') from None
    print(f"Prepared sequence {report['nextSequence']}; {report['verifiedPublicPacks']} packs; publication still required.")


if __name__ == '__main__':
    main()
