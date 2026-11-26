// Eye at the right end of a password field: a click shows or hides what was typed, the focus stays in the field.
// Same pictogram and behaviour as FiliTextField of the fili-ui kit (secret field): the open eye means "show", the struck
// eye "hide". The owner binds its TextInput's echoMode to `revealed` and sets `field`; `revealed` goes back to false
// when the eye is hidden (the field closes).
import QtQuick
import QtQuick.Shapes
import qs

Item {
    id: eye
    property Item field
    property bool revealed: false
    readonly property string eyePath: "M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0 M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z"
    readonly property string eyeOffPath: "M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49 M14.084 14.158a3 3 0 0 1-4.242-4.242 M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143 M2 2l20 20"

    width: 14
    height: 14
    onVisibleChanged: if (!visible) revealed = false
    function toggle() {
        revealed = !revealed;
        if (field)
            field.forceActiveFocus();
    }
    Accessible.role: Accessible.Button
    Accessible.name: eye.revealed ? FiliI18n.tr("Hide password") : FiliI18n.tr("Show password")

    Shape {
        width: 24
        height: 24
        scale: eye.width / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: area.containsMouse ? FiliTheme.brume : FiliTheme.ardoise
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: eye.revealed ? eye.eyeOffPath : eye.eyePath }
        }
    }
    MouseArea {
        id: area
        anchors { fill: parent; margins: -6 }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: eye.toggle()
    }
}
