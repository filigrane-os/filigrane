// Indicators and toggles: screen recording, SSH, airplane mode, VPN, watch reports, updates
import QtQuick
import qs
import qs.bar

BarModule {
    Row {
        // Screen recording: visible only while recording, click = stop (start it from menu › Capture)
        BarScript { objectName: "rec"; title: FiliI18n.tr("Recording"); cmd: FiliTheme.bin + "/bar-status rec"; signal: 11; color: FiliTheme.cendre; click: FiliTheme.bin + "/bar-toggle rec" }
        // Incoming SSH session, airplane mode (click = turn off), VPN: written by bar-stats when the state changes
        BarScript { objectName: "remote"; title: "SSH"; stat: "remote"; color: FiliTheme.cendre }
        BarScript { objectName: "air"; title: FiliI18n.tr("Airplane mode"); stat: "air"; color: FiliTheme.sable; click: FiliTheme.bin + "/bar-toggle air" }
        BarScript { objectName: "vpn"; title: "VPN"; stat: "vpn" }
        // Unread watch reports, click = read them
        BarScript { objectName: "news"; title: FiliI18n.tr("News"); cmd: FiliTheme.bin + "/bar-news"; interval: 3600; signal: 15; color: FiliTheme.brume2; click: FiliTheme.bin + "/bar-news open" }
        // xbps updates (hidden when there are none), click = update in a floating terminal
        BarScript { objectName: "update"; title: FiliI18n.tr("Updates"); cmd: FiliTheme.bin + "/bar-update"; interval: 3600; signal: 16; color: FiliTheme.sable; click: FiliTheme.bin + "/bar-update run" }
    }
}
