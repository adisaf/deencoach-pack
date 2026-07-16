# Autorité de structure du Coran

Le fichier `tools/quran-structure.tsv` fixe la structure canonique utilisée par
les validateurs de packs : 114 sourates et 6 236 versets selon la numérotation
de Kūfah associée à la transmission de Ḥafṣ d'après ʿĀṣim.

La table a été recoupée le 16 juillet 2026 avec la liste des chapitres publiée
par Quran Foundation (`https://api.quran.com/api/v4/chapters`) et avec les deux
corpus Tanzil archivés par ce dépôt. Son empreinte SHA-256 canonique est
`56507b865b7c940c98489ee4dbbbb1db49504a1a9dcb9d20088309c727d1ef42`.

Cette table ne contient aucun texte religieux. Elle sert uniquement à refuser
un artefact incomplet, dupliqué ou dont la séquence des versets est incorrecte.
Toute modification doit conserver une source tracée, être relue selon la
méthodologie Ahl al-Sunnah wa al-Jamāʿah du projet et faire l'objet d'une
nouvelle validation globale des packs Coran.
