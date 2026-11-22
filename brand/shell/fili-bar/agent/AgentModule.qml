// AI agent (fili-ai and terminal sessions, fili-ai-session; state read by AgentState): sand and blinking when the agent
// waits for an answer (ASK), DONE when it finished without being looked at. Click = agent panel (sessions, actions),
// Super+click or middle click = what is waiting (the chat, else the terminal session that waits, else the last one,
// again: the next; none: fili-ai), right click = menu (open the agent, choose it)
import QtQuick
import qs
import qs.bar

BarScript {
    objectName: "ai"
    // Sessions and limits (AgentState); this instance marks the sessions looked at as seen. Loaded by its URL, like the panel: a
    // module folder linked from a package does not give its siblings to the type resolution of the shell
    Loader {
        id: stateLoader
        source: Qt.resolvedUrl("AgentState.qml")
        onLoaded: item.watching = true
    }
    readonly property var agent: stateLoader.item
    panel: "agent"
    panelSource: Qt.resolvedUrl("AgentPanel.qml")
    value: agent ? agent.ai : BarState.empty
    colors: ({ off: FiliTheme.barMuted, idle: FiliTheme.barText2, working: FiliTheme.barText, waiting: FiliTheme.barWarn, done: FiliTheme.barAccent })
    blinkClass: "waiting"
    hover.onLeftClicked: hover.meta ? agent?.aiAsk() : togglePanel()
    hover.onMiddleClicked: agent?.aiAsk()
    hover.onRightClicked: contextMenu([{ glyph: "\uf08e", text: FiliI18n.tr("Open the AI agent"), cmd: FiliTheme.bin + "/fili-ai", app: true },
                                       { glyph: "\uf0ec", text: FiliI18n.tr("Choose the agent…"), cmd: FiliTheme.bin + "/fili-ai pick" }])
}
