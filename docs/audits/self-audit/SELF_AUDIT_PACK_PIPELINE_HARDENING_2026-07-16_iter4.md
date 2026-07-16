# Self-audit du canal de packs signé, itération 4

Date : 16 juillet 2026

## Périmètre

- registre actif signé Ed25519 et anti-rollback
- publication de releases immuables
- téléchargement HTTPS borné et redirections contrôlées
- validation sémantique des corpus Coran et traductions
- provenance et snapshots de licence
- sécurité du dépôt public et CI programmée

## Findings corrigés

1. Le registre actif possède désormais une séquence monotone, une durée de vie
   bornée, une signature Ed25519 et une comparaison avec `origin/main`.
2. Le workflow de signature autorise une nouvelle révision strictement
   croissante sans exiger une identité byte à byte avec l'ancien index. Un
   second contrôle d'optimistic concurrency précède la promotion locale.
3. Le helper HTTPS suit les redirections manuellement et valide chaque hôte
   avant la requête suivante.
4. Une release est créée en draft, ses assets sont retéléchargés et comparés
   avant sa publication.
5. Les validateurs imposent 114 sourates, 6 236 versets et la séquence exacte
   des versets pour les cinq traductions QuranEnc et les deux textes Tanzil.
6. La CI vérifie l'empreinte exacte de l'autorité de structure et effectue un
   smoke distant quotidien du registre, des signatures et d'un artefact par
   pack actif.
7. Les preuves de licence Tanzil et QuranEnc sont suivies comme archives gzip
   déterministes. La CI compare leur SHA-256 décompressé aux manifests signés.
8. Le signataire authentifie aussi le registre distant avant de l'utiliser
   comme base anti-rollback et refuse une modification concurrente de sa
   signature.
9. Le validateur QuranEnc exige l'ordre original strict des numéros de versets,
   en plus de leur couverture canonique exacte.
10. Une nouvelle release est construite depuis des manifests candidats
    immuables encore inactifs. Le registre signé n'est activé qu'après le
    re-téléchargement public et la vérification de tous les artefacts.
11. Le smoke programmé contrôle quotidiennement tous les petits packs et un
    septième déterministe des traductions, soit une couverture publique
    complète de chaque artefact sur sept jours.
12. Le signataire refuse une activation tant que chaque artefact du manifest
    candidat n'est pas publiquement re-téléchargeable avec sa taille et son
    SHA-256 exacts.
13. La validation sémantique QuranEnc reçoit explicitement le manifest candidat
    et le builder refuse lui aussi tout ordre de versets non canonique.

## Preuves exécutées

- `git diff --check` : succès
- `bash -n tools/*.sh` : succès
- `guard-public-repository.sh` : succès
- `validate-client-manifests.sh` : 14 manifests valides, 0 invalide
- `verify-client-manifest-signatures.sh` : 15 signatures valides
- corpus Tanzil : 6 236 versets chacun, 0 doublon, 0 sourate incomplète
- traductions QuranEnc : 5 fois 114 sourates avec couverture canonique exacte
- redirection inter-hôte hors allowlist : refusée
- clé publique : aucune clé privée ou secret présent dans Git

## Dette externe non masquée

Les anciennes releases Mushaf restent en quarantaine dans l'application. Leur
retrait immédiat casserait des clients historiques. Aucun nouveau lien runtime
n'est activé tant qu'une preuve publique de redistribution et une migration
client authentifiée ne sont pas archivées. Ce point ne bloque pas la
publication du registre Coran signé, mais bloque toute nouvelle release Mushaf.

## Verdict

GO pour le commit et le déploiement du canal signé Coran. GO sous condition
pour le dépôt global : aucune nouvelle publication Mushaf avant fermeture de la
gate de licence et de migration.
