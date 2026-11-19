// fili-panel Messages: the last conversations of Conversations (fili-im) without opening its window. A click on a
// conversation shows its last messages (a peek: nothing is marked read and no receipt is sent) and a field to answer;
// "Mark as read" and "Open" are next to it. `fili-im` does the work through its daemon (`--json chats|messages`, `send`,
// `read`, `open`).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.bar
import qs.controls
import qs

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    readonly property string cmd: FiliTheme.bin + "/fili-im"
    property var chats: []
    property var accounts: []
    // Open conversation (peek), its last messages, and a notice (an error, or "Sent")
    property int current: 0
    property var lines: []
    property string notice: ""
    property bool failed: false
    readonly property var shown: {
        const unread = chats.filter(c => c.unread > 0);
        const rest = chats.filter(c => !(c.unread > 0));
        return unread.concat(rest).slice(0, 6);
    }

    function refresh() {
        listing.running = true;
        states.running = true;
        if (current)
            peek(current);
    }
    function peek(id) {
        current = id;
        history.command = [cmd, "--json", "messages", String(id), "--limit", "5"];
        history.running = true;
    }
    function who(m) {
        return m.from_me ? FiliI18n.tr("You") : (m.sender_name || m.sender || "?");
    }
    function snippet(m) {
        if (!m)
            return "";
        if (m.deleted)
            return FiliI18n.tr("Message deleted");
        return m.text && m.text.plain ? m.text.plain.replace(/\s+/g, " ") : (m.media ? "[" + m.kind + "]" : "");
    }
    function stateWord(a) {
        const words = { connected: FiliI18n.tr("connected"), connecting: FiliI18n.tr("connecting"), needs_pairing: FiliI18n.tr("needs pairing"),
                        logged_out: FiliI18n.tr("signed out"), banned: FiliI18n.tr("blocked"), phone_offline: FiliI18n.tr("phone offline"), error: FiliI18n.tr("error") };
        return words[a.state] || a.state;
    }
    function send(text) {
        const t = text.trim();
        if (t === "" || !current)
            return;
        notice = "";
        failed = false;
        sender.command = [cmd, "send", String(current), t];
        sender.running = true;
    }
    function markRead() {
        reader.command = [cmd, "read", String(current), "--receipt"];
        reader.running = true;
    }

    Process {
        id: listing
        command: [view.cmd, "--json", "chats", "--limit", "20"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.chats = JSON.parse(text);
                } catch (e) {
                }
            }
        }
    }
    Process {
        id: states
        command: [view.cmd, "--json", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.accounts = JSON.parse(text).accounts || [];
                } catch (e) {
                }
            }
        }
    }
    Process {
        id: history
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.lines = JSON.parse(text);
                } catch (e) {
                }
            }
        }
    }
    Process {
        id: sender
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim().replace(/^fili-im: /, "");
                view.failed = t !== "";
                view.notice = t !== "" ? t : FiliI18n.tr("Sent");
            }
        }
        onExited: view.refresh()
    }
    Process {
        id: reader
        onExited: view.refresh()
    }
    Process { id: opener }
    Component.onCompleted: refresh()
    // The daemon changes the alert files whenever something arrives: the panel follows them while it is open
    BarWatched { id: watch; path: BarState.alerts + "/messages.count"; onContentChanged: view.refresh() }

    Text {
        text: FiliI18n.tr("Conversations")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        visible: view.shown.length === 0
        Layout.fillWidth: true
        text: view.accounts.length === 0 ? FiliI18n.tr("No account yet") : FiliI18n.tr("No conversation")
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }

    Repeater {
        model: view.shown
        ColumnLayout {
            id: row
            required property var modelData
            readonly property bool open: view.current === modelData.id
            Layout.fillWidth: true
            spacing: FiliTheme.space1
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: FiliTheme.radiusControl
                color: rowArea.containsMouse || row.open ? FiliTheme.nuit3 : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: FiliTheme.space2; right: badge.left; rightMargin: FiliTheme.space2; top: parent.top; topMargin: 4 }
                    text: row.modelData.title
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: row.modelData.unread > 0 ? FiliTheme.weightAccent : Font.Normal }
                }
                Text {
                    anchors { left: parent.left; leftMargin: FiliTheme.space2; right: badge.left; rightMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: 4 }
                    text: view.snippet(row.modelData.last)
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                }
                Text {
                    id: badge
                    anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                    text: row.modelData.unread > 0 ? String(row.modelData.unread) : ""
                    color: FiliTheme.sable
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList; weight: FiliTheme.weightAccent }
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.notice = "";
                        row.open ? view.current = 0 : view.peek(row.modelData.id);
                    }
                }
            }
            // Peek: the last messages, then the reply field
            Repeater {
                model: row.open ? view.lines : []
                Text {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: FiliTheme.space2
                    text: view.who(modelData) + ": " + view.snippet(modelData)
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: modelData.from_me ? FiliTheme.ardoise : FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                }
            }
            Rectangle {
                visible: row.open
                Layout.fillWidth: true
                implicitHeight: 30
                radius: FiliTheme.radiusControl
                color: FiliTheme.nuit
                border { width: 1; color: reply.activeFocus ? FiliTheme.nuit4 : FiliTheme.nuit3 }
                TextInput {
                    id: reply
                    objectName: "messages-reply"
                    anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: FiliTheme.brume
                    selectionColor: FiliTheme.nuit4
                    selectedTextColor: FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    onAccepted: { view.send(text); text = ""; }
                    Text {
                        visible: !reply.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: FiliI18n.tr("Reply…")
                        color: FiliTheme.ardoise
                        font: reply.font
                    }
                }
            }
            RowLayout {
                visible: row.open
                Layout.fillWidth: true
                PanelButton {
                    Layout.fillWidth: true
                    label: FiliI18n.tr("Mark as read")
                    dim: row.modelData.unread === 0
                    onClicked: view.markRead()
                }
                PanelButton {
                    Layout.fillWidth: true
                    label: FiliI18n.tr("Open")
                    onClicked: { opener.command = [view.cmd, "open", String(row.modelData.id)]; opener.running = true; }
                }
            }
        }
    }
    Text {
        visible: view.notice !== ""
        Layout.fillWidth: true
        Layout.leftMargin: FiliTheme.space2
        text: view.notice
        wrapMode: Text.Wrap
        color: view.failed ? FiliTheme.cendre : FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { visible: view.accounts.length > 0; text: FiliI18n.tr("ACCOUNTS") }
    Repeater {
        model: view.accounts
        Text {
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: FiliTheme.space2
            text: (modelData.self_name || modelData.name) + " · " + view.stateWord(modelData)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: modelData.state === "connected" ? FiliTheme.ardoise : FiliTheme.sable
            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
        }
    }
    PanelButton {
        Layout.topMargin: FiliTheme.space1
        objectName: "open-app"
        glyph: "\uf08e"
        label: FiliI18n.tr("Open Conversations")
        dim: true
        onClicked: {
            FiliPanel.close();
            FiliTheme.run("fili-im");
        }
    }
}
