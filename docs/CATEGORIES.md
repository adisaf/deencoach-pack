# Pack categories

Each pack belongs to a single category. The category is declared in `manifests/<category>/<pack>.json` and validated against `schemas/pack-manifest.schema.json`.

## Active categories

### `mushaf_font`

Per-page Mushaf TTF fonts. ZIP contains `p1.ttf` through `p<pageCount>.ttf`. Required manifest fields: `transmission`, `layoutAssetPath`, `fontNamePrefix`.

Currently published: `mushaf_qpc_v1`, `mushaf_qpc_v2`, `mushaf_qpc_v4_tajweed`.

## Reserved categories (not yet published)

| Category | Purpose |
|---|---|
| `audio_recitation` | Per-surah recitation MP3 (`001.mp3` through `114.mp3`). |
| `translation` | Quran translation, monolithic JSON or per-surah split. |
| `tafsir` | Tafsir, monolithic or per-surah. |
| `adhkar_audio` | Adhkar / dua audio bundle. |

## Adding a new category

1. Add the literal to the `category` enum in `schemas/pack-manifest.schema.json`.
2. Document expected ZIP layout and required manifest fields here.
3. Update the mobile app to consume the new category.
4. Validate religious content per the methodology in [SECURITY.md](../SECURITY.md).
