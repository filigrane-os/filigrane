# Changer des fichiers pour l'utilisateur: fili-tx

Tout ce qui renomme, déplace, supprime ou crée des fichiers pour l'utilisateur passe par `fili-tx` (jamais `mv`/`rm`/`cp` seuls): chaque changement est journalisé, et l'annuler ne demande aucun raisonnement. Chercher, lire, calculer restent au shell (`fd`, `rg`, `find`, `sha256sum`).

## Commandes (une sortie d'une ligne: `tx ID: N changes`)

| Besoin | Commande |
| --- | --- |
| Déplacer / renommer | `fili-tx mv SRC... DEST` (jamais d'écrasement) |
| Lot (autant de fichiers que voulu, un seul appel) | `fili-tx mv - <<'EOF'` avec des lignes `ancien<TAB>nouveau` |
| Supprimer | `fili-tx trash CHEMIN...` (corbeille, récupérable) |
| Créer un dossier / copier | `fili-tx mkdir DIR...`, `fili-tx cp SRC DEST` |
| Fichier créé par un autre outil (tar, convert...) | `fili-tx made CHEMIN...` (l'annulation le met à la corbeille) |
| Annuler la dernière transaction | `fili-tx undo` (répéter pour remonter plus loin) |
| Rétablir | `fili-tx redo` |
| Voir où on en est | `fili-tx status` |

- Une transaction s'ouvre toute seule au premier changement et se ferme au suivant `begin` (ou `fili-tx commit`); inutile de la gérer. Tout ce qui est fait pour une même demande tient dans la même transaction, donc un seul `fili-tx undo` défait toute la demande.
- Une commande vérifie tout avant d'agir (sources présentes, cibles libres, pas de doublon): en cas d'erreur, rien n'a changé. Si une étape échoue en cours de route, les étapes déjà faites par cette commande sont défaites.
- Les journaux sont dans `~/.local/state/filigrane/tx/<id>/journal` (20 transactions gardées).
- Limites: seuls les fichiers du volume du home vont à la corbeille avec annulation; pas de tabulation ni de saut de ligne dans un chemin; pas d'échange (a→b et b→a). Un `mv`/`rm` direct échappe au journal: pas d'annulation.

## Compresser et décompresser: `fili-archive`

Pour une archive, `fili-archive` (jamais `zip`/`tar`/`7z` à la main): il n'écrase rien, n'écrit le résultat qu'une fois fini, et chaque appel est une transaction `fili-tx` (« `fili-tx undo` pour annuler »).

| Besoin | Commande |
| --- | --- |
| Compresser un ou plusieurs fichiers ou dossiers | `fili-archive pack [-f zip\|7z\|tar.gz\|tar.xz\|tar.zst] [-l fast\|normal\|best] [--no-hidden] [-o SORTIE] CHEMIN...` (zip par défaut, niveau normal, à côté des fichiers; `-q`: sans transaction ni notification, pour Casier qui a son panneau « Compresser… » et son propre défaire) |
| Extraire | `fili-archive unpack [-o DOSSIER] ARCHIVE...` (dans un dossier à part, à côté de l'archive) |
| Voir le contenu | `fili-archive list ARCHIVE` |

Sortie: un chemin créé par ligne. Un double-clic sur une archive (Casier, `xdg-open`) lance `fili-archive open`. Mots de passe: pas encore pris en charge.

## Dire à l'utilisateur comment revenir en arrière

Après un changement, une phrase: ce qui a été fait et « `fili-tx undo` pour annuler ». Si l'utilisateur demande d'annuler, lancer `fili-tx undo` (pas de reconstruction à la main depuis la conversation), puis vérifier avec `fili-tx status`.

## Recevoir des fichiers (LocalSend, Bluetooth)

`fili-share receive PROTO on|off` active la réception: il lance le démon du protocole (`localsendd`, `obexd`) et `fili-receive` (`apps/fili-receive`), qui pose une notification « Accepter / Refuser » à chaque envoi (même Casier fermé), suit le transfert puis annonce « Reçu de … » avec « Afficher ». Casier: l entrée « À proximité » de la barre latérale (ou Fichier › À proximité, Ctrl+Shift+R) montre les appareils (dépôt de fichiers pour envoyer), les interrupteurs de réception et les derniers fichiers (journal `~/.local/state/filigrane/received.tsv`, `fili-share received`). Réglages dans `fili-file.toml`: `receive_dir`, `receive_confirm` (`ask`|`always`), `receive_minutes` (coupe la réception après ce délai). Bluetooth: agent OBEX `org.bluez.obex.Agent1` de `fili-receive`, non testé sans adaptateur.
