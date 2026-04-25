# Versioning

Each pack follows [Semantic Versioning 2.0.0](https://semver.org/) independently.

| Bump | When |
|---|---|
| MAJOR `X.0.0` | Backwards-incompatible change (file naming, format, structure). Forces re-download for every user. |
| MINOR `1.X.0` | Backwards-compatible additions. |
| PATCH `1.0.X` | Backwards-compatible fixes (corrupt glyph, typo, audio gap). |

## Tag convention

`<category>-v<MAJOR>.<MINOR>.<PATCH>` (example: `mushaf-fonts-v1.0.0`).

## MAJOR bumps

A MAJOR bump triggers a forced re-download of large binaries (50–200 MB) on every device that already has the previous version. **Do not bump MAJOR without explicit maintainer approval.** Default to PATCH or MINOR whenever possible.

## Pre-releases

Use the SemVer pre-release suffix when staging a new version: `mushaf-fonts-v2.0.0-rc.1`. Mark the corresponding GitHub release as "pre-release".
