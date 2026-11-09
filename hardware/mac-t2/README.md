# Mac Intel à puce T2

MacBook Pro/Air 2018-2020, Mac mini 2018, iMac 2020, iMac Pro, Mac Pro 2019. Détection automatique par `lspci` (`106b:1801` / `106b:1802`), comme Omarchy.

## Approche

Omarchy utilise un noyau `linux-t2` patché (Arch). Void n'en a pas : on garde le noyau Void et on compile les pilotes manquants en **DKMS**, reconstruits à chaque mise à jour du noyau.

| Fonction | Source |
|---|---|
| Clavier, trackpad (USB virtuel), audio | DKMS `t2bce` (`t2bce_core/dma/vhci/audio`, dépôt AdityaGarg8/t2bce, révision épinglée) |
| Wi-Fi Broadcom, Bluetooth, NVMe, `hid-apple` | noyau Void 6.18 (déjà activés). Clavier : Fn et Ctrl gauche inversés (`HID_APPLE_OPTS` dans `setup.sh`) |
| Wi-Fi: firmware | script officiel t2linux, à lancer à la main (`t2-wifi-firmware`) |
| Ventilateurs | DKMS `applesmc-t2` : `applesmc.c` de v6.18.7 + correctifs `30xx-applesmc` de t2linux (révision épinglée, vérifiés contre `applesmc/SHA256SUMS`, série 6.18 seulement). L'`applesmc` du noyau Void bloque le démarrage sur T2 : il est sur liste noire, et le service `t2fanrd` (Rust, valeurs Omarchy) charge la version DKMS après le démarrage, ou s'arrête si elle manque |
| Audio: haut-parleurs / casque | profils ALSA UCM du dépôt t2bce ; sur MacBookPro16,2, DSP haut-parleurs façon macOS (`audio/`) : FIR asahi-audio du MacBook Pro 13" M1 (j293, même châssis) + bankstown + lsp-plugins, chargé par WirePlumber (~10 % d'un cœur pendant la lecture) |
| Trackpad | DKMS `t2-trackpad` : `hid-apple` et `hid-magicmouse` de v6.18.7 + correctifs t2linux (partie HID de 4001, 4003-4005, révision épinglée) + `9001` (port manuel des correctifs stables jusqu'à v6.18.57, dont une correction de sécurité). Sans lui, le noyau Void voit le trackpad comme une souris (pas de défilement à deux doigts). `t2-compat.h` remplace les définitions SPI Apple Silicon absentes. Série 6.18 seulement |
| Clavier | Command = touche Mod de niri (Super), copier/coller = Ctrl+C/V, aucun remappage keyd. keyd capture le clavier interne : le DKMS `appletb` (v2, `0001-keyd-virtual-keyboard.patch`) écoute aussi son clavier virtuel pour Fn et le réveil de la Touch Bar. Fn et Ctrl gauche inversés |
| Touch Bar | DKMS `appletb` : `hid-appletb-kbd`, `hid-appletb-bl` (et `appletbdrm`, compilé mais non chargé), désactivés dans la config du noyau Void. Sources du tag stable `v<version>` sur git.kernel.org, vérifiées contre `appletb/SHA256SUMS`. Touches spéciales dessinées par la T2 (Fn pour F1-F12), comme Omarchy, sans démon `tiny-dfr` |

Réglages appliqués : paramètres noyau `intel_iommu=on iommu=pt pm_async=off mem_sleep_default=deep` (suspension stable), `rd.luks.allow-discards` (TRIM à travers LUKS: btrfs active alors `discard=async` tout seul), `brcmfmac.feature_disable=0x82000` (wpa_supplicant 2.11+ casse le Wi-Fi Broadcom), modules chargés au démarrage (`/etc/modules-load.d/t2.conf`) et ajoutés à l'initramfs dracut.

## Avant d'installer (sur macOS)

1. Recovery (Cmd+R au démarrage) > Utilitaire de sécurité de démarrage : sécurité **Aucune sécurité**, **autoriser le démarrage depuis un support externe**.
2. Un **clavier et une souris USB** et un **adaptateur Ethernet USB** : sans `t2bce`, clavier, trackpad et Wi-Fi internes ne marchent pas pendant l'installation.
3. Démarrer l'ISO Void avec la touche **Option** (choisir "EFI Boot").

## Installer

```
./install-void.sh --disk /dev/nvme0n1 --user thomas --profile baremetal
```

Attention : `install-void.sh` utilise **tout le disque** et **efface macOS**. Pas de double démarrage pour l'instant. Pour garder macOS, installer sur un SSD externe (`--disk /dev/sdX`).

Le bootstrap détecte la puce T2, installe les en-têtes et DKMS, compile `t2bce`, configure le démarrage, les ventilateurs et l'audio.

## Double démarrage (Void à côté d'Omarchy ou d'un autre Linux)

Cas visé (pas encore testé de bout en bout) : un volume LUKS2 + btrfs déjà utilisé par un autre système, démarré par Limine sur une ESP Linux séparée de celle d'Apple. Void s'installe dans des sous-volumes de premier niveau à côté:

| Sous-volume | Monté sur (Void) | Rôle |
|---|---|---|
| `@void` | `/` | racine Void |
| `@home-void` | `/home` | home propre de Void (dotfiles du dépôt sans conflit) |
| `@home` (l'autre système) | `/mnt/omarchy-home`, lien `~/home.bak` | ancien home, intact |
| `@swap` | `/swap` | swapfile No_COW (swap seulement, pas d'hibernation) |

L'ESP est montée sur `/boot/efi` : les noyaux restent dans `@void`, seul `/boot/efi/void/` est écrit sur l'ESP.

`./dualboot.sh` (root, idempotent) écrit `/etc/fstab`, `/etc/dracut.conf.d/10-dualboot.conf` (hostonly, `crypt btrfs resume`) et `/etc/kernel/cmdline` avec les UUID détectés à l'exécution (aucun dans le dépôt). Le clavier du prompt LUKS est `us` par défaut (`LUKS_KEYMAP`), car la phrase de passe doit se taper comme sur l'autre système. `setup.sh` ajoute ensuite ses paramètres T2 à `/etc/kernel/cmdline`.

### Démarrage et retour arrière

- **Limine** : `limine-void sync` (lancé par les hooks `/etc/kernel.d/post-install` et `post-remove`) copie les deux noyaux les plus récents dans `/boot/efi/void/` et réécrit uniquement le bloc `/+Void Linux` à la fin de `limine.conf` (copie précédente : `limine.conf.void-bak`). `default_entry` et les entrées de l'autre système ne sont pas touchés. Il prend le même verrou que les outils Limine d'Omarchy (`/run/lock/boot-partition.lock`).
- **Noyaux** : ne pas utiliser `vkpurge rm all` (il ne garde que le noyau en cours). Utiliser `limine-void purge --yes`, qui garde les deux plus récents et le noyau épinglé.
- **`t2-rollback`** : si le dernier noyau casse le matériel, `sudo t2-rollback` bloque les mises à jour du noyau (`xbps-pkgdb -m hold`), met l'avant-dernier noyau en tête du menu « Void Linux » et propose de redémarrer (Limine n'a pas de « prochain démarrage seulement » : choisir « Void Linux » au menu). `t2-rollback 6.18.56_1` pour une version précise, `t2-rollback --undo` pour revenir au plus récent, `--status` pour l'état.
- **Mises à jour** : `void-update` (au lieu de `xbps-install -Su`) prend un instantané snapper de `@void` avant et après (10 gardés, pas d'instantanés horaires). Pas de `limine-snapper-sync` sur Void : pas d'entrée Limine par instantané. Restaurer un instantané `N` depuis l'autre système (ou une clé live), `@void` non monté :
  ```
  mount -o subvolid=5 /dev/mapper/<volume> /mnt/top
  mv /mnt/top/@void /mnt/top/@void.casse
  btrfs subvolume snapshot /mnt/top/@void.casse/.snapshots/N/snapshot /mnt/top/@void
  ```
  puis redémarrer sur Void. Après vérification, supprimer `@void.casse` (ses instantanés imbriqués d'abord).

**Hibernation** : désactivée (`nohibernate`). Non fiable sur Mac T2 (essai raté sur ce Mac), et dangereuse en double démarrage : les deux systèmes partagent le même système de fichiers btrfs. Si l'un est en hibernation, ne jamais démarrer l'autre (corruption possible). La veille simple ne pose pas ce problème.

**Veille** : la carte Wi-Fi (ARPT) ne réveille plus la machine (`72-t2-wifi-nowake.rules`), elle provoquait des réveils parasites capot fermé. Pas de veille automatique sur inactivité (verrou à 5 min, écran éteint à 10 min, comme Omarchy): le 18 oct. 2026, une veille S3 lancée sur batterie n'a jamais repris (démarrage à froid le lendemain, `tree-log replay` btrfs, aucune trace après `suspend entry`), et la session a été perdue. Cause non tranchée entre batterie vidée et plantage au réveil: les hooks `/etc/zzz.d/{suspend,resume}/10-sleeplog` (`setup.sh --only sleeplog`) journalisent la batterie (`grep sleeplog /var/log/socklog/user/current`). Omarchy a la même cmdline T2 et aucun contournement de veille. La veille manuelle reste possible. Réveil lent: au réveil S3, le noyau rallumait les cœurs 1 à 7 en 10 à 35 s (`Enabling non-boot CPUs`, même symptôme sur MacBook Pro 2015), écran noir pendant ce temps, si bien que le capot semblait ne pas réveiller. `setup.sh --only sleeplog` les arrête avant la veille et les rallume après (`/etc/zzz.d/{suspend/90-cpu-offline,resume/05-cpu-online}`). elogind (capot) ne lance pas `/etc/zzz.d`: le hook `/usr/libexec/elogind/system-sleep/50-zzz.d` les relaie. Le capot ne sort pas la machine de veille (seul le bouton power, S3 comme s2idle, LID0 et EC armés): elogind ignore donc le capot (`system/elogind/10-lid.conf`) et niri appelle `~/.local/bin/lid`, qui verrouille et éteint l'écran, puis met en veille seulement après 5 min capot fermé. Le message `e-suspend: segfault` au réveil est un bug connu d'elogind 252 ([elogind #341](https://github.com/elogind/elogind/issues/341), corrigé en 255) : il survient après la veille, sans effet.

## Après le premier démarrage

1. Wi-Fi/Bluetooth : `t2-wifi-firmware`, méthode 5 (sans macOS, télécharge l'image de récupération Apple ; choisir macOS Monterey à Sonoma), puis redémarrer.
2. Vérifier : `lsmod | grep -E 't2bce|hci_bcm4377|brcmfmac'` et `dmesg | grep -iE 'brcmfmac|t2bce'`.
3. Ventilateurs : `sudo sv status /var/service/t2fanrd`.

## Statut

Aucune de ces étapes n'a été testée sur un vrai Mac T2 (la VM n'a pas de puce T2). Testé seulement : la syntaxe des scripts et la compilation des modules contre le noyau Void 6.18.

Réutilisation : `./hardware/mac-t2/setup.sh --only dkms|touchbar|smc|trackpad|keys|boot|audio|fan|net|tools` (`T2_FORCE=1` pour forcer sans puce détectée).

Sources : [t2linux](https://wiki.t2linux.org/), [t2bce](https://github.com/AdityaGarg8/t2bce), [Omarchy fix-t2.sh](https://github.com/omacom/omarchy/blob/quattro/install/hardware/apple/fix-t2.sh).
