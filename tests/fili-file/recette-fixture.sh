#!/bin/sh
# Jeu de fichiers pour la recette à la main de Casier (apps/fili-file/RECETTE.md): /tmp/casier-recette (ou $1).
# Noms difficiles, gros dossier, liens, archives (dont une protégée), image, PDF, dossier en lecture seule.
# Refait à neuf à chaque lancement. Usage: tests/fili-file/recette-fixture.sh [DOSSIER]
set -eu
D="${1:-/tmp/casier-recette}"
case "$D" in /tmp/*) ;; *) echo "dossier hors /tmp refusé: $D" >&2; exit 2 ;; esac
rm -rf "$D"
mkdir -p "$D/noms" "$D/gros" "$D/liens" "$D/archives" "$D/medias" "$D/lecture-seule" "$D/vide" "$D/destination" "$D/conflit/source" "$D/conflit/cible"

# Noms difficiles: espaces, accents, emoji, très long, point initial, apostrophes
for n in "avec espaces.txt" "été à la plage.txt" "emoji 🎉.txt" "l'apostrophe.txt" ".caché.txt" "MAJUSCULES.TXT" "sans extension" "deux.points.dans.nom.tar.txt"; do
    printf 'contenu de %s\n' "$n" > "$D/noms/$n"
done
long="$(printf 'très-long-nom-%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14)"
printf 'long\n' > "$D/noms/$long.txt"
mkdir -p "$D/noms/dossier avec espaces" "$D/noms/dossier vide"
printf 'x\n' > "$D/noms/dossier avec espaces/dedans.txt"

# Gros dossier (défilement, tri, sélection)
i=0; while [ "$i" -lt 5000 ]; do : > "$D/gros/fichier-$(printf %05d "$i").txt"; i=$((i + 1)); done

# Liens: valide, cassé, vers un dossier
printf 'cible\n' > "$D/liens/cible.txt"
ln -s cible.txt "$D/liens/lien-valide"
ln -s absent.txt "$D/liens/lien-casse"
ln -s ../noms "$D/liens/lien-dossier"

# Archives: normale et protégée (mot de passe: secret)
mkdir -p "$D/archives/src" && printf 'dans larchive\n' > "$D/archives/src/lisez-moi.txt"
(cd "$D/archives/src" && 7z a -bd -y ../normale.zip lisez-moi.txt >/dev/null && 7z a -bd -y -psecret ../protegee.zip lisez-moi.txt >/dev/null && 7z a -bd -y ../normale.7z lisez-moi.txt >/dev/null) 2>/dev/null || echo "7z absent: archives non créées" >&2

# Médias: PNG et PDF minimaux
python3 -I - "$D/medias" <<'PY'
import struct, sys, zlib
d = sys.argv[1]
def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
w = h = 64
raw = b"".join(b"\x00" + b"".join(bytes((x * 4 % 256, y * 4 % 256, 160)) for x in range(w)) for y in range(h))
open(f"{d}/image.png", "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
objs = [b"<</Type/Catalog/Pages 2 0 R>>", b"<</Type/Pages/Kids[3 0 R]/Count 1>>",
        b"<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>",
        b"<</Length 44>>\nstream\nBT /F1 18 Tf 20 50 Td (Recette Casier) Tj ET\nendstream", b"<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>"]
out = b"%PDF-1.4\n"; offs = []
for i, o in enumerate(objs, 1):
    offs.append(len(out)); out += f"{i} 0 obj\n".encode() + o + b"\nendobj\n"
x = len(out); out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode() + b"".join(f"{o:010d} 00000 n \n".encode() for o in offs)
out += f"trailer\n<</Size {len(objs)+1}/Root 1 0 R>>\nstartxref\n{x}\n%%EOF\n".encode()
open(f"{d}/document.pdf", "wb").write(out)
PY
printf 'Texte pour l aperçu.\nDeuxième ligne.\n' > "$D/medias/notes.txt"

# Dossier en lecture seule (erreur « permission refusée » à la création d'un élément)
printf 'protégé\n' > "$D/lecture-seule/fichier.txt"; chmod 555 "$D/lecture-seule"

# Conflit de nom: même nom, contenu différent
printf 'SOURCE (nouveau)\n' > "$D/conflit/source/rapport.txt"; printf 'CIBLE (ancien)\n' > "$D/conflit/cible/rapport.txt"
printf 'autre\n' > "$D/conflit/source/autre.txt"
echo "$D"
