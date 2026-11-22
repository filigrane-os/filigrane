pragma Singleton
// fili-ask: the small floating field of "Ask Rob…" (Mod+Ctrl+Y, the entry of every application menu, the header button of
// the applications): a line to ask Rob about the active application without opening the drawer. The application is the one
// noted by `fili-ai here` just before (context.json); Rob's session scoped to it gets the question (FiliAi.askHere).
// Enter = send and open the chat on the new session (so one sees what happens), Shift+Enter = send and stay where you
// are (the bar's AI dot shows the work, a notification says "Rob has finished" with an Open button), Escape or click outside = close (the draft is kept). Without an application in the
// context, the field is not shown (an ordinary drawer opens).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.bar

Singleton {
    id: ask
    property bool open: false
    // Application the question is about (app_id of the context) and its display name
    property string appId: ""
    readonly property string appLabel: TaskbarLayout.appName(appId)
    readonly property string ctxFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/context.json"
    // Typed text (read and written by the tests)
    property alias text: input.text

    function show() {
        FiliShell.popupOpened("ask");
        if (FiliTheme.testing) {
            open = true;
            return;
        }
        read.running = false;
        read.running = true;
    }
    function close() {
        // The draft stays: reopening the field brings back what was being typed
        open = false;
    }
    function submit(drawer) {
        const t = input.text.trim();
        if (!t)
            return;
        close();
        input.text = "";
        FiliAi.askHere(t, drawer);
    }

    Process {
        id: read
        command: ["cat", ask.ctxFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let c = null;
                try {
                    c = JSON.parse(text);
                } catch (e) {}
                ask.appId = c?.window?.app_id ?? "";
                // No application (empty desktop): the drawer, as for any question
                if (ask.appId)
                    ask.open = true;
                else
                    FiliAi.show();
            }
        }
    }
    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "ask")
                ask.close();
        }
    }

    PanelWindow {
        visible: ask.open && !FiliTheme.testing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-ask"
        WlrLayershell.keyboardFocus: ask.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        MouseArea { anchors.fill: parent; onPressed: ask.close() }
        Rectangle {
            id: box
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Math.round(parent.height * 0.18) }
            width: Math.min(parent.width - 2 * FiliTheme.space6, 520)
            height: col.implicitHeight + 2 * FiliTheme.space4
            color: FiliTheme.nuit
            border { color: FiliTheme.border; width: FiliTheme.borderWidth }
            radius: FiliTheme.radiusWindow
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space4 }
                spacing: FiliTheme.space2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: FiliTheme.space2
                    Text {
                        text: String.fromCodePoint(0xf06a9)
                        color: FiliTheme.voile
                        font { family: "Fili Icons"; pixelSize: 16 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: ask.appLabel ? FiliI18n.tr("Rob, about %1").replace("%1", ask.appLabel) : "Rob"
                        elide: Text.ElideRight
                        color: FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: FiliTheme.weightAccent }
                    }
                }
                TextInput {
                    id: input
                    Layout.fillWidth: true
                    focus: ask.open
                    color: FiliTheme.brume
                    selectionColor: FiliTheme.nuit3
                    selectedTextColor: FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size + 2; weight: Font.Light }
                    clip: true
                    Text {
                        visible: !input.text
                        text: FiliI18n.tr("Ask anything about this application…")
                        color: FiliTheme.ardoise
                        font: input.font
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Keys.onPressed: k => {
                        if (k.key === Qt.Key_Escape) {
                            ask.close();
                        } else if (k.key === Qt.Key_Return || k.key === Qt.Key_Enter) {
                            ask.submit(!(k.modifiers & Qt.ShiftModifier));
                            k.accepted = true;
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: FiliI18n.tr("Enter to send · Shift+Enter to send without opening the chat · Esc to cancel")
                    elide: Text.ElideRight
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                }
            }
        }
    }
}
