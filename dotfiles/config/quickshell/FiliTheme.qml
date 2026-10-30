pragma Singleton
// Filigrane (brand.md): fond nuit, texte brume, accent voile; aucune autre couleur vive, états désaturés.
// Mode clair (fili-theme light, choisi dans le fili-panel écrans): les noms gardent leur rôle du mode sombre
// (nuit = fond, brume = texte, voile = accent) et prennent les teintes claires: fond papier, texte nuit, accent
// ardoise foncé, états assombris (contraste ≥ 4,8:1 sur papier)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme
    // "dark" (défaut) ou "light", lu dans l'état de fili-theme et relu dès qu'il change (les tests le fixent)
    property string mode: "dark"
    readonly property bool light: mode === "light"
    // Couleur d'accentuation (nom), lue dans l'état de fili-theme comme le mode
    property string accent: "default"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/theme"
    FileView {
        path: theme.testing ? "" : theme.stateFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: theme.mode = text().trim() === "light" ? "light" : "dark"
        onLoadFailed: theme.mode = "dark"
    }
    FileView {
        path: theme.testing ? "" : theme.stateFile.replace(/theme$/, "accent")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: theme.accent = text().trim()
        onLoadFailed: theme.accent = "default"
    }
    // FileView ne voit pas naître un fichier dans un dossier absent
    Component.onCompleted: if (!testing) Quickshell.execDetached(["mkdir", "-p", stateFile.replace(/\/[^/]*$/, "")])

    readonly property color nuit: light ? "#f3f1ec" : "#1c222b"
    readonly property color nuitProfond: light ? "#f8f7f3" : "#181d25"
    readonly property color nuit2: light ? "#e9e6df" : "#232b36"
    readonly property color nuit3: light ? "#dfdbd2" : "#2d3744"
    readonly property color nuit4: light ? "#cdc8bd" : "#3c4858"
    readonly property color ardoise: "#5f7894"
    readonly property color brume2: light ? "#4f5e70" : "#a9b8c8"
    // Couleur d'accentuation (fili-theme accent): [sombre, sombre vif, clair, clair vif]; défaut = brume en sombre, noir (nuit) en clair
    readonly property var accentTones: ({ default: ["#dbe7f4", "#f3f1ec", "#1c222b", "#0f1319"], voile: ["#9dbbd6", "#b9d0e4", "#3f5a78", "#2f4a66"], ardoise: ["#7f9ab6", "#9ab2ca", "#4f6884", "#3d5470"], sauge: ["#a3bfa8", "#bcd3c0", "#4a7354", "#385a42"], sable: ["#d2bf92", "#e0d1ab", "#80662b", "#654f1f"], cendre: ["#c98f93", "#d9a8ab", "#9a4f55", "#7d3c42"], brume: ["#dbe7f4", "#f3f1ec", "#4f5e70", "#1c222b"] })
    readonly property var tone: accentTones[accent] || accentTones.default
    readonly property color voile: light ? tone[2] : tone[0]
    readonly property color voileVif: light ? tone[3] : tone[1]
    readonly property color brume: light ? "#1c222b" : "#dbe7f4"
    readonly property color sable: light ? "#80662b" : "#d2bf92"
    readonly property color cendre: light ? "#9a4f55" : "#c98f93"
    // Couleur c avec l'opacité a (voiles translucides)
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property string font: "Jost"
    readonly property string mono: "JetBrains Mono"
    // Échelle typographique (tokens.md): système 13, vue (listes) 12, petit (secondaire, infobulles, intertitres) 11,
    // étiquette 10; titre ≥ 18 (seul palier où le Light est permis); accent = Jost SemiBold 600
    readonly property int size: 13
    readonly property int sizeList: 12
    readonly property int sizeSmall: 11
    readonly property int sizeLabel: 10
    readonly property int sizeTitle: 18
    readonly property int weightAccent: Font.DemiBold
    // Rayons: repères et jauges 2, contrôles / lignes / fiches 6, fenêtres de couche 10
    readonly property int radiusMark: 2
    readonly property int radiusControl: 6
    readonly property int radiusWindow: 10
    // Espacements: éléments liés 4, entre contrôles 8, entre groupes 12, bord d'onglet 16, marge de panneau 20, alerte 24
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 20
    readonly property int space6: 24
    readonly property int barHeight: 24
    // Rythme de la fili-bar, un seul pour tous les modules (pas d'écart propre aux groupes): marge de chaque module
    // (l'écart entre deux textes vaut donc 2 × pad), cellule minimale d'une icône seule (son trait fait ~10 px: de
    // même marge visible), espace entre l'étiquette (CPU, RAM) et sa valeur
    readonly property int pad: 7
    readonly property int iconCell: 24
    readonly property int labelGap: 5
    // Texte réduit à une seule icône (code privé Nerd Font / Fili Icons)
    function isIcon(t) {
        return /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF])$/.test(t);
    }

    // Règle de la fili-bar: icône (ou étiquette) en ardoise devant la valeur en blanc. "<icône> valeur" est coupé ici;
    // un état (sable, cendre, voile...) colore tout le module, seul le neutre (brume, brume2) grise l'icône.
    function glyph(t) {
        const m = /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF]) (.+)$/.exec(t);
        return m ? m[1] : "";
    }
    function value(t) {
        const m = /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF]) (.+)$/.exec(t);
        return m ? m[2] : t;
    }
    function iconColor(c) {
        return Qt.colorEqual(c, brume) || Qt.colorEqual(c, brume2) ? ardoise : c;
    }

    // Icône d'une sortie audio d'après ses propriétés PipeWire: casque (filaire ou Bluetooth), enceinte Bluetooth,
    // écran (HDMI, DisplayPort); "" pour des haut-parleurs (l'appelant garde l'icône graduée selon le volume)
    function sinkGlyph(p) {
        if (!p)
            return "";
        const s = [p["device.form-factor"], p["device.icon-name"], p["device.icon_name"], p["device.profile.name"],
                   p["node.name"], p["alsa.name"]].join(" ").toLowerCase();
        const head = /head(phone|set)|hands-?free|earbud/.test(s);
        if (p["device.api"] === "bluez5" || s.indexOf("bluez") >= 0 || s.indexOf("bluetooth") >= 0)
            return String.fromCodePoint(/speaker|car|portable/.test(s) && !head ? 0xf09a2 : 0xf0970);
        if (head)
            return String.fromCodePoint(0xf025);
        if (/hdmi|displayport/.test(s))
            return String.fromCodePoint(0xf0379);
        return "";
    }

    // Scripts et binaires de la distribution (~/.local/bin; FILI_BIN pour les tests)
    readonly property string bin: Quickshell.env("FILI_BIN") || Quickshell.env("HOME") + "/.local/bin"

    // Mode test (tests/fili-shell/run.sh): fenêtres masquées, commandes enregistrées au lieu d'être lancées
    readonly property bool testing: Quickshell.env("FILI_TEST") === "1"
    property var ran: []

    // Lance une commande shell détachée (actions des clics), depuis $HOME: un dossier courant supprimé ferait
    // échouer foot et d'autres ("failed to get current working directory"). Commande, sortie et erreurs dans
    // $XDG_RUNTIME_DIR/fili-shell-run.log (tmpfs) pour comprendre un clic qui ne lance rien
    function run(cmd) {
        if (!cmd)
            return;
        if (testing) {
            ran = ran.concat([cmd]);
            return;
        }
        Quickshell.execDetached(["sh", "-c", 'cd "$HOME" 2>/dev/null; l="${XDG_RUNTIME_DIR:-/tmp}/fili-shell-run.log"; echo "$(date +%T) $1" >> "$l"; sh -c "$1" >> "$l" 2>&1 || echo "  -> code $?" >> "$l"', "sh", cmd]);
    }
}
