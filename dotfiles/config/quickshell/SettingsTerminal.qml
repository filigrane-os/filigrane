// Settings page "Aéroport" (fili-settings): the terminal (fili-term). The keyboard shortcuts: a preset (`fili-term keymap
// NAME` writes `keymap = "NAME"` in ~/.config/filigrane/fili-term.toml, open windows follow at once), and the file for
// the keys one by one ([keys] section).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    property string keymap: "default"
    readonly property string bin: "/usr/bin/fili-term"

    function setKeymap(name) {
        keymap = name;
        FiliTheme.run(bin + " keymap " + name);
    }

    Process {
        id: read
        running: !FiliTheme.testing
        command: [view.bin, "keymap"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() !== "") view.keymap = text.trim()
        }
    }

    Text {
        text: "Aéroport"
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Aéroport is the terminal (fili-term). Choose how its keys work.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { divided: false; text: FiliI18n.tr("KEYBOARD SHORTCUTS") }
    PanelChips {
        objectName: "keymap"
        model: [
            { label: FiliI18n.tr("Default"), value: "default" },
            { label: "Mac", value: "mac" },
            { label: "tmux", value: "tmux" },
            { label: FiliI18n.tr("None"), value: "none" }
        ]
        current: view.keymap
        onPicked: v => view.setKeymap(v)
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: view.keymap === "mac" ? FiliI18n.tr("Cmd keys of a Mac keyboard: the Super key (Meta+T new tab, Meta+W close, Meta+F find…). The compositor keeps the combinations it uses itself.")
            : view.keymap === "tmux" ? FiliI18n.tr("Prefix Ctrl+B, then a key, as in tmux: C new tab, N and P next and previous, 1 to 9 a tab, / find.")
            : view.keymap === "none" ? FiliI18n.tr("No shortcut: set the ones you want in the file below.")
            : FiliI18n.tr("Ctrl+Shift+letter, so that Ctrl+letter stays with the shell: T new tab, W close, F find, Ctrl+PgUp and Ctrl+PgDown or Alt+1 to 9 to change tab.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelButton {
        objectName: "keys-file"
        label: FiliI18n.tr("Edit the keys one by one…")
        onClicked: FiliTheme.run("xdg-open ~/.config/filigrane/fili-term.toml")
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("In the [keys] section of fili-term.toml: new-tab = \"Ctrl+Shift+T | Meta+T\". Alternatives are separated by |, a chord by a comma, an empty value removes the shortcut.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
