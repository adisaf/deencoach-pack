# Uploads — mushaf-fonts (local staging)

Working directory for ZIPs prepared before `gh release create`. Binaries are gitignored; only this README is tracked.

## Expected files

| File | Size (compressed) | SHA-256 |
|---|---|---|
| `qpc-v1.zip` | 54 502 444 B | `b276e07b6e7c8df255c0a61fa9ae7f0d02fde074eec4e04c13fec75cf72e0031` |
| `qpc-v2.zip` | 136 208 148 B | `9ead3836904f22324b5805c079c2911e13f384f2ca820254a36b8a22c28de555` |
| `qpc-v4-tajweed.zip` | 68 739 219 B | `b29c028277b4b8bdc1fa15fd5c642191ed9eb88f81fff2ec7da2554f688f6562` |

Each ZIP contains 604 TTF files named `p1.ttf` through `p604.ttf`, sourced from QUL Tarteel.

## Verify

```bash
cd uploads/mushaf-fonts/
xattr -c *.zip 2>/dev/null   # macOS only, clears quarantine bit
shasum -a 256 *.zip
```

Hashes must match the table above. If they do not, re-fetch the source from QUL Tarteel.

## Publish

See [`docs/HOSTING.md`](../../docs/HOSTING.md).
