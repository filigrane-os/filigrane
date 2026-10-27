pragma Singleton
// fili-sound: sons de la fili-shell (thème freedesktop, joués par pw-play): nouvelle notification (FiliNotification) et
// chargeur branché (événements du noyau sur power_supply, via `udevadm monitor`: rien ne sonde, le processus dort).
// Chacun s'active et se coupe dans le fili-notification-center; réglage gardé dans ~/.local/state/fili-sound/ (un
// fichier par son, "off" = coupé; absent = activé).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: snd
    property bool notify: true
    property bool plug: true
    // Chargeur branché (lu dans /sys/class/power_supply/*/online)
    property bool ac: false
    readonly property string dir: Quickshell.env("HOME") + "/.local/state/fili-sound"
    readonly property string themeDir: "/usr/share/sounds/freedesktop/stereo/"

    function play(name) {
        if (FiliTheme.testing)
            FiliTheme.ran = FiliTheme.ran.concat(["sound " + name]);
        else
            Quickshell.execDetached(["pw-play", themeDir + name + ".oga"]);
    }
    // Une nouvelle notification: un son, pas un par notification d'une rafale
    function notified() {
        if (!notify || quiet.running)
            return;
        play("message-new-instant");
        quiet.start();
    }
    function set(which, on) {
        if (which === "notify")
            notify = on;
        else
            plug = on;
        if (!FiliTheme.testing)
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && echo "$3" > "$1/$2"', "sh", dir, which, on ? "on" : "off"]);
    }
    // Nouvel état du chargeur: son seulement au branchement
    function acEvent(online) {
        const plugged = online && !ac;
        ac = online;
        if (plugged && plug)
            play("power-plug");
    }

    Timer {
        id: quiet
        interval: 1000
    }

    Process {
        id: prefs
        running: !FiliTheme.testing
        command: ["sh", "-c", 'for k in notify plug; do printf "%s=%s\\n" "$k" "$(cat "$1/$k" 2>/dev/null)"; done', "sh", snd.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                snd.notify = text.indexOf("notify=off") < 0;
                snd.plug = text.indexOf("plug=off") < 0;
            }
        }
    }
    // État du chargeur: une fois au démarrage (sans son), puis à chaque événement power_supply
    Process {
        id: acRead
        command: ["sh", "-c", "cat /sys/class/power_supply/A*/online 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: snd.acEvent(text.trim() === "1")
        }
    }
    Process {
        id: acInit
        running: !FiliTheme.testing
        command: acRead.command
        stdout: StdioCollector {
            onStreamFinished: snd.ac = text.trim() === "1"
        }
    }
    Process {
        id: events
        running: !FiliTheme.testing
        command: ["udevadm", "monitor", "--kernel", "--subsystem-match=power_supply"]
        stdout: SplitParser {
            // « KERNEL[…] change /devices/…/ADP1 (power_supply) »: la batterie change souvent, elle ne compte pas
            onRead: line => {
                if (line.indexOf("(power_supply)") > 0 && line.indexOf("BAT") < 0)
                    acRead.running = true;
            }
        }
        onExited: retry.start()
    }
    Timer {
        id: retry
        interval: 5000
        onTriggered: events.running = true
    }
}
