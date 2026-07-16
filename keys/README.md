# Clés publiques de signature

Les manifests clients sont signés en Ed25519. Seules les clés publiques sont
versionnées ici. La clé privée correspondante reste dans le trousseau macOS
sous le service `deencoach-pack-ed25519-2026-07` et ne doit jamais être
exportée vers Git, CI ou une release.

| Identifiant | Fichier | État |
| --- | --- | --- |
| `deencoach-pack-2026-07` | `deencoach-pack-2026-07.pub.pem` | actif |

La clé publique doit correspondre exactement à celle embarquée dans
`PackManifestTrustStore` du projet Flutter. Chaque manifest a une durée de
validité maximale de 90 jours : le client refuse ceux expirés ou dont la
fenêtre de validité dépasse cette borne. Toute rotation est additive : livrer
la nouvelle clé dans l'application, signer un lot de transition, publier les
nouveaux manifests, puis retirer l'ancienne clé seulement après expiration de
ses manifests.

En cas de compromission présumée : révoquer immédiatement les accès du
compte concerné, générer une nouvelle paire Ed25519 hors Git, livrer sa clé
publique dans une version applicative, signer et publier de nouveaux manifests
avec cette clé, puis retirer l'ancienne clé à l'expiration de sa fenêtre de
90 jours. Ne jamais tenter de remplacer une signature existante sans nouvelle
révision de manifest, sous un nouveau chemin `-rN.json`, et journal de décision.
