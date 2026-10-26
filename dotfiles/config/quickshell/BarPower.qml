// Batterie (sysfs, UPower absent): capacité et état relus chaque minute; avertissement <= 25 %, critique <= 10 %
import QtQuick
import Quickshell.Io

BarItem {
    id: batt
    readonly property string dir: "/sys/class/power_supply/BAT0"
    property int capacity: -1
    property string status: ""
    readonly property bool charging: status === "Charging" || status === "Full"

    text: capacity < 0 ? "" : (status === "Charging" ? "" : ["", "", "", "", ""][Math.min(4, Math.floor(capacity / 20))]) + " " + capacity + "%"
    color: status === "Charging" ? FiliTheme.voile : capacity <= 10 ? FiliTheme.cendre : capacity <= 25 ? FiliTheme.sable : FiliTheme.brume
    tip: status ? status + ", " + capacity + "%" : ""

    FileView { id: cap; path: batt.dir + "/capacity"; blockLoading: true; printErrors: false }
    FileView { id: st; path: batt.dir + "/status"; blockLoading: true; printErrors: false }
    function read() {
        cap.reload();
        st.reload();
        const c = parseInt(cap.text());
        batt.capacity = isNaN(c) ? -1 : c;
        batt.status = st.text().trim();
    }
    Component.onCompleted: read()
    Timer {
        running: true
        repeat: true
        interval: 60000
        onTriggered: batt.read()
    }
}
