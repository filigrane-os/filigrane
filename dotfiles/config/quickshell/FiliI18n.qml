pragma Singleton
// Traductions du fili-shell. Textes écrits en anglais dans le code: FiliI18n.tr("Battery %1 %", n). Une autre langue
// est un catalogue i18n/<langue>.json ({"texte anglais": "traduction"}, %1, %2... dans l'ordre voulu), partagé avec
// bar-stats (apps/bar-stats/src/i18n.rs); pas de catalogue, ou pas d'entrée, = anglais. Langue: FILI_LANG, sinon le
// choix de l'utilisateur (fili-lang: $XDG_STATE_HOME/filigrane/locale, suivi en direct: changer de langue retraduit
// tout le shell sans le relancer), sinon la première posée de LC_ALL, LC_MESSAGES, LANG ("fr_FR.UTF-8" -> fr; C, POSIX
// -> en), comme lib/i18n.sh pour les scripts.
// Clé spéciale "@decimal": séparateur décimal (num). Dates: locale (Qt) de la langue.
// Ajouter une langue: copier i18n/fr.json, traduire les valeurs, scripts/check-i18n.sh.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: i18n
    // Choix de l'utilisateur (fili-lang), "" = langue du système
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/locale"
    property string choice: ""
    FileView {
        id: stateView
        path: i18n.stateFile
        // Lu dès la création: la langue est juste au premier affichage
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: i18n.choice = text().trim()
        onLoadFailed: i18n.choice = ""
    }
    // fili-lang prévient aussi par le canal du shell (`fili-shell lang`): inotify ne voit pas naître un fichier dans un
    // dossier créé après le début du suivi
    Connections {
        target: FiliShell
        function onCommand(target, action, args) {
            if (target === "lang")
                stateView.reload();
        }
    }
    // FileView ne voit pas naître un fichier dans un dossier absent
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateFile.replace(/\/[^/]*$/, "")])
    // Variable de langue retenue (LANG=fr_FR.UTF-8 -> fr_FR)
    readonly property string posix: (Quickshell.env("FILI_LANG") || choice || Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "en").split(/[.@]/)[0]
    readonly property string lang: {
        const l = posix.split("_")[0];
        return /^[a-z]+$/.test(l) ? l : "en";
    }
    // Locale Qt des dates (noms des jours et des mois, premier jour de la semaine): en_GB pour l'anglais sans région
    // (semaine du lundi, 24 h)
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

    // Texte traduit, %1, %2... remplacés par les arguments
    function tr(s, ...args) {
        const t = catalog[s] ?? s;
        return args.length ? t.replace(/%(\d)/g, (m, n) => args[n - 1] ?? m) : t;
    }
    // Nombre avec d décimales et le séparateur de la langue
    function num(v, d) {
        const s = Number(v).toFixed(d ?? 0);
        return catalog["@decimal"] ? s.replace(".", catalog["@decimal"]) : s;
    }
}
