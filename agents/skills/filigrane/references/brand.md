# Identité Filigrane

Référence de marque, à appliquer pour tout travail visuel (fond d'écran, barre, menu, plymouth, ISO, README, site, icônes). Fichiers maîtres : `brand/` à la racine du dépôt. Brandbook illustré (scènes sur toutes les plateformes, couleur et gris) : https://claude.ai/artifact/K448pohHCitnyA8rn4dyR4

## Idée

Des voiles translucides qui se superposent : l'OS est le voile, tout reste visible à travers. Trois principes : transparence (les voiles se densifient en se croisant, ils ne masquent pas), légèreté (pointes effilées, Jost Light), retrait (discret, lisible quand on le cherche). Slogan : « L'OS en toute discrétion ». Nom complet `Filigrane`, nom court `fili` (commandes, paquets, hôte).

## Couleurs

```css
:root {
  --fili-papier: #f3f1ec;  /* fond clair de référence */
  --fili-nuit:   #1c222b;  /* fond sombre, tuile d'icône, texte sur clair */
  --fili-ardoise:#5f7894;  /* couleur de marque, liens, logo une couleur */
  --fili-voile:  #9dbbd6;  /* ton dominant des voiles, accents sur sombre */
  --fili-brume:  #dbe7f4;  /* texte et voiles clairs sur fond sombre */
}
```

| Texte sur fond | Contraste | Usage |
|---|---|---|
| nuit / papier | 14,2:1 | texte courant |
| brume / nuit | 12,8:1 | texte sur sombre |
| voile / nuit | 8,0:1 | accents sur sombre |
| ardoise / blanc | 4,6:1 | liens, petits titres |
| ardoise / papier | 4,0:1 | titres ≥ 18 px seulement |

Interface sombre (niri, shell Quickshell, foot) : fond `nuit`, texte `brume`, accent `voile`. Pas d'autre couleur vive ; les couleurs d'état (erreur, alerte) restent désaturées.

## Dans l'OS

Teintes dérivées (entre nuit et voile) et états désaturés, communs à toutes les configs : nuit profond `#181d25`, nuit-2 `#232b36` (champs, cartes), nuit-3 `#2d3744` (sélection), nuit-4 `#3c4858` (liserés), brume-2 `#a9b8c8` (texte secondaire), sable `#d2bf92` (alerte), cendre `#c98f93` (erreur), sauge `#a3bfa8` (succès). Palette 16 couleurs du terminal : `dotfiles/config/foot/foot.ini` (reprise par alacritty, nvim via catppuccin `color_overrides`, zellij).
- Mode clair (optionnel, le sombre reste le défaut) : `fili-theme light|dark`, choisi dans le fili-panel écrans (APPARENCE). Fond papier `#f3f1ec`, papier profond `#f8f7f3`, papier-2 `#e9e6df`, papier-3 `#dfdbd2` (sélection), papier-4 `#cdc8bd` (liserés), texte nuit, texte secondaire `#4f5e70`, accent ardoise foncé `#3f5a78` (vif `#2f4a66`), icônes ardoise, états assombris : sable `#80662b`, cendre `#9a4f55`, sauge `#4a7354`. Valeurs dans `FiliTheme.qml`, `[colors-light]` de foot, `filigrane-light.css` (GTK3), `gtk-4.0/gtk.css`, latte de nvim, `theme.kdl` généré pour niri ; fond `filigrane-clair.png`. Alacritty, zellij, swaylock et Plymouth restent sombres.

- Polices : `dotfiles/home/.local/share/fonts/` (Jost, JetBrains Mono, variables, OFL). Interface en Jost, terminaux en JetBrains Mono.
- Icônes : au trait fin, jamais pleines. Police « Fili Icons » (Lucide, ISC) générée par `scripts/fili-icons.py` sur les codes Font Awesome / Nerd Font déjà utilisés; fontconfig la place juste derrière Jost (`dotfiles/config/fontconfig/conf.d/60-fili-icons.conf`), le terminal garde les Nerd Fonts. Nouvelle icône : une ligne dans `MAP` du script, le relancer.
- Son : le bruit du papier et de l'écriture, jamais une cloche; sourd, discret, sans aigus stridents (bruit filtré, petits chocs graves, écho aérien, volume bas). `brand/sound/notification.wav` (notification: deux frappes de machine à écrire) généré par `brand/sound/make-sounds.py`, joué par la fili-shell (`FiliSound.qml`). Nouveau son: une entrée dans `SOUNDS` du script.
- Barre (fili-bar): chaque module est « icône ou étiquette en ardoise → valeur en brume » (son 85 %, clavier fr, écran 65 %, Bluetooth 2 (appareils connectés)/SHARE/OFF, notifications 3 (nombre)/MUTE, CPU/RAM). Règle appliquée par `BarItem`/`BarScript` (`FiliTheme.glyph/value/iconColor`); un état (sable, cendre, voile) colore tout le module. États en majuscules.
- Logo : `brand/` lié dans `~/.local/share/filigrane` (bouton menu de la barre : `filigrane-sombre.svg`).
- Fond d'écran `filigrane.png` (défaut après installation) et images Plymouth : générés par `scripts/brand-assets.sh` (relancer si `brand/` change).
- Autres fonds livrés (`dotfiles/home/.local/share/wallpapers/voile-*.jpg`, 2560×1600) : photos de brume en couches, tons nuit/voile/brume, toutes CC0 (Unsplash via Wikimedia Commons) : `voile-brume-bleue` (Blue haze over wooded slopes), `voile-crepuscule` (Blue dusk in the mountains), `voile-foret-brouillard` (Dense fog in the woods), `voile-mer-de-nuages` (Sea of clouds), `voile-montagne-brumeuse` (Misty Mountains zR40wedS1aQ). Tout nouveau fond : licence libre vérifiée (CC0 ou domaine public), source notée ici.
- Démarrage : thème Plymouth `system/plymouth/filigrane/` (logo empilé, étiquette « PHRASE DE PASSE », points), installé par `sudo system/plymouth/install.sh` (régénère l'initramfs).

## Typographie

- **Jost** (linéale géométrique, OFL), pas d'empattement : c'est la police de l'interface et du nom.
- Nom dans le logo : Jost Light 300, CAPITALES, espacement 0,4 em (`F I L I G R A N E`). Dans les SVG, les lettres sont des tracés : aucune police requise.
- Titres Jost 300, sous-titres 400, texte 300-400, étiquettes 500 en capitales espacées 0,12-0,16 em. Code : JetBrains Mono.
- Pas de paquet Void : fichiers dans `dotfiles/home/.local/share/fonts/` (liés dans `~/.local/share/fonts/`), Google Fonts pour le web (`family=Jost:wght@300;400;500`).

## Fichiers (`brand/`)

| Fichier | Usage |
|---|---|
| `filigrane-empile-{clair,sombre,gris,sombre-gris,ardoise,blanc}.svg` | logo complet, voiles au-dessus du nom (usage principal) |
| `filigrane-horizontal-{clair,sombre,gris,sombre-gris,ardoise,blanc}.svg` | logo en ligne (en-têtes, barres, pied de page) |
| `filigrane-couleur.svg` | symbole, fonds clairs (rendu fidèle de l'image d'origine) |
| `filigrane-couleur-doux.svg` | idem, arêtes adoucies, grands visuels (fond d'écran) |
| `filigrane-sombre.svg` · `-sombre-gris.svg` | symbole sur fond sombre (l'encre devient lumière bleutée) |
| `filigrane-gris.svg` · `-gris-aplat.svg` | niveaux de gris : dégradé (impression N&B), aplats (une encre tramée) |
| `filigrane-mono-{noir,blanc,ardoise}.svg` | une couleur (tampon, gravure, photo) |
| `filigrane-icone.svg` · `-icone-claire.svg` | icône d'application sombre (défaut) et claire, ≥ 48 px |
| `filigrane-icone-petite.svg` · `favicon.svg` | ≤ 32 px : cadrage serré sur le croisement des voiles |

Export : `rsvg-convert -w <px> brand/<fichier>.svg -o <fichier>.png` ; favicon : PNG 16/32/48 puis `magick f16.png f32.png f48.png favicon.ico`. Les fichiers une couleur découpent leurs liserés avec des masques SVG : ne pas les passer dans un outil qui « recolore tout ».

## Choisir la version

| Fond | Version |
|---|---|
| blanc, papier, gris clair | couleur ; en N&B : gris dégradé ou aplats ; noir |
| gris moyen | blanc ou noir plein uniquement (aucune version translucide ne tient) |
| gris foncé, nuit, noir | sombre ; écran monochrome : sombre-gris ; sinon blanc |
| photo | blanc ou noir plein |

## Icône

- Tuile carrée, rayon 22,5 % (macOS/Linux) ; iOS 28 %, Android cercle ou goutte, Windows 10 %. Tuile `nuit` par défaut, `papier` pour la version claire.
- Les voiles gardent **toujours** les proportions du logo (échelle uniforme, jamais étirés) : la tuile coupe les pointes qui débordent.
- ≥ 48 px : `filigrane-icone.svg`. ≤ 32 px : `filigrane-icone-petite.svg`. En 16 px les voiles pâles restent doux : limite connue.

## Tailles et espace

- Zone de protection : la hauteur de la bosse (voile du haut) libre tout autour.
- Minimum : logo horizontal 160 px (40 mm imprimé) ; en dessous, l'icône.

## À ne pas faire

Déformer, faire pivoter, recolorer les voiles un par un, ajouter ombre ou contour, logo couleur sur fond sombre ou sur photo, écrire le nom avec une police à empattement ou en gras, ajouter des effets (le seul flou admis dans l'OS reste celui derrière le menu).

## Sources

Générateurs et fichiers de travail (hors dépôt) : `~/Pictures/filigrane/kit/` (`trace/voiles_fideles.py` rend toutes les versions des voiles depuis les arêtes relevées sur l'image d'origine ; `brandbook/` construit le brandbook). Polices de travail : `~/.cache/filigrane-fonts/`. Aucune recherche d'antériorité de marque n'a été faite.
