# Renouvellement du canal signé

Préparer un lot atomique de nouvelles révisions immuables et d'un index de
séquence supérieure. Aucun contrôle de sécurité client ne change. Le script
ne publie rien et n'écrit pas dans le checkout source.

## Préparation

Python 3.12+, Git, OpenSSL, jq et le trousseau macOS existant sont requis.
Depuis la racine de ce dépôt :

```bash
python3 -m unittest discover -s tools -p test_renew_signed_channel.py -v
python3 tools/renew_signed_channel.py --source-root "$PWD" \
  --output /private/tmp/deen-signed-channel-candidate
```

La sortie doit être nouvelle. Le HEAD source doit égaler le HEAD public.
Les anciennes signatures sont vérifiées ; seuls les champs de validité des
manifests changent. Les artefacts, hashes, versions et sources restent identiques.
La clé du trousseau n'est jamais affichée, copiée dans Git ou conservée dans la
sortie. Les validateurs existants vérifient le lot final, chaque artefact public
et la protection anti-rollback dans un dépôt temporaire isolé.

## Livraison autorisée

Relire `renewal-identity.json` et les nouvelles paires JSON/signature.
Avant toute livraison, recontrôler le HEAD public et la marge de validité. Si
le HEAD a changé, régénérer le lot ; ne jamais réutiliser une ancienne séquence.
Publier ensemble les nouvelles révisions et les deux fichiers d'index, en
préservant toutes les anciennes révisions. La préparation ne vaut pas
publication et nécessite une autorisation explicite du propriétaire.
Après livraison, vérifier les octets réellement servis puis l'installation
FR/EN et la lecture hors ligne dans l'application.

## Échéance opérationnelle

Le mainteneur détenteur du trousseau prépare le renouvellement 30 jours avant
expiration (`renewBefore`), puis livre avec au moins 14 jours de marge.
Le workflow quotidien exige désormais cette marge de 30 jours : son échec
signale une intervention, jamais une permission de réduire la sécurité.
Le mainteneur traite ces échecs. Aucun secret CI ou automatisme de publication
n'est introduit. Même après expiration, le lot atomique restaure le canal sans
modifier en place les révisions ni accepter des métadonnées expirées.
