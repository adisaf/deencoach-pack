# Hosting a pack

Maintainer-only operational notes. Run from the repo root.

## 1. Prepare the ZIP

Place the artifact at `uploads/<category>/<pack-id>.<extension>` (gitignored).
Use a ZIP when the client must extract several files. A single raw source file
is allowed only when the client consumes it directly and the manifest sets
`artifactFormat` to `raw`. For `mushaf_font` packs, rebuild the ZIP from the
downloaded QUL source archives plus `render/mushaf_render_assets.json` instead
of mutating an existing ZIP in place. Include `render/mushaf_render_assets.json`
in the ZIP when the manifest declares `renderAssetPath`.

## 2. Compute integrity values

```bash
shasum -a 256 uploads/<category>/<pack-id>.<extension>
ls -la uploads/<category>/<pack-id>.<extension>          # sizeCompressed
unzip -l uploads/<category>/<pack-id>.zip | tail -1      # ZIP seulement
```

## 3. Update the manifest

Edit `manifests/<category>/<pack-id>.json` against `schemas/pack-manifest.schema.json`. Required fields: `id`, `category`, `version`, `displayName`, `description`, `url`, `sizeCompressed`, `sizeUncompressed`, `sha256`, `fileCount`, `license`, `minAppVersion`. Quran-related packs also need `transmission`. For `mushaf_font` packs with a precompiled render JSON, set `renderAssetPath` to `render/mushaf_render_assets.json`. `fileCount` remains the expected TTF count for the mobile installer.

The `url` must follow:

```
https://github.com/adisaf/deencoach-pack/releases/download/<category>-v<version>/<pack-id>.zip
```

## 4. Validate locally before any commit

```bash
./tools/validate-manifests.sh <category> <pack-id>
```

This command must exit `0`. A versioned manifest with an absent, malformed or
placeholder digest is a publication failure. Do not push the manifest and do
not create a release until the actual ZIP hash and sizes have been measured.

## 4.b Manifests consommés par l'application

Les nouveaux packs Deen Coach utilisent `signed-manifests/` en complément du
manifest de publication. L'application vérifie la signature Ed25519 avant de
lire une URL d'artefact. La clé privée reste dans le trousseau macOS et ne doit
jamais être ajoutée à Git ou à la CI.

Pour les packs QuranEnc, l'artefact est une réponse JSON par sourate. Le script
de construction conserve les réponses verbatim et génère 114 SHA-256 dans le
manifest signé. Les 114 fichiers doivent être joints à la release désignée par
les URLs du manifest, alors que le manifest et sa signature restent publiés sur
`origin/main` pour être vérifiés avant tout téléchargement.

```bash
./tools/build-tanzil-text-packs.sh
./tools/sign-client-manifests.sh quran-text
./tools/build-quranenc-translation-packs.sh
./tools/validate-client-manifests.sh
./tools/verify-client-manifest-signatures.sh
./tools/verify-quran-text-pack.sh uploads/quran-text/quran-uthmani-hafs.txt
./tools/verify-quranenc-translation-pack.sh quran_translation_fr_noor
```

Ne construisez pas une source `conditional`, `written_permission_required` ou
`source_license_unknown`. Consultez d'abord `docs/SOURCE_RIGHTS_MATRIX.md`.

## 5. Commit and push the manifest

```bash
git add manifests/<category>/<pack-id>.json
git commit -m "feat(<category>): publish <pack-id> v<version>"
git push origin main
```

La signature Ed25519 du manifest est la garantie consommée par l’application.

## 6. Publier une release signée consommable par l’application

Le `justfile` local est volontairement ignoré par Git. Créez-le depuis le
modèle versionné, sans y ajouter de secret :

```bash
cp justfile.example justfile
```

Il délègue les contrôles reproductibles au script versionné
`tools/release-signed-pack-category.sh`.

Avant la publication, les manifests et signatures doivent être commités puis
publiés sur `origin/main`. La pré-vérification échoue sinon, afin que l’URL
du manifest consommé par Flutter ne puisse jamais désigner un artefact non
traçable dans le dépôt.

```bash
just doctor
just release-verify quran-text quran-text-v1.0.0
just release-tag quran-text quran-text-v1.0.0
just release-publish quran-text quran-text-v1.0.0
```

Pour les traductions QuranEnc déjà admissibles :

```bash
just release-verify quran-translations quranenc-translations-v1.0.0
just release-tag quran-translations quranenc-translations-v1.0.0
just release-publish quran-translations quranenc-translations-v1.0.0
```

`release-tag` exige l’identité Git de Fawaz ADISA, crée un tag annoté pointant
sur `origin/main` et le publie. `release-publish` exige ce tag déjà publié,
refuse une release existante, puis retélécharge chaque artefact public et
contrôle son SHA-256 et sa taille. Ce dernier contrôle est la preuve que
l’application mobile peut récupérer les URL réellement publiées.

Pour rejouer uniquement ce contrôle après coup :

```bash
just release-verify-published quran-text quran-text-v1.0.0
```

Le runbook ne permet volontairement que `quran-text` et
`quran-translations`, les deux catégories dont les droits de redistribution,
les sources et les manifests signés sont documentés. Les autres catégories
restent bloquées tant que leur gate juridique et religieux n’est pas levé.

## 7. Commande GitHub CLI historique

```bash
gh release create <category>-v<version> --verify-tag \
  --title "<Category title> v<version>" \
  --notes-file release-notes.md \
  uploads/<category>/<pack-id>.zip
```

Le runbook `just` est obligatoire pour les packs consommés par l’application,
car il vérifie aussi les signatures Ed25519, les URLs, les versions et tous les
artefacts publics.

## 8. Vérification historique

```bash
./tools/verify-checksums.sh <category> <pack-id>
```

Must exit 0. The script downloads the public URL and checks the SHA-256 against the manifest.

Pour une release signée consommée par Flutter, vérifiez aussi la signature et
les artefacts publiés après téléchargement dans un répertoire propre. Puis
mettez seulement les URLs finales dans le catalogue Flutter et exécutez une QA
connectée, hors ligne, annulation, reprise et redémarrage.
