# Matrice de droits et de provenance des sources

Date d'audit : 2026-07-13

Ce document est la gate obligatoire avant toute production ou publication d'un
pack Deen Coach. Une URL publiquement téléchargeable ne vaut jamais licence de
redistribution. Les valeurs `allowed` et `conditional` ci-dessous ne dispensent
pas de la revue religieuse ni de la conservation de la provenance dans le
manifest.

## Statuts

| Statut | Conséquence opérationnelle |
| --- | --- |
| `allowed` | Peut être empaqueté après vérification automatisée et attribution intégrée. |
| `conditional` | Peut être empaqueté seulement après vérification du contenu précis et de toutes les obligations indiquées. |
| `written_permission_required` | Aucun miroir, ZIP ou asset public avant accord écrit du titulaire. |
| `source_license_unknown` | Aucun miroir tant qu'une licence officielle exploitable n'est pas archivée. |

## Sources externes

| Source | Packs concernés | Statut | Conditions impératives | Preuve officielle |
| --- | --- | --- | --- | --- |
| Tanzil | `quran_text_uthmani_hafs`, `quran_text_simple_search` | `allowed` | Copie verbatim seulement, avis Tanzil intégré, attribution et lien visibles, veille des mises à jour. | https://tanzil.net/docs/Text_License |
| QuranEnc, version exposée par l'API | `quran_translation_fr_noor`, `quran_translation_en_saheeh`, `quran_translation_en_hilali_khan`, `quran_translation_en_rwwad`, `quran_translation_fr_rashid` | `allowed` | Réponses API conservées sans réécriture, attribution de l'éditeur et QuranEnc, version source, informations de transcription, veille des versions. | https://quranenc.com/ff/home/api |
| QuranEnc, version non exposée par l'API | `quran_translation_fr_hamidullah`, `quran_tafsir_mukhtasar_ar`, `quran_tafsir_mukhtasar_fr` | `conditional` | Les endpoints répondent mais les clés sont absentes de la liste officielle de métadonnées. Aucun miroir avant version officielle traçable et revue `talib-al-ilm` du corpus exact. | https://quranenc.com/ff/home/api |
| KFGQPC, polices Mushaf V1/V2/V4 | `mushaf_qpc_v1`, `mushaf_qpc_v2`, `mushaf_qpc_v4_tajweed` | `source_license_unknown` | QUL identifie les ressources comme provenant de KFGQPC, mais indique que chaque ressource conserve ses propres droits. Le portail officiel KFGQPC affiche tous droits réservés et ne fournit pas, pour ces artefacts précis, une licence de redistribution archivable. Aucun miroir, ZIP, manifest signé ou activation runtime avant archivage du texte officiel applicable, de son digest et de la preuve binaire de la source. | https://fonts.qurancomplex.gov.sa/ |
| Quran Foundation | Récitations audio par sourate et métadonnées API | `written_permission_required` | Les conditions limitent le cache durable et la redistribution brute. Les accès Content API sont serveur uniquement. | https://api-docs.quran.foundation/legal/developer-terms/ |
| Assabile | Adhan HQ | `written_permission_required` | Le site déclare tous droits réservés. Le téléchargement individuel ne vaut pas droit de republier. | https://www.assabile.com/ |
| AbdurRahman.org / SalafiAudio | Audio pas-à-pas de la prière | `source_license_unknown` | Le contenu attribué au Dr. Saleh As-Saleh reste religieusement identifiable, mais le droit de recopier les MP3 doit être archivé avant tout miroir. | https://salafiaudio.files.wordpress.com/2015/03/ |
| EveryAyah | Audio Rabbana | `source_license_unknown` | Aucune licence de redistribution officielle archivée lors de l'audit. | https://everyayah.com/ |
| Archive.org, HisnulMuslimAudio | Audio du Hisn al-Muslim | `source_license_unknown` | Le statut de l'item et les droits des enregistrements doivent être établis par une licence ou une autorisation du titulaire. | https://archive.org/details/HisnulMuslimAudio_201510 |
| IslamCan | Audio alphabet arabe intégré | `source_license_unknown` | Les fichiers sont actuellement inclus dans l'application mais aucune licence de redistribution exploitable n'est archivée dans le registre. | https://www.islamcan.com/learn-arabic/ |
| QUL / Tarteel | Scripts, layouts, polices, tajwīd et ressources associées | `conditional` | Vérifier et archiver la licence de chaque ressource et de son auteur. La FAQ QUL ne confère pas une licence uniforme. | https://qul.tarteel.ai/faq |
| fawazahmed0/quran-api | Translittérations | `conditional` | Le dépôt est sous Unlicense, mais les sources éditoriales sous-jacentes restent à identifier et attribuer avant redistribution. | https://github.com/fawazahmed0/quran-api |
| quran411.com | `quran_transliteration_simple` embarqué dans l'application | `source_license_unknown` | Une page de conditions consultée le 2026-07-13 signale des restrictions, mais aucun snapshot immuable, aucune licence de reproduction et aucun digest ne sont archivés. Aucun nouvel artefact avant autorisation écrite explicite ou corpus de remplacement dont la licence est archivée. | https://quran411.com/terms-of-use |
| Production interne | Lettres, Hifz, adhkār, Asmā’ | `conditional` | Autorité éditoriale prouvée, licence des voix, revue `talib-al-ilm`, source et degré pour chaque contenu religieux. | Registre éditorial interne |

## Exigences minimales de provenance

Tout manifest publié doit contenir les champs suivants dans `provenance` :

```json
{
  "sourceAuthority": "Tanzil",
  "sourceUrl": "https://tanzil.net/download/",
  "sourceVersion": "1.1",
  "retrievedAt": "2026-07-13",
  "licenseUrl": "https://tanzil.net/docs/Text_License",
  "licenseSnapshotSha256": "<sha256>",
  "attribution": "Tanzil Quran Text, Copyright (C) 2007-2021 Tanzil Project",
  "redistributionStatus": "allowed"
}
```

Le contenu de l'attribution, le digest du document de licence et la version
source sont aussi inclus dans l'archive quand la source l'exige. Un changement
de version amont déclenche une nouvelle revue religieuse, juridique et de
checksum avant publication.

## Décisions de migration

1. Construire les deux textes Tanzil et les cinq traductions QuranEnc dont la
   version et les conditions sont archivées. Les réponses QuranEnc restent
   verbatim, sourate par sourate, avec les informations de transcription.
2. Ne jamais empaqueter ni publier les audios Quran Foundation, Assabile,
   EveryAyah ou Archive.org avant la gate correspondante.
3. Mettre en quarantaine les packs Mushaf KFGQPC V1/V2/V4 : aucun nouveau ZIP,
   manifest signé, lien de téléchargement ou activation runtime. Les assets de
   release historiques restent un risque public à traiter par une décision de
   retrait explicite du propriétaire du dépôt. Toute reprise exige, ressource
   par ressource, le texte officiel de licence, son digest et la preuve binaire
   de la source.
4. La source distante ne doit rester qu'un canal de construction contrôlé,
   jamais une dépendance runtime de l'application après migration.
