// Settings page "Firewall" (fili-settings): what may connect to this computer from the network. Incoming connections are
// refused unless allowed here or answering something this machine started; outgoing traffic is free. The settings are the
// ones of ~/.config/filigrane/firewall.toml (this page follows the file, FileView): a switch to filter or not, three
// presets (ping, device discovery, LocalSend) and the ports opened by hand, each for the local network only or for
// anywhere. Every change goes through the `fili-firewall` command, which has the rules checked and loaded at once by
// fili-firewall-apply (the only part run as root, through polkit: the authentication window of the fili-shell asks for the
// password or a fingerprint); when the rules or the authentication are refused nothing changes and the reason is shown here.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    // 8 between two controls and between a section title and its first control (tokens.md); groups of rows have 12
    spacing: FiliTheme.space2
    readonly property string cli: FiliTheme.bin + "/fili-firewall"
    // Settings read from the file (the defaults when the file does not say)
    property bool enabled: true
    property var presets: ({ ping: true, mdns: true, localsend: true })
    // [{ proto, port, scope, name }], in the order of the file
    property var ports: []
    // Last message of a refused change
    property string error: ""
    // Form of a new port
    property string newProto: "tcp"
    property string newPort: ""
    property string newScope: "lan"
    property string newName: ""
    // The name says why the port is open; fili-firewall refuses a quote, a backslash, a comma, a hash and brackets
    readonly property bool nameBad: /["\\,#\[\]]/.test(newName) || newName.length > 60
    readonly property bool portBad: newPort !== "" && !(/^[0-9]{1,5}$/.test(newPort) && Number(newPort) >= 1 && Number(newPort) <= 65535)
    readonly property bool canAdd: newPort !== "" && !portBad && !nameBad

    // The presets: id, title, what it does
    readonly property var presetList: [
        { id: "ping", label: FiliI18n.tr("Answer pings"), detail: FiliI18n.tr("Other machines can check that this one is up. Five a second at most.") },
        { id: "mdns", label: FiliI18n.tr("Device discovery"), detail: FiliI18n.tr("Lets Chromium find Chromecasts and other devices on the network.") },
        { id: "localsend", label: FiliI18n.tr("Receive files (LocalSend)"), detail: FiliI18n.tr("Lets fili-share receive files, from the local network only.") }
    ]

    function load(text) {
        const p = FiliTheme.parseToml(text)[""] ?? {};
        enabled = p.enabled !== "false";
        presets = { ping: p.ping !== "false", mdns: p.mdns !== "false", localsend: p.localsend !== "false" };
        ports = (Array.isArray(p.ports) ? p.ports : []).map(e => e.split(":")).filter(a => a.length >= 3).map(a => ({ proto: a[0], port: a[1], scope: a[2], name: a.slice(3).join(":") }));
    }
    // Runs the command; its error message, if any, is shown. In the tests the command is only recorded.
    function fw(args) {
        error = "";
        if (FiliTheme.testing) {
            FiliTheme.run(cli + " " + args);
            return;
        }
        job.command = ["sh", "-c", cli + " " + args];
        job.running = true;
    }
    function setEnabled(on) {
        fw(on ? "on" : "off");
    }
    function setPreset(id, on) {
        fw((on ? "allow " : "block ") + id);
    }
    function add() {
        if (!canAdd)
            return;
        const name = newName.trim();
        fw("open " + newProto + " " + Number(newPort) + " " + newScope + (name !== "" ? " " + sq(name) : ""));
        newPort = "";
        newName = "";
    }
    function remove(p) {
        fw("close " + p.proto + " " + p.port);
    }
    // Single-quoted for the shell
    function sq(t) {
        return "'" + t.replace(/'/g, "'\\''") + "'";
    }
    function portLabel(p) {
        return p.proto.toUpperCase() + " " + p.port;
    }
    function scopeLabel(s) {
        return s === "any" ? FiliI18n.tr("Anywhere") : FiliI18n.tr("Local network");
    }

    // Rounded text box of the forms
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        property string hint
        property bool digits: false
        signal accepted
        Layout.fillWidth: true
        implicitHeight: 28
        radius: FiliTheme.radiusControl
        color: FiliTheme.nuit2
        border { color: input.activeFocus ? FiliTheme.voile : FiliTheme.nuit4; width: FiliTheme.borderWidth }
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            activeFocusOnTab: true
            inputMethodHints: field.digits ? Qt.ImhDigitsOnly : Qt.ImhNone
            color: FiliTheme.brume
            selectionColor: FiliTheme.voile
            selectedTextColor: FiliTheme.nuit
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            Accessible.name: field.hint
            onAccepted: field.accepted()
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: input.text === "" && !input.activeFocus
                text: field.hint
                color: FiliTheme.ardoise
                font: input.font
            }
        }
    }

    Process {
        id: job
        stderr: StdioCollector {
            onStreamFinished: view.error = text.trim()
        }
        // Cancelled or refused authentication, or refused rules: nothing changed, said in words when the command did not
        onExited: code => {
            if (code !== 0 && view.error === "")
                view.error = FiliI18n.tr("Nothing changed: the authentication was cancelled or refused.");
        }
    }
    FileView {
        path: FiliTheme.testing ? "" : (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/filigrane/firewall.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: view.load(text())
        onLoadFailed: view.load("")
    }

    Text {
        text: FiliI18n.tr("Firewall")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("What may connect to this computer from the network. Incoming connections are refused unless you allow them here; outgoing ones, and the answers to them, are always free. A change applies at once and asks you to confirm with your password.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    PanelSection { divided: false; text: FiliI18n.tr("PROTECTION") }
    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        Text {
            Layout.fillWidth: true
            text: FiliI18n.tr("Refuse incoming connections")
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        Text {
            objectName: "state"
            text: view.enabled ? FiliI18n.tr("ON") : FiliI18n.tr("OFF")
            color: view.enabled ? FiliTheme.brume2 : FiliTheme.sable
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
        }
        PanelSwitch {
            objectName: "enabled"
            checked: view.enabled
            onToggled: view.setEnabled(!view.enabled)
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: !view.enabled
        text: FiliI18n.tr("The firewall is off: every program of this computer that listens can be reached from the network.")
        color: FiliTheme.sable
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    // Groups of rows: 12 between two rows (each has a title and a line of detail, 4 apart)
    PanelSection { text: FiliI18n.tr("ALLOWED") }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space3
        Repeater {
            model: view.presetList
            RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: FiliTheme.space3
                opacity: view.enabled ? 1 : 0.5
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: FiliTheme.space1
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.label
                        color: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: row.modelData.detail
                        color: FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }
                }
                PanelSwitch {
                    objectName: "preset-" + row.modelData.id
                    checked: view.presets[row.modelData.id]
                    switchable: view.enabled
                    onToggled: view.setPreset(row.modelData.id, !view.presets[row.modelData.id])
                }
            }
        }
    }

    PanelSection { text: FiliI18n.tr("OPEN PORTS") }
    Text {
        visible: view.ports.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("No port opened by hand. Add one below to let a program of this computer be reached.")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space3
        Repeater {
            model: view.ports
            RowLayout {
                id: entry
                required property var modelData
                objectName: "port-" + modelData.proto + "-" + modelData.port
                Layout.fillWidth: true
                spacing: FiliTheme.space3
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: FiliTheme.space1
                    // The name, to remember why; without one the port itself is the title
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: entry.modelData.name !== "" ? entry.modelData.name : view.portLabel(entry.modelData)
                        color: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                    // Anywhere is the riskier choice: in sable, and said in words
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (entry.modelData.name !== "" ? view.portLabel(entry.modelData) + " · " : "") + view.scopeLabel(entry.modelData.scope)
                        color: entry.modelData.scope === "any" ? FiliTheme.sable : FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }
                }
                PanelButton {
                    objectName: "close-" + entry.modelData.proto + "-" + entry.modelData.port
                    Layout.fillWidth: false
                    Layout.preferredWidth: 72
                    label: FiliI18n.tr("Remove")
                    onClicked: view.remove(entry.modelData)
                }
            }
        }
    }

    PanelSection { text: FiliI18n.tr("OPEN A PORT") }
    // Form: labels on the left (80), controls aligned, 8 between lines
    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        Text {
            Layout.preferredWidth: 80
            text: FiliI18n.tr("Name")
            color: FiliTheme.brume2
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        Field {
            objectName: "new-name"
            hint: FiliI18n.tr("Why: Dev server, Printer…")
            text: view.newName
            input.onTextEdited: view.newName = text
            onAccepted: view.add()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        Text {
            Layout.preferredWidth: 80
            text: FiliI18n.tr("Protocol")
            color: FiliTheme.brume2
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelChips {
            objectName: "new-proto"
            model: [{ label: "TCP", value: "tcp" }, { label: "UDP", value: "udp" }]
            current: view.newProto
            onPicked: v => view.newProto = v
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        Text {
            Layout.preferredWidth: 80
            text: FiliI18n.tr("Port")
            color: FiliTheme.brume2
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        Field {
            objectName: "new-port"
            digits: true
            hint: "8080"
            text: view.newPort
            input.onTextEdited: view.newPort = text
            onAccepted: view.add()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        Text {
            Layout.preferredWidth: 80
            text: FiliI18n.tr("From")
            color: FiliTheme.brume2
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelChips {
            objectName: "new-scope"
            model: [{ label: FiliI18n.tr("Local network"), value: "lan" }, { label: FiliI18n.tr("Anywhere"), value: "any" }]
            current: view.newScope
            onPicked: v => view.newScope = v
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: view.portBad || view.nameBad
            text: view.nameBad ? FiliI18n.tr("The name cannot hold a quote, a backslash, a comma, a hash or a bracket, and has 60 characters at most.") : FiliI18n.tr("The port is a number from 1 to 65535.")
            color: FiliTheme.sable
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
        }
        Item { Layout.fillWidth: true; visible: !(view.portBad || view.nameBad) }
        PanelButton {
            objectName: "add"
            Layout.fillWidth: false
            Layout.preferredWidth: 72
            label: FiliI18n.tr("Open")
            dim: !view.canAdd
            onClicked: view.add()
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: view.error !== ""
        objectName: "error"
        text: view.error
        color: FiliTheme.cendre
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Local network means the private addresses (10.x, 172.16-31.x, 192.168.x, and the local IPv6 ones). Open a port to anywhere only for a service you run on purpose.")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
