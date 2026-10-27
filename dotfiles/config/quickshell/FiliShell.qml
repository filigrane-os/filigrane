pragma Singleton
// fili-shell: canal de commandes du shell. Une ligne par commande dans le tuyau nommé $XDG_RUNTIME_DIR/fili-shell,
// écrite par le client ~/.local/bin/fili-shell ou les scripts:
//   bar refresh N...                      rafraîchit les modules de la fili-bar abonnés à N
//   notification dnd on|off|toggle | dismiss-all | dismiss RÉSUMÉ | center | history RÉPONSE
//   launcher open OPTIONS.json RÉPONSE | launcher close RÉPONSE      (fili-launcher)
//   panel NOM | close                    ouvre/ferme un fili-panel
//   reload
// Lu par bar-stats (apps/bar-stats, seul processus résident du shell), qui recopie ces lignes et y mêle les siennes:
//   stat NOM JSON                         module de la fili-bar (cpu, mem, temp, disk, net, remote, air, vpn, backup, display), voir BarScript
//   ac 0|1                                chargeur (FiliSound)
//   info SUJET JSON                       fiche demandée par request("info SUJET") sur son entrée standard (FiliInfo)
// Sans bar-stats (apps/ non compilé): un `cat` ouvert en lecture-écriture. Les réponses partent vers le tuyau RÉPONSE.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: shell
    readonly property string fifo: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili-shell"

    // Un seul panneau de la fili-bar ouvert à la fois (fili-panel, fili-calendar, fili-notification-center): celui qui
    // s'ouvre l'annonce ("panel", "calendar", "center"), les autres se ferment
    signal popupOpened(string who)
    // Un fili-panel est ouvert (posé par FiliPanel): la fili-tooltip ne s'affiche pas
    property bool panelOpen: false
    // Instant de la dernière fermeture d'un fili-panel (ms): la fili-tooltip attend un peu après, sinon elle surgit
    // aussitôt sous la souris et on croirait à un bug
    property double panelClosedAt: 0
    // Le fili-notification-center est ouvert (posé par FiliNotification)
    property bool centerOpen: false
    // Un panneau de la barre est ouvert (fili-panel ou centre de notifications): ni fiche ni double clic
    readonly property bool anyOpen: panelOpen || centerOpen
    onAnyOpenChanged: if (!anyOpen) panelClosedAt = Date.now()

    // bar refresh N
    signal refresh(int n)
    // notification ..., menu ..., reload: élément visé, action et arguments
    signal command(string target, string action, var args)
    // stat NOM JSON: nouvel état d'un module; dernier état gardé pour les barres créées ensuite (écran branché)
    signal stat(string name, var data)
    readonly property var stats: ({})
    // info SUJET JSON: réponse à request("info SUJET")
    signal info(string topic, var data)

    // Requête à bar-stats (entrée standard), sans lancer de processus; ignorée sans bar-stats
    function request(line) {
        if (reader.running)
            reader.write(line + "\n");
    }

    // Écrit une réponse dans le tuyau de la requête
    function reply(path, text) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", text, path]);
    }

    Process {
        id: reader
        running: true
        // Tuyau recréé à chaque démarrage, lecteur tué avec Quickshell (sinon un ancien lecteur volerait les commandes)
        command: ["sh", "-c", 'f="$1"; rm -f "$f"; mkfifo -m 600 "$f" || exit 1; [ -x "$2/bar-stats" ] && exec "$2/bar-stats" "$f"; exec setpriv --pdeathsig TERM cat 0<>"$f"',
            "sh", shell.fifo, FiliTheme.bin]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("stat ") || line.startsWith("info ")) {
                    const j = line.indexOf(" ");
                    const i = line.indexOf(" ", j + 1);
                    try {
                        const data = JSON.parse(line.slice(i + 1));
                        if (line.startsWith("stat ")) {
                            shell.stats[line.slice(j + 1, i)] = data;
                            shell.stat(line.slice(j + 1, i), data);
                        } else {
                            shell.info(line.slice(j + 1, i), data);
                        }
                    } catch (e) {}
                    return;
                }
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
