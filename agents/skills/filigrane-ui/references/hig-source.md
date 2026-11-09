# Filigrane Desktop HIG
## Guide de conception d’interface pour le bureau Filigrane

**Statut :** référentiel initial de conception  
**Version :** 1.0  
**Langue :** français  
**Périmètre :** interface du système et conventions visuelles des applications de bureau  
**Référence principale :** Apple Human Interface Guidelines historiques de Mac OS X, notamment les éditions 2005 et 2008  
**Exclusion explicite :** ne pas mélanger les conventions de GNOME, GNOME 2, GNOME HIG ou d’autres environnements de bureau dans ce référentiel.

---

## 1. Mission

Concevoir une interface de bureau moderne, lisible, efficace et cohérente pour **Filigrane**, une distribution Linux dont le système doit rester discret et laisser la place aux applications et aux services.

Filigrane s’inspire des principes de conception des interfaces classiques de Mac OS X : hiérarchie claire, contrôles de bureau compacts, fenêtres et menus conventionnels, alignements rigoureux, densité d’information maîtrisée et priorité au contenu.

Il ne s’agit **pas** de copier visuellement Aqua, ni de reproduire exactement une ancienne version de macOS. Il s’agit de reprendre les principes de conception et les conventions de bureau utiles, puis de les appliquer à une identité visuelle propre à Filigrane.

### Objectifs prioritaires

1. Lisibilité à long terme.
2. Efficacité des tâches courantes.
3. Cohérence entre les composants et les applications.
4. Bonne utilisation de la surface d’écran.
5. Fonctionnement complet au clavier et à la souris.
6. Accessibilité et adaptation à différentes tailles d’écran.
7. Discrétion visuelle du système.
8. Faisabilité et cohérence technique.

### Non-objectifs

- Concevoir une interface tactile ou mobile.
- Agrandir tous les boutons au nom d’une règle universelle.
- Multiplier les cartes, les surfaces décoratives, les ombres ou les animations.
- Imiter pixel par pixel Aqua, Windows, GNOME ou un autre bureau.
- Introduire des choix de design simplement parce qu’ils sont à la mode.
- Sacrifier l’accessibilité ou la lisibilité pour obtenir une interface compacte.

---

## 2. Références et limites documentaires

### Références historiques principales

- **Apple Human Interface Guidelines, Mac OS X Leopard, 2008**  
  Archive historique : <https://leopard-adc.pepas.com/documentation/UserExperience/Conceptual/AppleHIGuidelines/XHIGIntro/XHIGIntro.html>

- **Apple Human Interface Guidelines, édition 2005**  
  Copie d’archive PDF : <https://blog-geofcrowl-static-images.s3.us-east-1.amazonaws.com/2020-02-17-collection-higs/APPLE-Guidelines-2005.pdf>

Ces documents constituent les références d’inspiration. Ils ne sont pas des spécifications techniques actuelles pour Linux. Les valeurs chiffrées et les règles de ce document qui ne sont pas explicitement attribuées à Apple sont des propositions propres à Filigrane.

### Règle de provenance

Lorsqu’une règle est ajoutée au référentiel, la classer dans l’une des catégories suivantes :

- **Principe Apple historique** : principe documenté dans une référence historique Apple.
- **Règle Filigrane** : décision de conception propre au projet.
- **Décision à valider** : proposition nécessitant un prototype, des tests ou une décision explicite.

Ne jamais présenter une valeur ou une convention proposée par Filigrane comme une règle officielle d’Apple sans source vérifiable.

---

## 3. Principes fondamentaux

### 3.1 Le contenu avant le système

- L’application et son contenu constituent le centre de l’attention.
- Les éléments système doivent être prévisibles, utiles et visuellement discrets.
- Les bordures, séparateurs, arrière-plans et effets visuels servent à expliquer la structure, pas à la décorer.
- Éviter les éléments persistants qui consomment de l’espace sans apporter de valeur fonctionnelle.

### 3.2 Densité utile, jamais densité aveugle

- Exploiter efficacement la surface d’écran.
- Ne pas ajouter de marges décoratives importantes par défaut.
- Grouper les contrôles selon leur fonction.
- Éviter les longues distances entre un libellé et le contrôle correspondant.
- Préserver une zone interactive utilisable, même lorsque le contrôle visuel est compact.
- Permettre à l’utilisateur d’augmenter la taille du texte et, lorsque c’est pertinent, l’échelle de l’interface.

### 3.3 Une même fonction, un même comportement

- Un même type de contrôle doit avoir une apparence, un comportement et des états cohérents partout.
- Une action principale, une action secondaire et une action destructive doivent être distinguables de manière constante.
- Les raccourcis clavier doivent suivre une convention stable.
- Les menus, dialogues, notifications et fenêtres doivent partager les mêmes règles de structure.
- Une exception doit être justifiée par le contexte fonctionnel, pas par une préférence esthétique locale.

### 3.4 Prévisibilité avant originalité

- Les contrôles doivent être reconnaissables et agir comme prévu.
- Les interactions ne doivent pas dépendre d’un effet visuel subtil.
- Les animations ne doivent pas retarder les tâches.
- Les actions destructrices, irréversibles ou coûteuses doivent être clairement identifiées.
- L’utilisateur doit pouvoir comprendre où il se trouve, ce qui est sélectionné et quel sera l’effet d’une action.

### 3.5 Clavier et souris en priorité

- Toutes les fonctions essentielles doivent être accessibles au clavier.
- La navigation par Tab et Maj+Tab doit suivre un ordre logique.
- Les menus et commandes importantes doivent exposer leurs raccourcis lorsqu’ils en possèdent.
- Le focus clavier doit être visible.
- Les actions principales doivent rester accessibles à la souris sans exiger de gestes complexes.
- Ne pas supposer que l’écran est tactile.

---

## 4. Modèle mental de l’interface

Séparer les décisions de conception en trois niveaux.

### 4.1 Environnement système

Concerne notamment :

- gestion des fenêtres ;
- panneau, barre de tâches ou lanceur ;
- menu système ;
- notifications ;
- sélecteur d’applications ;
- paramètres système ;
- dialogues système ;
- états de connexion, de volume, d’alimentation et de session.

### 4.2 Applications

Concerne notamment :

- barre de menus et commandes ;
- barres d’outils ;
- vues en liste, en tableau et en arborescence ;
- formulaires ;
- onglets ;
- boîtes de dialogue ;
- sélection de fichiers ;
- recherche ;
- états vides, erreurs et confirmations.

Les applications peuvent avoir leurs propres besoins, mais doivent respecter le vocabulaire visuel et les conventions d’interaction communes de Filigrane.

### 4.3 Système visuel

Concerne :

- typographie ;
- couleurs ;
- icônes ;
- espacements ;
- dimensions des contrôles ;
- bordures ;
- rayons ;
- ombres ;
- animations ;
- états interactifs ;
- contrastes et règles d’accessibilité.

---

## 5. Grille d’espacement et dimensions de départ

Les valeurs suivantes sont des **tokens initiaux Filigrane**, et non des mesures officielles d’Apple. Les valider avec des prototypes sur plusieurs résolutions et facteurs de mise à l’échelle.

### 5.1 Échelle d’espacement

| Token | Valeur initiale | Usage typique |
|---|---:|---|
| `space-1` | 4 px | séparation minimale entre éléments étroitement liés |
| `space-2` | 8 px | espacement interne courant |
| `space-3` | 12 px | séparation entre groupes proches |
| `space-4` | 16 px | séparation entre groupes distincts |
| `space-6` | 24 px | séparation de sections |
| `space-8` | 32 px | séparation majeure, à utiliser avec parcimonie |

Utiliser une grille de 4 px comme base, sans forcer chaque dimension à être un multiple de 4 si la lisibilité, la typographie ou le rendu natif exige autre chose.

### 5.2 Tailles de texte initiales

| Rôle | Valeur initiale | Règle |
|---|---:|---|
| Texte principal | 13–14 px | valeur de départ pour une densité de bureau |
| Texte secondaire | 12–13 px | uniquement si le contraste et la lisibilité restent suffisants |
| Libellé de contrôle | 13–14 px | cohérent avec le texte principal |
| Titre de fenêtre ou de section | selon hiérarchie | ne pas surdimensionner pour créer artificiellement de l’importance |
| Texte d’aide | 12–13 px | information secondaire, jamais indispensable si elle devient difficile à lire |

Ces tailles correspondent à des valeurs de conception initiales. Le rendu réel dépend de la police, du moteur de rendu, du facteur d’échelle et de la définition employée. Ne pas figer des tailles en pixels sans tester la mise à l’échelle.

### 5.3 Dimensions des contrôles

- Privilégier des contrôles compacts et alignés.
- Ne pas imposer une hauteur unique à tous les contrôles.
- Les champs de saisie doivent avoir une hauteur adaptée à la police, au texte et à leur usage.
- Les boutons doivent être dimensionnés selon leur libellé et leur importance.
- Les zones cliquables doivent rester suffisamment grandes pour être utilisées précisément. La compacité visuelle ne justifie pas une cible interactive minuscule.
- Les listes et tableaux peuvent être denses, avec une hauteur de ligne ajustée à la taille du texte et au besoin de sélection.
- Prévoir une option d’échelle supérieure pour les utilisateurs qui en ont besoin.

Ne pas définir les dimensions finales avant d’avoir choisi le toolkit, la police système et la stratégie de mise à l’échelle.

---

## 6. Fenêtres et dialogues

### Fenêtres

- Les fenêtres doivent être identifiables, déplaçables et redimensionnables lorsque leur fonction le justifie.
- La hiérarchie entre fenêtre active et fenêtres inactives doit être claire sans effets excessifs.
- Les contrôles de fenêtre doivent avoir un emplacement et un comportement cohérents.
- Les titres doivent être courts et informatifs.
- Éviter les grandes zones vides dans les barres de titre.
- Préserver les conventions de déplacement, de redimensionnement, de minimisation et de fermeture définies par l’environnement.
- Les fenêtres doivent se comporter correctement à différentes résolutions et avec plusieurs écrans.

### Dialogues

- Utiliser un dialogue pour une tâche ciblée, une décision ou une saisie liée au contexte.
- Garder le dialogue proportionné à son contenu.
- Regrouper les champs par relation fonctionnelle.
- Placer les libellés près des champs correspondants.
- Distinguer clairement les actions principales, secondaires et destructrices.
- Éviter les confirmations superflues pour les actions réversibles.
- Pour une action destructive ou irréversible, expliquer ce qui sera affecté et proposer une issue sûre.
- Définir explicitement le comportement d’Echap, Entrée et du focus.
- Éviter les dialogues empilés ou les parcours qui ouvrent de nombreux niveaux de fenêtres.

### État et retour utilisateur

Après une action, l’interface doit indiquer de façon appropriée :

- si l’action a réussi ;
- si elle est en cours ;
- si elle a échoué ;
- ce que l’utilisateur peut faire ensuite.

Préférer un retour local, concis et directement associé à l’action. Réserver les notifications globales aux événements qui nécessitent réellement l’attention de l’utilisateur.

---

## 7. Boutons et actions

- Les boutons doivent avoir un libellé clair lorsque l’icône seule ne suffit pas.
- Employer des verbes précis : « Enregistrer », « Fermer », « Importer », plutôt que des libellés vagues.
- Maintenir un ordre cohérent entre actions principales et secondaires.
- Une action destructive doit être reconnaissable sans dépendre uniquement de la couleur.
- Éviter de présenter plusieurs boutons avec la même emphase si une seule action est prioritaire.
- Ne pas transformer chaque élément de l’interface en bouton arrondi ou en grande tuile.
- Les boutons iconiques doivent utiliser une icône connue, une infobulle utile et un nom accessible.
- L’état désactivé doit être perceptible et compréhensible, sans rendre le contrôle illisible.

### États à définir

Chaque contrôle interactif doit prévoir, lorsque cela s’applique :

- normal ;
- survol ;
- focus clavier ;
- pressé ;
- sélectionné ;
- désactivé ;
- chargement ;
- erreur.

Ne pas dépendre exclusivement du survol : il n’existe pas sur tous les dispositifs de pointage.

---

## 8. Menus, barres d’outils et raccourcis

### Menus

- Les commandes doivent être regroupées par fonction.
- Les séparateurs ne doivent être utilisés qu’entre des groupes réellement distincts.
- Les libellés doivent être concis et cohérents.
- Les commandes indisponibles doivent avoir un état désactivé compréhensible.
- Les raccourcis clavier doivent être affichés lorsqu’ils sont définis et utiles.
- Les menus contextuels doivent proposer les commandes pertinentes pour l’élément ou la sélection courante.
- Ne pas placer une commande importante uniquement dans un menu contextuel.

### Barres d’outils

- Présenter les commandes fréquemment utilisées.
- Éviter de dupliquer sans raison toutes les commandes déjà accessibles de manière évidente.
- Garder une taille et un espacement cohérents entre icônes.
- Utiliser des libellés lorsque les icônes risquent d’être ambiguës.
- Les barres d’outils ne doivent pas devenir une collection de gros boutons décoratifs.

### Clavier

- Définir une convention globale pour les commandes courantes.
- Préserver les conventions du système et des applications lorsque c’est possible.
- Éviter d’attribuer le même raccourci à des actions différentes dans un même contexte.
- Documenter les raccourcis spécifiques à Filigrane.
- Vérifier l’ordre de tabulation et l’accès à toutes les fonctions essentielles.

---

## 9. Champs, formulaires et réglages

- Chaque champ doit avoir un libellé explicite, associé de façon programmatique.
- Utiliser un texte indicatif dans un champ uniquement comme exemple, jamais comme unique libellé.
- Aligner les champs d’un même formulaire.
- Garder les messages d’aide près du contrôle concerné.
- Indiquer les champs obligatoires avant ou au moment de la validation.
- Afficher les erreurs près du champ concerné et expliquer comment les corriger.
- Préserver les valeurs saisies en cas d’erreur.
- Grouper les paramètres par sujet et donner des intitulés explicites.
- Éviter les longues pages de réglages sans regroupement ni recherche.
- N’utiliser un interrupteur marche/arrêt que pour une préférence immédiatement applicable ou dont le comportement est clairement documenté.
- Utiliser des choix exclusifs, cases à cocher, listes ou boutons radio selon la nature de la décision, et non selon une préférence esthétique.

---

## 10. Listes, tableaux et navigation de contenu

- Favoriser les vues en liste et en tableau lorsque la comparaison ou la densité d’information est importante.
- Aligner les colonnes et les valeurs de manière cohérente.
- Les en-têtes doivent décrire précisément le contenu.
- La sélection doit être visuellement distincte du survol.
- La navigation clavier doit permettre de parcourir les éléments et de comprendre l’élément actif.
- Ne pas employer des cartes comme présentation par défaut pour des données tabulaires.
- Utiliser une vue en cartes uniquement si les éléments sont réellement indépendants et si cette présentation apporte une valeur fonctionnelle.
- Les colonnes secondaires peuvent être masquées ou ajustées si nécessaire, mais les fonctions essentielles doivent rester accessibles.
- Les états vides doivent expliquer ce qui manque et, si possible, comment commencer.
- Les listes longues doivent proposer une recherche, un tri ou un filtrage lorsque le volume le justifie.

---

## 11. Typographie et lisibilité

- Choisir une police système lisible, disponible et bien rendue sur la plateforme.
- Établir une échelle typographique courte et cohérente.
- Utiliser la taille, le poids et l’espacement pour établir la hiérarchie.
- Éviter d’utiliser plusieurs polices sans raison fonctionnelle.
- Ne pas utiliser une taille minuscule pour faire tenir artificiellement davantage d’informations.
- Les libellés doivent être compréhensibles sans dépendre uniquement du contexte visuel.
- Les textes longs doivent avoir une largeur confortable et un interlignage adapté.
- Les unités, dates, nombres et formats doivent être cohérents avec la langue et les paramètres régionaux.
- Tester les accents, caractères spéciaux, langues longues et textes qui ne tiennent pas dans les dimensions prévues.

---

## 12. Couleurs, bordures et profondeur

Filigrane doit avoir une identité propre, sobre et discrète.

### Principes

- Employer une palette limitée.
- Utiliser les couleurs d’accent pour les actions et états qui le méritent.
- Le contraste doit rester suffisant dans tous les thèmes pris en charge.
- Ne pas utiliser la couleur comme unique indicateur d’erreur, de sélection ou d’état.
- Les bordures et séparateurs doivent clarifier la structure sans quadriller chaque surface.
- Les ombres doivent signaler une relation de profondeur réelle, comme une fenêtre flottante ou un menu, plutôt que décorer chaque panneau.
- Les surfaces doivent être hiérarchisées avec retenue.
- Éviter les dégradés, effets de verre et transparences décoratives lorsqu’ils réduisent le contraste ou compliquent la lecture.
- Le thème clair et le thème sombre doivent partager la même sémantique de couleurs et de composants.

### Tokens à définir avant implémentation

Les valeurs exactes restent à décider et à tester :

- `color-background`
- `color-surface`
- `color-surface-raised`
- `color-text-primary`
- `color-text-secondary`
- `color-border`
- `color-accent`
- `color-selection`
- `color-focus`
- `color-success`
- `color-warning`
- `color-danger`
- `color-disabled`

Chaque token doit avoir une fonction sémantique. Les composants ne doivent pas choisir librement des couleurs arbitraires lorsqu’un token existant convient.

---

## 13. Icônes et imagerie

- Employer un style d’icônes cohérent dans l’ensemble du système.
- Les icônes doivent être reconnaissables à leur taille d’utilisation réelle.
- Ne pas mélanger arbitrairement des icônes pleines, filaires, photoréalistes et emoji dans un même groupe fonctionnel.
- Les icônes d’action doivent avoir une signification stable.
- Une icône ambiguë doit être accompagnée d’un libellé ou d’une infobulle.
- Les icônes ne doivent pas remplacer un texte indispensable à la compréhension.
- Prévoir une taille optique cohérente, sans exiger que toutes les formes aient exactement la même boîte visuelle.
- Tester les icônes aux tailles réelles, notamment dans les menus, panneaux et zones de notification.

---

## 14. Accessibilité

L’accessibilité est une exigence de base, pas une option ajoutée après le design.

- Contraste suffisant pour le texte, les icônes et les états interactifs.
- Focus clavier visible.
- Navigation logique au clavier.
- Noms accessibles pour les contrôles iconiques.
- Libellés associés aux champs.
- États non exprimés uniquement par la couleur.
- Respect des préférences de taille de texte et de mise à l’échelle lorsque la plateforme le permet.
- Pas d’animation indispensable à la compréhension.
- Pas de clignotement ou de mouvement inutile.
- Messages d’erreur compréhensibles et associés aux contrôles concernés.
- Vérifier le fonctionnement avec les technologies d’assistance disponibles sur la plateforme choisie.

La compacité ne doit jamais rendre un contrôle impossible à identifier ou à utiliser. Les tailles minimales des cibles interactives doivent être définies après choix du toolkit et test d’usage.

---

## 15. Mouvement et animation

- Une animation doit expliquer un changement d’état ou aider à conserver le contexte spatial.
- Les animations doivent être rapides, discrètes et interruptibles lorsque c’est pertinent.
- Les transitions ne doivent pas ralentir les tâches répétitives.
- Les retours d’état doivent rester compréhensibles sans animation.
- Éviter les rebonds, les mouvements décoratifs et les transitions longues.
- Respecter une préférence de réduction des animations si elle est disponible.
- Ne pas utiliser l’animation pour masquer une latence ou un comportement imprévisible.

---

## 16. Notifications et messages système

- Réserver les notifications globales aux événements qui nécessitent une attention hors du contexte courant.
- Utiliser un message local pour les résultats d’une action locale.
- Le texte doit expliquer ce qui s’est passé et, lorsque c’est utile, la prochaine action possible.
- Éviter les notifications répétitives ou non essentielles.
- Les messages critiques doivent être clairement différenciés, sans dépendre uniquement de la couleur.
- Une notification ne doit pas voler le focus clavier de façon inattendue.
- Le contenu et les actions d’une notification doivent rester accessibles.

---

## 17. Recherche et découverte

- La recherche doit être facilement repérable dans les interfaces qui en ont besoin.
- Préserver le contexte pendant une recherche ou un filtrage.
- Distinguer recherche globale, recherche dans une vue et filtre local.
- Les résultats doivent être ordonnés de façon prévisible.
- Afficher un état vide utile si aucun résultat n’est trouvé.
- Ne pas ajouter un champ de recherche à chaque petit panneau sans nécessité.
- Les raccourcis d’accès à la recherche doivent être documentés et cohérents.

---

## 18. Adaptation aux écrans

- Concevoir d’abord pour un environnement de bureau, mais ne pas supposer une résolution unique.
- Les fenêtres doivent fonctionner sur des écrans de taille et de densité différentes.
- Éviter les dimensions fixes qui rendent le contenu inaccessible.
- Prévoir des comportements clairs quand une fenêtre devient étroite.
- Préserver les informations et commandes essentielles lors du redimensionnement.
- Tester plusieurs facteurs d’échelle, résolutions et configurations multi-écrans.
- Les menus et dialogues doivent rester entièrement visibles autant que possible.
- Ne pas confondre adaptation aux écrans avec conversion automatique de l’interface en interface tactile.

---

## 19. États et erreurs

Chaque vue importante doit définir ses états pertinents :

- chargement ;
- contenu disponible ;
- contenu vide ;
- erreur ;
- accès refusé ;
- absence de connexion, si applicable ;
- opération en cours ;
- opération réussie ;
- opération annulée.

Règles :

- Les erreurs doivent être explicites et orientées vers la résolution.
- Ne pas afficher un code technique brut à l’utilisateur final sans explication.
- Conserver le travail de l’utilisateur lorsque c’est possible.
- Proposer une récupération ou une nouvelle tentative lorsque cela a du sens.
- Distinguer une erreur bloquante d’un avertissement.
- Ne pas présenter une opération comme réussie avant d’avoir reçu confirmation de son résultat.

---

## 20. Identité visuelle Filigrane

L’identité doit refléter l’idée d’un système qui s’efface derrière les applications et les services.

- Sobre, précise et durable.
- Pas de décoration sans fonction.
- Pas d’imitation directe de la marque ou des ressources graphiques Apple.
- Pas de copie des composants propriétaires d’un autre environnement.
- Palette et iconographie propres à Filigrane.
- La personnalité de Filigrane doit venir de la qualité d’exécution, de la typographie, des proportions et de la cohérence, plutôt que d’effets visuels omniprésents.

Le logo et les éléments de marque peuvent être distinctifs, mais ne doivent pas perturber la lisibilité du bureau.

---

## 21. Règles de décision pour une IA

Lorsqu’une IA conçoit, code, révise ou évalue une interface Filigrane, appliquer les règles suivantes dans cet ordre.

1. **Respecter la demande fonctionnelle explicite.**
2. **Respecter ce référentiel.**
3. **Réutiliser les composants et tokens existants avant d’en créer de nouveaux.**
4. **Privilégier les conventions classiques du bureau et les références Apple historiques.**
5. **Ne pas introduire de conventions GNOME ou GNOME HIG.**
6. **Ne pas adopter un modèle tactile/mobile par défaut.**
7. **Ne pas agrandir les espacements ou les contrôles sans justification fonctionnelle ou d’accessibilité.**
8. **Préserver la densité utile sans réduire la lisibilité.**
9. **Garantir les usages clavier et souris.**
10. **Maintenir des états interactifs et des retours utilisateur explicites.**
11. **En cas de conflit entre compacité et accessibilité, rechercher une solution qui préserve les deux ; ne pas supprimer silencieusement une exigence.**
12. **Si une décision importante n’est pas définie, signaler l’incertitude et proposer une décision explicite au lieu d’inventer une règle officielle.**

### Interdictions par défaut

Sauf demande explicite ou nécessité démontrée, ne pas :

- créer de grandes cartes pour chaque groupe d’informations ;
- appliquer des rayons très arrondis à tous les composants ;
- utiliser de très grands boutons pour les commandes de bureau ;
- augmenter les marges de manière uniforme ;
- remplacer des tableaux par des cartes sans bénéfice fonctionnel ;
- cacher les commandes essentielles derrière des menus imbriqués ;
- utiliser uniquement des icônes ambiguës ;
- multiplier les couleurs d’accent ;
- ajouter des animations décoratives ;
- introduire des motifs de conception provenant de GNOME ou GNOME HIG.

---

## 22. Checklist de revue d’interface

Avant de valider une interface, vérifier chaque point applicable.

### Fonction et structure

- [ ] La fonction principale de la vue est immédiatement compréhensible.
- [ ] Le contenu important est visuellement prioritaire.
- [ ] Les contrôles sont regroupés selon leur fonction.
- [ ] Les éléments décoratifs n’occupent pas inutilement de place.
- [ ] La structure est cohérente avec les autres vues Filigrane.

### Densité et alignement

- [ ] Les espacements sont cohérents.
- [ ] Les libellés sont proches des contrôles associés.
- [ ] Les tailles des contrôles sont justifiées par leur fonction.
- [ ] La densité reste confortable à la taille d’affichage cible.
- [ ] Aucun contrôle n’est minuscule au point d’être difficile à utiliser.

### Interaction

- [ ] Les actions ont des libellés clairs.
- [ ] Les états survol, focus, pressé, sélectionné et désactivé sont définis selon le besoin.
- [ ] Le clavier permet d’utiliser toutes les fonctions essentielles.
- [ ] Le focus est visible et l’ordre de tabulation est logique.
- [ ] Les actions destructrices sont reconnaissables et protégées de façon proportionnée.
- [ ] Les résultats et erreurs sont communiqués clairement.

### Visuel

- [ ] La typographie suit l’échelle commune.
- [ ] Les couleurs proviennent des tokens sémantiques.
- [ ] Les icônes suivent un style cohérent.
- [ ] Les bordures, ombres et rayons servent la hiérarchie.
- [ ] L’interface n’imite pas directement Aqua et conserve l’identité Filigrane.

### Accessibilité et adaptation

- [ ] Le contraste est suffisant.
- [ ] Les contrôles ont des noms accessibles.
- [ ] L’interface fonctionne avec une échelle de texte supérieure.
- [ ] La vue reste utilisable sur différentes tailles d’écran.
- [ ] Les animations ne sont pas indispensables à la compréhension.

### Cohérence de provenance

- [ ] Aucune règle propre à GNOME ou GNOME HIG n’a été ajoutée.
- [ ] Les recommandations Apple historiques sont distinguées des décisions propres à Filigrane.
- [ ] Les nouvelles valeurs de design ont été testées ou sont identifiées comme provisoires.

---

## 23. Décisions à prendre avant de figer le système

Ne pas traiter les valeurs initiales comme définitives avant d’avoir répondu à ces questions :

1. **Toolkit graphique :** lequel sera utilisé pour le shell système et les applications ?
2. **Gestionnaire de fenêtres :** quelles conventions de déplacement, de focus, de redimensionnement et de contrôle des fenêtres seront retenues ?
3. **Police système :** quelle police et quelle stratégie de rendu seront utilisées ?
4. **Échelle :** comment gérer le HiDPI, la mise à l’échelle fractionnaire et la taille du texte ?
5. **Thèmes :** thème clair, sombre, ou les deux ?
6. **Palette :** quels tokens et quelles valeurs de couleur définir ?
7. **Icônes :** quelle famille d’icônes et quelles tailles optiques utiliser ?
8. **Raccourcis :** quelle convention globale appliquer ?
9. **Accessibilité :** quelles technologies d’assistance et quelles préférences système doivent être prises en charge ?
10. **Compatibilité :** quelles applications doivent respecter directement le guide, et lesquelles peuvent conserver leur propre interface ?

Tant que ces décisions ne sont pas prises, l’IA doit éviter de coder en dur des valeurs dépendantes du toolkit ou de la plateforme.

---

## 24. Consigne système courte à fournir à une IA de développement

> Tu conçois des interfaces pour Filigrane, un environnement de bureau Linux moderne, discret, lisible et efficace. Prends comme référence de conception les Apple Human Interface Guidelines historiques de Mac OS X, notamment les éditions 2005 et 2008. Ne mélange pas ces principes avec GNOME, GNOME 2 HIG ou les conventions d’autres environnements de bureau.
>
> Privilégie les conventions classiques du bureau : fenêtres, menus, contrôles compacts, listes et tableaux lorsque cela convient, alignements rigoureux, hiérarchie typographique, raccourcis clavier et interaction souris/clavier. Préserve une densité d’information utile sans sacrifier la lisibilité ni l’accessibilité. N’utilise pas de grandes marges, de gros boutons, de cartes, de rayons arrondis ou d’animations décoratives par défaut.
>
> Réutilise les tokens et composants Filigrane existants. Garde les contrôles cohérents entre les vues. Définis les états interactifs, le focus clavier, les erreurs et les retours d’action. N’invente pas de valeurs présentées comme des règles officielles d’Apple : distingue les références historiques des décisions propres à Filigrane. Si le toolkit, la police ou l’échelle ne sont pas connus, signale les décisions dépendantes de ces choix avant de les figer.

---

## 25. Critère de réussite

Une interface Filigrane est réussie si un utilisateur peut comprendre rapidement son organisation, repérer les actions disponibles, travailler efficacement au clavier et à la souris, afficher une quantité utile d’informations et retrouver les mêmes comportements d’une application à l’autre.

Le système doit être présent quand il est utile et discret le reste du temps.

**Principe directeur : Filigrane s’efface derrière le travail, sans jamais rendre l’interface invisible, obscure ou difficile à utiliser.**
