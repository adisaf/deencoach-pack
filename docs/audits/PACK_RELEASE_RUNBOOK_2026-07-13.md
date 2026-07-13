# Self-audit : runbook de publication des packs, 2026-07-13

## Résumé exécutif

Verdict : GO sous condition de publication des manifests et signatures sur
`origin/main`. Le runbook local refuse toute release tant que cette condition
de traçabilité n’est pas satisfaite et vérifie les artefacts publics après la
publication.

## Corrections appliquées

### [P2][confiance élevée] Vérification post-publication dépendante des fichiers locaux

Fichier et ligne d'origine :
`/Users/fawazadisa/Sites/deencoach-pack/tools/release-signed-pack-category.sh:266`.

Preuve : le flux commun exécutait la validation des artefacts locaux avant
`verify-published`. Après nettoyage de `uploads/`, le contrôle d’une release
existante aurait échoué sans même tenter le téléchargement public.

Risque : impossibilité de rejouer le contrôle de disponibilité et d’intégrité
depuis un poste qui ne possède pas les fichiers de préparation ignorés par Git.

Cause racine : la validation locale et la vérification distante partageaient
un préambule unique alors que leurs préconditions sont différentes.

Correction appliquée : séparation de `validate_signed_manifests` et de
`validate_local_contract`. L’action `verify-published` valide les manifests et
signatures, contrôle leurs URLs, puis télécharge les artefacts publics sans
consulter `uploads/`.

Preuve après correction : `just release-verify-published quran-text
quran-text-v1.0.0` atteint les URLs GitHub et échoue explicitement en HTTP 404,
ce qui est attendu avant création de la release.

## Validation

| Contrôle | Résultat | Preuve |
| --- | --- | --- |
| Syntaxe Bash | Passé | `bash -n tools/release-signed-pack-category.sh` |
| Diff final | Passé | `git diff --check` |
| Recettes locales | Passé | `just --list`, avec trois recettes de release exposées |
| Préparation opérateur | Passé | `just doctor`, GitHub CLI authentifié, `jq`, OpenSSL, curl et SHA-256 présents |
| Intégrité Tanzil locale | Passé | 2 manifests, signatures et copies de 6 236 versets validés |
| Intégrité QuranEnc locale | Passé | 5 manifests et 570 réponses validés, 114 sourates par traduction |
| Garde `origin/main` | Passé | pré-vérification refusée car les manifests actuels ne sont pas encore sur `origin/main` |
| Téléchargement public | Bloqué attendu | HTTP 404 avant la création de `quran-text-v1.0.0` |
| ShellCheck | Non exécuté | outil indisponible dans l’environnement, syntaxe Bash vérifiée |

## Findings résiduels

Aucun finding concret dans le périmètre audité.

La publication elle-même, le téléchargement public réussi et la QA mobile
connectée restent intentionnellement non exécutés : ils nécessitent d’abord un
commit et un push explicitement autorisés, puis une autorisation explicite de
créer les releases GitHub.

## État de l'audit

Audit vert sous réserves. Le code est prêt à publier mais les deux commandes de
pré-vérification prouvent correctement que les manifests locaux ne sont pas
encore publiés. Aucune release, aucun tag, aucun commit et aucun push n’ont été
créés durant cette mission.
