# Filigrane-Icons

Thème d'icônes de Filigrane: les dossiers, les glyphes de la barre latérale et l'icône des fichiers (`file.svg`),
le reste venant d'Adwaita puis hicolor (`Inherits=Adwaita,hicolor`).

## Origine et licence

Ces fichiers sont extraits du thème **Nordic-Slot-Dark-Icons** de L4ki
(<https://github.com/L4ki/Slot-Plasma-Themes>), publié sous **GNU GPL v3** (texte dans `COPYING`).
Ce dossier est donc lui aussi sous GPL v3, indépendamment du reste du dépôt. Les sources sont celles du thème d'origine,
disponibles à l'adresse ci-dessus.

## Modifications (2026-10-30)

Thème réduit et adapté pour Filigrane, par `scripts/icon-theme-build.sh`:
- seuls sont gardés `places/scalable`, `places/16`, `places/symbolic`, `mimetypes/symbolic`, trois symboliques de
  `devices/symbolic` (`computer`, `drive-harddisk`, `drive-removable-media`);
- `mimetypes/scalable/file.svg` (icône des fichiers) est un dessin propre à Filigrane (2026-10-30), qui remplace la copie de
  `application-x-generic.svg`; il n'est pas issu de Nordic;
- `folder-accent-<accent>.svg`, `folder-dark-default.svg` et `folder-light-default.svg` sont des copies des dossiers de
  couleur voisine (`folder-brume`: `folder-blue.svg` recoloré en `#dbe7f4` et `#a9b8c8`);
- nouvel `index.theme` (nom `Filigrane-Icons`, héritage Adwaita et hicolor).

Installation: `scripts/icon-theme.sh` (copie vers `~/.local/share/icons`, lancée par `bootstrap.sh`).
Mise à jour depuis le thème d'origine: `scripts/icon-theme-build.sh [dossier ou archive]`.
