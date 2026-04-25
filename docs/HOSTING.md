# Hosting a pack

Maintainer-only operational notes. Run from the repo root.

## 1. Prepare the ZIP

Place the ZIP at `uploads/<category>/<pack-id>.zip` (gitignored).

## 2. Compute integrity values

```bash
shasum -a 256 uploads/<category>/<pack-id>.zip
ls -la uploads/<category>/<pack-id>.zip          # sizeCompressed
unzip -l uploads/<category>/<pack-id>.zip | tail -1   # sizeUncompressed + fileCount
```

## 3. Update the manifest

Edit `manifests/<category>/<pack-id>.json` against `schemas/pack-manifest.schema.json`. Required fields: `id`, `category`, `version`, `displayName`, `description`, `url`, `sizeCompressed`, `sizeUncompressed`, `sha256`, `fileCount`, `license`, `minAppVersion`. Quran-related packs also need `transmission`.

The `url` must follow:

```
https://github.com/adisaf/deencoach-pack/releases/download/<category>-v<version>/<pack-id>.zip
```

## 4. Commit and push the manifest

```bash
git add manifests/<category>/<pack-id>.json
git commit -S -m "feat(<category>): publish <pack-id> v<version>"
git push origin main
```

Use `-S` to GPG-sign the commit when possible.

## 5. Create the signed release with assets

```bash
gh release create <category>-v<version> \
  --title "<Category title> v<version>" \
  --notes-file release-notes.md \
  uploads/<category>/<pack-id>.zip
```

To sign the release tag, configure `git tag -s` defaults locally (see GitHub docs on signed tags).

## 6. Verify

```bash
./tools/verify-checksums.sh <category> <pack-id>
```

Must exit 0. The script downloads the public URL and checks the SHA-256 against the manifest.
