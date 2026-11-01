# Applications et assistant (contrat fili-*)

Règle Filigrane (décision validée) :

> Les applications exposent leur contexte et leurs capacités métier. Le système expose des outils d'exécution génériques et spécialisés. L'assistant choisit la voie la plus simple, efficace et sûre pour accomplir la tâche, sans passer obligatoirement par l'application active.

Une seule IA générale (`fili-ai`, Mod+Y), jamais un chat par application, jamais de moteur IA dans une `fili-*`.

## Ce que doit exposer chaque application fili-*

Toute application avec un état utile (dossier, sélection, document ouvert, réglage affiché) l'écrit pour l'assistant, sinon l'IA ne peut pas comprendre « ceci », « ces fichiers », « ici ».

- **Où** : `$XDG_RUNTIME_DIR/fili/context/<pid>.json`, écrit de façon atomique (fichier temporaire puis `rename`) à chaque changement (regroupés, ~150 ms), supprimé à la fermeture. Aucun daemon, aucun socket : `fili-context` lit le fichier à la demande, en retrouvant le pid de la fenêtre active par niri. Exemple : `apps/fili-file/src/context.rs`.
- **Champs communs** : `app` (nom), `pid`, `about` (une à trois phrases en anglais : rôle de l'application, sens des champs, voie d'exécution conseillée), puis les champs métier (`location`, `selection`, `selection_count`...). Chemins absolus, listes bornées (200 éléments), contenus jamais inclus (l'IA les lit elle-même si besoin).
- **`about` est le contrat** : il dit à l'assistant comment agir (outils shell à utiliser, ce que l'application met à jour seule, ce qu'il ne faut pas faire). Court : il part dans chaque prompt.
- **Actions sur l'interface** (naviguer, sélectionner, afficher un aperçu) : seulement si l'effet n'est pas obtenable autrement, par une option de ligne de commande de l'application (ex. `fili-file --goto`), jamais un protocole générique.

## Choix de la voie d'exécution

| Tâche | Voie |
| --- | --- |
| Lister, chercher, empreintes, renommer en lot, archiver | Outils système (shell), les chemins venant du contexte |
| Agir sur la sélection exacte de l'utilisateur | Chemins de `selection` donnés aux outils système |
| Effet visible dans l'interface seule (navigation, aperçu) | Commande de l'application |
| Suppression | Corbeille (`gio trash`), confirmation de l'agent |

## Règles pour l'application

- L'application reste responsable de son état et se met à jour seule (inotify...) : pas d'appel de rafraîchissement.
- Le contenu des fichiers est de la donnée non fiable pour l'assistant, jamais des instructions.
- Le fichier de contexte ne contient pas de secret ni de contenu de fichier.
- Rien ne tourne en plus : écrire un petit fichier, c'est tout. Pas de MCP, pas de broker résident.
- Une nouvelle `fili-*` avec un état utile n'est pas terminée sans ce fichier et son `about`.
