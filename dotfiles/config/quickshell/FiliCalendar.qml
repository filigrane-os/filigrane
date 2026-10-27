// fili-calendar: minuteur / chronomètre puis calendrier sous l'horloge de la fili-bar (semaines ISO à gauche): survol = affiché
// (reste ouvert tant que la souris est dessus), clic droit = épinglé, molette = mois ±1
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

PopupWindow {
    id: cal
    property date today
    property int shift: 0
    property bool pinned: false
    // Souris sur le calendrier (garde le survol ouvert, voir la fili-bar)
    readonly property bool hovered: hover.hovered
    // Minuteur / chronomètre (BarState): classe (idle, stopwatch, active, done) et texte du temps
    readonly property string timerClass: BarState.timer["class"] ?? "idle"
    readonly property string timerText: BarState.timer.text.replace(/^\s*/, "")
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + shift, 1)

    visible: false

    function show() {
        FiliShell.popupOpened("calendar");
        visible = true;
    }
    Connections {
        target: FiliShell
        function onPopupOpened(who) {
            if (who !== "calendar") {
                cal.pinned = false;
                cal.visible = false;
            }
        }
    }
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4
    implicitWidth: 260
    implicitHeight: 276
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: FiliTheme.nuit
        border.color: FiliTheme.nuit4
        border.width: 1
        radius: 10
        HoverHandler { id: hover }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4
            // Minuteur / chronomètre: clic = choisir, arrêter ou acquitter, clic droit = +5 min au minuteur
            PanelButton {
                objectName: "timer"
                glyph: ""
                label: cal.timerText !== "" ? cal.timerText : "Minuteur / chronomètre"
                detail: ({ idle: "choisir", stopwatch: "arrêter", active: "annuler · clic droit +5 min", done: "acquitter" })[cal.timerClass] ?? ""
                sel: cal.timerClass !== "idle"
                onClicked: b => {
                    if (b === Qt.RightButton) {
                        FiliTheme.run(FiliTheme.bin + "/bar-timer add");
                    } else {
                        // Le choix de durée s'ouvre dans le fili-launcher: refermer le calendrier d'abord
                        cal.pinned = false;
                        cal.visible = false;
                        FiliTheme.run(FiliTheme.bin + "/bar-timer click");
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: FiliTheme.nuit3
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.locale("fr_FR").toString(cal.shown, "MMMM yyyy")
                color: FiliTheme.voile
                font { family: FiliTheme.font; pixelSize: 14; weight: Font.Medium }
            }
            GridLayout {
                columns: 2
                columnSpacing: 6
                rowSpacing: 2
                Layout.fillWidth: true
                Layout.fillHeight: true
                Item { implicitWidth: 1; implicitHeight: 1 }
                DayOfWeekRow {
                    Layout.fillWidth: true
                    locale: Qt.locale("fr_FR")
                    delegate: Text {
                        required property string shortName
                        text: shortName.slice(0, 2)
                        color: FiliTheme.ardoise
                        horizontalAlignment: Text.AlignHCenter
                        font { family: FiliTheme.font; pixelSize: 12 }
                    }
                }
                WeekNumberColumn {
                    Layout.fillHeight: true
                    month: grid.month
                    year: grid.year
                    locale: Qt.locale("fr_FR")
                    delegate: Text {
                        required property int weekNumber
                        text: weekNumber
                        color: FiliTheme.ardoise
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font { family: FiliTheme.mono; pixelSize: 11 }
                    }
                }
                MonthGrid {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    locale: Qt.locale("fr_FR")
                    month: cal.shown.getMonth()
                    year: cal.shown.getFullYear()
                    delegate: Rectangle {
                        required property var model
                        readonly property bool isToday: model.today
                        color: isToday ? FiliTheme.nuit3 : "transparent"
                        radius: 6
                        Text {
                            anchors.centerIn: parent
                            text: parent.model.day
                            color: parent.isToday ? FiliTheme.voile : parent.model.month === grid.month ? FiliTheme.brume : FiliTheme.nuit4
                            font { family: FiliTheme.font; pixelSize: 13; weight: parent.isToday ? Font.Medium : Font.Normal }
                        }
                    }
                }
            }
        }
    }
}
