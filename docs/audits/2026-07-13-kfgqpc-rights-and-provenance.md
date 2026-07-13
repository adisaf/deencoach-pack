# Audit de droits et de provenance KFGQPC

Date : 2026-07-13

## Contexte détecté

- Mode : projet de redistribution publique de packs téléchargeables pour une
  application mobile gratuite, distribuée à des utilisateurs internationaux.
- Matière : droits d'auteur, licence de logiciels et de contenus, provenance
  d'artefacts binaires et exactitude des attributions.
- Limite : cette analyse n'est pas un avis juridique local. Elle applique une
  règle opérationnelle de prudence : aucune redistribution sans droit explicite
  et archivé pour l'artefact précis.

## Faits vérifiés

1. Le portail officiel des polices KFGQPC permet de télécharger des polices et
   affiche « tous droits réservés » au Complexe Roi Fahd.
2. La documentation QUL associe les ressources V1, V2 et V4 au Quran Printing
   Complex, mais sa FAQ précise que les ressources n'ont pas toutes le même
   statut de droits et demande de vérifier les informations de licence de
   l'auteur de chaque ressource avant usage.
3. Les manifests historiques `qpc-v1.json`, `qpc-v2.json` et
   `qpc-v4-tajweed.json` pointent vers des ZIP Deen Coach reconstruits depuis
   QUL. Aucun texte officiel de licence attaché à chacun de ces artefacts, ni
   son empreinte SHA-256, n'est archivé dans ce dépôt.
4. L'affirmation historique « Use, Copy, Distribute Free of Cost, no
   modification, no sale » n'est pas accompagnée ici d'une source officielle
   correspondant aux binaires distribués. Elle ne peut donc pas fonder une
   publication.

Sources consultées :

- https://fonts.qurancomplex.gov.sa/en/
- https://qul.tarteel.ai/docs/qpc
- https://qul.tarteel.ai/faq

## Décision opérationnelle

Statut : `source_license_unknown`.

Les trois packs sont mis en quarantaine : aucune nouvelle version, aucun
manifest client signé, aucun lien de téléchargement actif dans l'application
et aucune republication ne sont permis. Le client Deen Coach applique déjà ce
refus avant tout téléchargement.

Les assets de release historiques demeurent publiquement accessibles. Leur
retrait GitHub est une action externe destructrice qui doit faire l'objet d'une
décision explicite du propriétaire du dépôt. Tant qu'ils existent, ils sont
signalés comme risque de conformité et ne doivent pas être promus.

## Conditions de réactivation

Pour chaque variante V1, V2 et V4, réunir et archiver :

1. l'artefact original téléchargé depuis une URL d'autorité ou une autorisation
   écrite du titulaire ;
2. le texte officiel de licence applicable à cet artefact et son SHA-256 ;
3. le SHA-256 du binaire original et la démonstration de correspondance avec
   tout ZIP Deen Coach ;
4. l'attribution exigée et la preuve que la redistribution, le reconditionnement
   en ZIP et la distribution mondiale gratuite sont autorisés ;
5. une revue religieuse séparée, fondée sur la source exacte, confirmant la
   transmission Hafs an Asim via al-Shatibiyya et l'absence de modification du
   rasm ;
6. un manifest Deen Coach signé Ed25519 avec provenance complète, suivi des
   validations, d'un self-audit et d'une QA Android et iOS.

Sans ces éléments, la décision reste inchangée. Wa Allahu a'lam.
