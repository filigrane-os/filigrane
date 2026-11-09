pragma Singleton
// Display identification (Settings > Display > Identify): the name and make/model of each output in large letters
// on that very screen for a few seconds, to tell which rectangle of the canvas is which screen. Windows exist only
// while shown.
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: ident
    property bool shown: false
    // name -> "make model", from the Outputs request of the settings page
    property var labels: ({})

    function show(labels) {
        ident.labels = labels;
        shown = true;
        hide.restart();
    }
    Timer {
        id: hide
        interval: 4000
        onTriggered: ident.shown = false
    }

    Variants {
        model: ident.shown && !FiliTheme.testing ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; left: true }
            margins { top: 40; left: 40 }
            implicitWidth: box.width
            implicitHeight: box.height
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "fili-identify"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            Rectangle {
                id: box
                width: col.width + 2 * FiliTheme.space3
                height: col.height + 2 * FiliTheme.space3
                radius: FiliTheme.radiusControl
                color: FiliTheme.nuit
                border.color: FiliTheme.voile
                border.width: FiliTheme.borderWidth
                Column {
                    id: col
                    anchors.centerIn: parent
                    Text {
                        text: modelData.name
                        color: FiliTheme.voile
                        font { family: FiliTheme.font; pixelSize: 56; weight: FiliTheme.weightAccent }
                    }
                    Text {
                        text: ident.labels[modelData.name] ?? ""
                        color: FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                }
            }
        }
    }
}
