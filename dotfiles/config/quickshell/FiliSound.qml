pragma Singleton
// fili-sound: sounds of the fili-shell (notification: brand/sound/notification.wav; charger: freedesktop theme; pw-play): new notification (FiliNotification) and
// charger plugged in (kernel events on power_supply, read by bar-stats: nothing polls).
// Each one is turned on and off in the fili-notification-center; setting kept in ~/.local/state/fili-sound/ (one
// file per sound, "off" = muted; absent = on).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: snd
    property bool notify: true
    property bool plug: true
    // Charger plugged in (read from /sys/class/power_supply/*/online)
    property bool ac: false
    readonly property string dir: Quickshell.env("HOME") + "/.local/state/fili-sound"
    readonly property string brandDir: Quickshell.env("HOME") + "/.local/share/filigrane/sound"
    readonly property string themeDir: "/usr/share/sounds/freedesktop/stereo/"

    // Brand sound (brand/sound, linked into ~/.local/share/filigrane/sound) or, failing that, from the freedesktop theme
    function play(name) {
        if (FiliTheme.testing)
            FiliTheme.ran = FiliTheme.ran.concat(["sound " + name]);
        else
            Quickshell.execDetached(["sh", "-c", 'f="$1/$2.wav"; [ -r "$f" ] || f="$3$2.oga"; exec pw-play "$f"', "sh", brandDir, name, themeDir]);
    }
    // Applications whose notifications stay silent (niri: "Screenshot captured", of no interest)
    readonly property var silentApps: ["niri"]
    // A new notification: one sound, not one per notification of a burst
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
    // New state of the charger: sound only when plugged in
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

    // Settings read at start, without a process (missing file: on)
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
    // State of the charger (`ac 0|1` of bar-stats, see FiliShell): at start (silent), then at every change
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
