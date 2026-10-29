pragma Singleton
// États de la fili-bar lus dans leurs fichiers, sans lancer de script: FileView relit un fichier dès qu'il change
// (inotify), même absent au départ. Chaque état est un objet {text, class, tooltip}, comme une ligne JSON de script
// (BarScript.value), partagé par les barres de tous les écrans.
//   alertes   ~/.local/state/alerts/<kind>[.count]   écrites par bar-alert push, wa-count; vidées par bar-alert open
//   tiroir    $XDG_RUNTIME_DIR/bar-tray-open          présent = ouvert (bar-tray toggle)
//   minuteur  $XDG_RUNTIME_DIR/bar-timer              "T <fin>" | "S <début>" | "done" (bar-timer click/add/expire)
//   sauvegarde                                         stat backup de bar-stats, gardée visible 10 s après la fin
//   agent IA   $XDG_RUNTIME_DIR/fili-ai/state.json     sessions de Claude Code et limites du forfait (fili-ai-session)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: st
    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string alerts: Quickshell.env("HOME") + "/.local/state/alerts"
    readonly property var empty: ({ text: "" })

    component Watched: FileView {
        property bool exists: false
        property string content: ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            exists = true;
            content = text();
        }
        onLoadFailed: {
            exists = false;
            content = "";
        }
    }

    // ───── alertes (mail, WhatsApp, agenda) ─────
    Watched { id: mailF; path: st.alerts + "/mail" }
    Watched { id: mailC; path: st.alerts + "/mail.count" }
    Watched { id: whatsappF; path: st.alerts + "/whatsapp" }
    Watched { id: whatsappC; path: st.alerts + "/whatsapp.count" }
    Watched { id: calF; path: st.alerts + "/cal" }
    Watched { id: calC; path: st.alerts + "/cal.count" }

    // Instant (s) qui fait expirer les événements de l'agenda, avancé chaque minute tant qu'il y en a
    property real minute: Date.now() / 1000
    readonly property var mail: alert("mail", mailF.content, mailC.exists ? mailC.content : null, minute)
    readonly property var whatsapp: alert("whatsapp", whatsappF.content, whatsappC.exists ? whatsappC.content : null, minute)
    readonly property var cal: alert("cal", calF.content, calC.exists ? calC.content : null, minute)
    // Au repos, dans le tiroir ouvert (sans alerte: sinon elle est sortie dans la barre)
    readonly property var mailIdle: drawer("mail", mail)
    readonly property var whatsappIdle: drawer("whatsapp", whatsapp)
    readonly property var calIdle: drawer("cal", cal)

    Timer {
        interval: 60000
        repeat: true
        running: calF.content !== ""
        onTriggered: {
            st.minute = Date.now() / 1000;
            // Plus aucun événement à venir: le fichier est vidé (comme le faisait bar-alert)
            if (st.cal.text === "" && !calC.exists)
                calF.setText("");
        }
    }

    // Lignes "champ<TAB>champ..." d'un fichier d'alertes
    function rows(text) {
        return text.split("\n").filter(l => l !== "").map(l => l.split("\t"));
    }
    // count: contenu de <kind>.count (compteur réel de non-lus, prioritaire), null s'il n'existe pas
    function alert(kind, text, count, now) {
        const r = rows(text);
        // Fiches au standard de la fili-tooltip: titre à gauche, lignes expéditeur / sujet à droite
        const lines = r.slice(-8).map(x => [x[0], x[1] ?? ""]);
        const wa = String.fromCodePoint(0xf05a3);
        const name = { mail: "Proton Mail", cal: "Proton Calendar", whatsapp: "WhatsApp" }[kind];
        if (count !== null) {
            const n = parseInt(count);
            if (!(n > 0))
                return empty;
            return { text: wa + " " + n, class: "active", tooltip: { title: name, rows: [[FiliI18n.tr("Unread"), String(n)]].concat(lines), hint: FiliI18n.tr("click: open the web app") } };
        }
        if (r.length === 0)
            return empty;
        if (kind === "cal") {
            // "début epoch<TAB>HH:MM<TAB>titre", affiché jusqu'à 5 min après le début
            const live = r.filter(x => Number(x[0]) >= now - 300).sort((a, b) => Number(a[0]) - Number(b[0]));
            if (live.length === 0)
                return empty;
            const title = live[0][2] ?? "";
            const short = title.length > 28 ? title.slice(0, 27) + "…" : title;
            return { text: " " + short + " " + (live[0][1] ?? ""), class: "active",
                     tooltip: { title: name, rows: live.map(x => [x[1], x[2] ?? ""]), hint: FiliI18n.tr("click: open %1", name) } };
        }
        if (kind === "mail")
            return { text: " " + r.length, class: "active", tooltip: { title: name, rows: lines, hint: FiliI18n.tr("click: open %1", name) } };
        return { text: wa + " " + r.length, class: "active", tooltip: { title: name, rows: lines, hint: FiliI18n.tr("click: open the web app") } };
    }
    function drawer(kind, a) {
        if (!trayOpen || a.text !== "")
            return empty;
        const [g, name] = { mail: ["", "Proton Mail"], cal: ["", "Proton Calendar"] }[kind] ?? [String.fromCodePoint(0xf05a3), "WhatsApp"];
        return { text: g, class: "idle", tooltip: { title: name, hint: FiliI18n.tr("click: open") } };
    }

    // ───── tiroir ─────
    Watched { id: trayF; path: st.run + "/bar-tray-open" }
    readonly property bool trayOpen: trayF.exists
    readonly property var trayHandle: trayOpen ? { text: "", class: "open", tooltip: { title: FiliI18n.tr("Drawer"), hint: FiliI18n.tr("click: fold") } } : { text: "", tooltip: { title: FiliI18n.tr("Drawer"), hint: FiliI18n.tr("click: show the backup") } }

    // ───── sauvegarde ─────
    // Repliée, visible seulement en cours ou en échec; repassée au repos, elle reste 10 s (pour pouvoir la relancer
    // après un clic par erreur)
    property var backupRaw: empty
    property bool backupLinger: false
    readonly property var backup: trayOpen || backupLinger || backupRaw["class"] !== "idle" ? backupRaw : empty
    function setBackup(j) {
        if (j["class"] === "idle" && (backupRaw["class"] ?? "idle") !== "idle") {
            backupLinger = true;
            linger.restart();
        }
        backupRaw = j;
    }
    Timer {
        id: linger
        interval: 10000
        onTriggered: st.backupLinger = false
    }
    Connections {
        target: FiliShell
        function onStat(name, data) {
            if (name === "backup")
                st.setBackup(data);
        }
    }
    Component.onCompleted: {
        if (FiliShell.stats.backup)
            backupRaw = FiliShell.stats.backup;
        // FileView ne voit pas naître un fichier dans un dossier absent
        if (!FiliTheme.testing)
            Quickshell.execDetached(["mkdir", "-p", alerts]);
    }

    // ───── agent IA ─────
    // Sessions écrites par fili-ai-session (hooks et status line de Claude Code): état, fenêtre niri, contexte, coût;
    // limites du forfait gardées après la dernière session. Fenêtre d'une session qui attend regardée: plus de mise en
    // avant (fili-ai-session seen)
    Watched { id: aiF; path: st.run + "/fili-ai/state.json" }
    property var aiData: ({ sessions: [], limits: null })
    readonly property string aiText: aiF.content
    onAiTextChanged: {
        try {
            aiData = aiText.trim() ? JSON.parse(aiText) : { sessions: [], limits: null };
        } catch (e) {
            // Fichier en cours d'écriture: l'état précédent reste
        }
        aiSeen();
    }
    readonly property var ai: aiFor(aiData, Niri.focusedId, Niri.windows)
    Connections {
        target: Niri
        function onFocusedIdChanged() {
            st.aiSeen();
        }
    }
    function aiSeen() {
        for (const s of aiData.sessions ?? [])
            if (s.attention && s.window !== undefined && s.window === Niri.focusedId)
                FiliTheme.run(FiliTheme.bin + "/fili-ai-session seen " + s.id);
    }
    // Nom d'une session: titre de sa fenêtre (sujet donné par Claude Code, sans son indicateur d'activité ✳ ◐ ⠋...), sinon son dossier
    function aiName(s, windows) {
        const title = (windows?.[s.window]?.title ?? "").replace(/^[\u2000-\u2bff\s]+/, "");
        return title || (s.cwd ?? "").split("/").filter(x => x).pop() || "~";
    }
    // Ligne de limite du forfait: usage, remise à zéro, jauge et repère du rythme régulier (part écoulée de la
    // fenêtre: 5 h ou 7 jours), comme le « pace » du panneau des agents d'Omarchy
    function aiLimit(label, l, span, fmt, now) {
        if (!l || l.used_percentage === undefined)
            return null;
        const reset = l.resets_at ? " · " + FiliI18n.tr("resets %1", FiliI18n.locale.toString(new Date(l.resets_at * 1000), fmt)) : "";
        const mark = l.resets_at ? 1 - (l.resets_at - now) / span : -1;
        return [label, Math.round(l.used_percentage) + " %" + reset, { value: l.used_percentage / 100, mark: mark }];
    }
    // now: instant (s), l'heure courante par défaut (fixé par les tests)
    function aiFor(data, focused, windows, now) {
        const icon = String.fromCodePoint(0xf06a9);
        const sessions = data?.sessions ?? [];
        // Une session regardée en ce moment n'appelle plus l'attention
        const calls = sessions.filter(s => s.attention && s.window !== focused);
        const rows = sessions.slice(0, 6).map(s => {
            const state = { working: FiliI18n.tr("working"), waiting: FiliI18n.tr("waiting for you"), done: FiliI18n.tr("finished") }[s.state] ?? FiliI18n.tr("ready");
            const parts = [state];
            if (s.ctx !== undefined && s.ctx !== null)
                parts.push(FiliI18n.tr("context %1 %", Math.round(s.ctx)));
            if (s.cost)
                parts.push(FiliI18n.num(s.cost, 2) + " $");
            if (s.model)
                parts.push(s.model);
            return [aiName(s, windows), parts.join(" · ")];
        });
        const waitMsg = sessions.find(s => s.state === "waiting" && s.message)?.message;
        if (waitMsg)
            rows.push(["", waitMsg]);
        if (sessions.length === 0)
            rows.push([FiliI18n.tr("Sessions"), FiliI18n.tr("none")]);
        const lim = data?.limits;
        now = now ?? Date.now() / 1000;
        const five = aiLimit(FiliI18n.tr("5-hour limit"), lim?.five_hour, 5 * 3600, "HH:mm", now);
        const week = aiLimit(FiliI18n.tr("Weekly limit"), lim?.seven_day, 7 * 86400, "ddd HH:mm", now);
        if (five)
            rows.push(five);
        if (week)
            rows.push(week);
        if ((five || week) && lim.seen && now - lim.seen > 900)
            rows.push(["", FiliI18n.tr("as of %1", FiliI18n.locale.toString(new Date(lim.seen * 1000), "ddd HH:mm"))]);
        const card = {
            title: sessions.length ? "Claude Code" : FiliI18n.tr("AI agent"),
            rows: rows,
            hint: FiliI18n.tr("click: go to the session (none: start the agent) · middle click: new session · right click: choose the agent")
        };
        if (calls.some(s => s.state === "waiting"))
            return { text: icon + " ASK", class: "waiting", tooltip: card };
        if (calls.length)
            return { text: icon + " DONE", class: "done", tooltip: card };
        const working = sessions.filter(s => s.state === "working").length;
        if (sessions.length)
            return { text: icon + (sessions.length > 1 ? " " + sessions.length : ""), class: working ? "working" : "idle", tooltip: card };
        return { text: icon, class: "off", tooltip: card };
    }

    // ───── minuteur / chronomètre ─────
    Watched { id: timerF; path: st.run + "/bar-timer" }
    readonly property var timerFile: {
        const p = timerF.content.trim().split(" ");
        return { kind: p[0] ?? "", val: Number(p[1] ?? 0) };
    }
    // Seconde courante, avancée seulement tant qu'un minuteur ou un chronomètre tourne
    property real second: Date.now() / 1000
    readonly property var timer: timerFor(timerFile.kind, timerFile.val, second)
    // Minuteur écoulé: bar-timer expire (état "done" et notification), une fois par minuteur
    property real expired: 0
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: st.timerFile.kind === "S" || st.timerFile.kind === "T"
        onTriggered: {
            st.second = Date.now() / 1000;
            if (st.timerFile.kind === "T" && st.timerFile.val <= st.second && st.expired !== st.timerFile.val) {
                st.expired = st.timerFile.val;
                FiliTheme.run(FiliTheme.bin + "/bar-timer expire");
            }
        }
    }
    // secondes -> [H:]MM:SS
    function fmt(s) {
        const p = n => String(n).padStart(2, "0");
        return s >= 3600 ? Math.floor(s / 3600) + ":" + p(Math.floor(s % 3600 / 60)) + ":" + p(s % 60) : p(Math.floor(s / 60)) + ":" + p(s % 60);
    }
    function timerFor(kind, val, now) {
        const icon = "";
        now = Math.floor(now);
        if (kind === "")
            return { text: icon, class: "idle", tooltip: FiliI18n.tr("Timer / stopwatch (click: choose)") };
        if (kind === "S")
            return { text: icon + " " + fmt(Math.max(0, now - val)), class: "stopwatch", tooltip: FiliI18n.tr("Stopwatch (click: stop)") };
        if (kind === "T" && val - now > 0)
            return { text: icon + " " + fmt(val - now), class: "active", tooltip: FiliI18n.tr("Timer (click: cancel, right click: +5 min)") };
        return { text: icon + " 00:00", class: "done", tooltip: FiliI18n.tr("Done (click: dismiss)") };
    }
}
