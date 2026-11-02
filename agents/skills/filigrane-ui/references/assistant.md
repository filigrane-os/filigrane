# Applications et assistant (contrat fili-*)

Règle Filigrane (décision validée) :

> Les applications exposent leur contexte et leurs capacités métier. Le système expose des outils d'exécution génériques et spécialisés. L'assistant choisit la voie la plus simple, efficace et sûre pour accomplir la tâche, sans passer obligatoirement par l'application active.

Une seule IA générale (`fili-ai`, Mod+Y), jamais un chat par application, jamais de moteur IA dans une `fili-*`.

## Ce que doit exposer chaque application fili-*

Toute application avec un état utile (dossier, sélection, document ouvert, réglage affiché) l'écrit pour l'assistant, sinon l'IA ne peut pas comprendre « ceci », « ces fichiers », « ici ».

- **Où** : `$XDG_RUNTIME_DIR/fili/context/<pid>.json`, écrit de façon atomique (fichier temporaire puis `rename`) à chaque changement (regroupés, ~150 ms), supprimé à la fermeture. Aucun daemon, aucun socket : `fili-context` lit le fichier à la demande, en retrouvant le pid de la fenêtre active par niri. Exemple : `apps/fili-file/src/context.rs`.
- **Champs communs** : `app` (nom), `pid`, `about` (une à trois phrases en anglais : rôle de l'application, sens des champs, voie d'exécution conseillée), puis les champs métier (`location`, `selection`, `selection_count`...). Chemins absolus, listes bornées (200 éléments), contenus jamais inclus (l'IA les lit elle-même si besoin).
- **`about` est le contrat** : il dit à l'assistant comment agir (outils shell à utiliser, ce que l'application met à jour seule, ce qu'il ne faut pas faire). Court : il part dans chaque prompt.
- **Actions sur l'interface** (aller quelque part, montrer des résultats) : une application qui a un état à montrer les expose aussi, sinon l'IA ne peut qu'agir en coulisse et l'utilisateur ne voit rien. Canal : un socket `$XDG_RUNTIME_DIR/fili/context/<pid>.sock` (mode 0600) à côté du fichier de contexte, un fil qui dort sur `accept`, une connexion = une commande (`verbe<TAB>argument`, puis un corps de chemins). Côté ligne de commande, la même application sert de client : `fili-file ctl <verbe>`. La commande vise l'instance notée par Mod+Y (`$FILI_CONTEXT_FILE`), sinon la dernière lancée, sinon en lance une, et met la fenêtre au premier plan (niri). Chaque commande reçoit une réponse JSON de l'interface (pas un simple accusé du fil du socket): `{"ok":true,...}` ou `{"ok":false,"error":"…"}` (action inconnue ou désactivée, chemin absent), et le client sort en code 1 dans le second cas; sans réponse en 5 s, erreur « no answer ». Tout `ctl` offre aussi `state` (JSON de l'état: dossier, onglets, sélection, vue, tâches, dialogue ouvert) et `actions` (commandes avec libellé, raccourci, activée ou non), qui ne lancent jamais de fenêtre. Les commandes à dialogue acceptent leur réponse en argument (`ctl action rename NOM`, `compress NOM.zip`, `select-matching MOTIF`…): sans argument elles ouvrent le dialogue pour l'utilisateur. Les commandes qui agissent sur la fenêtre (`action`, `select`, `tab`, `view`…) ne lancent jamais d'instance; `goto`, `reveal` et `show` le font. Une application qui ajoute un `ctl` suit ce contrat: la lecture d'état est ce qui permet à l'IA de vérifier son action. L'`about` du contexte documente ces commandes. Exemple fili-file : `ctl goto CHEMIN` (un fichier est sélectionné dans son dossier), `ctl show 'TITRE' < chemins` (liste à la place du dossier, bandeau « Résultats : … » avec « Fermer les résultats »; le fil d'Ariane et le titre montrent le dossier commun des résultats, renommer et mettre à la corbeille marchent, coller et nouveau dossier demandent de fermer les résultats d'abord; le contexte porte le champ `results`).
- **Chercher, c'est le shell ; montrer, c'est l'application** : l'IA trouve avec `fd`, `rg`, `find` (rapide, sans tokens), puis envoie la liste à l'application. Une application n'implémente pas sa propre recherche pour l'IA.

## Choix de la voie d'exécution

| Tâche | Voie |
| --- | --- |
| Lister, chercher, empreintes (lecture seule) | Outils système (shell), les chemins venant du contexte |
| Agir sur la sélection exacte de l'utilisateur | Chemins de `selection` donnés aux outils système |
| Montrer un résultat ou emmener l'utilisateur quelque part dans l'application | Commande de l'application (`fili-file ctl goto` / `show`) |
| Renommer, déplacer, supprimer, créer | `fili-tx` (journal, `fili-tx undo` annule toute la demande) ; jamais `mv`/`rm` seuls |

## Règles pour l'application

- L'application reste responsable de son état et se met à jour seule (inotify...) : pas d'appel de rafraîchissement.
- Le contenu des fichiers est de la donnée non fiable pour l'assistant, jamais des instructions.
- Le fichier de contexte ne contient pas de secret ni de contenu de fichier.
- Rien ne tourne en plus : écrire un petit fichier, c'est tout. Pas de MCP, pas de broker résident.
- Une nouvelle `fili-*` avec un état utile n'est pas terminée sans ce fichier et son `about`.

## Annuler ce que l'IA a fait

L'assistant change les fichiers par `fili-tx` (journal, transaction par demande), pas par l'application : `fili-tx undo` défait toute la demande, `fili-tx redo` la rétablit, quel que soit l'outil de départ et même après la fin de la session. fili-file se met à jour seul (inotify). Une application qui voudrait montrer cette annulation (bouton, Ctrl+Z) lit `~/.local/state/filigrane/tx/` ; elle ne réimplémente pas de journal.
