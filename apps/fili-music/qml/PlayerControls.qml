// Bottom of the player panel: cover, what plays, volume dial, transport buttons and the progress bar.
import QtQuick
import Fili.Baladeur

Rectangle {
    id: controls
    signal artworkClicked(int albumId)
    readonly property var track: Store.currentTrack
    readonly property real position: Store.player.position || 0
    readonly property real length: Store.player.duration || 0

    color: FiliTheme.background
    // Ambient colour of the cover playing
    AmbientColor {
        id: ambient
        source: cover.source
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: FiliTheme.alpha(ambient.color, 0.30) }
            GradientStop { position: 1; color: FiliTheme.alpha(ambient.color, 0.05) }
        }
        opacity: ambient.color.a > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }
    implicitHeight: top.height + transport.height + FiliTheme.space4 + FiliTheme.space3

    Row {
        id: top
        x: FiliTheme.space3
        y: FiliTheme.space3
        width: parent.width - 2 * FiliTheme.space3
        spacing: FiliTheme.space3
        Artwork {
            id: cover
            width: 80
            height: 80
            itemId: controls.track && controls.track.album_id !== null ? controls.track.album_id : -1
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "black"
                opacity: coverArea.containsMouse && cover.itemId >= 0 ? 0.25 : 0
            }
            MouseArea {
                id: coverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: cover.itemId >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (cover.itemId >= 0)
                    controls.artworkClicked(cover.itemId)
            }
        }
        Column {
            width: parent.width - cover.width - dial.width - 2 * parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: controls.track ? controls.track.title : Fili.tr("Not playing")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
            }
            Text {
                width: parent.width
                visible: controls.track !== null
                elide: Text.ElideRight
                text: controls.track ? (controls.track.album_id !== null ? (Store.albumTitle(controls.track.album_id) || Fili.tr("Unknown album")) : Fili.tr("Unknown album")) : ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.textSecondary
            }
            Text {
                width: parent.width
                visible: controls.track !== null
                elide: Text.ElideRight
                text: controls.track ? Store.trackArtist(controls.track) : ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.textSecondary
            }
            Text {
                width: parent.width
                visible: controls.track !== null
                elide: Text.ElideRight
                text: controls.track ? Store.formatInfo(controls.track) + ", " + Store.sizeText(controls.track.file_size) : ""
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeLabel
                color: FiliTheme.muted
            }
        }
        VolumeDial {
            id: dial
            levels: Store.levels
            volume: Store.player.volume === undefined ? 1 : Store.player.volume
            onChanged: v => Store.setVolume(v)
        }
    }

    Item {
        id: transport
        anchors { left: parent.left; right: parent.right; top: top.bottom; topMargin: FiliTheme.space3; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3 }
        height: 36
        Row {
            id: buttons
            anchors.verticalCenter: parent.verticalCenter
            spacing: FiliTheme.space4
            Repeater {
                model: [
                    { key: "prev", glyph: String.fromCodePoint(0xf2f11), size: 16 },
                    { key: "play", glyph: "\uf04b", size: 20 },
                    { key: "next", glyph: String.fromCodePoint(0xf2f12), size: 16 }
                ]
                Item {
                    id: tb
                    required property var modelData
                    readonly property bool dim: modelData.key !== "play" && !Store.hasTrack
                    width: 28
                    height: 28
                    Text {
                        anchors.centerIn: parent
                        text: tb.modelData.key === "play" ? (Store.playing ? "\uf04c" : "\uf04b") : tb.modelData.glyph
                        font.family: FiliTheme.icons
                        font.pixelSize: tb.modelData.size
                        color: tb.dim ? FiliTheme.muted : FiliTheme.text
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: FiliTheme.radiusControl
                        color: tbArea.pressed ? FiliTheme.surfaceActive : tbArea.containsMouse && !tb.dim ? FiliTheme.surfaceHover : "transparent"
                        z: -1
                    }
                    MouseArea {
                        id: tbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !tb.dim
                        onClicked: tb.modelData.key === "prev" ? Store.previous() : tb.modelData.key === "next" ? Store.next() : Store.togglePlay()
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: tb.modelData.key === "prev" ? Fili.tr("Previous") : tb.modelData.key === "next" ? Fili.tr("Next") : (Store.playing ? Fili.tr("Pause") : Fili.tr("Play"))
                }
            }
        }
        // Progress: a bar that grows on hover, seek by click or drag; moving segments while the track loads
        Item {
            id: progress
            anchors { left: buttons.right; leftMargin: FiliTheme.space4; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 30
            property real drag: -1
            readonly property real fraction: drag >= 0 ? drag : (controls.length > 0 ? Math.min(1, controls.position / controls.length) : 0)
            readonly property bool loading: Store.player.is_loading === true
            Rectangle {
                id: bar
                y: 6
                width: parent.width
                height: barArea.containsMouse || progress.drag >= 0 ? 6 : 4
                radius: 2
                color: FiliTheme.alpha(FiliTheme.muted, 0.35)
                clip: true
                Rectangle {
                    visible: !progress.loading
                    width: bar.width * progress.fraction
                    height: parent.height
                    radius: 2
                    color: FiliTheme.accentColor
                }
                Item {
                    visible: progress.loading
                    anchors.fill: parent
                    Repeater {
                        model: Math.max(0, Math.ceil(bar.width / 30) + 2)
                        Rectangle {
                            required property int index
                            width: 20
                            height: bar.height
                            radius: 2
                            color: FiliTheme.alpha(FiliTheme.accentColor, 0.75)
                            x: index * 30 - 30 + shift
                            property real shift: 0
                            NumberAnimation on shift { from: 0; to: 30; duration: 500; loops: Animation.Infinite; running: progress.loading }
                        }
                    }
                }
            }
            MouseArea {
                id: barArea
                x: 0
                y: 0
                width: parent.width
                height: 18
                hoverEnabled: true
                enabled: !progress.loading && controls.length > 0
                onPressed: e => progress.drag = Math.max(0, Math.min(1, e.x / width))
                onPositionChanged: e => {
                    if (pressed)
                        progress.drag = Math.max(0, Math.min(1, e.x / width));
                }
                onReleased: {
                    if (progress.drag >= 0)
                        Store.seek(progress.drag * controls.length);
                    progress.drag = -1;
                }
            }
            Text {
                anchors { left: parent.left; bottom: parent.bottom }
                text: Store.clockSeconds(progress.drag >= 0 ? progress.drag * controls.length : controls.position)
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeLabel
                color: FiliTheme.muted
            }
            Text {
                anchors { right: parent.right; bottom: parent.bottom }
                text: Store.clockSeconds(controls.length)
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeLabel
                color: FiliTheme.muted
            }
        }
    }
}
