// Round volume control: 40 ticks on a 270 degree arc, the volume in the middle; drag around it or use the wheel.
import QtQuick
import Fili.Baladeur

Item {
    id: dial
    property real volume: 1
    signal changed(real volume)
    property real dragVolume: -1
    readonly property real shown: dragVolume >= 0 ? dragVolume : volume
    readonly property int ticks: 40

    width: 80
    height: 80

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
    }
    // Ticks: each one hangs from the centre and turns around it; the first is at the bottom left
    Repeater {
        model: dial.ticks
        Item {
            id: tick
            required property int index
            readonly property real fraction: index / (dial.ticks - 1)
            x: dial.width / 2
            y: dial.height / 2
            width: 0
            height: 0
            rotation: 225 + 270 * fraction
            Rectangle {
                x: -1
                y: -(dial.height / 2 - 8) - 2
                width: 2
                height: 5
                radius: 1
                color: tick.fraction <= dial.shown ? FiliTheme.accentColor : FiliTheme.border
            }
        }
    }
    Column {
        anchors.centerIn: parent
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(dial.shown * 100)
            font.family: FiliTheme.font
            font.pixelSize: 20
            font.weight: Font.Medium
            color: FiliTheme.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "%"
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: FiliTheme.muted
        }
    }
    function fromPoint(x, y) {
        let angle = Math.atan2(y - height / 2, x - width / 2) * 180 / Math.PI;
        if (angle < 0)
            angle += 360;
        // The arc starts at the bottom left (135 degrees, clockwise from the right on screen) and covers 270 degrees
        const n = angle >= 135 ? angle - 135 : angle + 225;
        return Math.max(0, Math.min(1, n / 270));
    }
    MouseArea {
        anchors.fill: parent
        onPressed: e => dial.dragVolume = dial.fromPoint(e.x, e.y)
        onPositionChanged: e => dial.dragVolume = dial.fromPoint(e.x, e.y)
        onReleased: {
            if (dial.dragVolume >= 0)
                dial.changed(dial.dragVolume);
            dial.dragVolume = -1;
        }
        onWheel: e => dial.changed(Math.max(0, Math.min(1, dial.volume + (e.angleDelta.y > 0 ? 0.02 : -0.02))))
    }
    Accessible.role: Accessible.Slider
    Accessible.name: Fili.tr("Volume")
}
