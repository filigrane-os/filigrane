// Settings page "Login" (fili-settings): the programs niri starts at login, beyond the ones of the distribution and the
// plugins of the fili-bar. Each item of ~/.config/filigrane/login.toml: a switch, its name and command, a button to
// remove it; a form adds one. Every change is made by the `fili-login` command, which writes that file; this page
// follows it (FileView). A change applies at the next login: nothing is started or stopped here.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property string cli: FiliTheme.bin + "/fili-login"
    // [{ id, name, command, enabled }], in the order of the file
    property var items: []
    // What the form holds
    property string newName: ""
    property string newCommand: ""
    // fili-login refuses a double quote and a backslash in the name or the command
    readonly property bool badChars: /["\\]/.test(newName + newCommand)
    readonly property bool canAdd: newName.trim() !== "" && newCommand.trim() !== "" && !badChars

    function load(text) {
        const p = FiliTheme.parseToml(text);
        items = Object.keys(p).filter(k => k.startsWith("items.")).map(k => ({
            id: k.slice(6),
            name: p[k].name || k.slice(6),
            command: p[k].command || "",
            enabled: p[k].enabled !== "false"
        }));
    }
    // Single-quoted for the shell
    function sq(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }
    function toggle(item) {
        FiliTheme.run(cli + (item.enabled ? " disable " : " enable ") + item.id);
    }
    function remove(item) {
        FiliTheme.run(cli + " remove " + item.id);
    }
    function add() {
        if (!canAdd)
            return;
        FiliTheme.run(cli + " add " + sq(newName.trim()) + " " + sq(newCommand.trim()));
        newName = "";
        newCommand = "";
    }

    FileView {
        path: FiliTheme.testing ? "" : (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/filigrane/login.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: view.load(text())
        onLoadFailed: view.items = []
    }

    Text {
        text: FiliI18n.tr("Login")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Programs and services started when you log in. The system services and the plugins of the bar start by themselves and are not listed. A change applies at the next login.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    PanelSection { text: FiliI18n.tr("STARTED AT LOGIN") }
    Text {
        visible: view.items.length === 0
        Layout.fillWidth: true
        text: FiliI18n.tr("Nothing yet. Add a program below.")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    Repeater {
        model: view.items
        RowLayout {
            id: item
            required property var modelData
            objectName: "item-" + modelData.id
            Layout.fillWidth: true
            spacing: FiliTheme.space2
            PanelSwitch {
                objectName: "on-" + item.modelData.id
                checked: item.modelData.enabled
                onToggled: view.toggle(item.modelData)
            }
            ColumnLayout {
                Layout.fillWidth: true
                // Takes what the button leaves: a long command is elided instead of widening the page
                Layout.preferredWidth: 0
                Layout.minimumWidth: 0
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: item.modelData.name
                    color: item.modelData.enabled ? FiliTheme.brume : FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: item.modelData.command
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                }
            }
            PanelButton {
                objectName: "remove-" + item.modelData.id
                Layout.fillWidth: false
                Layout.preferredWidth: 72
                label: FiliI18n.tr("Remove")
                onClicked: view.remove(item.modelData)
            }
        }
    }

    PanelSection { text: FiliI18n.tr("ADD") }
    Repeater {
        model: [
            { field: "name", label: FiliI18n.tr("Name"), hint: "Proton Bridge" },
            { field: "command", label: FiliI18n.tr("Command"), hint: "protonmail-bridge --noninteractive" }
        ]
        RowLayout {
            id: form
            required property var modelData
            Layout.fillWidth: true
            spacing: FiliTheme.space2
            Text {
                Layout.preferredWidth: 80
                text: form.modelData.label
                color: FiliTheme.brume2
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                radius: FiliTheme.radiusControl
                color: FiliTheme.nuit2
                border { color: input.activeFocus ? FiliTheme.voile : FiliTheme.nuit4; width: FiliTheme.borderWidth }
                TextInput {
                    id: input
                    objectName: "new-" + form.modelData.field
                    anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    activeFocusOnTab: true
                    color: FiliTheme.brume
                    selectionColor: FiliTheme.voile
                    selectedTextColor: FiliTheme.nuit
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    Accessible.name: form.modelData.label
                    onAccepted: view.add()
                    text: form.modelData.field === "name" ? view.newName : view.newCommand
                    onTextEdited: {
                        if (form.modelData.field === "name")
                            view.newName = text;
                        else
                            view.newCommand = text;
                    }
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: input.text === "" && !input.activeFocus
                        text: form.modelData.hint
                        color: FiliTheme.ardoise
                        font: input.font
                    }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: view.badChars
            text: FiliI18n.tr("A double quote or a backslash cannot be used here: use single quotes, or a script.")
            color: FiliTheme.sable
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
        }
        Item { Layout.fillWidth: true; visible: !view.badChars }
        PanelButton {
            objectName: "add"
            Layout.fillWidth: false
            Layout.preferredWidth: 72
            label: FiliI18n.tr("Add")
            dim: !view.canAdd
            onClicked: view.add()
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The command runs once per session, from your home folder. If it must survive a crash, wrap it in a loop; it must tolerate a second copy of itself.")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
