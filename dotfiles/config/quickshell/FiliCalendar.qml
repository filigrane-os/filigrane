// fili-calendar: calendrier sous l'horloge de la fili-bar (semaines ISO à gauche): survol = affiché, clic droit = épinglé, molette = mois ±1
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

PopupWindow {
    id: cal
    property date today
    property int shift: 0
    property bool pinned: false
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
    implicitHeight: 230
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: FiliTheme.nuit
        border.color: FiliTheme.nuit4
        border.width: 1
        radius: 10

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4
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
