# Tokens de l'interface

Valeurs communes au fili-shell, aux outils `fili-*` et aux thèmes. Provenance : **[Apple]** principe Apple historique (HIG Mac OS X Leopard 2008, chapitres « Text » et « Layout Guidelines »), **[Filigrane]** décision du projet, **[À valider]** proposition à confirmer par un prototype. Unité : pixel logique (1 pt Apple = 1 px logique, l'échelle HiDPI vient de niri).

## Typographie

Police d'interface Jost (variable, tous les poids), code et terminaux JetBrains Mono. Les tailles et les poids reprennent les polices système d'Apple, avec Jost à la place de Lucida Grande. **[Apple]** Le gras d'Apple devient Jost SemiBold 600 : Jost, plus fin et à petit œil, y pèse autant que Lucida Grande Bold sans alourdir le texte sur fond sombre. **[Filigrane]**

| Rôle | Taille | Poids | Usage |
|---|---:|---|---|
| Système | 13 | Regular 400 | texte courant, menus, contrôles, contenu des fiches, valeurs de la fili-bar (`FiliTheme.size`; échelle : `size`, `sizeList`, `sizeSmall`, `sizeLabel`, `sizeTitle`, accent `weightAccent`) |
| Système accentué | 13 | SemiBold 600 | message d'une alerte, avec parcimonie |
| Vue | 12 | Regular 400 | lignes des listes et tableaux (menu, notifications, historique) |
| Petit | 11 | Regular 400 | texte secondaire, en-têtes de colonnes, infobulles, petits contrôles, précisions sous un réglage |
| Petit accentué | 11 | SemiBold 600 | titre d'un groupe de réglages sans cadre, texte bref sous un champ ; avec parcimonie |
| Étiquette | 10 | Regular 400 | libellés sous les icônes d'une barre d'outils, graduations de curseur ; rare |
| Mini | 9 | Regular 400 | contrôles mini ; à éviter dans le shell (Jost a un petit œil) |

- Intertitres de section des fili-panel et étiquettes : capitales espacées (0,12-0,16 em), 11 px, couleur ardoise (`PanelSection`). **[Filigrane]**
- Grands titres et nom (fili-about, écran d'accueil, ≥ 18 px) : Jost Light 300. Le Light ne descend pas sous 18 px. **[Filigrane]**
- Ne jamais réduire une taille pour faire tenir du texte : couper, tronquer avec infobulle, ou élargir. **[Apple]**

## Échelle de l'écran

- Tout est en pixels logiques : niri applique l'échelle de l'écran (1, 1,25, 1,5, 1,75, 2, 3), le shell n'en tient jamais compte. Jamais de taille en pixels physiques, jamais de division ni de multiplication par l'échelle. **[Filigrane]**
- Les jetons de ce fichier valent donc à toutes les échelles. Vérifié au 2026-10-29 à 1,25, 1 et 1,75 (barre, fili-panel écrans) : proportions et alignements conservés.
- Les traits de 1 px (bordures, séparateurs) peuvent tomber entre deux pixels physiques à une échelle fractionnaire : les garder à 1, ne pas les compenser. **[Filigrane]**

## Espacement

Jetons `FiliTheme.space1` à `space6` (valeurs ci-dessous) ; rayons `radiusMark`, `radiusControl`, `radiusWindow`.

| Token | Valeur | Usage | Provenance |
|---|---:|---|---|
| `space-1` | 4 | éléments très liés (icône et sa valeur dans une fiche) | [Filigrane] |
| `space-2` | 8 | entre deux contrôles, entre un intertitre et son premier contrôle | [Apple] |
| `space-3` | 12 | entre groupes ; au-dessus et au-dessous d'un séparateur | [Apple] |
| `space-4` | 16 | entre un cadre de groupe et le bord d'un onglet ; gaps de niri | [Apple] / [Filigrane] |
| `space-5` | 20 | marge des bords d'une fenêtre ou d'un panneau (côtés et bas) | [Apple] |
| `space-6` | 24 | côtés d'une alerte | [Apple] |

- Haut d'une fenêtre : premiers contrôles 14 px sous la barre de titre (10 px en contrôles mini). **[Apple]**
- Barre inférieure : 32 px en contrôles normaux, 22 px en petits ; 8 px entre contrôles et depuis le bord gauche. **[Apple]**
- fili-bar : hauteur 24, marge par module `pad` 7 (écart entre deux textes 14), cellule d'icône seule 24, étiquette → valeur 5 (`FiliTheme.qml`). **[Filigrane]**
- La cohérence prime sur la valeur exacte : un écart régulier se remarque moins qu'un écart irrégulier. **[Apple]**

## Formes

- Rayons **[Filigrane]**, trois valeurs : 2 (repères, jauges, petites marques), 6 (contrôles, champs, lignes sélectionnées, fiches), 10 (fenêtres de couche : fili-panel, fili-tooltip, fili-launcher, notifications). Le `FocusRing` ajoute son écart (2) au rayon de sa cible. Cercles (interrupteur, poignée de curseur) : moitié de leur côté.
- Bordures : 1 px, `nuit4` ; séparateurs 1 px, seulement entre groupes réellement distincts. **[Filigrane]**
- Ombres : aucune dans le shell ; la profondeur vient de la teinte (`nuitProfond` < `nuit` < `nuit2`). Flou : seulement derrière le fili-launcher. **[Filigrane]**
- Contour de focus niri : 1 px. **[Filigrane]**

## Couleurs

Couleurs de marque (`papier`, `nuit`, `ardoise`, `voile`, `brume`) et contrastes : `filigrane` skill, `references/brand.md`. Interface sombre par défaut : fond `nuit`, texte `brume`, accent `voile`. Aucune autre couleur vive ; les états restent désaturés.

| Token sémantique | `FiliTheme` | Sombre | Clair |
|---|---|---|---|
| `color-background` (fond profond, fenêtres de couche) | `nuitProfond` | `#181d25` | `#f8f7f3` |
| `color-surface` (fond) | `nuit` | `#1c222b` | `#f3f1ec` |
| `color-surface-raised` (champs, fiches) | `nuit2` | `#232b36` | `#e9e6df` |
| `color-selection` | `nuit3` | `#2d3744` | `#dfdbd2` |
| `color-border` | `nuit4` | `#3c4858` | `#cdc8bd` |
| `color-text-primary` | `brume` | `#dbe7f4` | `#1c222b` |
| `color-text-secondary` | `brume2` | `#a9b8c8` | `#4f5e70` |
| `color-label` (icônes, intertitres) | `ardoise` | `#5f7894` | `#5f7894` |
| `color-accent` / `color-focus` | `voile` | `#9dbbd6` | `#3f5a78` |
| `color-accent-strong` | `voileVif` | `#b9d0e4` | `#2f4a66` |
| `color-warning` (sable) | `sable` | `#d2bf92` | `#80662b` |
| `color-danger` (cendre) | `cendre` | `#c98f93` | `#9a4f55` |
| `color-success` (sauge) | — | `#a3bfa8` | `#4a7354` |
| `color-disabled` | `ardoise` | `#5f7894` | `#5f7894` |

- Les noms gardent leur rôle d'un mode à l'autre (`nuit` = fond, `brume` = texte, `voile` = accent). Mode clair optionnel : `fili-theme light|dark`, choisi dans le fili-panel écrans (APPARENCE). Contraste des états clairs ≥ 4,8:1 sur papier.
- Valeurs dans `dotfiles/config/quickshell/FiliTheme.qml`, `[colors-light]` de `foot.ini`, `filigrane-light.css` (GTK3), `gtk-4.0/gtk.css`, latte de nvim, `theme.kdl` généré pour niri ; fond clair `filigrane-clair.png`. Alacritty, zellij, swaylock et Plymouth restent sombres.
- Palette 16 couleurs du terminal : `dotfiles/config/foot/foot.ini` (reprise par alacritty, nvim via catppuccin `color_overrides`, zellij).
- Un composant prend un token ; jamais une couleur littérale quand un token convient.

## États

| État | Rendu |
|---|---|
| survol | fond `nuit3` (`PanelButton`, `PanelChips`), sans changer la taille |
| focus clavier | `FocusRing` 1 px `voile`, visible seulement après usage du clavier (`FiliShell.keyNav`) |
| pressé / actif | fond `nuit4` (puce active de `PanelChips`) |
| sélectionné | texte et icône `voile` (`PanelButton.sel`) ; distinct du survol, qui ne touche que le fond |
| désactivé | texte `ardoise` (`PanelButton.dim`), toujours lisible, sans réaction au survol |
| chargement | valeur remplacée par « … » ou jauge, jamais un faux résultat |
| alerte / erreur / succès | tout le module prend `sable` / `cendre` / `sauge`, plus un mot en capitales |

Le survol n'est jamais le seul moyen d'accéder à une information ou une action. **[Apple]**
