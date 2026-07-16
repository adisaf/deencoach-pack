# deencoach-pack

Public registry of downloadable content packs for the [Deen Coach](https://deencoach.app) mobile app (Quran, prayer, learning).

Pack metadata lives in `manifests/`. Pack artifacts, including ZIPs, raw text and
per-surah JSON responses, live in [GitHub Releases](https://github.com/adisaf/deencoach-pack/releases) of this repository.

## How it works

The mobile app fetches a signed manifest JSON, verifies its Ed25519 signature,
then downloads each declared artifact only after its SHA-256 and expected size
have been received. ZIP artifacts are extracted locally; raw artifacts stay
verbatim.

Every manifest consumed by the mobile app is signed with the versioned Deen Coach Ed25519 public key, and every artifact carries a published SHA-256. Releases are attached to a pre-existing annotated Git tag. A versioned manifest cannot use a placeholder digest. See [SECURITY.md](SECURITY.md) for verification and disclosure.

## Product context

Full product, methodology and contact information lives on the official site: **https://deencoach.app**.

## Repository layout

| Path | Purpose |
|---|---|
| `manifests/<category>/<pack>.json` | Pack metadata consumed by the app. |
| `schemas/pack-manifest.schema.json` | JSON Schema validating every manifest. |
| `docs/` | Operational notes for maintainers (hosting, versioning, categories). |
| `tools/verify-checksums.sh` | Script to re-verify every published pack against its declared SHA-256. |
| `tools/validate-client-manifests.sh` | Validates signed client manifests, artifact paths, provenance and digests. |
| `tools/verify-client-manifest-signatures.sh` | Verifies Ed25519 signatures from the versioned public key. |
| `tools/build-tanzil-text-packs.sh` | Rebuilds the permitted verbatim Tanzil text packs. |
| `tools/build-quranenc-translation-packs.sh` | Rebuilds the permitted versioned QuranEnc responses without rewriting them. |
| `signed-manifests/` | Immutable manifests verified by the Flutter client before any artifact URL is used. |
| `signed-manifests/active-revisions.json` | Signed active revision index with a monotonic anti-rollback sequence. |

Signed manifest paths are append-only. Any change to URLs, fallbacks, validity
or metadata creates a new `-rN.json` and matching `.sig` pair. Existing pairs
must never be overwritten because released clients and CDN caches may still
request them.

The active index is signed separately as
`signed-manifests/active-revisions.json.sig`. Its monotonic `sequence` lets
clients reject a previously observed registry revision while immutable pack
manifests remain independently verifiable.

## License

The repository code (manifests, schemas, scripts, docs) is released under the [MIT License](LICENSE). A pack content may be distributed only when its original licence, provenance and attribution are verified for the exact artefact. The source of truth is [the rights matrix](docs/SOURCE_RIGHTS_MATRIX.md); a manifest `license` field alone is not proof of redistribution rights.

---

Maintained by [@adisaf](https://github.com/adisaf). `Wa Allahu aʿlam`.
