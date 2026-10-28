// fili-panel moniteur: charge, mémoire, disque, température et plus gros processus (FiliInfo monitor, sans processus), tests de débit
// réseau et de disque (fili-speedtest), accès à htop
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: view
    spacing: 4
    property string running: ""
    property var results: ({})

    function test(kind) {
        if (running)
            return;
        running = kind;
        speed.command = [FiliTheme.bin + "/fili-speedtest", kind];
        speed.running = true;
    }
    Process {
        id: speed
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = Object.assign({}, view.results);
                    r[view.running] = JSON.parse(text);
                    view.results = r;
                } catch (e) {}
                view.running = "";
            }
        }
    }
    Timer { running: true; repeat: true; interval: 2000; onTriggered: info.refresh() }

    PanelInfo { id: info; title: true; topic: "monitor" }
    PanelSection { text: "TESTS" }
    PanelButton {
        objectName: "test-net"
        glyph: ""
        label: view.running === "net" ? FiliI18n.tr("Speed test running…") : FiliI18n.tr("Network speed test")
        detail: view.results.net ? FiliI18n.tr("%1 ↓ %2 ↑ Mbit/s, ping %3 ms", Math.round(view.results.net.down_mbps), Math.round(view.results.net.up_mbps), view.results.net.ping_ms) : FiliI18n.tr("~35 MB")
        onClicked: view.test("net")
    }
    PanelButton {
        objectName: "test-disk"
        glyph: ""
        label: view.running === "disk" ? FiliI18n.tr("Disk test running…") : FiliI18n.tr("Disk speed test")
        detail: view.results.disk ? FiliI18n.tr("%1 write · %2 read MB/s", view.results.disk.write_mbps, view.results.disk.read_mbps) : FiliI18n.tr("512 MB")
        onClicked: view.test("disk")
    }
    PanelButton {
        Layout.topMargin: 4
        glyph: ""
        label: FiliI18n.tr("Full monitor (htop)")
        dim: true
        onClicked: { FiliPanel.close(); FiliTheme.run(FiliTheme.bin + "/bar-tui htop"); }
    }
}
