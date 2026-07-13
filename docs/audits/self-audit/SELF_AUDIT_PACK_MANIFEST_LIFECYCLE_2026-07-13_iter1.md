# Self-audit : cycle de vie des manifests signés

Date : 2026-07-13  
Périmètre : registre public, manifests Ed25519, scripts de signature,
renouvellement, CI et garde anti-secrets.

## Verdict

GO pour une PR protégée. Aucun finding CRITICAL, HIGH ou MEDIUM ouvert dans le
périmètre livré.

## Findings corrigés

| Sévérité | Cause racine | Correction vérifiée |
| --- | --- | --- |
| P1 | Les manifests n'avaient ni fenêtre de validité ni contrôle anticipé d'expiration. | `issuedAt` et `expiresAt` signés, durée maximale de 90 jours, marge CI de 14 jours et exécution quotidienne. |
| P1 | Un couple manifest-signature pouvait devenir incohérent si une publication locale échouait entre les deux fichiers ou était interrompue. | Staging complet, vérification Ed25519, sauvegarde de tous les couples, publication avec restauration globale sur erreur, validation finale échouée, `SIGHUP`, `SIGINT` ou `SIGTERM`. Une restauration qui échoue conserve les sauvegardes et retourne une erreur critique. |
| P1 | La garde publique ne reconnaissait pas les PAT GitHub fine-grained ni `.envrc`. | Détection de `github_pat_` et des fichiers `.envrc` suivis. |
| P2 | Les producteurs pouvaient générer une fenêtre incompatible avec le client. | Borne de 90 jours dans les scripts de construction, de signature et de renouvellement. |
| P2 | Une signature de bonne taille pouvait être incompatible avec la clé publique mobile. | Vérification Ed25519 contre la clé publique avant toute publication locale. |

## Contrôles exécutés

- `bash -n` sur les scripts modifiés : passé.
- `tools/refresh-signed-manifest-validity.sh` : 7 manifests re-signés, puis
  contrat et signatures validés.
- `tools/sign-client-manifests.sh quran-text quran_text_uthmani_hafs` :
  génération staging, publication avec rollback et validations passées.
- Échec contrôlé avec une marge de validité impossible : rollback déclenché,
  puis contrat normal et signatures de nouveau valides pour les 7 manifests.
- `tools/guard-public-repository.sh` : passé.
- `tools/validate-client-manifests.sh` : 7 valides, 0 invalide.
- `tools/verify-client-manifest-signatures.sh` : 7 signatures Ed25519 valides.
- `git diff --check` et audit U+2014 sur le périmètre : passés.

## Limites et exploitation

- Le scan local par expressions régulières complète GitHub Secret Scanning et
  Push Protection activés dans la configuration du dépôt. La preuve de cette
  configuration est vérifiée trimestriellement avec les commandes consignées
  dans `devops.md`.
- Les packs dont la redistribution n'est pas démontrée restent hors registre
  signé. Cette barrière de licence et de provenance est intentionnelle.
- La publication distante reste protégée par PR et par le statut obligatoire
  `Pack integrity`; aucune release n'est créée par ce changement de cycle de
  vie.
