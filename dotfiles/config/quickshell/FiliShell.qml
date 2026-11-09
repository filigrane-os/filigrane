pragma Singleton
// fili-shell: command channel of the shell. One line per command in the named pipe $XDG_RUNTIME_DIR/fili-shell,
// written by the client ~/.local/bin/fili-shell or by the scripts:
// bar refresh N...                      refreshes the fili-bar modules subscribed to N
// notification dnd on|off|toggle | dismiss-all | dismiss SUMMARY | center | history REPLY
// launcher open OPTIONS.json REPLY | launcher close REPLY      (fili-launcher)
// panel NAME | close                   opens/closes a fili-panel
// appmenu toggle | close               menu of the active application from the keyboard (AppMenu, Mod+F10)
// chat [ACTION]                         fili-chat drawer (FiliChat, Mod+Y): toggle (default), show, close, new, sessions, rename, stop, allow, deny, float, dock... (FiliChat.act)
// hotkeys toggle | about toggle         shortcuts window (FiliHotkeys), "About" (FiliAbout)
// settings [PAGE]                       Settings window (FiliSettings), on the page PAGE (display...)
// lang reload                           re-reads the language chosen with fili-lang (FiliI18n)
// reload
// Read by bar-stats (apps/bar-stats, the only resident process of the shell), which copies these lines and mixes in its own:
// stat NAME JSON                        fili-bar module (cpu, mem, temp, disk, net, remote, air, vpn, backup, display), see BarScript
// ac 0|1                                charger (FiliSound)
// info TOPIC JSON                       card requested by request("info TOPIC") on its standard input (FiliInfo)
// Without bar-stats (apps/ not compiled): a `cat` opened read-write. The replies go to the REPLY pipe.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: shell
    readonly property string fifo: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili-shell"

    // A single fili-bar panel open at a time (fili-panel, fili-calendar, fili-notification-center): the one that
    // opens announces it ("panel", "calendar", "center"), the others close
    signal popupOpened(string who)
    // A fili-panel is open (set by FiliPanel): the fili-tooltip is not shown
    property bool panelOpen: false
    // Instant of the last closing of a fili-panel (ms): the fili-tooltip waits a little after it, otherwise it pops up
    // at once under the mouse and looks like a bug
    property double panelClosedAt: 0
    // The fili-notification-center is open (set by FiliNotification)
    property bool centerOpen: false
    // A bar panel is open (fili-panel or notification center): neither card nor double click
    readonly property bool anyOpen: panelOpen || centerOpen
    // Panels driven from the keyboard (Mod+A, arrows...): outline of the chosen item (FocusRing); forgotten on closing
    property bool keyNav: false
    onAnyOpenChanged: {
        if (!anyOpen) {
            panelClosedAt = Date.now();
            keyNav = false;
        }
    }

    // bar refresh N
    signal refresh(int n)
    // notification ..., menu ..., reload: target, action and arguments
    signal command(string target, string action, var args)
    // stat NAME JSON: new state of a module; last state kept for the bars created later (screen plugged in)
    signal stat(string name, var data)
    readonly property var stats: ({})
    // info TOPIC JSON: reply to request("info TOPIC")
    signal info(string topic, var data)

    // Request to bar-stats (standard input), without starting a process; ignored without bar-stats
    function request(line) {
        if (reader.running)
            reader.write(line + "\n");
    }

    // Write a reply to the pipe of the request
    function reply(path, text) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", text, path]);
    }

    Process {
        id: reader
        running: true
        // Pipe recreated at every start, reader killed with Quickshell (otherwise an old reader would steal the commands)
        command: ["sh", "-c", 'f="$1"; rm -f "$f"; mkfifo -m 600 "$f" || exit 1; for d in "$2" /usr/bin; do [ -x "$d/bar-stats" ] && exec "$d/bar-stats" "$f"; done; exec setpriv --pdeathsig TERM cat 0<>"$f"',
            "sh", shell.fifo, FiliTheme.bin]
        // Translation catalog of bar-stats: the one of the fili-shell (FiliI18n)
        environment: ({ FILI_I18N: Quickshell.shellDir + "/i18n" })
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
    // Language change (fili-lang): bar-stats restarted (it reads the language at start), script modules re-read
    Connections {
        target: FiliI18n
        function onLangChanged() {
            reader.running = false;
            for (let n = 1; n <= 30; n++)
                shell.refresh(n);
        }
    }
}
