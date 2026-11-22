// Settings page "Wallpaper" (fili-settings): a grid of the images of ~/.local/share/wallpapers (those of the
// distribution) and ~/Pictures/Wallpapers (the user's own, drop images there); a click runs `wallpaper IMAGE`, which
// remembers the choice. The image in use is outlined.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.controls

ColumnLayout {
    id: view
    spacing: FiliTheme.space1
    property var images: []
    property string current: ""
    readonly property string home: Quickshell.env("HOME")
    readonly property string distDir: home + "/.local/share/wallpapers"
    readonly property string userDir: home + "/Pictures/Wallpapers"

    function pick(path) {
        current = path;
        FiliTheme.run("'" + FiliTheme.bin + "/wallpaper' '" + path.replace(/'/g, "'\\''") + "'");
    }
    function openFolder() {
        FiliTheme.run("mkdir -p '" + userDir + "' && xdg-open '" + userDir + "'");
    }

    Process {
        running: !FiliTheme.testing
        command: ["sh", "-c", 'for d in "$1" "$2"; do [ -d "$d" ] && find -L "$d" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) | sort; done; echo "@"; cat "${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper" 2>/dev/null', "sh", view.distDir, view.userDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n@\n");
                view.images = parts[0].split("\n").map(l => l.trim()).filter(l => l);
                view.current = (parts[1] ?? "").trim();
            }
        }
    }

    Text {
        text: FiliI18n.tr("Wallpaper")
        color: FiliTheme.voile
        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: FiliI18n.tr("The image behind the windows. Add your own to the Pictures/Wallpapers folder.")
        color: FiliTheme.brume2
        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
    }
    PanelSection { divided: false; text: FiliI18n.tr("IMAGES") }
    Flow {
        id: grid
        objectName: "wallpapers"
        Layout.fillWidth: true
        spacing: FiliTheme.space2
        readonly property int cols: Math.max(1, Math.floor((width + spacing) / (140 + spacing)))
        readonly property real cell: (width - (cols - 1) * spacing) / cols
        Repeater {
            model: view.images
            Rectangle {
                id: tile
                required property string modelData
                readonly property bool on: modelData === view.current
                width: grid.cell
                height: grid.cell * 0.6
                radius: FiliTheme.radiusControl
                color: FiliTheme.nuit3
                border { width: on ? 2 : 0; color: FiliTheme.voile }
                activeFocusOnTab: true
                Keys.onReturnPressed: view.pick(modelData)
                Keys.onSpacePressed: view.pick(modelData)
                Accessible.role: Accessible.Button
                Accessible.name: modelData.split("/").pop()
                Image {
                    anchors { fill: parent; margins: tile.on ? 3 : 0 }
                    source: "file://" + tile.modelData
                    sourceSize.width: 280
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                FocusRing { shown: tile.activeFocus }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.pick(tile.modelData)
                }
            }
        }
    }
    PanelButton {
        objectName: "open-folder"
        label: FiliI18n.tr("Open the folder of your wallpapers")
        onClicked: view.openFolder()
    }
}
