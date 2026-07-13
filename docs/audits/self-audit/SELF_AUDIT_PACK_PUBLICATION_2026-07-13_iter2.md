# Self-audit : publication publique des packs

Date : 2026-07-13  
Périmètre : scripts de construction et de publication, manifests Ed25519,
workflow GitHub Actions, documentation et runbook local.

## 1. Résumé exécutif

Verdict : GO pour le commit puis la publication contrôlée des deux releases
initiales. Les corrections lient désormais chaque manifest à sa version de tag,
refusent les secrets et vérifient le dépôt, l’identité GitHub, les signatures,
les SHA-256 et les tailles avant et après publication.

## 2. Findings

### CRITICAL

Aucun finding ouvert.

### HIGH

Aucun finding ouvert.

### MEDIUM

Aucun finding ouvert.

### LOW

Aucun finding ouvert.

## 3. Contrôles fondés sur les preuves

- Correctness : `quran-text-v1.0.0` et `quranenc-translations-v1.0.0` sont
  validés contre leurs versions de manifest ; les cinq lots QuranEnc portent
  chacun 114 réponses et les deux textes Tanzil 6 236 versets.
- Sécurité : le garde refuse les fichiers `.env` suivis, les motifs de clé
  privée et les jetons évidents ; le scan passif de tout l’historique Git n’a
  trouvé aucune correspondance sensible.
- Chaîne de confiance : les sept manifests satisfont le contrat client et
  leurs signatures Ed25519 sont valides avec la clé publique versionnée.
- Publication : le runbook limite les catégories autorisées, impose le dépôt
  `adisaf/deencoach-pack`, le compte GitHub `adisaf`, l’identité Git Fawaz
  ADISA, un tag annoté et une vérification publique de chaque artefact.
- Maintenabilité : les scripts restent sous 500 lignes, passent `bash -n` et
  la CI exécute le garde, la syntaxe Bash et les validations cryptographiques
  avec une action GitHub épinglée à un SHA immuable.

## 4. Recommandations transverses

- Ne jamais modifier la clé publique sans une mise à jour coordonnée de la
  liste de confiance mobile.
- Ne jamais réutiliser un tag ni une release : publier une nouvelle version de
  pack, puis mettre à jour le catalogue mobile lorsque l’invalidation de pack
  l’exige.
- Conserver localement les artefacts de préparation jusqu’à la vérification
  publique des SHA-256 et tailles.
- Garder les corpus QuranEnc verbatim, avec attribution, version et digest des
  conditions d’utilisation archivés dans la provenance.

## 5. Correctif CI post-publication

Le workflow GitHub Actions a révélé que l’image Ubuntu ne fournit pas
nécessairement `rg`. Le garde de dépôt a donc été rendu portable en utilisant
`grep -E`, disponible sur le runner, pour détecter les fichiers `.env` suivis.
Le contrôle de sécurité reste identique et le prérequis `rg` a été retiré du
runbook local. La correction ne touche ni les manifests, ni les signatures, ni
les artefacts déjà publiés.
