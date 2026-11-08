pragma Singleton
// Translations of the fili-shell. Texts written in English in the code: FiliI18n.tr("Battery %1 %", n). Another language
// is a catalog i18n/<language>.json ({"English text": "translation"}, %1, %2... in the wanted order), shared with
// bar-stats (apps/bar-stats/src/i18n.rs); no catalog, or no entry, = English. Language: FILI_LANG, else the
// user's choice (fili-lang: $XDG_STATE_HOME/filigrane/locale, followed live: changing the language retranslates
// the whole shell without restarting it), else the first one set of LC_ALL, LC_MESSAGES, LANG ("fr_FR.UTF-8" -> fr; C, POSIX
// -> en), like lib/i18n.sh for the scripts.
// Plugins of the fili-bar bring their own: bar/modules/<name>/i18n/<language>.json (see pluginCatalog).
// Special key "@decimal": decimal separator (num). Dates: Qt locale of the language.
// Adding a language: copy i18n/fr.json, translate the values, scripts/check-i18n.sh.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: i18n
    // Choice of the user (fili-lang), "" = language of the system
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/locale"
    property string choice: ""
    FileView {
        id: stateView
        path: i18n.stateFile
        // Read as soon as created: the language is right at the first display
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: i18n.choice = text().trim()
        onLoadFailed: i18n.choice = ""
    }
    // fili-lang also warns through the shell channel (`fili-shell lang`): inotify does not see a file appear in a folder
    // created after the watching began
    Connections {
        target: FiliShell
        function onCommand(target, action, args) {
            if (target === "lang")
                stateView.reload();
        }
    }
    // FileView does not see a file appear in a missing folder
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", stateFile.replace(/\/[^/]*$/, "")]);
        scanPlugins();
    }
    // Variable de langue retenue (LANG=fr_FR.UTF-8 -> fr_FR)
    readonly property string posix: (Quickshell.env("FILI_LANG") || choice || Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "en").split(/[.@]/)[0]
    readonly property string lang: {
        const l = posix.split("_")[0];
        return /^[a-z]+$/.test(l) ? l : "en";
    }
    // Qt locale of the dates (names of days and months, first day of the week): en_GB for English without a region
    // (week starting on Monday, 24 h)
    readonly property var locale: Qt.locale(/^[a-z]+_[A-Z]+$/.test(posix) ? posix : lang === "en" ? "en_GB" : lang)
    property var catalog: ({})

    FileView {
        path: i18n.lang === "en" ? "" : Quickshell.shellDir + "/i18n/" + i18n.lang + ".json"
        blockLoading: true
        printErrors: false
        onPathChanged: if (path === "") i18n.catalog = {}
        onLoadFailed: i18n.catalog = {}
        onLoaded: {
            try {
                i18n.catalog = JSON.parse(text());
            } catch (e) {
                i18n.catalog = {};
            }
        }
    }

    // Translations shipped by the fili-bar modules (bar/modules/<name>/i18n/<language>.json, same format as a catalog):
    // read when the language changes; the catalog of the shell wins over them. A plugin written in English needs none.
    property var pluginCatalog: ({})
    function scanPlugins() {
        if (lang !== "en")
            plugins.running = true;
        else
            pluginCatalog = ({});
    }
    onLangChanged: scanPlugins()
    Process {
        id: plugins
        command: ["sh", "-c", 'printf "["; s=; for f in "$1"/*/i18n/"$2".json; do [ -f "$f" ] || continue; printf "%s" "$s"; cat "$f"; s=,; done; printf "]"', "sh", Quickshell.shellDir + "/bar/modules", i18n.lang]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    i18n.pluginCatalog = Object.assign({}, ...JSON.parse(text).reverse());
                } catch (e) {
                    i18n.pluginCatalog = ({});
                }
            }
        }
    }

    // Translated text, %1, %2... replaced by the arguments
    function tr(s, ...args) {
        const t = catalog[s] ?? pluginCatalog[s] ?? s;
        return args.length ? t.replace(/%(\d)/g, (m, n) => args[n - 1] ?? m) : t;
    }
    // Number with d decimals and the separator of the language
    function num(v, d) {
        const s = Number(v).toFixed(d ?? 0);
        return catalog["@decimal"] ? s.replace(".", catalog["@decimal"]) : s;
    }
}
