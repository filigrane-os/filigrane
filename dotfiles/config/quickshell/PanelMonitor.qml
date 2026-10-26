// fili-panel moniteur: charge, mémoire, disque, température et plus gros processus (fili-info monitor), tests de débit
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

    PanelInfo { id: info; title: true; cmd: FiliTheme.bin + "/fili-info monitor" }
    PanelSection { text: "TESTS" }
    PanelButton {
        objectName: "test-net"
        glyph: ""
        label: view.running === "net" ? "Test de débit en cours…" : "Test de débit réseau"
        detail: view.results.net ? Math.round(view.results.net.down_mbps) + " ↓ " + Math.round(view.results.net.up_mbps) + " ↑ Mbit/s, ping " + view.results.net.ping_ms + " ms" : "~35 Mo"
        onClicked: view.test("net")
    }
    PanelButton {
        objectName: "test-disk"
        glyph: ""
        label: view.running === "disk" ? "Test du disque en cours…" : "Test de vitesse du disque"
        detail: view.results.disk ? view.results.disk.write_mbps + " écr. · " + view.results.disk.read_mbps + " lect. Mo/s" : "512 Mo"
        onClicked: view.test("disk")
    }
    PanelButton {
        Layout.topMargin: 4
        glyph: ""
        label: "Moniteur complet (htop)"
        dim: true
        onClicked: { FiliPanel.close(); FiliTheme.run(FiliTheme.bin + "/bar-tui htop"); }
    }
}
