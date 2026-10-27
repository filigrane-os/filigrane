pragma Singleton
// Filigrane (brand.md): fond nuit, texte brume, accent voile; aucune autre couleur vive, états désaturés
import QtQuick
import Quickshell

Singleton {
    readonly property color nuit: "#1c222b"
    readonly property color nuit3: "#2d3744"
    readonly property color nuit4: "#3c4858"
    readonly property color ardoise: "#5f7894"
    readonly property color brume2: "#a9b8c8"
    readonly property color voile: "#9dbbd6"
    readonly property color brume: "#dbe7f4"
    readonly property color sable: "#d2bf92"
    readonly property color cendre: "#c98f93"

    readonly property string font: "Jost"
    readonly property string mono: "JetBrains Mono"
    readonly property int size: 13
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
