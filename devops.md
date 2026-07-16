# Contexte DevOps

## Métadonnées

- Projet : Deen Coach Pack Registry
- Criticité globale : critique
- Date de création : 2026-07-13
- Dernière mise à jour : 2026-07-16
- Propriétaire : Fawaz ADISA
- Contact astreinte : non défini

## Infrastructure

- Cloud principal : GitHub
- Régions : gérées par GitHub
- Cloud secondaire : aucun
- Architecture : registre public de manifests signés Ed25519 et d’artefacts GitHub Releases
- Environnements : local de préparation, GitHub `main`, GitHub Releases publiques

## Services actifs

| Service | Compute | Database | Queue | Cache | CDN | Criticité |
| --- | --- | --- | --- | --- | --- | --- |
| registre de packs | GitHub Actions | aucune | aucune | CDN GitHub | GitHub Releases | critique |

## Réseau et DNS

- DNS public : GitHub et `raw.githubusercontent.com`
- Domaines : `github.com/adisaf/deencoach-pack`
- CDN / WAF : infrastructure GitHub, configuration non administrée dans ce dépôt

## Conformité

- PCI DSS : non applicable
- PAYFAC : non applicable
- RGPD : aucun compte utilisateur ni donnée personnelle stockée par le registre
- Exigence métier : offline-first, attribution et redistribution vérifiées, méthodologie Ahl al-Sunnah wa al-Jamā'ah

## CI/CD

- Outil : GitHub Actions
- Pipeline : garde secrets et clés privées, syntaxe Bash, validation des manifests et signatures Ed25519
- Stratégie de publication : branche courte, PR verte vers `main`, tag annoté, GitHub Release, re-téléchargement SHA-256 et taille

## Observabilité

- Santé : `just release-verify-published <category> <tag>`
- Logs : GitHub Actions et historique GitHub Releases
- Alerting : non configuré, contrôle manuel obligatoire avant chaque publication

## Sécurité

- Secrets : clé privée Ed25519 dans le trousseau macOS, jamais dans Git ni GitHub Actions
- Intégrité mobile : index actif et manifests signés Ed25519, séquence anti-rollback, SHA-256 et taille par artefact avant installation
- Publication : compte GitHub et identité Git Fawaz ADISA vérifiés par le runbook
- Dépôt public : garde anti-secrets, PR obligatoire, statut `Pack integrity`
  strict, force-push et suppression interdits, Actions limitées aux actions
  GitHub épinglées par SHA
- Rotation Ed25519 : manifests bornés à 90 jours, renouvelés et re-signés
  avant expiration ; procédure de compromission dans `keys/README.md`
- Preuve de configuration GitHub : exécuter trimestriellement
  `gh api repos/adisaf/deencoach-pack/branches/main/protection` et
  `gh api repos/adisaf/deencoach-pack/actions/permissions`, puis consigner
  tout écart avant publication

## Backups et DR

- Source de vérité : Git GitHub et GitHub Releases
- RPO : dernière release publiée
- RTO : re-publication contrôlée depuis le commit et les archives locales vérifiées
- Limite : les binaires de préparation sont ignorés par Git et doivent être conservés par l’opérateur jusqu’à vérification publique complète

## Budget

- Coût d’infrastructure direct : nul dans le dépôt, GitHub Releases et GitHub Actions selon les quotas du compte propriétaire
- Seuil d’alerte : revue trimestrielle de l’usage Actions et du volume des releases avant tout changement de distribution
- Interdiction : aucun service payant, CDN tiers ou quota facturé ne peut être ajouté sans décision documentée du propriétaire

## Historique

| Date | Action | Auteur | Référence |
| --- | --- | --- | --- |
| 2026-07-13 | Ajout du runbook public sécurisé, de la CI et du contexte opératoire | Fawaz ADISA | Stabilisation 2026-H2 |
| 2026-07-13 | Protection GitHub de `main`, permissions Actions minimales et expiration des manifests à 90 jours | Fawaz ADISA | Stabilisation 2026-H2 |
| 2026-07-16 | Signature Ed25519 du registre actif et séquence anti-rollback consommable par les clients mobiles | Fawaz ADISA | Correctif régressions packs |
