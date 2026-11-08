// Filigrane logo (brand/, linked into ~/.local/share/filigrane by bootstrap.sh): click opens the menu, middle click: About
import QtQuick
import Quickshell
import qs
import qs.bar

BarModule {
    // 10 px margin on the left, then the 44 px logo
    implicitWidth: 54
    implicitHeight: FiliTheme.barHeight

    Image {
        x: 10
        width: 44
        height: parent.height
        source: "file://" + Quickshell.env("HOME") + "/.local/share/filigrane/filigrane-" + (FiliTheme.light ? "couleur" : "sombre") + ".svg"
        sourceSize.width: 44
        fillMode: Image.PreserveAspectFit
    }
    BarHover {
        objectName: "logo"
        x: 10
        width: 44
        height: parent.height
        tip: ({ title: "Filigrane", hint: FiliI18n.tr("click: menu · right click: terminal · middle click: about") })
        click: "setsid -f " + FiliTheme.bin + "/menu"
        rclick: "setsid -f foot"
        onMiddleClicked: FiliAbout.show()
    }
}
