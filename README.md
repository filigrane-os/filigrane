# Filigrane

Environnement Void Linux (niri, identité visuelle Filigrane) rejouable sur VM, PC ou Mac Intel (x86_64, glibc, UEFI).
Objectif: un système léger qui s'efface, pour laisser la RAM et le CPU au navigateur, aux agents et aux conteneurs.

## Structure

| Chemin | Rôle |
|---|---|
| `install-void.sh` | Depuis l'ISO live : partitionne le disque, installe la base, appelle `bootstrap.sh`, installe GRUB |
| `bootstrap.sh` | Sur un Void existant : paquets, services runit, clavier/fuseau, groupes, sudo, dotfiles, Claude Code. Idempotent |
| `config.env` | Réglages par défaut de la distribution : clavier (`us`), fuseau, locale, disposition niri (`XKB_*`), groupes, autologin, Claude Code |
| `packages/*.txt` | Listes xbps : `base`, `desktop`, `dev`, `vm`, `baremetal`, `cpu-{intel,amd}`, `gpu-{intel,amd,nvidia}`, `mac-t2` |
| `users/<login>/` | Couche personnelle (voir plus bas) : `config.env`, `packages/*.txt`, `services/*.txt`, `dotfiles/`, `layer.sh` |
| `apps/` | Outils natifs en Rust : `bar-stats` (modules Waybar), `menu-backdrop` (flou du menu), `budget` (budget ressources) |
| `distro/` | Dépôt xbps de la distribution et ISO live (voir `distro/README.md`) |
| `services/*.txt` | Services runit : `common`, `vm` |
| `dotfiles/home`, `dotfiles/config` | Fichiers liés par symlink dans `~` et `~/.config` |
| `hardware/<machine>/` | Tout ce qui est propre à un matériel : `mac-t2/` (Mac Intel à puce T2, voir son README). `dotfiles/{home,config}` y est lié en plus des dotfiles communs |
| `scripts/` | `pull-from-vm.sh`, `brand-assets.sh` (visuels Filigrane), `gen-emoji.py` |

Trois couches, appliquées dans l'ordre ; un fichier de même chemin dans une couche suivante remplace le précédent :

1. **la distribution** (racine du dépôt), générique : ce qu'aurait n'importe quel utilisateur ;
2. **le matériel** (`hardware/<machine>/`) ;
3. **la couche personnelle** (`users/<login>/`) : comptes, services tiers, goûts. Ici `users/thomas` : bépo, Proton (Mail, Calendar, Drive), WhatsApp, iCloud, Google Chrome, imprimante Dell, veille Omarchy/t2linux. Niri l'inclut par `~/.config/niri/local.kdl`, cron-watch par `~/.config/cron-watch/jobs.d/`.

`--user-layer <login>|none` choisit la couche et la mémorise dans `.user-layer` (hors git). Sans ce fichier : `users/<utilisateur>` s'il existe, avec un avertissement. `none` = distribution seule, comme une installation neuve depuis l'ISO.

Axes matériels, détectés puis forçables (utile pour tester) :

- **profil** (`vm` ou `baremetal`) : flag `hypervisor` de `/proc/cpuinfo`, ou `--profile` / `PROFILE=`.
- **machine** (`generic` ou `mac-t2`) : puce T2 Apple trouvée dans `/sys/bus/pci`, ou `--machine` / `MACHINE=`. `generic` n'exécute rien de `hardware/`. Pour une nouvelle machine : créer `hardware/<nom>/` (avec `setup.sh` et éventuellement `dotfiles/`) et l'ajouter au `case` de `bootstrap.sh`.

- **cpu** (`intel`, `amd`, `other`) : `vendor_id` de `/proc/cpuinfo`, ou `--cpu`. Machine physique seulement : `packages/cpu-<x>.txt` (firmware, microcode). `other` (ARM, RISC-V) n'ajoute rien.
- **gpu** (liste `intel,amd,nvidia`, ou `none`) : fabricants lus dans `/sys/class/drm`, ou `--gpu`. Machine physique seulement : `packages/gpu-<x>.txt` (Vulkan, accélération vidéo). NVIDIA = pilote libre nouveau. Un GPU inconnu (VM, SoC) n'ajoute rien, Mesa de base suffit.
- **arch** (`x86_64`, `aarch64`, `riscv64`) : `uname -m`, ou `--arch`. Sert à ignorer les binaires x86_64 (Proton Drive CLI). Les paquets absents du dépôt de l'architecture sont déjà ignorés avec un avertissement.

`./bootstrap.sh --plan [options]` affiche les listes retenues pour une configuration et quitte, sans rien modifier.

**CI** (`.github/workflows/ci.yml`, pull requests vers `main` et push sur `main`, `develop` et `distro`) : syntaxe et shellcheck (scripts de `~/.local/bin` compris), JSON valides, consignes et skills des agents, `niri validate` (distribution et couche personnelle), `--plan` sur 8 configurations (VM, PC Intel/AMD/NVIDIA/hybride, Mac T2, ARM, RISC-V), existence des paquets dans le dépôt Void (`scripts/check-packages.sh`, aarch64 à titre indicatif), pose des dotfiles dans un HOME vierge pour `generic` et `mac-t2`, avec les skills des agents et un test de `fili-ai` sans réseau. Aucune installation système n'est testée en CI.

`install-void.sh` (x86_64 UEFI seulement) accepte les mêmes options et les transmet à `bootstrap.sh`.

## Ce que contient le bureau

- **Session** : sur la VM, connexion automatique sur `tty1` (`AUTOLOGIN=auto` : actif en VM, inactif sur machine physique), puis `~/.zprofile` lance `dbus-run-session niri`. Désactiver : `touch ~/.no-niri`, ou se connecter sur `tty2` à `tty6`.
- **Thème** : identité Filigrane (`brand/`, polices Jost et JetBrains Mono) pour niri, waybar, fuzzel, mako, foot, swaylock, GTK, zellij, nvim, fond d'écran et écran de démarrage Plymouth (invite de passphrase LUKS). Visuels générés par `scripts/brand-assets.sh`.
- **Menu** (`Mod+Space`) : catégories à vide, recherche floue sur tout dès qu'on tape (applications, actions système, entrées perso). Clavier : `Maj+Retour arrière` remonte d'un niveau, `Échap` quitte tout le menu (`fuzzel` ne sait pas distinguer un retour arrière sur saisie vide). `Mod+D` ouvre le lanceur d'applications seul (`menu apps`): les plus lancées d'abord, puis les applis avant leurs préférences (compteur dans `~/.local/state/menu-apps-count`). Entrées perso dans `~/.config/menu/entries` (`Libellé | mode | commande`, par exemple `Claude | term | claude`).
- **Captures** : outil intégré à niri, sans logiciel en plus. `Mod+Shift+4` zone, `Mod+Shift+3` écran, `Mod+Shift+Ctrl+4` fenêtre, `Mod+Shift+5` interface de capture, `Print` / `Ctrl+Print` / `Alt+Print`, ou le menu (`Capture: ...`). Enregistrées dans `~/Screenshots` (local, hors iCloud) et copiées dans le presse-papiers.
- **Shell** : zsh sans oh-my-zsh, zellij à la demande (`zj`), pas lancé automatiquement, outils CLI repris du Mac (`eza`, `fzf`, `zoxide`, `ripgrep`, `bat`, `lazygit`, `gh`), neovim avec LazyVim.
- **Chromium** natif Wayland (variable `CHROME_FLAGS` posée par niri). **Conteneurs** : `podman`, alias `d`.
- **Fond d'écran** : `swaybg` via `wallpaper [image]`, images dans `~/.local/share/wallpapers/`. Les images téléchargées ne sont pas dans le dépôt (licence inconnue).
- **Veille automatique** : `cron-watch` (lancé par niri, un `bash` endormi d'environ 3 Mo, sans daemon cron) rejoue des tâches périodiques avec rattrapage après reboot. `watch-void` : notification mako des mises à jour xbps (toutes les 6 h). `watch-claude omarchy|t2` : chaque semaine, si Omarchy ou t2linux ont du neuf, `claude -p` (lecture seule, sans réseau ni Bash, plafond 1 $) compare au dépôt et écrit des propositions d'intégration dans `~/.local/state/watch/reports/`, avec notification. Prompts dans `dotfiles/config/watch/`.
- **Proton Drive** : CLI officielle (`proton-drive`, binaire épinglé et vérifié par SHA-512, sans démon) installée par `bootstrap.sh`. Elle garde sa session dans le trousseau (`gnome-keyring`, lancé à la demande par D-Bus). Une seule fois, créer le trousseau puis se connecter :
  ```
  read -rs "P?Mot de passe du trousseau : " && printf '%s' "$P" | gnome-keyring-daemon --replace --unlock --components=secrets --daemonize >/dev/null; unset P
  proton-drive auth login
  ```
  Puis par exemple `proton-drive filesystem upload -f skip -d merge -t ./dossier /my-files/sauvegardes`. Le trousseau est verrouillé à chaque démarrage : la première utilisation de la session le redemande.
- **Claude Code** : installé par `bootstrap.sh` (`~/.local/bin/claude`, `/login` au premier lancement, `Mod+Y`), avec la skill `filigrane` (règles xbps/runit, budget ressources, identité visuelle, tout changement durable reporté dans ce dépôt).

## Ce que Void + niri apporte par rapport à macOS

Mesures sur le même MacBook (T2), au repos, après démarrage récent. Côté Mac, l'indexation Spotlight est coupée (sinon `mds_stores` fait monter le load à 40).

| | Void + niri | macOS (indexation coupée) |
|---|---|---|
| RAM, système seul (hors applications) | ~0,8 Go | ~6,5 Go (dont 2,7 Go de noyau « wired ») |
| CPU au repos | 92-94 % d'inactivité | ~94 % |
| Puissance totale (machine entière, écran compris, sur batterie) | 19,4 W, Chromium ouvert | ~24 W, sans navigateur |
| Swap | 0 | 0 |

- **RAM** : macOS pèse environ 8 fois plus que Void hors applications. Son noyau seul fait plus de 3 fois tout le système Linux.
- **CPU** : équivalent au repos une fois l'indexation finie. `WindowServer` reste pourtant à ~16 % pour un affichage statique, sans équivalent sous niri.
- **Énergie** : le Mac tire ~4,6 W de plus (+24 %) avec moins d'applications ouvertes.
- **Conséquence** : la RAM et la batterie libérées reviennent au navigateur, aux agents et aux conteneurs, d'où la règle « l'OS doit se faire oublier ».

Ce que macOS ne permet pas sur ce Mac et qui marche ici en natif (sans adaptateur ni logiciel tiers) :

- **DisplayPort MST** : plusieurs écrans distincts chaînés ou via un hub sur un seul port, là où macOS ne fait que de la recopie.
- **Bluetooth LDAC** : casque (Sony WH-1000XM4) en LDAC, alors que macOS s'arrête à AAC et SBC. Codec au choix dans wiremix (onglet Configuration : LDAC, AAC, SBC-XQ, SBC). Le Bluetooth interne du Mac T2 (BCM4364 sur UART) demande un noyau avec `CONFIG_SERIAL_DEV_BUS=y` : [void-packages#63047](https://github.com/void-linux/void-packages/issues/63047), corrigé par [#63089](https://github.com/void-linux/void-packages/pull/63089), pas encore fusionnée.

## Réinstaller un système complet

1. Démarrer sur l'ISO live Void (glibc x86_64), réseau actif, `root` / `voidlinux`.
2. `xbps-install -Sy git && git clone https://github.com/thooams/filigrane && cd filigrane`
3. `./install-void.sh --disk /dev/sda --user thomas --hostname void` (NVMe : `/dev/nvme0n1`)
4. Taper le chemin du disque pour confirmer l'effacement, saisir les mots de passe, redémarrer.

GRUB est installé en `--removable` : pas d'entrée NVRAM, donc démarrage fiable sur PC comme sur Mac Intel.

## Rejouer sur un Void déjà installé

```
git clone https://github.com/thooams/filigrane ~/filigrane && cd ~/filigrane
./bootstrap.sh                 # tout (demande le mot de passe sudo)
./bootstrap.sh --dotfiles-only # liens seulement
```

Les dotfiles existants sont déplacés en `*.bak.<date>`. Le dépôt doit rester à son emplacement (les liens pointent dedans). Les liens vers le dépôt devenus orphelins (fichier déplacé ou supprimé) sont retirés.

Sans accès à GitHub, copier le dépôt depuis un autre poste (pas de `rsync` sur Void de base) :
`tar --exclude=.git -C ~/Projects/filigrane -cf - . | ssh void 'mkdir -p ~/filigrane && tar -xf - -C ~/filigrane'`, puis `ssh -t void 'cd ~/filigrane && ./bootstrap.sh'` (`-t` pour le mot de passe sudo).

## Workflow

La VM sert de terrain d'essai : on règle niri, waybar, le menu... dessus (les fichiers sont des liens vers `~/filigrane` sur la VM), puis `scripts/pull-from-vm.sh` rapatrie le tout, on relit le diff et on commite.
Nouveau paquet : l'ajouter dans le bon fichier `packages/*.txt` (distribution) ou `users/<login>/packages/*.txt` (personnel).

## Limites connues

- UEFI uniquement, pas de LUKS/LVM, pas de BIOS legacy ni d'EFI 32 bits (Mac Pro 2006).
- `install-void.sh` utilise tout le disque. Double démarrage sur un volume LUKS + btrfs existant : à la main, voir `hardware/mac-t2/README.md` (`dualboot.sh`).
- Mac T2 : Touch Bar en touches spéciales seulement (pas de `tiny-dfr`), firmware Wi-Fi à récupérer à la main (`t2-wifi-firmware`, ou copie depuis un autre système ; jamais dans le dépôt), voir `hardware/mac-t2/README.md`.
- Wi-Fi Broadcom des vieux Mac (sans T2) : pilote propriétaire non inclus.
- Non testés de bout en bout : `install-void.sh`, le profil `baremetal`, le profil `mac-t2` (la VM de développement n'est pas réinstallable sans être effacée, et n'a pas de puce T2).
- Les actions `Éteindre`, `Redémarrer` et `Veille` du menu passent par `sudo` sans mot de passe (règle `/etc/sudoers.d/zz-power`, limitée à `zzz`, `reboot`, `poweroff`), faute de `polkit`.
