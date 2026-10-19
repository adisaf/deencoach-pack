import copy
import base64
import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from renew_signed_channel import INDEX, KEY_ID, RenewalError, canonical, command, plan_renewal, sign_candidates, validate_bundle


class RenewalPlanTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.now = dt.datetime(2026, 10, 19, tzinfo=dt.timezone.utc)
        self.previous = {
            'packId': 'quran_translation_fr_noor', 'signingKeyId': KEY_ID,
            'version': '1.0.0', 'issuedAt': '2026-07-16T00:00:00Z',
            'expiresAt': '2026-10-14T00:00:00Z',
            'artifacts': [{'sha256': 'a' * 64, 'expectedBytes': 123,
                           'url': 'https://github.com/adisaf/deencoach-pack/releases/download/v1/noor.zip'}],
            'provenance': {'attribution': 'Unchanged source attribution'},
        }
        self.relative = 'quran-translations/quran_translation_fr_noor-r2.json'
        self.path = self.root / self.relative
        self.path.parent.mkdir()
        self.path.write_bytes(canonical(self.previous))
        self.index = {'schemaVersion': 1, 'sequence': 1, 'signingKeyId': KEY_ID,
                      'issuedAt': self.previous['issuedAt'], 'expiresAt': self.previous['expiresAt'],
                      'revisions': [{'packId': self.previous['packId'],
                                     'category': 'quran-translations', 'manifest': self.relative}]}
        self.write_index()

    def write_index(self):
        (self.root / INDEX).write_bytes(canonical(self.index))

    def test_expired_channel_renews_atomically_without_mutating_previous_bytes(self):
        original_manifest = self.path.read_bytes()
        original_index = (self.root / INDEX).read_bytes()
        result = plan_renewal(self.root, self.now)
        new_index = json.loads(result[INDEX])
        self.assertEqual(new_index['sequence'], 2)
        next_path = new_index['revisions'][0]['manifest']
        self.assertTrue(next_path.endswith('-r3.json'))
        candidate = json.loads(result[next_path])
        expected = dict(self.previous, issuedAt='2026-10-19T00:00:00Z', expiresAt='2027-01-17T00:00:00Z')
        self.assertEqual(candidate, expected)
        self.assertEqual(self.path.read_bytes(), original_manifest)
        self.assertEqual((self.root / INDEX).read_bytes(), original_index)
        self.assertFalse((self.root / next_path).exists())

    def test_existing_inactive_revision_is_never_replaced(self):
        occupied = self.root / self.relative.replace('-r2', '-r3')
        occupied.write_bytes(b'immutable old bytes')
        result = plan_renewal(self.root, self.now)
        self.assertTrue(json.loads(result[INDEX])['revisions'][0]['manifest'].endswith('-r4.json'))
        self.assertEqual(occupied.read_bytes(), b'immutable old bytes')

    def test_orphan_signature_is_a_collision(self):
        (self.root / (self.relative.replace('-r2', '-r3') + '.sig')).write_bytes(b'old')
        with self.assertRaises(RenewalError):
            plan_renewal(self.root, self.now)

    def test_invalid_validity_is_rejected(self):
        for days in (-1, 0, 14, 91):
            with self.subTest(days=days), self.assertRaises(RenewalError):
                plan_renewal(self.root, self.now, days)

    def test_rollback_or_invalid_sequence_is_rejected(self):
        for sequence in (0, -1, True, '2'):
            self.index['sequence'] = sequence
            self.write_index()
            with self.subTest(sequence=sequence), self.assertRaises(RenewalError):
                plan_renewal(self.root, self.now)

    def test_unsafe_or_inconsistent_paths_are_rejected(self):
        for path in ('../escape-r2.json', 'quran-text/quran_translation_fr_noor-r2.json'):
            self.index['revisions'][0]['manifest'] = path
            self.write_index()
            with self.subTest(path=path), self.assertRaises(RenewalError):
                plan_renewal(self.root, self.now)

    def test_pack_identity_mismatch_is_rejected(self):
        self.path.write_bytes(canonical(dict(self.previous, packId='another')))
        with self.assertRaises(RenewalError):
            plan_renewal(self.root, self.now)

    def test_duplicate_packs_are_rejected(self):
        self.index['revisions'].append(copy.deepcopy(self.index['revisions'][0]))
        self.write_index()
        with self.assertRaises(RenewalError):
            plan_renewal(self.root, self.now)


class SigningTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.stage = Path(self.temporary.name)
        (self.stage / 'signed-manifests').mkdir()
        (self.stage / 'keys').mkdir()
        self.private = command('openssl', 'genpkey', '-algorithm', 'ED25519')
        self.public = self.stage / 'keys' / f'{KEY_ID}.pub.pem'
        self.public.write_bytes(command('openssl', 'pkey', '-pubout', input=self.private))

    def run_signer(self, candidates):
        def execute(*arguments, **kwargs):
            if arguments[0] == 'security':
                return base64.b64encode(self.private)
            return command(*arguments, **kwargs)
        with patch('renew_signed_channel.command', side_effect=execute):
            sign_candidates(self.stage, candidates)

    def verify(self, path):
        return command('openssl', 'pkeyutl', '-verify', '-rawin', '-pubin',
                       '-inkey', str(self.public), '-in', str(path), '-sigfile', str(path) + '.sig')

    def test_signatures_verify_but_reject_tampered_bytes(self):
        import subprocess
        self.run_signer({INDEX: b'{"sequence":2}\n'})
        path = self.stage / 'signed-manifests' / INDEX
        self.verify(path)
        self.assertEqual(len(Path(str(path) + '.sig').read_bytes()), 64)
        path.write_bytes(b'{"sequence":1}\n')
        with self.assertRaises(subprocess.CalledProcessError):
            self.verify(path)

    def test_wrong_key_is_rejected_before_candidate_write(self):
        self.private = command('openssl', 'genpkey', '-algorithm', 'ED25519')
        with self.assertRaises(RenewalError):
            self.run_signer({INDEX: b'{}'})
        self.assertFalse((self.stage / 'signed-manifests' / INDEX).exists())

    def test_immutable_collision_is_rejected(self):
        path = self.stage / 'signed-manifests' / 'existing-r2.json'
        path.write_bytes(b'original')
        with self.assertRaises(RenewalError):
            self.run_signer({'existing-r2.json': b'changed'})
        self.assertEqual(path.read_bytes(), b'original')

    def test_validators_run_only_in_the_disposable_public_repository(self):
        with patch('renew_signed_channel.command') as execute:
            validate_bundle(self.stage, {INDEX: b'{}', 'quran-translations/test-r3.json': b'{}'})
        self.assertEqual(execute.call_count, 3)
        for call in execute.call_args_list:
            self.assertEqual(call.kwargs['cwd'], self.stage)
            self.assertEqual(call.kwargs['env']['SIGNED_DIR_OVERRIDE'], str(self.stage / 'signed-manifests'))


if __name__ == '__main__':
    unittest.main()
