# Uploads - mushaf-fonts (local staging)

Working directory for ZIPs prepared before `gh release create`. Binaries are gitignored; only this README is tracked.

## Expected files

| File | Size (compressed) | SHA-256 |
|---|---:|---|
| `qpc-v1.zip` | 55 056 211 B | `11a821f0c65048d485321eea38b889aa47a54fa67c245a05454d8aa6319818a4` |
| `qpc-v2.zip` | 136 709 275 B | `e914e4deb8ac2bf9798ad6902dca0489d843f0412d9dcde693d235d6b62a2c1d` |
| `qpc-v4-tajweed.zip` | 69 975 419 B | `dd9f7d2336447cb8678144b73e5dc568e6e7596e73d12fb1966859509dc2e643` |

Each ZIP contains:

- 604 TTF files named `p1.ttf` through `p604.ttf`, sourced from QUL Tarteel.
- `render/mushaf_render_assets.json`, generated from the matching QUL layout and script SQLite files used by the Deen Coach app.

The precompiled render JSON remains inside the downloadable pack. It is not bundled in the mobile app.

## Source inputs

Current local rebuild inputs came from `/Users/fawazadisa/Downloads/temp`:

| Pack | Font QUL | Layout QUL | Script QUL |
|---|---:|---:|---:|
| `qpc-v1.zip` | #238 | #15 | #57 |
| `qpc-v2.zip` | #249 | #10 | #61 |
| `qpc-v4-tajweed.zip` | #240 | #19 | #47 |

Rebuild from the downloaded source archives and generate `render/mushaf_render_assets.json` before publishing. Do not mutate a published ZIP in place without updating its manifest hash.

## Verify

```bash
cd uploads/mushaf-fonts/
xattr -c *.zip 2>/dev/null   # macOS only, clears quarantine bit
shasum -a 256 *.zip
unzip -l qpc-v1.zip render/mushaf_render_assets.json
unzip -l qpc-v2.zip render/mushaf_render_assets.json
unzip -l qpc-v4-tajweed.zip render/mushaf_render_assets.json
```

Hashes must match the table above. Each ZIP must expose `render/mushaf_render_assets.json`.

## Publish

See [`docs/HOSTING.md`](../../docs/HOSTING.md).
