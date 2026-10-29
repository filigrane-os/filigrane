// Contour de l'élément choisi au clavier dans les fili-panel et le fili-notification-center, visible seulement une
// fois le clavier utilisé (FiliShell.keyNav): rien ne change pour la souris. Enfant de l'élément (pas dans un Layout).
import QtQuick

Rectangle {
    property Item target: parent
    property bool shown: target.activeFocus
    property real gap: 2
    anchors { fill: target; margins: -gap }
    radius: (target.radius ?? FiliTheme.radiusControl) + gap
    color: "transparent"
    border.width: 1
    border.color: FiliTheme.voile
    visible: shown && FiliShell.keyNav
}
