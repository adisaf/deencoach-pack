# Snapshots immuables des licences sources

Ces archives gzip déterministes conservent les octets exacts des documents
officiels récupérés par les scripts de construction le 13 juillet 2026. Elles
ne constituent pas une nouvelle licence et doivent toujours être lues avec la
matrice `docs/SOURCE_RIGHTS_MATRIX.md`.

| Source | URL officielle | Archive | SHA-256 archive | SHA-256 après décompression |
| --- | --- | --- | --- | --- |
| Tanzil Quran Text License | https://tanzil.net/docs/Text_License | `TANZIL_TEXT_LICENSE.txt.gz` | `8ba95de46c424c876e22ebed8e48139088dacecdb2dee8ae6631b701868bc6c1` | `665c0e48132115892b1ed4445903468b785917040d29802d750d0956a28a30f2` |
| QuranEnc Terms | https://quranenc.com/ff/home/api | `QURANENC_TERMS.html.gz` | `9e02a7106915333f81a410e92ed3886fa8d250b4910f98a906857e5f212f490b` | `851663275ce2b0d335f6607e023c79ad2777268557f6e066a78bfb62ed0cbb4e` |

Vérification locale :

```bash
gzip -dc provenance/licenses/TANZIL_TEXT_LICENSE.txt.gz | shasum -a 256
gzip -dc provenance/licenses/QURANENC_TERMS.html.gz | shasum -a 256
```
