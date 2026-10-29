# Filigrane Desktop HIG

Guide de conception de l'interface Filigrane, adapté de `hig-source.md` (v1.0) à ce que Filigrane est réellement : niri + un shell Quickshell (fili-shell), pas de bureau à fenêtres flottantes. Référence : Apple Human Interface Guidelines historiques de Mac OS X (2005, Leopard 2008), archive <https://leopard-adc.pepas.com/documentation/UserExperience/Conceptual/AppleHIGuidelines/XHIGIntro/XHIGIntro.html>. Pas de convention GNOME, GNOME 2 HIG ou d'un autre bureau. Valeurs chiffrées : `tokens.md`.

Provenance de chaque règle ajoutée : **[Apple]** principe Apple historique sourcé, **[Filigrane]** décision du projet, **[À valider]** proposition à prototyper. Ne jamais présenter une règle Filigrane comme une règle d'Apple.

## 1. Mission

Une interface lisible, efficace et cohérente, qui s'efface derrière le travail sans devenir obscure. Reprendre les principes du Mac OS X classique (hiérarchie claire, contrôles compacts, alignements rigoureux, densité maîtrisée, contenu d'abord), pas le visuel d'Aqua.

Priorités : lisibilité durable, efficacité des tâches courantes, cohérence, bon usage de l'écran, clavier et souris complets, accessibilité, discrétion, faisabilité légère (l'OS se fait oublier : pas de processus en plus pour un effet).

Non-objectifs : tactile ou mobile, gros boutons par principe, cartes, ombres et animations décoratives, imitation d'Aqua/Windows/GNOME, mode du moment, compacité au détriment de la lisibilité.

## 2. Décisions déjà prises

Les questions de la section 23 de la source ont leur réponse :

| Sujet | Décision |
|---|---|
| Toolkit du shell | Quickshell (QML, Qt Quick en rendu logiciel) : fili-bar, fili-tooltip, fili-panel, fili-launcher, notifications, fili-about |
| Outils maison | binaires natifs (Rust, `apps/`) ; une interface graphique éventuelle passe par le fili-shell |
| Applications tierces | gardent leur interface ; Filigrane fournit le thème (GTK3/4, foot, nvim, niri) |
| Fenêtres | niri, colonnes défilantes en mosaïque, pas de barres de titre ni de boutons de fenêtre |
| Police | Jost (interface), JetBrains Mono (code, terminaux) ; échelle d'Apple (`tokens.md`) |
| Échelle | échelle de sortie de niri (HiDPI, fractionnaire) ; le shell travaille en pixels logiques |
| Thèmes | sombre par défaut, clair optionnel (`fili-theme`), même sémantique |
| Palette | `FiliTheme.qml`, tokens sémantiques dans `tokens.md` |
| Icônes | « Fili Icons » (Lucide, trait fin, jamais pleines) ; Nerd Fonts dans le terminal |
| Raccourcis | `Mod+…` pour niri (bépo main droite, flèches aussi), liste `Mod+K` ; Esc / Entrée / Tab / flèches dans le shell |
| Langue | anglais dans le code, `FiliI18n.tr()`, catalogue `i18n/<lang>.json` |

Reste **[À valider]** : l'échelle des rayons, la taille minimale des cibles, la prise en charge des technologies d'assistance (le shell n'expose pas encore d'accessibilité AT-SPI), une préférence de réduction des animations.

## 3. Principes

**Le contenu avant le système.** Le shell est prévisible, utile et discret. Bordures, séparateurs, fonds et effets expliquent la structure, ils ne décorent pas. Rien de persistant qui prend de la place sans servir (les indicateurs de la fili-bar, comme les alertes ou le minuteur, n'apparaissent que s'ils ont quelque chose à dire).

**Densité utile, jamais aveugle.** Pas de grande marge décorative, contrôles groupés par fonction, libellé près de son contrôle, cible cliquable utilisable même si le contrôle est compact, texte qui suit l'échelle de niri.

**Une fonction, un comportement.** Même apparence, mêmes états, mêmes touches partout. Action principale, secondaire et destructive toujours distinguées de la même façon. Une exception se justifie par la fonction, jamais par le goût local.

**Prévisibilité avant originalité.** Contrôles reconnaissables ; aucune interaction ne dépend d'un effet subtil ; les animations ne retardent rien ; on sait où l'on est, ce qui est choisi et ce que fera l'action.

**Clavier et souris.** Toute fonction essentielle au clavier, ordre de tabulation logique, focus visible, raccourcis affichés quand ils existent. Pas de geste complexe, pas d'hypothèse tactile.

## 4. Fenêtres, panneaux et dialogues

- niri place les fenêtres : pas de déplacement libre, de minimisation ni de boutons de fenêtre ; la fenêtre active se reconnaît au contour de focus de niri (1 px). **[Filigrane]**
- Le shell ne crée que des fenêtres de couche à la taille de leur contenu (moins de mémoire) : fili-panel sous son module, fili-tooltip au survol, fili-about centré, notifications en haut à droite. Seule exception : le fili-launcher, plein écran pour son fond flou, sa boîte centrée. **[Filigrane]**
- Fermeture : Esc, un clic hors du panneau (perte de focus) ou sur la barre. Un panneau ne vole pas le focus d'une application sans action de l'utilisateur. **[Filigrane]**
- Dialogue : pour une décision ou une saisie liée au contexte, proportionné à son contenu, jamais empilé sur un autre. **[Apple]**
- Boutons d'une alerte : l'action en bas à droite, bouton par défaut (Entrée) ; Annuler à sa gauche (Esc). Si l'action peut perdre des données, Annuler peut être le défaut mais ne prend pas la place du bouton d'action ; un bouton destructif secondaire (« Ne pas enregistrer ») va à gauche, séparé des autres. **[Apple]**
- Marges : 20 px sur les côtés et en bas d'une fenêtre, 24 px sur les côtés d'une alerte. **[Apple]**
- Pas de confirmation pour une action réversible ; pour une action destructive ou irréversible, dire ce qui sera touché et offrir une issue sûre. **[Apple]**

## 5. Composants du shell

- **fili-bar** : chaque module est « icône ou étiquette en ardoise → valeur en brume » (son 85 %, clavier fr, écran 65 %, Bluetooth 2/SHARE/OFF, notifications 3/MUTE, CPU/RAM). Un état (sable, cendre, voile) colore tout le module ; états en capitales. Règle appliquée par `BarItem`/`BarScript` (`FiliTheme.glyph/value/iconColor`). Molette cumulée (120 = un cran), pas de 3 % pour le volume et la luminosité. **[Filigrane]**
- **Fiche** (fili-tooltip, `PanelInfo`) : `{ title, rows: [[label, value]...] | text, hint }`, titre à gauche, contenu à droite (libellé gris, valeur blanche, jauge optionnelle), puis un filet et l'indication de clic. Jamais une chaîne nue d'une ligne pour un nouveau module. **[Filigrane]**
- **fili-panel** : sections à intertitre en capitales (`PanelSection`, filet entre sections), lignes cliquables `PanelButton` (glyphe, libellé, détail à droite), `PanelSwitch`, `PanelSlider`, `PanelChips`. Clavier : ↑/↓ ou Tab entre éléments, Entrée/Espace agit, Maj+Entrée = clic droit, ←/→ panneau suivant (Maj+←/→ sur un curseur, un choix ou un champ). **[Filigrane]**
- **fili-launcher** : une liste floue unique, Maj+Retour arrière remonte d'un niveau, Esc quitte ; seul composant avec flou d'arrière-plan. **[Filigrane]**

## 6. Boutons et actions

- Libellé clair, verbe précis (« Enregistrer », « Connecter », « Oublier »), pas « OK » quand un verbe existe. **[Apple]**
- Une seule action mise en avant par vue. Une action destructive se reconnaît sans la couleur (mot explicite, place à part).
- Bouton icône seul : icône connue, infobulle, nom accessible.
- Désactivé : perceptible et compréhensible, jamais illisible.
- États à prévoir selon le contrôle : normal, survol, focus clavier, pressé, sélectionné, désactivé, chargement, erreur (`tokens.md`). Le survol n'est jamais nécessaire : tout ce qu'il montre est aussi au clic ou au clavier.

## 7. Menus et raccourcis

- Commandes groupées par fonction, séparateurs entre groupes réellement distincts, libellés courts, indisponible = désactivé. **[Apple]**
- Raccourcis affichés quand ils existent ; jamais deux actions pour un même raccourci dans un contexte. **[Apple]**
- Menu contextuel (clic droit) : les commandes de l'élément ; aucune commande importante seulement là. **[Apple]**
- Raccourcis Filigrane documentés dans `FiliHotkeys.qml` (Mod+K) et le skill `filigrane` (`references/niri.md`).

## 8. Champs, formulaires, réglages

- Chaque champ a un libellé ; le texte indicatif est un exemple, jamais le seul libellé. **[Apple]**
- Libellés empilés alignés, deux-points alignés à droite ; cases et boutons radio alignés à gauche ; contrôles de même nature de même largeur ; un contrôle dépendant est indenté sous celui dont il dépend. **[Apple]**
- Aide et erreur près du champ, avec la correction ; la saisie est conservée en cas d'erreur.
- Réglages groupés par sujet sous un intertitre ; interrupteur seulement pour un effet immédiat ; cases, radios, puces ou liste selon la nature du choix, pas selon l'esthétique.

## 9. Listes et tableaux

- Liste ou tableau dès qu'il faut comparer ou parcourir ; jamais des cartes pour des données tabulaires. **[Apple]**
- Colonnes et valeurs alignées (chiffres à droite), en-têtes précis, sélection distincte du survol, parcours au clavier.
- Liste longue : recherche, tri ou filtre ; état vide qui dit ce qui manque et comment commencer.

## 10. Typographie

- Échelle d'Apple transposée à Jost (`tokens.md`) : 13 Regular pour le texte et les contrôles, 12 pour les listes, 11 pour le secondaire, 10 pour les étiquettes ; gras seulement pour l'accent rare. **[Apple]**
- Hiérarchie par la taille, le poids et l'espacement ; une seule police d'interface. Light réservé aux grands titres (≥ 18 px). **[Filigrane]**
- Pas de taille minuscule pour faire tenir plus. Textes longs à largeur confortable. Dates, nombres, unités selon la langue (`FiliI18n`). Tester accents, textes longs (allemand), troncature avec infobulle. **[Apple]**

## 11. Couleurs, bordures, profondeur

- Palette limitée, un seul accent (`voile`), états désaturés ; jamais la couleur comme seul indicateur. **[Filigrane]**
- Bordures et séparateurs pour la structure, pas de quadrillage. Pas d'ombre dans le shell ; la profondeur vient de la teinte. Pas de dégradé, de verre ni de transparence qui réduit le contraste ; seul flou : derrière le fili-launcher. **[Filigrane]**
- Clair et sombre partagent les mêmes tokens. Un composant prend un token, jamais une couleur littérale.

## 12. Icônes

- Un seul style : Fili Icons (Lucide, trait fin), jamais pleines, jamais d'emoji dans un groupe d'icônes d'action. Nouvelle icône : une ligne dans `MAP` de `scripts/fili-icons.py`. **[Filigrane]**
- Une icône garde son sens partout ; ambiguë, elle reçoit un libellé ou une infobulle ; elle ne remplace pas un texte indispensable. Testée à sa taille réelle (barre, menu, notification).

## 13. États, erreurs, retours

- Après une action : réussie, en cours, échouée, et quoi faire ensuite ; retour local, près de l'action. **[Apple]**
- Chaque vue importante définit : chargement, contenu, vide, erreur, accès refusé, hors ligne si utile, opération en cours, réussie, annulée.
- Erreur explicite, tournée vers la solution, sans code brut seul ; travail de l'utilisateur conservé ; nouvelle tentative proposée si elle a un sens. Erreur bloquante (cendre) distincte d'un avertissement (sable). Jamais « réussi » avant la confirmation.

## 14. Notifications

- Notification globale seulement pour ce qui demande l'attention hors du contexte courant ; le résultat d'une action locale reste local. **[Apple]**
- Texte : ce qui s'est passé, puis l'action possible. Pas de répétition, pas de vol de focus, contenu et actions accessibles au clavier (centre de notifications). Message critique distinct sans la seule couleur.
- Son : papier et écriture, sourd et bas, jamais une cloche (`brand.md`). **[Filigrane]**

## 15. Mouvement

- Une animation explique un changement d'état ou garde le contexte spatial ; rapide, discrète, interruptible ; jamais de rebond ni de décor, jamais pour cacher une latence. Tout reste compréhensible sans elle. **[Apple]**
- niri : aucun effet en dehors du flou derrière le menu. Rien ne clignote, sauf `ASK` de fili-ai (attente d'une réponse). **[Filigrane]**

## 16. Accessibilité et écrans

- Contraste suffisant (`brand.md` : brume/nuit 12,8:1, ardoise réservée aux étiquettes et icônes), focus visible, navigation logique, noms accessibles, libellés associés, états non portés par la seule couleur, texte qui suit l'échelle. **[Apple]**
- La compacité ne rend jamais un contrôle introuvable ou inutilisable ; cible minimale **[À valider]** (proposition : 24 px de haut, la hauteur des cellules de la fili-bar).
- Plusieurs résolutions, échelles et écrans (une fili-bar par écran) ; panneaux et fiches entièrement visibles, jamais coupés par le bord.

## 17. Identité

Sobre, précise, durable ; la personnalité vient de l'exécution, de la typographie, des proportions et de la cohérence, pas des effets. Aucune ressource ni marque d'Apple, aucun composant propriétaire copié. Logo et marque : `brand.md`, sans gêner la lecture du bureau.

## 18. Interdits par défaut

Sauf demande explicite ou nécessité démontrée : grandes cartes par groupe, rayons très arrondis partout, gros boutons, marges uniformément agrandies, cartes à la place d'un tableau, commandes essentielles dans des menus imbriqués, icônes ambiguës seules, plusieurs couleurs d'accent, animations décoratives, motifs GNOME.

## 19. Checklist de revue

**Fonction et structure** : la fonction de la vue se comprend tout de suite ; le contenu important domine ; contrôles groupés par fonction ; aucun décor qui prend de la place ; même structure que les autres vues (fiche titre à gauche / contenu à droite, intertitres de panneau).

**Densité et alignement** : espacements de `tokens.md` et réguliers ; libellés près des contrôles ; tailles justifiées ; aucun contrôle minuscule.

**Interaction** : libellés clairs ; états définis (survol, focus, pressé, sélectionné, désactivé) ; tout au clavier, focus visible (`FocusRing`), ordre logique, Esc ferme ; action destructive reconnaissable et protégée en proportion ; résultats et erreurs dits clairement.

**Visuel** : échelle typographique d'Apple ; couleurs par token, clair et sombre vérifiés ; Fili Icons seulement ; bordures et rayons au service de la hiérarchie ; rien d'Aqua copié.

**Accessibilité et écrans** : contraste ; noms des boutons icônes ; échelle de niri supérieure testée ; écran étroit et multi-écran ; aucune animation indispensable.

**Provenance et vérification** : aucune règle GNOME ; Apple distingué de Filigrane ; nouvelle valeur testée ou marquée « à valider » ; `tests/fili-shell/run.sh` passe ; rendu vérifié par la capture de niri.

## 20. Critère de réussite

On comprend vite l'organisation, on repère les actions, on travaille au clavier comme à la souris, on voit une quantité utile d'informations et on retrouve les mêmes comportements partout. Filigrane s'efface derrière le travail, sans jamais rendre l'interface invisible, obscure ou difficile à utiliser.
