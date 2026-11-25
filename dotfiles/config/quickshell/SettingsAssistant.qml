// Settings page "Assistant" (fili-settings): which agent answers Lia, with which model, and whether it is installed and signed
// in. `fili-assistant status` gives the state, `fili-assistant set agent|model|agent-model` writes ~/.config/filigrane/ai.env
// (which the assistant reads when a session starts), install and sign in open a terminal. The login files of the agents are
// never opened: "signed in" only means that the agent's own login file exists.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    // From `fili-assistant status`
    property var status: ({ agent: "", model: "", agent_model: "", agents: [], models: [] })
    readonly property string cli: FiliTheme.bin + "/fili-assistant"
    readonly property var agent: status.agents.find(a => a.id === status.agent) ?? null
    readonly property string home: Quickshell.env("HOME")
    readonly property var names: ({ claude: "Claude", codex: "Codex", ollama: "Ollama", opencode: "opencode", none: FiliI18n.tr("None") })
    // Models offered for the agent (the aliases the agent understands; Ollama: the models that are pulled)
    readonly property var modelChoices: {
        const first = { label: FiliI18n.tr("Default of the agent"), value: "" };
        if (status.agent === "claude")
            return [first, { label: "Sonnet", value: "sonnet" }, { label: "Opus", value: "opus" }, { label: "Haiku", value: "haiku" }];
        if (status.agent === "ollama")
            return [first].concat(status.models.map(m => ({ label: m, value: m })));
        return [first];
    }
    readonly property var quickChoices: [{ label: FiliI18n.tr("Same as the model"), value: "default" }, { label: "Sonnet", value: "sonnet" }, { label: "Opus", value: "opus" }, { label: "Haiku", value: "haiku" }]

    function set(key, value) {
        const s = Object.assign({}, status);
        if (key === "agent")
            s.agent = value;
        else if (key === "model")
            s.model = value;
        else
            s.agent_model = value;
        status = s;
        FiliTheme.run(cli + " set " + key + " " + (value === "" ? "''" : value));
    }
    function reload() {
        if (!FiliTheme.testing)
            read.running = true;
    }

    Process {
        id: read
        running: !FiliTheme.testing
        command: [view.cli, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.status = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    FileView {
        path: view.home + "/.config/filigrane/ai.env"
        watchChanges: true
        printErrors: false
        onFileChanged: view.reload()
    }

    Text {
        text: FiliI18n.tr("Assistant")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The agent that answers Lia. Filigrane works without one.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { divided: false; text: FiliI18n.tr("AGENT") }
    PanelChips {
        objectName: "agent"
        model: view.status.agents.map(a => ({ label: view.names[a.id] ?? a.id, value: a.id }))
        current: view.status.agent
        onPicked: v => view.set("agent", v)
    }
    Text {
        objectName: "agent-desc"
        visible: view.agent !== null
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        wrapMode: Text.WordWrap
        text: view.agent ? view.agent.desc : ""
        color: FiliTheme.brume
        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
    }
    // State in words (colour is never the only signal)
    Text {
        objectName: "agent-state"
        visible: view.agent !== null && view.agent.id !== "none"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: view.agent ? (view.agent.installed ? FiliI18n.tr("Installed") : FiliI18n.tr("Not installed")) + " · " + (view.agent.id === "ollama" ? FiliI18n.tr("runs on this computer") : view.agent.signed_in ? FiliI18n.tr("Signed in") : FiliI18n.tr("Not signed in")) : ""
        color: view.agent && (!view.agent.installed || !view.agent.signed_in) ? FiliTheme.sable : FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        spacing: FiliTheme.space2
        visible: view.agent !== null && view.agent.id !== "none"
        PanelButton {
            objectName: "agent-install"
            visible: view.agent !== null && !view.agent.installed
            label: FiliI18n.tr("Install…")
            onClicked: FiliTheme.run(view.cli + " install " + view.status.agent)
        }
        PanelButton {
            objectName: "agent-login"
            visible: view.agent !== null && view.agent.installed && !view.agent.signed_in && view.agent.id !== "ollama"
            label: FiliI18n.tr("Sign in…")
            onClicked: FiliTheme.run(view.cli + " login " + view.status.agent)
        }
        PanelButton {
            objectName: "agent-update"
            visible: view.agent !== null && view.agent.installed
            label: FiliI18n.tr("Update…")
            onClicked: FiliTheme.run(view.cli + " install " + view.status.agent)
        }
    }
    PanelSection { visible: view.status.agent !== "none"; text: FiliI18n.tr("MODEL") }
    RowLayout {
        visible: view.status.agent !== "none"
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: FiliI18n.tr("Model")
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSelect {
            objectName: "model"
            Layout.preferredWidth: 200
            model: view.modelChoices
            current: view.status.model
            onPicked: v => view.set("model", v)
        }
    }
    RowLayout {
        visible: view.status.agent === "claude"
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        Text {
            Layout.fillWidth: true
            text: FiliI18n.tr("Quick requests")
            color: FiliTheme.brume
            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
        }
        PanelSelect {
            objectName: "agent-model"
            Layout.preferredWidth: 200
            model: view.quickChoices
            current: view.status.agent_model === "" ? "default" : view.status.agent_model
            onPicked: v => view.set("agent-model", v)
        }
    }
    Text {
        visible: view.status.agent === "claude"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("Quick requests are the short questions asked from an application (“Ask Lia…”): a lighter model answers faster.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    Text {
        visible: view.status.agent === "ollama" && view.status.models.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("No local model yet: run `ollama pull gpt-oss:20b` in a terminal (about 16 GB of memory).")
        color: FiliTheme.sable
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: FiliTheme.space1
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The change applies to the next conversation. Your sign-in files are never read by this page.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
}
