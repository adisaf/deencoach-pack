# Self-audit : fallbacks et révisions de manifests

Date : 2026-07-16
Périmètre : manifests clients, fallbacks amont, signature Ed25519, registre
actif, scripts de publication, runbook local et CI.

## 1. Verdict

Verdict final : GO pour commit et push sur `main`.

Les 7 manifests historiques et leurs signatures sont restés inchangés. Les 7
nouveaux manifests `r2` sont append-only, signés et sélectionnés explicitement
par `signed-manifests/active-revisions.json`.

## 2. Findings corrigés

- Mutation de manifests immuables : corrigée par des chemins `-rN.json`
  distincts et par le refus d'écraser une révision existante.
- Publication manifest-signature non atomique : corrigée par staging,
  vérification complète et rollback avant promotion.
- Fallback implicite depuis une page de provenance : supprimé. Les fallbacks
  sont déclarés explicitement et vérifiés byte-for-byte.
- Validation différente du client Flutter : alignement sur l'unicité, HTTPS,
  ports, fragments, userinfo, taille et nombre maximal de fallbacks.
- Faux succès avec zéro fallback : le vérificateur échoue maintenant si le
  filtre ne correspond à aucun manifest ou fallback.
- Vérification sur entrée non authentifiée : contrat et signature Ed25519 sont
  vérifiés avant tout téléchargement réseau.
- Runbook dupliquant les artefacts r1 et r2 : il sélectionne uniquement la
  révision active de chaque pack.
- Renouvellement en place : l'ancien script mutatif est neutralisé et impose
  la création d'une nouvelle révision.
- Archives expirées bloquant la CI : structure et signature restent vérifiées
  pour toutes les archives, tandis que la fraîcheur concerne les révisions
  actives.
- Omission silencieuse d'un pack dans le registre : chaque `packId` signé doit
  avoir exactement une révision active cohérente avec son nom de fichier.

## 3. Preuves

- 14 manifests valides, 0 invalide.
- 14 signatures Ed25519 valides.
- 572 fallbacks distants téléchargés et identiques à leur SHA-256 signé.
- Les 2 corpus Tanzil conservent chacun 6 236 versets.
- Les 5 packs QuranEnc conservent chacun 114 réponses verbatim.
- `bash -n tools/*.sh` : succès.
- `guard-public-repository.sh` : succès, aucun secret suivi détecté.
- `just verify-fallbacks quran-text quran_text_uthmani_hafs` : 1 fallback
  vérifié.
- Filtre inexistant : échec attendu avec code 1.
- Runbook `quran-text` : plus aucun doublon, arrêt attendu uniquement parce que
  les nouveaux fichiers ne sont pas encore présents sur `origin/main`.
- Self-audit indépendant final : GO.

## 4. Invariants de production

- Les artefacts GitHub Releases restent la source primaire.
- Les sources originales autorisées restent des fallbacks de disponibilité,
  jamais une autorité d'intégrité.
- Le SHA-256 signé décide de l'acceptation de chaque octet.
- Une révision existante ne doit jamais être remplacée.
- Toute nouvelle révision doit être créée, vérifiée, ajoutée au registre actif
  et publiée dans le même commit.
- Les packs KFGQPC restent en quarantaine tant que la preuve de redistribution
  et le contrat d'installation signé ne sont pas archivés.
