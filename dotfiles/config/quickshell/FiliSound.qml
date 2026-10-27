pragma Singleton
// fili-sound: sons de la fili-shell (notification: brand/sound/notification.wav; chargeur: thème freedesktop; pw-play): nouvelle notification (FiliNotification) et
// chargeur branché (événements du noyau sur power_supply, lus par bar-stats: rien ne sonde).
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
    readonly property string brandDir: Quickshell.env("HOME") + "/.local/share/filigrane/sound"
    readonly property string themeDir: "/usr/share/sounds/freedesktop/stereo/"

    // Son de la marque (brand/sound, lié dans ~/.local/share/filigrane/sound) ou, à défaut, du thème freedesktop
    function play(name) {
        if (FiliTheme.testing)
            FiliTheme.ran = FiliTheme.ran.concat(["sound " + name]);
        else
            Quickshell.execDetached(["sh", "-c", 'f="$1/$2.wav"; [ -r "$f" ] || f="$3$2.oga"; exec pw-play "$f"', "sh", brandDir, name, themeDir]);
    }
    // Applications dont les notifications restent muettes (niri: « Screenshot captured », sans intérêt)
    readonly property var silentApps: ["niri"]
    // Une nouvelle notification: un son, pas un par notification d'une rafale
    function notified(app) {
        if (!notify || quiet.running || silentApps.indexOf(app) >= 0)
            return;
        play("notification");
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

    // Réglages lus au démarrage, sans processus (fichier absent: activé)
    FileView {
        path: FiliTheme.testing ? "" : snd.dir + "/notify"
        printErrors: false
        onLoaded: snd.notify = text().trim() !== "off"
    }
    FileView {
        path: FiliTheme.testing ? "" : snd.dir + "/plug"
        printErrors: false
        onLoaded: snd.plug = text().trim() !== "off"
    }
    // État du chargeur (`ac 0|1` de bar-stats, voir FiliShell): au démarrage (sans son), puis à chaque changement
    property bool acKnown: false
    Connections {
        target: FiliShell
        enabled: !FiliTheme.testing
        function onCommand(target, action, args) {
            if (target !== "ac")
                return;
            if (snd.acKnown)
                snd.acEvent(action === "1");
            else
                snd.ac = action === "1";
            snd.acKnown = true;
        }
    }
}
