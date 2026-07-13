# Clés publiques de signature

Les manifests clients sont signés en Ed25519. Seules les clés publiques sont
versionnées ici. La clé privée correspondante reste dans le trousseau macOS
sous le service `deencoach-pack-ed25519-2026-07` et ne doit jamais être
exportée vers Git, CI ou une release.

| Identifiant | Fichier | État |
| --- | --- | --- |
| `deencoach-pack-2026-07` | `deencoach-pack-2026-07.pub.pem` | actif |

La clé publique doit correspondre exactement à celle embarquée dans
`PackManifestTrustStore` du projet Flutter. Toute rotation est additive :
livrer la nouvelle clé dans l'application, signer un lot de transition, puis
retirer l'ancienne clé seulement après expiration de ses manifests.
