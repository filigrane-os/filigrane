// AI agent (fili-ai and terminal sessions, fili-ai-session; state read by BarState): sand and blinking when the agent
// waits for an answer (ASK), DONE when it finished without being looked at. Click = agent panel (sessions, actions),
// Super+click or middle click = what is waiting (the chat, else the terminal session that waits, else the last one,
// again: the next; none: fili-ai), right click = menu (open the agent, choose it)
import QtQuick
import qs
import qs.bar

BarScript {
    objectName: "ai"
    panel: "agent"
    panelSource: Qt.resolvedUrl("AgentPanel.qml")
    value: BarState.ai
    colors: ({ off: FiliTheme.barMuted, idle: FiliTheme.barText2, working: FiliTheme.barText, waiting: FiliTheme.barWarn, done: FiliTheme.barAccent })
    blinkClass: "waiting"
    hover.onLeftClicked: hover.meta ? BarState.aiAsk() : togglePanel()
    hover.onMiddleClicked: BarState.aiAsk()
    hover.onRightClicked: contextMenu([{ glyph: "\uf08e", text: FiliI18n.tr("Open the AI agent"), cmd: FiliTheme.bin + "/fili-ai", app: true },
                                       { glyph: "\uf0ec", text: FiliI18n.tr("Choose the agent…"), cmd: FiliTheme.bin + "/fili-ai pick" }])
}
