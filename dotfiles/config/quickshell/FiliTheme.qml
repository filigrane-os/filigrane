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
    // Rythme de la fili-bar: marge de chaque module, cellule minimale d'une icône seule (toutes alignées sur la même
    // grille), espace entre deux groupes, espace entre l'étiquette (CPU, RAM) et sa valeur
    readonly property int pad: 6
    readonly property int iconCell: 26
    readonly property int gap: 14
    readonly property int labelGap: 5
    // Texte réduit à une seule icône (code privé Nerd Font / Fili Icons)
    function isIcon(t) {
        return /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF])$/.test(t);
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
