// Filigrane logo (brand/, linked into ~/.local/share/filigrane by bootstrap.sh): click opens the menu, middle click: About
import QtQuick
import Quickshell
import qs
import qs.bar

BarModule {
    implicitWidth: 44
    implicitHeight: FiliTheme.barHeight

    Image {
        anchors.centerIn: parent
        source: "file://" + Quickshell.env("HOME") + "/.local/share/filigrane/filigrane-" + (FiliTheme.light ? "couleur" : "sombre") + ".svg"
        sourceSize.width: 44
        fillMode: Image.PreserveAspectFit
    }
    BarHover {
        objectName: "logo"
        anchors.fill: parent
        tip: ({ title: "Filigrane", hint: FiliI18n.tr("click: menu · right click: terminal · middle click: about") })
        click: "setsid -f " + FiliTheme.bin + "/menu"
        rclick: "setsid -f foot"
        onMiddleClicked: FiliAbout.show()
    }
}
