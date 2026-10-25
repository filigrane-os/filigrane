# distro/: dépôt xbps et ISO

Prototype d'une distribution tirée de ce dépôt : **Filigrane**, l'OS présent en filigrane, qui laisse la RAM et le CPU aux applications. Commandes et paquets sous le nom court `fili` (`distro.env`).
Ce n'est pas un fork de Void : la distribution reste en aval de Void (mêmes miroirs, mêmes mises à jour de sécurité), et ne maintient que sa couche.

## Principe

| Brique | Rôle |
|---|---|
| Dépôt git (racine) | La source : listes de paquets, services, réglages système, dotfiles, outils Rust. `bootstrap.sh` l'applique |
| Couches | distribution (racine) → matériel (`hardware/<machine>`) → personnel (`users/<login>`, jamais dans l'ISO) |
| Dépôt xbps (`build-repo.sh`) | `fili-apps` : outils de `apps/` déjà compilés, pas besoin de cargo. `fili-<liste>` : un méta-paquet par `packages/<liste>.txt` |
| ISO (`build-iso.sh`) | Live console Void (`void-mklive`), avec le dépôt xbps, une copie générique du dépôt git et l'installateur `fili-install` |

Philosophie (voir `CLAUDE.md`) : l'OS laisse la RAM et le CPU au navigateur, aux agents et aux conteneurs. Les paquets Void natifs passent avant tout, aucun démon inutile, pas d'Electron, de JVM ni de Node résident. Les outils maison sont des binaires Rust. `budget` mesure le respect de cette règle.

## Construire

```
distro/build-repo.sh              # sans root: distro/out/repo (paquets non signés)
sudo distro/build-iso.sh          # root (void-mklive monte et chroote): distro/out/fili-live-x86_64-<date>.iso
```

En CI (`.github/workflows/distro.yml`, branche `distro` ou lancement manuel) : construction dans un conteneur Void privilégié, puis démarrage de l'ISO dans QEMU jusqu'à l'invite de connexion, et ISO gardée 7 jours en artefact.

## Installer depuis l'ISO

Démarrer l'ISO (session `anon` ouverte automatiquement), brancher le réseau, puis `fili-install`. L'installateur demande le disque, l'utilisateur et le nom de la machine, puis lance `install-void.sh`, qui efface tout le disque et demande de taper son chemin pour confirmer. Ensuite `bootstrap.sh --user-layer none` tourne dans le chroot et installe `fili-apps` depuis le dépôt embarqué.

## Limites du prototype

- **Réseau obligatoire** : seuls les paquets de la distribution sont dans l'ISO, les ~650 paquets Void sont téléchargés à l'installation.
- **Live en console** : pas de session niri pour essayer avant d'installer.
- **Pas de dépôt publié** : le dépôt n'est ni hébergé ni signé (il faudrait une clé `XBPS_PRIVKEY` en secret CI et un hébergement, par exemple GitHub Pages). Les mises à jour passent donc par `git pull` puis `./bootstrap.sh`, pas encore par `xbps-install -Su`.
- **Méta-paquets non utilisés** : `bootstrap.sh` installe encore les listes une par une. Les méta-paquets `fili-*` sont prêts pour le jour où le dépôt sera publié.
- **Copie du dépôt sans historique git** : pour suivre les mises à jour, cloner `DISTRO_GIT` à la place.
- **x86_64 seulement** pour l'ISO, et UEFI seulement pour l'installation, comme `install-void.sh`.
