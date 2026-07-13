# Security policy

This repository hosts content consumed automatically by the [Deen Coach](https://deencoach.app) mobile app. We take both **cryptographic integrity** (no tampered binary reaches a user) and **religious integrity** (no content contradicts the Ahl al-Sunnah methodology) seriously.

## Scope

- Manifest files in `manifests/**`
- JSON Schema in `schemas/`
- Operational scripts in `tools/`
- Pack binaries (ZIPs) attached to [GitHub Releases](https://github.com/adisaf/deencoach-pack/releases)

## Cryptographic integrity

- Every published pack carries a 64-character hex `sha256` field in its manifest.
- The mobile app refuses to install any pack whose downloaded ZIP SHA-256 does not match the manifest. The gate is enforced before extraction (no partial state on disk).
- A versioned manifest never accepts a placeholder or an empty digest. The
  publication gate accepts only a 64-character lowercase hexadecimal SHA-256.
- Manifests used by the signed mobile flow are verified with the versioned Ed25519 public key embedded in the app. Releases require a pre-existing annotated Git tag and are verified after publication by downloading every public artifact.

To validate the manifest contract, then re-verify any published pack locally:

```bash
./tools/validate-manifests.sh
./tools/verify-checksums.sh <category> <pack>
# Example: ./tools/verify-checksums.sh mushaf-fonts qpc-v1
```

The validation script rejects incomplete manifests before publication. The
checksum script downloads the ZIP from the URL declared in the manifest,
computes its SHA-256, and exits non-zero if it does not match.

## Religious integrity

- Quran text and recitation packs declare their transmission. The current accepted Quran-text transmission is **`Hafs an Asim via al-Shatibiyya`** only. Translations and tafsīr remain explicitly distinct from the Arabic text and preserve their source, version and attribution in provenance.
- Manifest sources (`source.scholarlyValidation`) document the chain of validation. Adding a new pack requires this field to reference a recognized scholarly authority.
- Sources outside Ahl al-Sunnah wa al-Jamaʿah (Sufi, Shi'a, Ismaili, modernist, unsourced) are rejected upstream and never enter this registry.

## Reporting a vulnerability

- **Cryptographic or supply-chain issue** (SHA-256 mismatch, malicious ZIP, dependency compromise, signature forgery): email **`security@deencoach.app`** with subject `SECURITY: <category> <pack>`. Provide the URL, expected vs observed SHA-256, and reproduction steps. Acknowledged within 72 hours.

- **Religious or methodological issue** (wrong transmission, incorrect attribution, dubious source): email **`talib@deencoach.app`** with subject `RELIGIOUS: <category> <pack>`. Provide the manifest path, the issue, and a scholarly reference if possible. Reviewed by a qualified `talib al-ʿilm` before any change.

- **Anything else**: open a public issue on this repository.

Please do **not** file public issues for security or religious vulnerabilities until they are acknowledged and a fix is published.

## Coordinated disclosure

For high-severity issues we follow a **48-hour acknowledge / 14-day fix / 30-day public disclosure** window. Critical issues that put users at risk of installing malicious binaries trigger an immediate manifest update (replacement URL or pack version bump) within 24 hours.

## Out of scope

- Localized typography preferences (these are user choices, not security issues).
- Personal disagreement with mainstream Ahl al-Sunnah methodology (this repository does not arbitrate fiqh debates).

---

`Wa Allahu aʿlam`.
