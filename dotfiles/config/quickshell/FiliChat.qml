pragma Singleton
// fili-chat: le chat de Filigrane, un tiroir au bord droit de l'écran. Mod+Y (`fili-chat toggle`, ou
// `fili-shell chat toggle`) l'affiche ou le cache; la conversation reste, car elle vit dans le démon fili-chat
// (apps/fili-chat) qui garde l'agent et l'historique de chaque session. Le tiroir ne se connecte au démon que
// pendant qu'il est ouvert ou qu'un agent travaille (le démon se coupe de lui-même sans client ni agent).
// Clavier: Retour envoie, Maj+Retour nouvelle ligne, Échap cache (ou ferme la liste des sessions),
// Ctrl+N nouvelle session, Ctrl+L liste des sessions, Ctrl+. interrompt l'agent; permission demandée par l'agent:
// Ctrl+Retour autorise, Ctrl+Retour arrière refuse. Mod+Y note l'application active (puce de contexte au-dessus
// de la saisie, jointe au prochain message). Pastille IA de la fili-bar: ASK (permission), DONE (réponse non lue).
// Protocole du démon: voir apps/fili-chat/src/main.rs.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: chat
    property bool open: false
    property bool listOpen: false
    property var sessions: []
    property string current: ""
    // Éléments de chaque session ouverte (id -> [{kind: user|assistant|tool|error|note, text, name}]); remplacé à chaque changement
    property var items: ({})
    property var states: ({})
    // Texte de l'agent en cours d'écriture (session courante)
    property string live: ""
    // Message tapé avant que la session n'existe
    property string pending: ""
    readonly property var log: items[current] ?? []
    // Tour en cours (l'agent travaille ou attend une permission)
    readonly property bool working: (states[current] ?? "idle") !== "idle"
    readonly property bool busy: Object.keys(states).some(k => states[k] !== "idle")
    // Sessions finies sans que le tiroir les ait montrées (id -> true)
    property var unread: ({})
    // Pour la pastille de la fili-bar: "waiting" (permission demandée), "done" (réponse non lue) ou ""
    readonly property string attention: Object.keys(states).some(k => states[k] === "waiting") ? "waiting" : Object.keys(unread).length ? "done" : ""
    // Application active notée par Mod+Y ({window: {app_id, title}, ...}) et jointe au prochain message si ctxOn
    property var ctx: null
    property bool ctxOn: false
    readonly property string ctxLabel: ctx ? [ctx.window?.app_id, ctx.window?.title].filter(x => x).join(" · ") : ""
    readonly property string ctxFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/context.json"
    readonly property string title: sessions.find(s => s.id === current)?.title || FiliI18n.tr("New session")
    readonly property bool linked: link.connected
    readonly property string sock: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili-chat/sock"
    property int tries: 0

    function show() {
        FiliShell.popupOpened("chat");
        FiliPanel.close();
        open = true;
        markRead();
        if (!FiliTheme.testing) {
            ctxRead.running = false;
            ctxRead.running = true;
        }
        focusInput();
    }
    function markRead() {
        if (!unread[current])
            return;
        const u = Object.assign({}, unread);
        delete u[current];
        unread = u;
    }
    function hide() {
        open = false;
        listOpen = false;
    }
    function toggle() {
        if (open)
            hide();
        else
            show();
    }
    signal focusInput
    onWorkingChanged: if (!working) focusInput()

    // ───── démon ─────
    function ensure() {
        if (FiliTheme.testing || link.connected)
            return;
        Quickshell.execDetached([FiliTheme.bin + "/fili-chat", "daemon"]);
        tries = 0;
        retry.start();
    }
    readonly property bool wantLink: open || busy
    onWantLinkChanged: {
        if (wantLink) {
            ensure();
        } else {
            retry.stop();
            link.connected = false;
        }
    }
    Timer {
        id: retry
        interval: 250
        repeat: true
        onTriggered: {
            if (link.connected || !chat.wantLink || ++chat.tries > 20) {
                stop();
                return;
            }
            link.connected = false;
            link.connected = true;
        }
    }
    // Contexte noté par `fili-chat toggle` juste avant l'ouverture
    Process {
        id: ctxRead
        command: ["cat", chat.ctxFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let c = null;
                try {
                    c = JSON.parse(text);
                } catch (e) {}
                chat.ctx = c && c.window && c.window.app_id ? c : null;
                chat.ctxOn = chat.ctx !== null;
            }
        }
    }
    Socket {
        id: link
        path: chat.sock
        onConnectedChanged: {
            if (connected) {
                retry.stop();
                if (chat.current)
                    chat.send_({ op: "open", id: chat.current });
            } else if (chat.wantLink) {
                // Démon arrêté alors qu'on l'attend: relancé
                chat.ensure();
            }
        }
        parser: SplitParser {
            onRead: line => {
                try {
                    chat.receive(JSON.parse(line));
                } catch (e) {}
            }
        }
    }
    function send_(obj) {
        if (FiliTheme.testing) {
            FiliTheme.ran = FiliTheme.ran.concat(["chat " + JSON.stringify(obj)]);
            return;
        }
        if (!link.connected)
            return;
        link.write(JSON.stringify(obj) + "\n");
        link.flush();
    }

    // ───── actions ─────
    function newSession() {
        listOpen = false;
        send_({ op: "new" });
    }
    function openSession(id) {
        listOpen = false;
        if (id === current)
            return;
        current = id;
        live = "";
        markRead();
        send_({ op: "open", id });
        focusInput();
    }
    function removeSession(id) {
        send_({ op: "delete", id });
    }
    function send(text) {
        const t = text.trim();
        if (!t || working)
            return;
        if (!current) {
            pending = t;
            send_({ op: "new" });
            return;
        }
        const req = { op: "send", id: current, text: t };
        if (ctxOn)
            req.context = true;
        ctxOn = false;
        send_(req);
    }
    // Réponse à la première permission en attente de la session courante
    function answer(rid, allow) {
        send_({ op: "answer", rid, allow });
    }
    function answerFirst(allow) {
        const a = log.find(i => i.kind === "ask" && i.status === "pending");
        if (a)
            answer(a.rid, allow);
    }
    function stop() {
        if (current)
            send_({ op: "stop", id: current });
    }

    // ───── événements du démon ─────
    function append(id, item) {
        if (items[id] === undefined)
            return;
        const m = Object.assign({}, items);
        m[id] = items[id].concat([item]);
        items = m;
    }
    function setState(id, st) {
        const was = states[id] ?? "idle";
        const m = Object.assign({}, states);
        m[id] = st;
        states = m;
        if (st === "idle" && id === current)
            live = "";
        // Tour fini hors de la vue du tiroir: à lire
        if (st === "idle" && was !== "idle" && !(open && id === current)) {
            const u = Object.assign({}, unread);
            u[id] = true;
            unread = u;
        }
    }
    function askItem(ev) {
        return { kind: "ask", rid: ev.rid, name: ev.tool, text: ev.summary, status: ev.status };
    }
    function item(ev) {
        if (ev.ev === "ask")
            return askItem(ev);
        const text = ev.ev === "tool" ? ev.summary : ev.role === "error" ? FiliI18n.tr(ev.text) : ev.text;
        return { kind: ev.ev === "tool" ? "tool" : ev.role, text, name: ev.name ?? "" };
    }
    function receive(ev) {
        if (ev.ev === "sessions") {
            sessions = ev.sessions;
            const m = Object.assign({}, states);
            for (const s of ev.sessions)
                m[s.id] = s.state;
            states = m;
            if (!sessions.some(s => s.id === current)) {
                current = pending ? current : (sessions[0]?.id ?? "");
                if (current && items[current] === undefined)
                    send_({ op: "open", id: current });
            }
        } else if (ev.ev === "created") {
            const m = Object.assign({}, items);
            m[ev.id] = [];
            items = m;
            current = ev.id;
            live = "";
            if (pending) {
                const t = pending;
                pending = "";
                const req = { op: "send", id: ev.id, text: t };
                if (ctxOn)
                    req.context = true;
                ctxOn = false;
                send_(req);
            }
        } else if (ev.ev === "history") {
            const m = Object.assign({}, items);
            m[ev.id] = ev.items.map(item);
            items = m;
        } else if (ev.ev === "msg" || ev.ev === "tool") {
            append(ev.id, item(ev));
            if (ev.role === "assistant" && ev.id === current)
                live = "";
        } else if (ev.ev === "ask") {
            // Demande de permission: une même demande est mise à jour quand elle est tranchée
            if (items[ev.id] === undefined)
                return;
            const a = items[ev.id].slice();
            const i = a.findIndex(x => x.kind === "ask" && x.rid === ev.rid);
            if (i >= 0)
                a[i] = askItem(ev);
            else
                a.push(askItem(ev));
            const m = Object.assign({}, items);
            m[ev.id] = a;
            items = m;
        } else if (ev.ev === "delta") {
            if (ev.id === current)
                live += ev.text;
        } else if (ev.ev === "state") {
            setState(ev.id, ev.state);
        } else if (ev.ev === "note") {
            append(ev.id, { kind: "note", text: FiliI18n.tr(ev.code === "interrupted" ? "Interrupted" : ev.code), name: "" });
        }
    }

    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "chat" && who !== "")
                chat.hide();
        }
    }

    PanelWindow {
        id: win
        visible: chat.open && !FiliTheme.testing
        anchors { top: true; bottom: true; right: true }
        margins.top: FiliTheme.barHeight
        implicitWidth: 440
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-chat"
        WlrLayershell.keyboardFocus: chat.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: chat.listOpen ? chat.listOpen = false : chat.hide()
            Keys.onPressed: e => {
                if (e.modifiers & Qt.ControlModifier) {
                    if (e.key === Qt.Key_N)
                        chat.newSession();
                    else if (e.key === Qt.Key_L)
                        chat.listOpen = !chat.listOpen;
                    else if (e.key === Qt.Key_Period)
                        chat.stop();
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                        chat.answerFirst(true);
                    else if (e.key === Qt.Key_Backspace)
                        chat.answerFirst(false);
                    else
                        return;
                    e.accepted = true;
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: FiliTheme.space1
                color: FiliTheme.nuit
                border { color: FiliTheme.nuit4; width: 1 }
                radius: FiliTheme.radiusWindow
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // En-tête: session courante (liste), nouvelle session, cacher
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        Layout.leftMargin: FiliTheme.space3
                        Layout.rightMargin: FiliTheme.space2
                        spacing: FiliTheme.space2
                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: chat.working ? FiliTheme.voile : FiliTheme.ardoise
                        }
                        Text {
                            Layout.fillWidth: true
                            text: chat.title + "  ▾"
                            elide: Text.ElideRight
                            color: FiliTheme.brume
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chat.listOpen = !chat.listOpen
                            }
                        }
                        Repeater {
                            model: [{ t: "+", tip: "New session", act: 0 }, { t: "×", tip: "Hide", act: 1 }]
                            Text {
                                required property var modelData
                                Layout.preferredWidth: 28
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.t
                                color: hit.containsMouse ? FiliTheme.brume : FiliTheme.brume2
                                font { family: FiliTheme.font; pixelSize: 20 }
                                MouseArea {
                                    id: hit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.act === 0 ? chat.newSession() : chat.hide()
                                }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: FiliTheme.nuit4 }

                    // Fil de la conversation (ou liste des sessions)
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: thread
                            anchors.fill: parent
                            visible: !chat.listOpen
                            model: chat.log
                            spacing: FiliTheme.space3
                            topMargin: FiliTheme.space3
                            bottomMargin: FiliTheme.space3
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            // Le fil suit la fin tant qu'on n'est pas remonté lire
                            property bool follow: true
                            onMovementEnded: follow = atYEnd
                            onCountChanged: if (follow) Qt.callLater(positionViewAtEnd)
                            Connections {
                                target: chat
                                function onLiveChanged() { if (thread.follow) Qt.callLater(thread.positionViewAtEnd); }
                                function onCurrentChanged() { thread.follow = true; Qt.callLater(thread.positionViewAtEnd); }
                            }
                            delegate: Item {
                                id: row
                                required property var modelData
                                width: thread.width
                                implicitHeight: isAsk ? askCard.height : body.implicitHeight + (isUser ? 16 : 0)
                                readonly property bool isAsk: modelData.kind === "ask"
                                readonly property bool isUser: modelData.kind === "user"
                                readonly property bool isTool: modelData.kind === "tool"
                                Rectangle {
                                    visible: row.isUser
                                    anchors { right: parent.right; rightMargin: FiliTheme.space3 }
                                    width: Math.min(parent.width * 0.85, body.implicitWidth + 20)
                                    height: parent.height
                                    radius: FiliTheme.radiusControl
                                    color: FiliTheme.nuit3
                                }
                                // Permission demandée par l'agent
                                Rectangle {
                                    id: askCard
                                    visible: row.isAsk
                                    x: FiliTheme.space3
                                    width: parent.width - 2 * FiliTheme.space3
                                    height: askCol.implicitHeight + 2 * FiliTheme.space2
                                    radius: FiliTheme.radiusControl
                                    color: FiliTheme.nuit2
                                    border { width: 1; color: row.modelData.status === "pending" ? FiliTheme.sable : FiliTheme.nuit4 }
                                    ColumnLayout {
                                        id: askCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space2 }
                                        spacing: FiliTheme.space2
                                        Text {
                                            Layout.fillWidth: true
                                            text: ({ pending: FiliI18n.tr("Allow %1?", row.modelData.name), allowed: FiliI18n.tr("%1 allowed", row.modelData.name), denied: FiliI18n.tr("%1 denied", row.modelData.name) })[row.modelData.status] ?? FiliI18n.tr("%1 cancelled", row.modelData.name)
                                            color: row.modelData.status === "pending" ? FiliTheme.sable : row.modelData.status === "denied" ? FiliTheme.cendre : FiliTheme.brume2
                                            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: row.modelData.text
                                            wrapMode: Text.WrapAnywhere
                                            maximumLineCount: 6
                                            elide: Text.ElideRight
                                            color: FiliTheme.brume
                                            font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeSmall }
                                        }
                                        RowLayout {
                                            visible: row.modelData.status === "pending"
                                            spacing: FiliTheme.space2
                                            Repeater {
                                                model: [{ label: "Allow", allow: true }, { label: "Deny", allow: false }]
                                                Rectangle {
                                                    required property var modelData
                                                    Layout.preferredWidth: 84
                                                    Layout.preferredHeight: 26
                                                    radius: FiliTheme.radiusControl
                                                    color: modelData.allow ? FiliTheme.voile : FiliTheme.nuit3
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: FiliI18n.tr(parent.modelData.label)
                                                        color: parent.modelData.allow ? FiliTheme.nuit : FiliTheme.brume
                                                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: chat.answer(row.modelData.rid, parent.modelData.allow)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                TextEdit {
                                    id: body
                                    visible: !row.isAsk
                                    x: row.isUser ? parent.width - width - FiliTheme.space3 - 10 : FiliTheme.space3
                                    y: row.isUser ? 8 : 0
                                    width: row.isUser ? Math.min(parent.width * 0.85 - 20, implicitWidth) : parent.width - 2 * FiliTheme.space3
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.Wrap
                                    textFormat: row.isTool || row.isUser || modelData.kind !== "assistant" ? TextEdit.PlainText : TextEdit.MarkdownText
                                    text: row.isTool ? "▸ " + modelData.name + "  " + modelData.text : modelData.text
                                    color: modelData.kind === "error" ? FiliTheme.cendre : (row.isTool || modelData.kind === "note") ? FiliTheme.ardoise : FiliTheme.brume
                                    selectionColor: FiliTheme.voile
                                    selectedTextColor: FiliTheme.nuit
                                    font {
                                        family: row.isTool ? FiliTheme.mono : FiliTheme.font
                                        pixelSize: row.isTool ? FiliTheme.sizeSmall : FiliTheme.size
                                        italic: modelData.kind === "note"
                                    }
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                            }
                            footer: Item {
                                width: thread.width
                                implicitHeight: (chat.live || chat.working ? liveText.implicitHeight + FiliTheme.space3 : 0) + (chat.working ? 24 : 0)
                                visible: chat.live !== "" || chat.working
                                TextEdit {
                                    id: liveText
                                    x: FiliTheme.space3
                                    y: FiliTheme.space3
                                    width: parent.width - 2 * FiliTheme.space3
                                    height: chat.live ? implicitHeight : 0
                                    readOnly: true
                                    wrapMode: TextEdit.Wrap
                                    textFormat: TextEdit.PlainText
                                    text: chat.live
                                    color: FiliTheme.brume
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                                Text {
                                    visible: chat.working
                                    anchors { left: parent.left; leftMargin: FiliTheme.space3; bottom: parent.bottom }
                                    text: FiliI18n.tr((chat.states[chat.current] ?? "") === "waiting" ? "Waiting for your answer…" : "Working…") + "  "
                                    color: FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                                    Text {
                                        anchors { left: parent.right; baseline: parent.baseline }
                                        text: FiliI18n.tr("Stop")
                                        color: FiliTheme.voile
                                        font: parent.font
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: chat.stop()
                                        }
                                    }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: chat.log.length === 0 && !chat.working
                                text: FiliI18n.tr("Ask anything about this machine or Filigrane.")
                                color: FiliTheme.ardoise
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                        }

                        ListView {
                            id: list
                            anchors.fill: parent
                            visible: chat.listOpen
                            model: chat.sessions
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            delegate: Rectangle {
                                id: srow
                                required property var modelData
                                width: list.width
                                height: 36
                                color: srow.modelData.id === chat.current ? FiliTheme.nuit3 : (rowHit.containsMouse ? FiliTheme.nuit2 : "transparent")
                                Text {
                                    anchors { left: parent.left; leftMargin: FiliTheme.space3; right: del.left; verticalCenter: parent.verticalCenter }
                                    text: (srow.modelData.state === "working" ? "● " : "") + (srow.modelData.title || FiliI18n.tr("New session"))
                                    elide: Text.ElideRight
                                    color: FiliTheme.brume
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                                MouseArea {
                                    id: rowHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: chat.openSession(srow.modelData.id)
                                }
                                Text {
                                    id: del
                                    anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                                    visible: rowHit.containsMouse || delHit.containsMouse
                                    text: "×"
                                    color: delHit.containsMouse ? FiliTheme.cendre : FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: 18 }
                                    MouseArea {
                                        id: delHit
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: chat.removeSession(srow.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // Saisie, avec la puce de contexte (application active à l'ouverture)
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: FiliTheme.nuit4 }
                    Rectangle {
                        visible: chat.ctxOn && chat.ctxLabel !== ""
                        Layout.fillWidth: true
                        Layout.leftMargin: FiliTheme.space3
                        Layout.rightMargin: FiliTheme.space3
                        Layout.topMargin: FiliTheme.space2
                        Layout.preferredHeight: 22
                        radius: FiliTheme.radiusControl
                        color: FiliTheme.nuit2
                        Text {
                            anchors { left: parent.left; leftMargin: FiliTheme.space2; right: chipX.left; verticalCenter: parent.verticalCenter }
                            text: FiliI18n.tr("Context") + ": " + chat.ctxLabel
                            elide: Text.ElideRight
                            color: FiliTheme.brume2
                            font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                        }
                        Text {
                            id: chipX
                            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                            text: "×"
                            color: FiliTheme.ardoise
                            font { family: FiliTheme.font; pixelSize: 16 }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chat.ctxOn = false
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(140, Math.max(44, input.implicitHeight + 2 * FiliTheme.space3))
                        TextEdit {
                            id: input
                            anchors { fill: parent; margins: FiliTheme.space3 }
                            wrapMode: TextEdit.Wrap
                            enabled: !chat.working
                            color: FiliTheme.brume
                            selectionColor: FiliTheme.voile
                            selectedTextColor: FiliTheme.nuit
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            focus: true
                            Keys.onPressed: e => {
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                    chat.send(text);
                                    text = "";
                                    e.accepted = true;
                                }
                            }
                            Connections {
                                target: chat
                                function onFocusInput() { input.forceActiveFocus(); }
                            }
                            Text {
                                visible: !input.text
                                text: chat.working ? FiliI18n.tr((chat.states[chat.current] ?? "") === "waiting" ? "Waiting for your answer…" : "Working…") : FiliI18n.tr("Message Filigrane…")
                                color: FiliTheme.ardoise
                                font: input.font
                            }
                        }
                    }
                }
            }
        }
    }
}
