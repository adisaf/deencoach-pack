# Pack categories

Each pack belongs to a single category. The category is declared in `manifests/<category>/<pack>.json` and validated against `schemas/pack-manifest.schema.json`.

Three statuses are used below:

| Status | Meaning |
|---|---|
| **active** | Published in this repo today (manifests + GitHub Releases). |
| **reserved** | Defined in the mobile app's pack registry but not yet hosted here. The convention is fixed; future contributions must follow it. |
| **prospective** | Idea documented to keep the namespace coherent. Not yet wired in the app, may be revisited or dropped. Adding one requires a pre-commit conversation with the maintainer and a `talib-al-ilm` review. |

Naming convention: `category` is **snake_case singular** in manifests (`mushaf_font`), **kebab-case singular or plural** in repo paths (`mushaf-fonts`).

## Quran

### `mushaf_font` (active)

Per-page Mushaf TTF fonts (one TTF per page). Required manifest fields: `transmission`, `layoutAssetPath`, `fontNamePrefix`. ZIP layout: `<fontNamePrefix>1.ttf` … `<fontNamePrefix><pageCount>.ttf`.

Currently published: `mushaf_qpc_v1`, `mushaf_qpc_v2`, `mushaf_qpc_v4_tajweed`.

Religious gates: `transmission` must be `"Hafs an Asim via al-Shatibiyya"`. Tajwid color systems are accepted only when sourced from a recognized publisher (KFGQPC, Dar al-Maarifah).

### `quran_audio` (reserved)

Full-Quran recitations, one MP3 per surah. ZIP layout: `001.mp3` … `114.mp3`. Required: `transmission`. Recommended: `source.scholarlyValidation` (reciter, isnād, ijāza when applicable). Bitrate floor: 96 kbps.

Religious gates: reciter must belong to Ahl al-Sunnah wa al-Jamaʿah. No Sufi nasheed-style readings, no Shi'a or Ismaili reciters.

### `quran_audio_learning` (reserved)

Pedagogical recitations (mu'allim mode, kid-repeat mode). Same ZIP layout as `quran_audio`. The pack metadata makes the educational pattern explicit (e.g. `tags: ["muallim", "word_by_word"]`).

### `quran_text` (reserved)

Quran source text variants downloadable as a single payload (e.g. Uthmani Hafs, Simple Clean for search). ZIP layout: `quran.txt` or `quran.json` plus a metadata manifest. Required: `transmission`.

Religious gates: text must come from a recognized source (Tanzil, KFGQPC, Madinah Press) and match the rasm. Never include user-modified text.

### `quran_translation` (reserved)

Translations of the meanings of the Quran (never "Translation of the Quran"; the Quran is by definition untranslatable per Ahl al-Sunnah). ZIP layout: monolithic `translation.json` or per-surah split when the file exceeds 10 MB. Required: `transmission`, `license` mentioning the translator.

Religious gates: published, recognized translator only. Display always carries the explicit "Translation of the meanings" label. Controversial translations (e.g. Hilali & Khan footnotes) trigger an in-app methodology disclaimer.

### `quran_tafsir` (reserved)

Tafsir (Quranic exegesis) downloadable as a single payload. ZIP layout: per-surah split (one JSON per surah). Required: `transmission`, `source.scholarlyValidation` referencing the original mufassir.

Religious gates: only mufassirun from Ahl al-Sunnah wa al-Jamaʿah (Ibn Kathīr, al-Saʿdī, al-Ṭabarī, al-Baghawī, al-Qurṭubī, Markaz Tafsir, etc.). Never Sufi (Tustarī, Ibn ʿArabī), Shi'a (al-Mīzān), or modernist tafsir without explicit framing.

### `quran_transliteration` (reserved)

Latin-script phonetic transliteration of the Quran for non-Arabic-speakers. ZIP layout: monolithic `transliteration.json` or per-surah. Required: `license`, `source` (Tanzil, fawazahmed0/quran-api, quran411.com).

Religious gates: transliteration must match the consonantal rasm. No personal romanization systems.

## Worship

### `prayer_audio` (reserved)

Adhan call-to-prayer audio bundles per muezzin. ZIP layout: `adhan_<muezzin>.mp3` files (variable count). Required: `license` per muezzin / source CDN (Assabile, archive.org).

Religious gates: muezzin must be from a recognized masjid (Mecca, Madinah, established mosques). Adhan structure must follow Ahl al-Sunnah formula (no Shi'a addition `ʿalī wa walī Allah`).

### `salah` (reserved)

Salah essentials audio guide (step-by-step tutorial). ZIP layout: `step_01.mp3` … `step_NN.mp3` per lesson sequence. Required: `source.scholarlyValidation` (teacher must be a known Sunni scholar, e.g. Dr. Saleh As-Saleh, AbdurRahman.org).

Religious gates: no schools-of-fiqh-specific bias outside the broad Ahl al-Sunnah methodology. Disclaimers for fiqh disagreements (e.g. hand placement, qabd vs sadl) shown in-app.

## Adhkar / Duas

### `dua_audio` (reserved)

Adhkar and dua audio (currently used for the unified Hisn al-Muslim per-entry pack). ZIP layout: per-entry MP3 keyed by `dua_<chapter>_<entry>.mp3`. Required: `source.scholarlyValidation` (recueil reference: Hisn al-Muslim of Saʿīd al-Qaḥṭānī).

Religious gates: every dua must be sourced (Quran, sahih hadith, hasan hadith). Reject weak (daʿīf) and fabricated (mawḍūʿ) supplications without explicit warning.

## Names of Allah

### `asma_allah` (reserved)

99 Names of Allah authenticated list and pronunciation audio. ZIP layout: `names.json` (text + dalīl) plus `audio/<index>.mp3`. Required: `source.scholarlyValidation` (Ibn ʿUthaymin's Al-Qawāʿid al-Muthlā, Comité Permanent).

Religious gates: stick to the methodology of `Al-Qawāʿid al-Muthlā` (81 Quran + 18 Sunnah). The weak Tirmidhi 3507 list is allowed only as a separate educational section with explicit warning.

## Learning

### `arabic_letters` (reserved)

Arabic alphabet pronunciation audio (28 core letters + harakat). ZIP layout: `<letter_id>.mp3` keyed by canonical letter id. Required: `source` (recognized teacher, internal production with talib-al-ilm review).

Religious gates: pronunciations follow tajweed makharij and sifat as per recognized Sunni authorities.

### `hifz` (reserved)

Hifz (memorization) curated content packs (audio loops 1×/5×/10×, structured plans). ZIP layout: per-ayah MP3 with repeat count metadata. Required: `transmission`, `source.scholarlyValidation`.

Religious gates: audio must come from a recognized reciter (Ahl al-Sunnah). Plan structure follows traditional madrasa pedagogy (juz, hizb, rub).

## Prospective categories

Documented to keep the namespace coherent. Not yet wired in the mobile app. Adding one requires conversation with the maintainer and `talib-al-ilm` review.

| Category | Purpose | Notes |
|---|---|---|
| `hadith_collection` | Full hadith collections (Bukhari, Muslim, Sunan, etc.) downloadable per book or per chapter. | Required: classification per hadith (sahih / hasan / daʿīf / mawḍūʿ) by named muhaddith. |
| `hadith_explanation` | Sharḥ (commentary) on hadith collections. | Same religious gates as `quran_tafsir`: only Ahl al-Sunnah commentators. |
| `99_names_explanation` | Detailed explanation of each Name of Allah (text + audio commentary). | Differentiated from `asma_allah` which is the names list itself. |
| `seerah_audio` | Audio biographies of the Prophet ﷺ and Companions. | Religious gates: only Sunni seerah scholars (Ibn Hisham, al-Mubarakpuri, etc.). No Shi'a or modernist accounts. |
| `seerah_text` | Text biographies in trilingual format. | Same gates as `seerah_audio`. |
| `aqidah_text` | Texts on Islamic creed (ʿaqīda) per Ahl al-Sunnah methodology. | Religious gates: Ibn Taymiyyah, Ibn al-Qayyim, Ibn ʿUthaymin, Lajna Daïma references only. No kalām, Sufi, Shi'a, or modernist treatises. |
| `fiqh_text` | Texts on Islamic jurisprudence. | Religious gates: from one of the four recognized madhāhib (Hanafi, Maliki, Shafiʿi, Hanbali) or general Ahl al-Sunnah. Avoid sectarian or unsourced material. |
| `qibla_offline_data` | Magnetometer calibration data for offline qibla compass. | Pure technical data, no religious gate beyond geographic accuracy. |
| `prayer_times_offline` | Prayer-times tables for the next N years per coordinate range, for users without network. | Methodology disclosure mandatory (calculation method, asr juristic). |
| `hijri_calendar_data` | Hijri/Gregorian conversion tables and major Islamic events. | Methodology: Umm al-Qura calendar by default, document any deviation. |
| `language_pack` | Additional UI translations beyond FR/EN/AR. | Must use a recognized translation provider, not crowdsourced unverified content. |

## Adding a new active category

1. Add the literal to the `category` enum in `schemas/pack-manifest.schema.json`.
2. Document expected ZIP layout, required manifest fields, and religious gates in this file.
3. Update the mobile app to consume the new category (`PackRemoteCatalog` constructor, `PackRemoteDownloadKind` enum, dedicated installer if the workflow differs from `mushaf_font`).
4. For every Quran-related category, validate methodology with `talib-al-ilm` before merge.
5. Bump the schema's `registryVersion` if breaking changes are introduced.
