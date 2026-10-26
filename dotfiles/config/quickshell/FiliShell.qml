pragma Singleton
// fili-shell: canal de commandes du shell. Une ligne par commande dans le tuyau nommé $XDG_RUNTIME_DIR/fili-shell,
// écrite par le client ~/.local/bin/fili-shell, bar-stats watch ou les scripts:
//   bar refresh N...                      rafraîchit les modules de la fili-bar abonnés à N
//   notification dnd on|off|toggle | dismiss-all | dismiss RÉSUMÉ | center | history RÉPONSE
//   launcher open OPTIONS.json RÉPONSE | launcher close RÉPONSE      (fili-launcher)
//   reload
// Lu par un `cat` ouvert en lecture-écriture (jamais de fin de fichier). Les réponses partent vers le tuyau RÉPONSE.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: shell
    readonly property string fifo: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili-shell"

    // bar refresh N
    signal refresh(int n)
    // notification ..., menu ..., reload: élément visé, action et arguments
    signal command(string target, string action, var args)

    // Écrit une réponse dans le tuyau de la requête
    function reply(path, text) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", text, path]);
    }

    Process {
        id: reader
        running: true
        // Tuyau recréé à chaque démarrage, lecteur tué avec Quickshell (sinon un ancien lecteur volerait les commandes)
        command: ["sh", "-c", 'f="$1"; rm -f "$f"; mkfifo -m 600 "$f" && exec setpriv --pdeathsig TERM cat 0<>"$f"', "sh", shell.fifo]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ");
                const target = parts.shift();
                const action = parts.shift() ?? "";
                if (target === "bar" && action === "refresh")
                    for (const n of parts)
                        shell.refresh(parseInt(n));
                else if (target)
                    shell.command(target, action, parts);
            }
        }
        onExited: again.start()
    }
    Timer {
        id: again
        interval: 1000
        onTriggered: reader.running = true
    }
}
