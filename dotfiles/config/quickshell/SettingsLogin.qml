// Settings page "Login" (fili-settings): the programs niri starts at login, beyond the ones of the distribution and the
// plugins of the fili-bar. Each item of ~/.config/filigrane/login.toml: a switch, its name and command, buttons to edit
// and to remove it. Two ways to add one: pick an installed application (dialog with a search, like the Workspaces
// page) or type a name and a command. Every change is made by the `fili-login` command, which writes that file; this
// page follows it (FileView). A change applies at the next login: nothing is started or stopped here.
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
    // What the form of a new item holds
    property string newName: ""
    property string newCommand: ""
    // Item being edited ("" = none) and what its form holds
    property string editId: ""
    property string editName: ""
    property string editCommand: ""
    // Picker of an application is open
    property bool adding: false
    // fili-login refuses a double quote and a backslash in the name or the command
    function bad(s) {
        return /["\\]/.test(s);
    }
    readonly property bool badChars: bad(newName + newCommand)
    readonly property bool canAdd: newName.trim() !== "" && newCommand.trim() !== "" && !badChars
    readonly property bool editBad: bad(editName + editCommand)
    readonly property bool canSave: editId !== "" && editName.trim() !== "" && editCommand.trim() !== "" && !editBad
    // Installed applications that can be added: [{ id, name, detail, icon, command }]
    readonly property var apps: appList(DesktopEntries.applications.values, items)

    function load(text) {
        const p = FiliTheme.parseToml(text);
        items = Object.keys(p).filter(k => k.startsWith("items.")).map(k => ({
            id: k.slice(6),
            name: p[k].name || k.slice(6),
            command: p[k].command || "",
            enabled: p[k].enabled !== "false"
        }));
        if (editId !== "" && !items.some(i => i.id === editId))
            editId = "";
    }
    // Single-quoted for the shell
    function sq(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }
    // Command line of a desktop entry (its arguments, field codes already removed), quoted where needed; "" when the
    // entry cannot start by itself (no command, needs a terminal, hidden) or holds a character fili-login refuses
    function appCommand(e) {
        if (!e || e.noDisplay || e.runInTerminal || !e.command || e.command.length === 0)
            return "";
        const line = e.command.map(a => /^[A-Za-z0-9_@%+=:,.\/-]+$/.test(a) ? a : sq(a)).join(" ");
        return bad(line) || bad(e.name ?? "") || line.indexOf("\n") >= 0 ? "" : line;
    }
    // Entries of the picker: the applications that can start, not yet in the list, by name
    function appList(entries, current) {
        const out = [], seen = {};
        for (const e of entries ?? []) {
            const c = appCommand(e);
            if (c === "" || seen[c] || current.some(i => i.command === c))
                continue;
            seen[c] = true;
            out.push({ id: e.id, name: e.name || e.id, detail: e.command[0].split("/").pop(), icon: e.icon ?? "", command: c });
        }
        return out.sort((a, b) => a.name.localeCompare(b.name));
    }
    function toggle(item) {
        FiliTheme.run(cli + (item.enabled ? " disable " : " enable ") + item.id);
    }
    function remove(item) {
        if (editId === item.id)
            editId = "";
        FiliTheme.run(cli + " remove " + item.id);
    }
    function startEdit(item) {
        editId = item.id;
        editName = item.name;
        editCommand = item.command;
    }
    function save() {
        if (!canSave)
            return;
        FiliTheme.run(cli + " edit " + editId + " " + sq(editName.trim()) + " " + sq(editCommand.trim()));
        editId = "";
    }
    function add() {
        if (!canAdd)
            return;
        FiliTheme.run(cli + " add " + sq(newName.trim()) + " " + sq(newCommand.trim()));
        newName = "";
        newCommand = "";
    }
    function addApp(entry) {
        FiliTheme.run(cli + " add " + sq(entry.name) + " " + sq(entry.command));
        adding = false;
    }

    // Rounded text box of the forms
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        property string hint
        signal accepted
        signal escaped
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
            color: FiliTheme.brume
            selectionColor: FiliTheme.voile
            selectedTextColor: FiliTheme.nuit
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            Accessible.name: field.hint
            onAccepted: field.accepted()
            Keys.onEscapePressed: e => { field.escaped(); e.accepted = true; }
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
        ColumnLayout {
            id: entry
            required property var modelData
            readonly property bool editing: view.editId === modelData.id
            objectName: "item-" + modelData.id
            Layout.fillWidth: true
            spacing: FiliTheme.space1

            // Shown
            RowLayout {
                visible: !entry.editing
                Layout.fillWidth: true
                spacing: FiliTheme.space2
                PanelSwitch {
                    objectName: "on-" + entry.modelData.id
                    checked: entry.modelData.enabled
                    onToggled: view.toggle(entry.modelData)
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    // Takes what the buttons leave: a long command is elided instead of widening the page
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: entry.modelData.name
                        color: entry.modelData.enabled ? FiliTheme.brume : FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: entry.modelData.command
                        color: FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }
                }
                PanelButton {
                    objectName: "edit-" + entry.modelData.id
                    Layout.fillWidth: false
                    Layout.preferredWidth: 56
                    label: FiliI18n.tr("Edit")
                    onClicked: view.startEdit(entry.modelData)
                }
                PanelButton {
                    objectName: "remove-" + entry.modelData.id
                    Layout.fillWidth: false
                    Layout.preferredWidth: 72
                    label: FiliI18n.tr("Remove")
                    onClicked: view.remove(entry.modelData)
                }
            }

            // Edited: name and command, Enter saves, Esc cancels
            ColumnLayout {
                visible: entry.editing
                Layout.fillWidth: true
                spacing: FiliTheme.space1
                Repeater {
                    model: [{ field: "name", label: FiliI18n.tr("Name") }, { field: "command", label: FiliI18n.tr("Command") }]
                    RowLayout {
                        id: line
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: FiliTheme.space2
                        Text {
                            Layout.preferredWidth: 80
                            text: line.modelData.label
                            color: FiliTheme.brume2
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        }
                        Field {
                            id: editField
                            objectName: "edit-" + line.modelData.field
                            hint: line.modelData.label
                            text: line.modelData.field === "name" ? view.editName : view.editCommand
                            input.onTextEdited: {
                                if (line.modelData.field === "name")
                                    view.editName = text;
                                else
                                    view.editCommand = text;
                            }
                            onAccepted: view.save()
                            onEscaped: view.editId = ""
                            // Focus on the command, the usual change, once the form is shown
                            Connections {
                                target: entry
                                function onEditingChanged() {
                                    if (entry.editing && line.modelData.field === "command")
                                        editField.input.forceActiveFocus();
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
                        visible: view.editBad
                        text: FiliI18n.tr("A double quote or a backslash cannot be used here: use single quotes, or a script.")
                        color: FiliTheme.sable
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }
                    Item { Layout.fillWidth: true; visible: !view.editBad }
                    PanelButton {
                        objectName: "cancel-" + entry.modelData.id
                        Layout.fillWidth: false
                        Layout.preferredWidth: 80
                        label: FiliI18n.tr("Cancel")
                        onClicked: view.editId = ""
                    }
                    PanelButton {
                        objectName: "save-" + entry.modelData.id
                        Layout.fillWidth: false
                        Layout.preferredWidth: 72
                        label: FiliI18n.tr("Save")
                        dim: !view.canSave
                        onClicked: view.save()
                    }
                }
            }
        }
    }

    PanelSection { text: FiliI18n.tr("ADD") }
    PanelButton {
        objectName: "add-app"
        glyph: "+"
        label: FiliI18n.tr("Add an application…")
        onClicked: view.adding = true
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space2
        text: FiliI18n.tr("Or a command")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
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
            Field {
                objectName: "new-" + form.modelData.field
                hint: form.modelData.hint
                text: form.modelData.field === "name" ? view.newName : view.newCommand
                input.onTextEdited: {
                    if (form.modelData.field === "name")
                        view.newName = text;
                    else
                        view.newCommand = text;
                }
                onAccepted: view.add()
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

    AppPicker {
        open: view.adding
        title: FiliI18n.tr("Add an application")
        placeholder: FiliI18n.tr("Search applications")
        emptyText: FiliI18n.tr("No application found")
        entries: view.apps
        onPicked: e => view.addApp(e)
        onClosed: view.adding = false
    }
}
