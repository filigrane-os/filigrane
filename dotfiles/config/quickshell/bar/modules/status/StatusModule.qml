// Indicators merged into one icon: screen recording, SSH, airplane mode, VPN, updates. The icon is the most urgent
// active indicator (a count when several are active) and shows nothing while none is; click = the status panel, one
// row per active indicator with its action (stop the recording, leave airplane mode, update).
import QtQuick
import qs
import qs.bar

BarModule {
    id: status
    panel: "status"
    panelSource: Qt.resolvedUrl("StatusPanel.qml")
    anchorItem: summary

    // The indicators keep running (state, scripts) but are never drawn: the summary replaces them
    Item {
        visible: false
        // Screen recording: visible only while recording, click = stop (start it from menu › Capture)
        BarScript { id: rec; objectName: "rec"; title: FiliI18n.tr("Recording"); cmd: FiliTheme.bin + "/bar-status rec"; signal: 11; color: FiliTheme.cendre; click: FiliTheme.bin + "/bar-toggle rec" }
        // Incoming SSH session, airplane mode (click = turn off), VPN: written by bar-stats when the state changes
        BarScript { id: remote; objectName: "remote"; title: "SSH"; stat: "remote"; color: FiliTheme.cendre }
        BarScript { id: air; objectName: "air"; title: FiliI18n.tr("Airplane mode"); stat: "air"; color: FiliTheme.barWarn; click: FiliTheme.bin + "/bar-toggle air" }
        BarScript { id: vpn; objectName: "vpn"; title: "VPN"; stat: "vpn" }
        // xbps updates (hidden when there are none), click = update in a floating terminal
        BarScript { id: upd; objectName: "update"; title: FiliI18n.tr("Updates"); cmd: FiliTheme.bin + "/bar-update"; interval: 3600; signal: 16; color: FiliTheme.barWarn; click: FiliTheme.bin + "/bar-update run" }
    }

    // Most urgent first
    readonly property var all: [rec, remote, air, vpn, upd]
    readonly property var active: all.filter(i => i.text !== "")
    readonly property var rows: active.map(i => ({
        key: i.objectName,
        glyph: FiliTheme.glyph(i.text),
        title: i.title,
        detail: FiliTheme.value(i.text),
        click: i.click ?? ""
    }))
    onRowsChanged: BarState.statusRows = rows

    BarRow {
        BarScript {
            id: summary
            panelNeedsVisible: true
            objectName: "status"
            title: FiliI18n.tr("Status")
            hint: FiliI18n.tr("click: details")
            colors: ({ rec: FiliTheme.cendre, remote: FiliTheme.cendre, air: FiliTheme.barWarn, vpn: FiliTheme.barText, update: FiliTheme.barWarn })
            value: {
                const a = status.active;
                if (a.length === 0)
                    return { text: "" };
                const top = a[0];
                const icon = FiliTheme.glyph(top.text);
                return {
                    text: icon + (a.length > 1 ? " " + a.length : ""),
                    "class": top.objectName,
                    tooltip: { title: FiliI18n.tr("Status"), rows: a.map(i => [i.title, FiliTheme.value(i.text) || FiliI18n.tr("active")]), hint: FiliI18n.tr("click: details") }
                };
            }
            hover.onLeftClicked: status.togglePanel(hover)
        }
    }
}
