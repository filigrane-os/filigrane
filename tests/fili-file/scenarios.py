#!/usr/bin/env python3
"""Scénarios de fili-file (voir run.sh): une instance sans affichage, pilotée par `fili-file ctl`, état lu par
`ctl state`, effets vérifiés sur le système de fichiers. Sortie TAP comme tests/fili-shell: « ok N - nom » ou
« not ok N - nom » suivi de la raison, puis « # fin: X échec(s) sur N ». Code 0 si tout passe."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

T = Path(os.environ["FILI_TEST_ROOT"])
BIN = os.environ["FILI_FILE_BIN"]
VERBOSE = bool(os.environ.get("FILI_VERBOSE"))
DATA = T / "home" / "data"
SOCK_DIR = T / "run" / "fili" / "context"


class App:
    def __init__(self):
        self.log = open(T / "app.log", "w")
        self.proc = subprocess.Popen([BIN, str(DATA)], stdout=self.log, stderr=self.log, start_new_session=True)
        self.pid = self.proc.pid
        (T / "pid").write_text(str(self.pid))
        self.wait(lambda: (SOCK_DIR / f"{self.pid}.sock").exists(), 20, "socket de l'application")

    def ctl(self, *args, stdin=None):
        """Lance `fili-file ctl --pid PID ARGS`; rend (code, JSON de la réponse ou None, texte brut)."""
        r = subprocess.run([BIN, "ctl", "--pid", str(self.pid), *args], input=stdin, capture_output=True, text=True, timeout=20)
        out = r.stdout.strip()
        try:
            data = json.loads(out) if out else None
        except ValueError:
            data = None
        if VERBOSE:
            print(f"#   ctl {' '.join(args)} -> rc={r.returncode} {out or r.stderr.strip()}")
        return r.returncode, data, out or r.stderr.strip()

    def ok(self, *args, stdin=None):
        rc, data, raw = self.ctl(*args, stdin=stdin)
        if rc != 0:
            raise AssertionError(f"ctl {' '.join(args)}: code {rc}: {raw}")
        return data

    def fails(self, *args, stdin=None, containing=""):
        """La commande doit échouer (code 1) avec ce texte dans l'erreur; rend le message."""
        rc, _, raw = self.ctl(*args, stdin=stdin)
        if rc != 1:
            raise AssertionError(f"ctl {' '.join(args)}: attendu un échec (code 1), code {rc}: {raw}")
        if containing not in raw:
            raise AssertionError(f"ctl {' '.join(args)}: « {containing} » absent de « {raw} »")
        return raw

    def state(self):
        return self.ok("state")["state"]

    def wait(self, pred, seconds=8, what="condition"):
        end = time.time() + seconds
        while time.time() < end:
            if self.proc.poll() is not None and what != "socket de l'application":
                raise AssertionError(f"fili-file s'est arrêté (code {self.proc.returncode}), voir app.log")
            try:
                if pred():
                    return
            except (AssertionError, KeyError):
                pass
            time.sleep(0.1)
        raise AssertionError(f"délai dépassé: {what}")


def names(d):
    return sorted(p.name for p in Path(d).iterdir())


def make(name, files):
    """Dossier frais DATA/name avec ces fichiers ({nom: contenu}; nom finissant par / = dossier); l'application y va."""
    d = DATA / name
    d.mkdir()
    for f, content in files.items():
        if f.endswith("/"):
            (d / f).mkdir()
        else:
            (d / f).write_text(content)
    return d


def eq(got, want, what=""):
    if got != want:
        raise AssertionError(f"{what}: obtenu {got!r}, attendu {want!r}".strip(": "))


app = None
results = []


def test(name):
    def deco(fn):
        results.append((name, fn))
        return fn
    return deco


# ---------------------------------------------------------------- démarrage et contrat de ctl

@test("démarrage: état de la fenêtre")
def _():
    s = app.state()
    eq(s["location"], str(DATA), "dossier")
    eq(s["tabs"], [str(DATA)], "onglets")
    eq((s["view"], s["hidden_shown"], s["preview"], s["dialog"], s["in_trash"], s["results"]), ("list", False, False, "", False, ""))
    assert s["can_act"] and s["pid"] == app.pid


@test("actions: liste complète avec libellés et raccourcis")
def _():
    acts = {a["name"]: a for a in app.ok("actions")["actions"]}
    assert len(acts) >= 41, len(acts)
    for n in ("copy", "cut", "paste", "rename", "trash", "undo", "new-folder", "duplicate", "compress", "extract", "select-all", "new-tab", "reload"):
        assert n in acts, n
    eq((acts["copy"]["label"], acts["copy"]["keys"]), ("Copy", "Ctrl+C"))
    assert all(isinstance(a["enabled"], bool) and a["label"] for a in acts.values())


@test("erreurs: action inconnue, désactivée, avec argument inutile, commande inconnue")
def _():
    app.fails("action", "nope", containing="unknown action")
    app.fails("action", "empty-trash", containing="disabled")
    app.fails("action", "copy", "foo", containing="takes no argument")
    app.fails("goto", str(DATA / "missing"), containing="not found")
    app.fails("dialog", "cancel", containing="no dialog")


# ---------------------------------------------------------------- navigation

@test("navigation: goto, retour, avant, parent")
def _():
    d = make("nav", {"a/": "", "b/": ""})
    app.ok("goto", str(d / "a"))
    eq(app.state()["location"], str(d / "a"))
    app.ok("goto", str(d / "b"))
    app.ok("action", "back")
    eq(app.state()["location"], str(d / "a"), "retour")
    app.ok("action", "forward")
    eq(app.state()["location"], str(d / "b"), "avant")
    app.ok("action", "up")
    eq(app.state()["location"], str(d), "parent")


@test("navigation: un fichier est sélectionné dans son dossier; reveal aussi (dossier compris)")
def _():
    d = make("goto-file", {"f.txt": "x", "sub/": ""})
    app.ok("goto", str(d / "f.txt"))
    s = app.state()
    eq((s["location"], s["selection"]), (str(d), [str(d / "f.txt")]))
    app.ok("goto", str(DATA))
    app.ok("reveal", str(d / "sub"))
    s = app.state()
    eq((s["location"], s["selection"]), (str(d), [str(d / "sub")]))
    app.fails("reveal", str(d / "absent"), containing="not found in")
    eq(app.state()["selection"], [str(d / "sub")], "sélection inchangée")


@test("navigation: chemin relatif résolu depuis le dossier de l'appelant")
def _():
    d = make("rel", {"in/": ""})
    r = subprocess.run([BIN, "ctl", "--pid", str(app.pid), "goto", "in"], cwd=d, capture_output=True, text=True)
    eq(r.returncode, 0, r.stdout + r.stderr)
    eq(app.state()["location"], str(d / "in"))


# ---------------------------------------------------------------- sélection

@test("sélection: remplacer, ajouter, vider, motif")
def _():
    d = make("sel", {"a.txt": "", "b.txt": "", "c.pdf": ""})
    app.ok("goto", str(d))
    eq(app.ok("select", stdin=f"{d}/a.txt\n{d}/c.pdf\n")["selected"], 2)
    eq(sorted(app.state()["selection"]), [str(d / "a.txt"), str(d / "c.pdf")])
    eq(app.ok("select", "--add", stdin=f"{d}/b.txt\n")["selected"], 3)
    eq(app.ok("select", "--pattern", "*.pdf")["selected"], 1)
    eq(app.state()["selection"], [str(d / "c.pdf")])
    eq(app.ok("select", "--none")["selected"], 0)
    eq(app.state()["selection"], [])


@test("sélection: un chemin hors du dossier est une erreur et n'est pas sélectionné")
def _():
    d = make("sel-bad", {"a.txt": ""})
    app.ok("goto", str(d))
    app.fails("select", stdin=f"{d}/a.txt\n{d}/absent\n", containing="absent")
    eq(app.state()["selection"], [str(d / "a.txt")], "le présent reste sélectionné")


@test("sélection: tout, inverser, même type, motif par action")
def _():
    d = make("sel2", {"a.txt": "", "b.txt": "", "c.pdf": ""})
    app.ok("goto", str(d))
    app.ok("action", "select-all")
    eq(len(app.state()["selection"]), 3)
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "invert-selection")
    eq(sorted(app.state()["selection"]), [str(d / "b.txt"), str(d / "c.pdf")])
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "select-same-kind")
    eq(sorted(app.state()["selection"]), [str(d / "a.txt"), str(d / "b.txt")])
    eq(app.ok("action", "select-matching", "c*")["selected"], 1)


@test("sélection: les fichiers cachés n'existent qu'une fois affichés")
def _():
    d = make("hid", {"a": "", ".h": ""})
    app.ok("goto", str(d))
    app.fails("select", stdin=f"{d}/.h\n", containing=".h")
    app.ok("hidden", "on")
    eq(app.state()["hidden_shown"], True)
    app.ok("select", stdin=f"{d}/.h\n")
    app.ok("hidden", "off")
    eq(app.state()["hidden_shown"], False)


# ---------------------------------------------------------------- onglets et affichage

@test("onglets: nouveau, changer, fermer, dernier onglet")
def _():
    d = make("tabs", {"x/": ""})
    app.ok("goto", str(d))
    app.ok("tab", "new", str(d / "x"))
    s = app.state()
    eq((s["tab"], s["tabs"], s["location"]), (1, [str(d), str(d / "x")], str(d / "x")))
    app.ok("tab", "switch", "0")
    s = app.state()
    eq((s["tab"], s["location"]), (0, str(d)))
    app.ok("tab", "close", "1")
    eq(len(app.state()["tabs"]), 1)
    app.fails("tab", "close", containing="last tab")
    app.fails("tab", "switch", "5", containing="no such tab")


@test("affichage: liste/icônes, aperçu, tri")
def _():
    app.ok("view", "icons")
    eq(app.state()["view"], "icons")
    app.ok("view", "list")
    eq(app.state()["view"], "list")
    app.ok("preview", "on")
    eq(app.state()["preview"], True)
    app.ok("preview", "off")
    eq(app.state()["preview"], False)
    app.ok("sort", "size", "desc")
    eq(app.state()["sort"], "size desc")
    app.ok("sort", "size", "asc")
    eq(app.state()["sort"], "size asc")
    app.ok("sort", "name")
    eq(app.state()["sort"], "name asc")
    app.fails("sort", "nope", containing="usage")


# ---------------------------------------------------------------- opérations sur les fichiers

@test("copier/coller dans un autre dossier (l'original reste)")
def _():
    d = make("cp", {"a.txt": "alpha", "dst/": ""})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "copy")
    app.ok("goto", str(d / "dst"))
    app.ok("action", "paste")
    app.wait(lambda: (d / "dst" / "a.txt").exists(), what="fichier collé")
    eq((d / "dst" / "a.txt").read_text(), "alpha")
    assert (d / "a.txt").exists()


@test("couper/coller déplace")
def _():
    d = make("mv", {"a.txt": "alpha", "dst/": ""})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "cut")
    app.ok("goto", str(d / "dst"))
    app.ok("action", "paste")
    app.wait(lambda: (d / "dst" / "a.txt").exists() and not (d / "a.txt").exists(), what="fichier déplacé")


@test("presse-papiers: copier le chemin, le nom, la base, le dossier")
def _():
    d = make("clip", {"rapport.final.txt": ""})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/rapport.final.txt\n")
    clip = T / "clip" / "text_plain"
    for action, want in (("copy-path", str(d / "rapport.final.txt")), ("copy-name", "rapport.final.txt"), ("copy-stem", "rapport.final"), ("copy-parent", str(d))):
        app.ok("action", action)
        app.wait(lambda: clip.exists() and clip.read_text() == want, 3, f"{action} dans le presse-papiers")


@test("dupliquer")
def _():
    d = make("dup", {"a.txt": "alpha"})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "duplicate")
    app.wait(lambda: (d / "a copy.txt").exists(), what="copie")
    eq((d / "a copy.txt").read_text(), "alpha")


def conflict(name, answer, check):
    d = make(name, {"a.txt": "new", "dst/": ""})
    (d / "dst" / "a.txt").write_text("old")
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "copy")
    app.ok("goto", str(d / "dst"))
    app.ok("action", "paste")
    app.wait(lambda: app.state()["dialog"] == "conflict", what="dialogue de conflit")
    app.fails("action", "copy", containing="disabled")
    app.ok("dialog", answer)
    app.wait(lambda: app.state()["dialog"] == "" and not app.state()["tasks"], what="fin de l'opération")
    check(d / "dst")


@test("conflit de nom: remplacer (l'ancien va à la corbeille)")
def _():
    def check(dst):
        eq((dst / "a.txt").read_text(), "new")
        eq(names(dst), ["a.txt"])
    conflict("cf-replace", "replace", check)


@test("conflit de nom: garder les deux")
def _():
    def check(dst):
        eq((dst / "a.txt").read_text(), "old")
        eq(names(dst), ["a copy.txt", "a.txt"])
        eq((dst / "a copy.txt").read_text(), "new")
    conflict("cf-both", "both", check)


@test("conflit de nom: ignorer")
def _():
    def check(dst):
        eq((dst / "a.txt").read_text(), "old")
        eq(names(dst), ["a.txt"])
    conflict("cf-skip", "skip", check)


@test("conflit de nom: annuler")
def _():
    def check(dst):
        eq((dst / "a.txt").read_text(), "old")
        eq(names(dst), ["a.txt"])
    conflict("cf-cancel", "cancel", check)


@test("renommer par argument; refus si le nom existe")
def _():
    d = make("ren", {"a.txt": "", "b.txt": ""})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "rename", "z.txt")
    eq(names(d), ["b.txt", "z.txt"])
    eq(app.state()["selection"], [str(d / "z.txt")])
    app.fails("action", "rename", "b.txt", containing="")
    eq(names(d), ["b.txt", "z.txt"], "rien n'a changé")
    app.ok("select", stdin=f"{d}/b.txt\n{d}/z.txt\n")
    app.fails("action", "rename", "q.txt", containing="exactly one")


@test("nouveau dossier par argument")
def _():
    d = make("nf", {})
    app.ok("goto", str(d))
    app.ok("action", "new-folder", "projets")
    assert (d / "projets").is_dir(), names(d)
    eq(app.state()["selection"], [str(d / "projets")])


@test("corbeille puis annuler; vider la corbeille demande confirmation")
def _():
    d = make("trash", {"a.txt": "alpha", "b.txt": ""})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    app.ok("action", "trash")
    app.wait(lambda: not (d / "a.txt").exists(), what="fichier à la corbeille")
    trash = T / "home" / ".local" / "share" / "Trash" / "files"
    assert (trash / "a.txt").exists(), names(trash) if trash.exists() else "pas de corbeille"
    app.ok("action", "undo")
    app.wait(lambda: (d / "a.txt").exists(), what="restauration")
    eq((d / "a.txt").read_text(), "alpha")
    # Dans la corbeille: vider demande confirmation; annuler ne supprime rien
    app.ok("select", stdin=f"{d}/b.txt\n")
    app.ok("action", "trash")
    app.wait(lambda: (trash / "b.txt").exists())
    app.ok("goto", str(trash))
    s = app.state()
    assert s["in_trash"], s
    app.ok("action", "empty-trash")
    eq(app.state()["dialog"], "confirm")
    app.ok("dialog", "cancel")
    assert (trash / "b.txt").exists()
    app.ok("action", "empty-trash")
    app.ok("dialog", "accept")
    app.wait(lambda: not (trash / "b.txt").exists(), what="corbeille vidée")


@test("compresser (zip, 7z, tar.gz) puis extraire")
def _():
    d = make("arc", {"a.txt": "alpha"})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    for n in ("one.zip", "two.7z", "three.tar.gz"):
        app.ok("action", "compress", n)
        app.wait(lambda n=n: (d / n).exists() and not app.state()["tasks"], 15, f"archive {n}")
    eq(sorted(names(d)), ["a.txt", "one.zip", "three.tar.gz", "two.7z"])
    app.ok("select", stdin=f"{d}/one.zip\n")
    app.ok("action", "extract")
    app.wait(lambda: len(names(d)) > 4 and not app.state()["tasks"], 15, "extraction")
    extracted = [p for p in names(d) if p not in ("a.txt", "one.zip", "three.tar.gz", "two.7z")]
    # a.txt existe déjà à côté de l'archive: l'extraction prend le premier nom libre
    eq(extracted, ["a 2.txt"], "fichier extrait")
    eq((d / "a 2.txt").read_text(), "alpha")


# ---------------------------------------------------------------- dialogues, résultats, recherche

@test("dialogues: motif, compresser, infos, À propos s'ouvrent, bloquent les raccourcis et se ferment")
def _():
    d = make("dlg", {"a.txt": ""})
    app.ok("goto", str(d))
    app.ok("select", stdin=f"{d}/a.txt\n")
    for action, name in (("select-matching", "match"), ("compress", "compress"), ("info", "info"), ("about", "about")):
        app.ok("action", action)
        app.wait(lambda name=name: app.state()["dialog"] == name, 3, f"dialogue {name}")
        app.fails("action", "copy", containing="disabled")
        app.ok("dialog", "cancel")
        app.wait(lambda: app.state()["dialog"] == "", 3, "dialogue fermé")
    app.ok("action", "info")
    app.wait(lambda: app.state()["dialog"] == "info", 3)
    app.fails("dialog", "accept", containing="no default button")
    app.ok("dialog", "cancel")


@test("résultats: show remplace le dossier, goto les ferme")
def _():
    d = make("res", {"a.txt": "", "sub/": ""})
    (d / "sub" / "b.txt").write_text("")
    app.ok("goto", str(d))
    app.ok("show", "Mes résultats", stdin=f"{d}/a.txt\n{d}/sub/b.txt\n")
    s = app.state()
    eq(s["results"], "Mes résultats")
    app.ok("goto", str(d))
    eq(app.state()["results"], "", "résultats fermés")


@test("recherche: le filtre est dans l'état")
def _():
    d = make("flt", {"alpha.txt": "", "beta.txt": ""})
    app.ok("goto", str(d))
    eq(app.ok("action", "search", "alp")["filter"], "alp")
    eq(app.state()["filter"], "alp")


def main():
    global app
    app = App()
    failed = 0
    for i, (name, fn) in enumerate(results, 1):
        try:
            fn()
            print(f"ok {i} - {name}")
        except Exception as e:  # noqa: BLE001 - tout échec est un résultat de test, pas une exception du banc
            failed += 1
            print(f"not ok {i} - {name}")
            print("#   " + str(e).replace("\n", "\n#   "))
        sys.stdout.flush()
        # Une fenêtre qui meurt rend les cas suivants sans objet
        if app.proc.poll() is not None:
            print(f"not ok - fili-file s'est arrêté (code {app.proc.returncode}); journal:")
            print("#   " + (T / "app.log").read_text()[-1500:].replace("\n", "\n#   "))
            failed += 1
            break
        # Remet la fenêtre à l'état neutre pour le cas suivant
        try:
            if app.state()["dialog"]:
                app.ctl("dialog", "cancel")
            app.ctl("hidden", "off")
            app.ctl("goto", str(DATA))
        except Exception:  # noqa: BLE001
            pass
    app.proc.terminate()
    print(f"# fin: {failed} échec(s) sur {len(results)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
