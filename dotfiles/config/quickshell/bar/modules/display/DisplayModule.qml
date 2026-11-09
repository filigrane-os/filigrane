// Displays: click = panel (layout, resolution, scale, rotation), wheel = brightness
import QtQuick
import qs
import qs.bar

BarScript {
    objectName: "display"
    panel: "display"
    panelSource: Qt.resolvedUrl("DisplayPanel.qml")
    stat: "display"; hideEmpty: false
    tipInfo: "display"
    hover.onLeftClicked: togglePanel()
    scrollUp: "brightnessctl -q set 3%+; " + FiliTheme.bin + "/fili-shell bar refresh 23"
    scrollDown: "brightnessctl -q set 3%-; " + FiliTheme.bin + "/fili-shell bar refresh 23"
}
