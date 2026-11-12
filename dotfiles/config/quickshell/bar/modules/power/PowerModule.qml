// Battery (sysfs, no UPower): capacity and state re-read every 15 s; warning <= 25 %, critical <= 10 %.
// When the power source changes (plugged / unplugged) the idle delays of the new source are applied (bar-toggle idle refresh).
// Click = power panel, right click = system menu (lock, sleep, quit...)
import QtQuick
import Quickshell.Io
import qs
import qs.bar

BarItem {
    id: batt
    objectName: "power"
    panel: "power"
    panelSource: Qt.resolvedUrl("PowerPanel.qml")
    tipInfo: "power"
    hover.onLeftClicked: togglePanel()
    hover.rclick: "setsid -f " + FiliTheme.bin + "/menu system"
    readonly property string dir: "/sys/class/power_supply/BAT0"
    property int capacity: -1
    property string status: ""
    readonly property bool charging: status === "Charging" || status === "Full"
    // On battery = discharging; anything else with a battery is plugged in
    readonly property bool onBattery: status === "Discharging"
    property string lastSource: ""
    onOnBatteryChanged: {
        if (status === "")
            return;
        const src = onBattery ? "battery" : "ac";
        if (lastSource !== "" && src !== lastSource)
            FiliTheme.run(FiliTheme.bin + "/bar-toggle idle refresh");
        lastSource = src;
    }

    text: capacity < 0 ? "" : (status === "Charging" ? "" : ["", "", "", "", ""][Math.min(4, Math.floor(capacity / 20))]) + " " + capacity + "%"
    color: status === "Charging" ? FiliTheme.barAccent : capacity <= 10 ? FiliTheme.cendre : capacity <= 25 ? FiliTheme.barWarn : FiliTheme.barText
    tip: status ? { title: FiliI18n.tr("Battery"), rows: [[FiliI18n.tr("Level"), capacity + " %"], [FiliI18n.tr("State"), { Charging: FiliI18n.tr("Charging"), Discharging: FiliI18n.tr("On battery"), Full: FiliI18n.tr("Full"), "Not charging": FiliI18n.tr("Plugged in, charging paused") }[status] ?? status]] } : ""

    FileView { id: cap; path: batt.dir + "/capacity"; blockLoading: true; printErrors: false }
    FileView { id: st; path: batt.dir + "/status"; blockLoading: true; printErrors: false }
    function read() {
        cap.reload();
        st.reload();
        const c = parseInt(cap.text());
        batt.capacity = isNaN(c) ? -1 : c;
        batt.status = st.text().trim();
        if (batt.lastSource === "" && batt.status !== "")
            batt.lastSource = batt.onBattery ? "battery" : "ac";
    }
    Component.onCompleted: read()
    Timer {
        running: true
        repeat: true
        interval: 15000
        onTriggered: batt.read()
    }
}
