// Commandes externes (fili-shell, bar-stats watch, scripts): une ligne par commande dans le tuyau nommé
// $XDG_RUNTIME_DIR/filigrane-shell, lu par un `cat` ouvert en lecture-écriture (jamais de fin de fichier).
// Remplace les signaux temps réel de Waybar et makoctl. Les réponses partent vers le tuyau donné par la requête.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: control
    readonly property string fifo: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/filigrane-shell"

    // signal N: rafraîchir les modules abonnés à N (ex-`pkill -RTMIN+N waybar`)
    signal refresh(int n)
    // Autres commandes: nom et arguments
    signal command(string name, var args)

    // Écrit une réponse dans le tuyau de la requête
    function reply(path, text) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", text, path]);
    }

    Process {
        id: reader
        running: true
        // Tuyau recréé à chaque démarrage, lecteur tué avec Quickshell (sinon un ancien lecteur volerait les commandes)
        command: ["sh", "-c", 'f="$1"; rm -f "$f"; mkfifo -m 600 "$f" && exec setpriv --pdeathsig TERM cat 0<>"$f"', "sh", control.fifo]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ");
                const name = parts.shift();
                if (name === "signal")
                    control.refresh(parseInt(parts[0]));
                else if (name)
                    control.command(name, parts);
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
