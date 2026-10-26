# Espace de travail de l'agent IA (Filigrane)

Ce dossier (`~/work` par défaut, `FILI_AI_WORKDIR`) est celui où `fili-ai` (Mod+Y) lance l'agent: projets, essais, fichiers temporaires de l'utilisateur. La machine tourne sous **Filigrane** (Void Linux + niri).

- Pour tout ce qui touche à l'OS (paquets, services, réglages, mises à jour, bureau, matériel, identité visuelle), charger la skill **filigrane** avant d'agir.
- Gestionnaire de paquets **xbps** (jamais apt, pacman, dnf, brew, nix, flatpak), init **runit** (jamais systemctl ni journalctl), root via `sudo`.
- La configuration de l'OS est un dépôt git: `$FILIGRANE_DIR` (`fili-ai status`), règles complètes dans son `AGENTS.md`. Un changement durable de l'OS va dans ce dépôt, pas seulement sur le système live, puis `./bootstrap.sh`.
- L'OS doit se faire oublier: solution la plus légère, avertir avant d'installer quelque chose de lourd (format dans la skill).
- Lecture seule d'abord pour diagnostiquer, cause en une ou deux phrases, puis correction. Dire ce qui a été fait, vérifié ou non testé.
