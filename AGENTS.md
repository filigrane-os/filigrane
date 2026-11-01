# Filigrane: Void Linux + niri

Ce dépôt décrit la machine (paquets, services, dotfiles) et la distribution Filigrane. L'agent IA choisi (Claude Code, Codex, opencode: `FILI_AI`) se lance avec `fili-ai` (Mod+Y) et lit ce fichier quand il travaille ici (`CLAUDE.md` l'importe). Les conversations portent sur cette machine: config, paquets, services, niri, dépannage. Les dotfiles de `~` et `~/.config` sont des liens vers `dotfiles/` (`bootstrap.sh`).

La skill `filigrane` (`agents/skills/filigrane/`, liée dans `~/.claude/skills` et `~/.agents/skills`) contient le détail (usage, mises à jour, système, niri, ressources, identité visuelle). Ce fichier ne garde que les règles toujours actives. Tout travail visuel suit `agents/skills/filigrane/references/brand.md` (fichiers maîtres dans `brand/`), et toute interface (fili-shell, outils `fili-*`, thèmes) le skill `filigrane-ui` (`agents/skills/filigrane-ui/`, HIG inspirée du Mac OS X classique).

Mod+Y note l'application active (`fili-context`, fichier `~/.local/state/filigrane/context.json`, `$FILI_CONTEXT_FILE`; Claude Code le reçoit dans son prompt système). Si l'utilisateur dit « ceci », « ces fichiers », « ici », lire ce fichier (champs `selection`, `location`, `about`) avant de demander. Les chemins se traitent avec les outils shell; corbeille avec `gio trash`.

Modifier des fichiers pour l'utilisateur (renommer, déplacer, supprimer, copier, créer, en lot): `fili-tx` (`mv`, `mv -` pour un lot sur l'entrée standard, `trash`, `mkdir`, `cp`, `made`), jamais `mv`/`rm`/`cp` seuls. Une demande = une transaction: `fili-tx undo` la défait en une commande (`redo`, `status`). Après un changement, dire « `fili-tx undo` pour annuler »; pour annuler, lancer `fili-tx undo`, pas de reconstruction à la main (détail: skill `filigrane`, `references/files.md`).

## Règles dures

- Gestionnaire de paquets: **xbps** (jamais apt, pacman, dnf, brew, nix, flatpak). Init: **runit** (jamais systemctl ni journalctl). Root via `sudo`.
- Lecture seule d'abord pour diagnostiquer, cause en une ou deux phrases, puis correction.
- Avant de recharger la config niri: `niri validate`.
- Après un changement du fili-shell (`dotfiles/config/quickshell/`, scripts `bar-*`, `fili-*`): `tests/fili-shell/run.sh` doit passer avant le commit.
- Toute application `fili-*` à fenêtre (fili-file, etc.) **expose son menu** au menu global de la fili-bar, avec toutes ses commandes et leurs raccourcis, jamais seulement des boutons ou un menu contextuel. Le menu vit dans la barre: **inutile de le dessiner dans la fenêtre**. Deux voies: une barre de menus du toolkit lue par AT-SPI (`GtkMenuBar`; vérifier avec `fili-appmenu menu PID`, JSON non `null`; la `MenuBar` de Qt Quick Controls n'exporte pas ses entrées, ne pas s'y fier), ou un menu de repli `dotfiles/config/filigrane/appmenu/<app_id>.json` (voir `AppMenu.qml`, skill `filigrane-ui`, `references/hig.md` §7). Un repli ne lance que des commandes: pour qu'il couvre les vraies actions (copier, renommer, corbeille…), l'application les expose par une commande de contrôle (`fili-file ctl --pid PID action NOM`, `%pid` dans le fichier de repli), jamais par des frappes simulées; un fichier de repli passe devant AT-SPI. Pour fili-file, `tests/fili-shell/check-fili-file-menu.py` garde le menu de la barre identique aux commandes et raccourcis de l'application.

- Réglages d'une application `fili-*`: `dotfiles/config/filigrane/<app>.toml` (facultatif, créé seulement s'il y a un vrai réglage; l'état d'usage va dans `~/.local/state/filigrane/`) et une entrée « Settings… » dans son menu de la barre qui l'ouvre avec `xdg-open` (détail: skill `filigrane-ui`, `references/hig.md`).
- Nom affiché (alias): une application peut avoir un nom pour l'utilisateur différent de son programme (`fili-file` = « Casier »). L'alias est le nom partout dans l'OS (lanceur, menu de la barre, titres de raccourcis, « À propos de… »); le nom de programme ne reste que dans Filigrane (dépôt, commandes, code, app-id) et dans la fiche « À propos » (« Aussi connu sous le nom de »). Toute application à alias a cette fiche, ouverte par la commande `about` (menu de la barre, entrée « À propos de … »).

## Déclaratif

Tout changement durable va dans ce dépôt, pas seulement sur le système live, dans la bonne couche:
- **distribution** (générique, utile à tout utilisateur): paquets `packages/`, services `services/`, réglages par défaut `config.env`, configs `dotfiles/`, outils `apps/`.
- **matériel**: `hardware/<machine>/`.
- **personnel** (comptes, services tiers, goûts de l'utilisateur): `users/<login>/` (`config.env`, `packages/`, `dotfiles/`, `layer.sh`), couche active dans `.user-layer` (`none`: la créer, puis `./bootstrap.sh --user-layer <login>`). Même chemin qu'un fichier de la distribution = il le remplace. Niri: `users/<login>/dotfiles/config/niri/local.kdl`.
- Dans le doute, personnel. Rien de personnel (compte, URL de service, chemin `/home/<login>`) dans la couche distribution.
- Puis `./bootstrap.sh` (idempotent) et montrer `git diff`. Dépôt xbps et ISO: `distro/` (voir son README).

## Ressources

L'OS doit se faire oublier: le navigateur, les agents et les conteneurs passent avant. Choisir la solution la plus légère (paquet Void natif, pas de daemon inutile, pas d'Electron/JVM/Node résident, pas d'effets niri hors du flou derrière le menu). Si un paquet ou service est lourd, **avertir avant d'installer** (format dans la skill). Mesurer après toute installation durable (`budget save avant` puis `budget diff avant`). Pour un outil maison, préférer un binaire natif léger et rapide (Rust, dans `apps/`, compilé par `bootstrap.sh`) à un script qui charge un runtime lourd (Python/GTK, Node), quitte à compiler.

## Git

- Dépôt **public**: avant chaque commit, scanner le diff stagé (tokens, mots de passe, clés, e-mails, IP) et montrer le résultat.
- Commit autorisé sans demander après un changement terminé et vérifié (scan ci-dessus obligatoire, jamais d'attribution à un agent IA). Push autorisé sans demander sur toute branche autre que `main`; jamais de push sur `main` (ni force-push) sans demande explicite.

## Interdits

`install-void.sh` (efface un disque entier), `mkfs`, `wipefs`, `parted`, `dd` sur un disque, et toute modification de `/etc/sudoers*`, `~/.ssh`, des identifiants des agents (`~/.claude/.credentials.json`, `~/.codex/auth.json`, `~/.local/share/opencode/auth.json`).
Sans confirmation: installer un paquet (`xbps-install <pkg>`, avertissement ressources si lourd), `xbps-remove` simple d'un paquet non critique (avec Claude Code, le hook `guard-destructive.sh` redemande pour `base-system`, noyau, glibc, xbps, runit, sudo, niri, `-R`/`-f`), `rm` dans le scratchpad ou le dépôt, commit après un changement vérifié (voir Git).
Demander avant: mises à jour système (`xbps-install -u/-Su`), `sv restart/stop` (services système), `rm` ailleurs, édition de `/etc`, bootloader, reboot, push sur `main`. Avec Claude Code et Codex, `sv` et `xbps-*` passent sans mot de passe sudo: la confirmation vient de l'agent (permissions et hook de Claude Code, bac à sable de Codex). Avec opencode, sudo garde son mot de passe: donner la commande à lancer.
Choix de conception (valeur, réglage, outil): prendre le défaut raisonnable, le dire en une ligne, ne pas poser de question. Après un remplacement validé par l'usage, nettoyer l'ancien (paquet, config) sans redemander.

## Style

Réponses en français, courtes et factuelles. Dire ce qui a été fait, vérifié ou non testé.
