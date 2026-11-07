// fili-panel AI agent: the sessions (terminal sessions of fili-ai-session and the chat) with a click to reach each one,
// the pending request of a session that is asking, and the agent actions (chat, new session, choose the agent).
// State, context, cost and plan limits stay in the fili-tooltip (BarState.aiFor), not repeated here.
import QtQuick
import QtQuick.Layouts
import qs.bar
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1

    readonly property var sessions: BarState.aiData.sessions ?? []
    readonly property string chatState: FiliChat.attention === "waiting" ? "waiting" : FiliChat.attention === "done" ? "done" : FiliChat.busy ? "working" : ""
    function stateText(s) {
        return { working: FiliI18n.tr("working"), waiting: FiliI18n.tr("waiting for you"), done: FiliI18n.tr("finished") }[s] ?? FiliI18n.tr("ready");
    }
    function glyph(s) {
        return s === "waiting" ? "\uf059" : s === "done" ? "\uf058" : s === "working" ? "\uf110" : "\uf111";
    }
    function go(cmd) {
        FiliPanel.close();
        FiliTheme.run(cmd);
    }

    PanelSection { text: FiliI18n.tr("SESSIONS") }
    // The chat comes first when it asks for something (same rule as Mod+click on the bar item)
    PanelButton {
        objectName: "agent-chat-session"
        visible: view.chatState !== ""
        glyph: view.glyph(view.chatState)
        label: FiliI18n.tr("Chat")
        detail: view.stateText(view.chatState)
        sel: view.chatState === "waiting"
        onClicked: { FiliPanel.close(); FiliChat.show(); }
    }
    Repeater {
        model: view.sessions
        PanelButton {
            required property var modelData
            objectName: "agent-session"
            glyph: view.glyph(modelData.state)
            label: BarState.aiName(modelData, Niri.windows)
            detail: view.stateText(modelData.state)
            sel: modelData.state === "waiting"
            dim: modelData.window === undefined
            onClicked: view.go(FiliTheme.bin + "/fili-ai-session focus " + modelData.id)
        }
    }
    // What the asking session wants (permission or question), under its row
    Text {
        objectName: "agent-message"
        readonly property string msg: view.sessions.find(s => s.state === "waiting" && s.message)?.message ?? ""
        visible: msg !== ""
        text: msg
        Layout.fillWidth: true
        Layout.leftMargin: FiliTheme.space2
        Layout.rightMargin: FiliTheme.space2
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
    }
    Text {
        visible: view.sessions.length === 0 && view.chatState === ""
        text: FiliI18n.tr("No session")
        Layout.leftMargin: FiliTheme.space2
        color: FiliTheme.ardoise
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
    }

    PanelSection { text: FiliI18n.tr("ACTIONS") }
    PanelButton {
        objectName: "agent-chat"
        glyph: "\uf075"
        label: FiliChat.open ? FiliI18n.tr("Hide the chat") : FiliI18n.tr("Show the chat")
        detail: "Mod+Y"
        onClicked: { FiliPanel.close(); FiliChat.toggle(); }
    }
    PanelButton {
        objectName: "agent-new"
        glyph: "\uf067"
        label: FiliI18n.tr("New terminal session")
        onClicked: view.go(FiliTheme.bin + "/fili-ai-session new")
    }
    PanelButton {
        objectName: "agent-pick"
        glyph: "\uf013"
        label: FiliI18n.tr("Choose the agent")
        onClicked: view.go("setsid -f " + FiliTheme.bin + "/fili-ai pick")
    }
}
