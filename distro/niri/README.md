# fili-niri: niri with the Filigrane patch

`fili-niri` replaces Void's `niri` package until niri fixes [niri-wm/niri#2691](https://github.com/niri-wm/niri/issues/2691):
on GPUs with few graphics pipes (CRTCs: three on Intel Ice Lake, the T2 MacBooks), a laptop panel turned off by niri
keeps its pipe reserved, so the third monitor of a dock gets none and shows a copy of another one until niri restarts.
With the patch, the pipe of a display turned off is lent to the display that needs it.

| Piece | Role |
|---|---|
| [filigrane-os/niri](https://github.com/filigrane-os/niri), branch `filigrane` | The patch (one commit on a niri release tag) and `FILIGRANE.md` |
| `upstream` | Pinned commit of that branch, `patchrev`, and the niri issue to watch |
| `build.sh` | Void's niri template renamed `fili-niri` (`replaces="niri>=0"`), the patch rebased on the niri release Void ships, `xbps-src pkg` |
| `publish.sh` | Adds the package to a copy of the published repository and rebuilds the signed index |
| `alert.sh` | GitHub issues of the workflow (build failed, niri fixed upstream) |
| `.github/workflows/niri.yml` | Every day: builds when Void ships a new niri or the pin changes, publishes, alerts |

Installation: `packages/desktop.txt` keeps Void's `niri` (the fallback on other architectures, or when the repository
cannot be reached); once the distribution's repository is set, `bootstrap.sh` installs `fili-niri`, whose `replaces`
removes `niri` (its `provides` satisfies `fili-desktop`).

Package version: Void's niri version, revision = Void's revision × 100 + `patchrev` (`fili-niri-26.04_201`). A new
niri in Void, or a new patch (`patchrev` bumped), is an update for `xbps-install -Su`. `repo.yml` keeps the package
(`DISTRO_EXTERNAL_PACKAGES` in `distro.env`).

## Alerts

- **fili-niri-build** issue: the patch no longer applies to the new niri release (rebase the `filigrane` branch on the
  new tag, push, put the new commit in `upstream`), or the build failed. Machines keep the previous `fili-niri`, patch
  included. The next successful build closes the issue.
- **fili-niri-upstream** issue: the niri issue was closed (with the commit that closed it), then a comment once the niri
  release Void ships contains that commit: time to try plain niri.

## Changing the patch

```
cd ~/Projects/niri && git checkout filigrane    # clone of the fork
# edit, commit, then build and test locally:
FILI_SRC_NIRI=~/Projects/niri distro/niri/build.sh    # xbps-src, about 20 minutes the first time
git push filigrane filigrane
```

Then put the new commit in `ref=`, bump `patchrev`, push: the workflow publishes the new package.

## Going back to plain niri

When the `fili-niri-upstream` issue says the fix is in Void's niri: `sudo xbps-remove -y fili-niri && sudo xbps-install -y niri`,
log out and in, and try the dock with the internal panel turned off. If the third monitor gets its own picture:
remove the `fili-niri` block of `bootstrap.sh`, `distro/niri/`, `.github/workflows/niri.yml` and `fili-niri` from
`DISTRO_EXTERNAL_PACKAGES`, delete the package from the `repo` release, and run the first step on every machine.
