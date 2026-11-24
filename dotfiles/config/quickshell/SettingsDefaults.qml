// Settings page "Default applications" (fili-settings): which program opens which kind of thing (browser, mail, folders,
// music...). `fili-defaults list` gives the categories and their current application, `fili-defaults candidates ID` the
// applications that can take one, `fili-defaults set ID DESKTOP_ID` writes the choice in ~/.config/mimeapps.list, which
// xdg-open, the portals and the toolkits read. "Edit with" is one list of editors, each registered once and used for every
// kind of file it handles (`fili-defaults editors|editor-add|editor-rm`), which the file manager offers. Every choice list
// ends with "Other…" (any application of the system, even one that does not list the file type) and "Command…" (a program
// that has no desktop entry).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // [{id, name, current}] from `fili-defaults list`
    property var categories: []
    // Bumped when mimeapps.list or edit-with.list changes: the lists are read again
    property int rev: 0
    // Category whose "Other…" application picker is open ("" = closed)
    property string pickerFor: ""
    readonly property string home: Quickshell.env("HOME")
    // "Edit with": [{id, name}] from `fili-defaults editors`, in order of priority
    property var editors: []
    readonly property string editorKey: "__editor__"

    // Every application that can start, for the picker "Other…" (the list of the choice only has those that declare the type)
    readonly property var allApps: {
        const out = [], seen = {};
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || !e.command || e.command.length === 0)
                continue;
            const id = e.id.endsWith(".desktop") ? e.id : e.id + ".desktop";
            if (seen[id])
                continue;
            seen[id] = true;
            out.push({ id: id, name: e.name || e.id, detail: e.command[0].split("/").pop(), icon: e.icon ?? "" });
        }
        return out.sort((a, b) => a.name.localeCompare(b.name));
    }

    function pick(id, desktop) {
        if (desktop === "__other__") {
            pickerFor = id;
            return;
        }
        if (desktop === "__command__") {
            FiliTheme.run(FiliTheme.bin + "/fili-defaults ask " + id);
            return;
        }
        categories = categories.map(c => c.id === id ? { id: c.id, name: c.name, current: desktop } : c);
        FiliTheme.run(FiliTheme.bin + "/fili-defaults set " + id + " " + desktop);
    }
    // An application picked among all of them: also declared for the types of the category (--any)
    function pickAny(id, desktop) {
        categories = categories.map(c => c.id === id ? { id: c.id, name: c.name, current: desktop } : c);
        FiliTheme.run(FiliTheme.bin + "/fili-defaults set " + id + " " + desktop + " --any");
        pickerFor = "";
    }

    FileView {
        path: view.home + "/.config/mimeapps.list"
        watchChanges: true
        printErrors: false
        onFileChanged: view.rev++
    }
    FileView {
        path: view.home + "/.config/filigrane/edit-with.list"
        watchChanges: true
        printErrors: false
        onFileChanged: view.rev++
    }
    onRevChanged: if (!FiliTheme.testing) {
        list.running = true;
        editorList.running = true;
    }
    function addEditor(desktop) {
        if (!editors.some(e => e.id === desktop))
            editors = editors.concat([{ id: desktop, name: (allApps.find(a => a.id === desktop) ?? { name: desktop }).name }]);
        FiliTheme.run(FiliTheme.bin + "/fili-defaults editor-add " + desktop);
        pickerFor = "";
    }
    function removeEditor(desktop) {
        editors = editors.filter(e => e.id !== desktop);
        FiliTheme.run(FiliTheme.bin + "/fili-defaults editor-rm " + desktop);
    }
    Process {
        id: editorList
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-defaults", "editors"]
        stdout: StdioCollector {
            onStreamFinished: view.editors = text.split("\n").filter(l => l !== "").map(l => {
                const f = l.split("\t");
                return { id: f[0], name: f[1] ?? f[0] };
            })
        }
    }

    Process {
        id: list
        running: !FiliTheme.testing
        command: [FiliTheme.bin + "/fili-defaults", "list"]
        stdout: StdioCollector {
            onStreamFinished: view.categories = text.split("\n").filter(l => l !== "").map(l => {
                const f = l.split("\t");
                return { id: f[0], name: f[1] ?? f[0], current: f[2] ?? "" };
            })
        }
    }

    Text {
        text: FiliI18n.tr("Default applications")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The program that opens each kind of file or link, for every application that follows the system rules.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    // One category: its name and the list of the applications that can take it, then the two ways to add one
    component CategoryRow: RowLayout {
        id: row
        required property var modelData
        // [{label, value}] from `fili-defaults candidates ID`
        property var choices: []
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1

        Process {
            id: candidates
            running: !FiliTheme.testing
            command: [FiliTheme.bin + "/fili-defaults", "candidates", row.modelData.id]
            stdout: StdioCollector {
                onStreamFinished: row.choices = text.split("\n").filter(l => l !== "").map(l => {
                    const f = l.split("\t");
                    return { label: f[1] ?? f[0], value: f[0] };
                })
            }
        }
        Connections {
            target: view
            function onRevChanged() {
                if (!FiliTheme.testing)
                    candidates.running = true;
            }
        }
        Text {
            Layout.fillWidth: true
            text: row.modelData.name
            elide: Text.ElideRight
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSelect {
            objectName: "default-" + row.modelData.id
            Layout.preferredWidth: 200
            model: row.choices.concat([
                { label: FiliI18n.tr("Other…"), value: "__other__" },
                { label: FiliI18n.tr("Command…"), value: "__command__" }
            ])
            current: row.modelData.current
            placeholder: FiliI18n.tr("None")
            onPicked: v => view.pick(row.modelData.id, v)
        }
    }

    PanelSection { divided: false; text: FiliI18n.tr("OPEN WITH") }
    Repeater {
        model: view.categories
        delegate: CategoryRow {}
    }
    PanelSection { text: FiliI18n.tr("EDIT WITH") }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Your editors, added once. The file manager offers “Edit with” and starts the first one that handles the kind of file (images, text, video, audio).")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    Repeater {
        model: view.editors
        delegate: RowLayout {
            id: ed
            required property var modelData
            Layout.fillWidth: true
            Layout.topMargin: FiliTheme.space1
            Text {
                Layout.fillWidth: true
                text: ed.modelData.name
                elide: Text.ElideRight
                color: FiliTheme.brume
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
            PanelButton {
                objectName: "editor-rm-" + ed.modelData.id
                label: FiliI18n.tr("Remove")
                onClicked: view.removeEditor(ed.modelData.id)
            }
        }
    }
    Text {
        visible: view.editors.length === 0
        Layout.fillWidth: true
        text: FiliI18n.tr("No editor yet")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space2
        spacing: FiliTheme.space2
        PanelButton {
            objectName: "editor-add"
            label: FiliI18n.tr("Add an application…")
            onClicked: view.pickerFor = view.editorKey
        }
        PanelButton {
            objectName: "editor-add-command"
            label: FiliI18n.tr("Add a command…")
            onClicked: FiliTheme.run(FiliTheme.bin + "/fili-defaults editor-ask")
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Other… lists every application of the system. Command… adds a program that has no entry in the menu: type its command.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    AppPicker {
        open: view.pickerFor !== ""
        title: FiliI18n.tr("Choose an application")
        placeholder: FiliI18n.tr("Search applications")
        emptyText: FiliI18n.tr("No application found")
        entries: view.allApps
        onPicked: e => view.pickerFor === view.editorKey ? view.addEditor(e.id) : view.pickAny(view.pickerFor, e.id)
        onClosed: view.pickerFor = ""
    }
}
