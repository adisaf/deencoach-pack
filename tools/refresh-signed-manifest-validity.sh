#!/usr/bin/env bash

set -euo pipefail

echo 'Erreur : le renouvellement en place est interdit pour les manifests immuables.' >&2
echo 'Créez une nouvelle révision -rN, vérifiez ses fallbacks, puis mettez à jour active-revisions.json.' >&2
exit 1
