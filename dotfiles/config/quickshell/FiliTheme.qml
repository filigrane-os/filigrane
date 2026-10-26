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

    // Scripts et binaires de la distribution (~/.local/bin)
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin"

    // Lance une commande shell détachée (actions des clics)
    function run(cmd) {
        if (cmd)
            Quickshell.execDetached(["sh", "-c", cmd]);
    }
}
