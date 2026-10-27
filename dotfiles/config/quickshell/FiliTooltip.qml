pragma Singleton
// fili-tooltip: fiche d'information unique de la fili-bar, sous l'élément survolé (après 400 ms), inspirée des
// panneaux d'Omarchy mais en lecture seule: les actions restent sur les clics, rappelés par la ligne d'aide.
// Contenu: texte (sortie des scripts, balisage Pango retiré, <tt> = chasse fixe) ou fiche
// { title, rows: [[libellé, valeur]...], text, hint }.
import QtQuick
import QtQuick.Layouts
import Quickshell

Singleton {
    id: tip
    property Item target: null
    property var card: ({})
    // Répit après la fermeture d'un fili-panel (ms), pendant lequel aucune fiche ne s'ouvre
    readonly property int cooldown: 1500

    function normalize(c) {
        if (typeof c === "string")
            c = { text: c };
        c = Object.assign({}, c ?? {});
        if (c.text) {
            c.mono = c.mono ?? c.text.indexOf("<tt>") >= 0;
            c.text = c.text.replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
        }
        return c;
    }
    function empty(c) {
        return !c || (!c.title && !c.text && !(c.rows && c.rows.length));
    }
    function show(item, content) {
        const c = normalize(content);
        // Rien pendant un fili-panel, ni juste après sa fermeture (la souris est encore sur l'icône cliquée: la fiche
        // surgirait aussitôt et on croirait à un bug): il faut quitter l'icône puis y revenir après le répit
        if (empty(c) || FiliShell.panelOpen || Date.now() < FiliShell.panelClosedAt + cooldown) {
            hide(item);
            return;
        }
        card = c;
        if (target !== item) {
            target = item;
            popup.visible = false;
            delay.restart();
        }
    }
    // Met à jour la fiche affichée (données arrivées après le survol) sans relancer le délai
    function update(item, content) {
        if (item === target)
            card = normalize(content);
    }
    function hide(item) {
        if (item && item !== target)
            return;
        delay.stop();
        popup.visible = false;
        target = null;
    }

    Timer {
        id: delay
        interval: 400
        onTriggered: if (tip.target && !tip.empty(tip.card)) popup.visible = true
    }

    PopupWindow {
        id: popup
        visible: false
        anchor.item: tip.target
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        implicitWidth: body.implicitWidth + 28
        implicitHeight: body.implicitHeight + 22
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: FiliTheme.nuit
            border.color: FiliTheme.nuit4
            border.width: 1
            radius: 10

            ColumnLayout {
                id: body
                anchors.centerIn: parent
                spacing: 6
                Text {
                    visible: !!tip.card.title
                    text: tip.card.title ?? ""
                    color: FiliTheme.voile
                    font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
                }
                GridLayout {
                    visible: !!(tip.card.rows && tip.card.rows.length)
                    columns: 2
                    columnSpacing: 16
                    rowSpacing: 3
                    Repeater {
                        model: (tip.card.rows ?? []).reduce((a, r) => a.concat([{ t: r[0], key: true }, { t: r[1], key: false }]), [])
                        Text {
                            required property var modelData
                            text: modelData.t
                            color: modelData.key ? FiliTheme.ardoise : FiliTheme.brume
                            Layout.maximumWidth: modelData.key ? 140 : 420
                            elide: Text.ElideRight
                            font { family: FiliTheme.font; pixelSize: 13 }
                        }
                    }
                }
                Text {
                    visible: !!tip.card.text
                    text: tip.card.text ?? ""
                    color: FiliTheme.brume
                    font.family: tip.card.mono ? FiliTheme.mono : FiliTheme.font
                    font.pixelSize: tip.card.mono ? 12 : FiliTheme.size
                }
                Rectangle {
                    visible: !!tip.card.hint
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 1
                    color: FiliTheme.nuit3
                }
                Text {
                    visible: !!tip.card.hint
                    text: tip.card.hint ?? ""
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: 12 }
                }
            }
        }
    }
}
