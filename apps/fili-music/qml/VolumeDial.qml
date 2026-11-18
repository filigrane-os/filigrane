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
    // Band levels (0..1, low to high) and the colour of the tick at `fraction` of the arc
    property var levels: []
    function lit(fraction) {
        if (levels.length === 0)
            return FiliTheme.accentColor;
        const at = fraction * (levels.length - 1);
        const i = Math.floor(at), j = Math.min(levels.length - 1, i + 1);
        const raw = levels[i] + (levels[j] - levels[i]) * (at - i);
        // Music sits between 0.3 and 0.75 of the raw scale: stretched over the whole range and sharpened, the level goes from
        // a very dark accent through the accent to a lightened one
        const level = Math.pow(Math.max(0, Math.min(1, (raw - 0.3) / 0.45)), 1.5);
        const dark = Qt.tint(FiliTheme.background, FiliTheme.alpha(FiliTheme.accentColor, 0.2));
        if (level < 0.6)
            return Qt.tint(dark, FiliTheme.alpha(FiliTheme.accentColor, level / 0.6));
        return Qt.tint(FiliTheme.accentColor, FiliTheme.alpha(Qt.lighter(FiliTheme.accentBright, 1.35), (level - 0.6) / 0.4));
    }
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
                // An active tick follows the sound: its band (low to high along the arc) lights it from the accent colour towards
                // the bright one, a calm one is dimmed; the ticks beyond the volume stay off
                color: tick.fraction <= dial.shown ? dial.lit(tick.fraction) : FiliTheme.border
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
