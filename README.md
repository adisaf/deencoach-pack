# deencoach-pack

Public registry of downloadable content packs for the [Deen Coach](https://deencoach.app) mobile app (Quran, prayer, learning).

Pack metadata lives in `manifests/`. Pack binaries (ZIPs) live in [GitHub Releases](https://github.com/adisaf/deencoach-pack/releases) of this repository.

## How it works

The mobile app fetches a manifest JSON, downloads the ZIP from the URL it advertises, verifies the SHA-256, then extracts and activates the content locally.

Every release is signed by the maintainer ([@adisaf](https://github.com/adisaf)) and every pack carries a published SHA-256. A versioned manifest cannot use a placeholder digest. See [SECURITY.md](SECURITY.md) for verification and disclosure.

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

## License

The repository code (manifests, schemas, scripts, docs) is released under the [MIT License](LICENSE). Pack contents (TTF, audio, translations) keep their original licenses, declared in each manifest's `license` field.

---

Maintained by [@adisaf](https://github.com/adisaf). `Wa Allahu aʿlam`.
