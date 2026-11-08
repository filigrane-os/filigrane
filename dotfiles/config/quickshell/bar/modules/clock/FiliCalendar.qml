// fili-calendar: calendar then timer / stopwatch under the clock of the fili-bar (ISO weeks on the left): hover = shown
// (stays open while the mouse is on it), right click = pinned, wheel = month ±1
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.bar
import qs.controls
import qs

PopupWindow {
    id: cal
    property date today
    property int shift: 0
    property bool pinned: false
    // Mouse on the calendar (keeps the hover open, see the fili-bar)
    readonly property bool hovered: hover.hovered
    // Timer / stopwatch (BarState): class (idle, stopwatch, active, done) and time text
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
        border.color: FiliTheme.border
        border.width: FiliTheme.borderWidth
        radius: FiliTheme.radiusWindow
        HoverHandler { id: hover }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: FiliTheme.space3
            spacing: FiliTheme.space1
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: FiliI18n.locale.toString(cal.shown, "MMMM yyyy")
                color: FiliTheme.voile
                font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
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
                    locale: FiliI18n.locale
                    delegate: Text {
                        required property string shortName
                        text: shortName.slice(0, 2)
                        color: FiliTheme.ardoise
                        horizontalAlignment: Text.AlignHCenter
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                    }
                }
                WeekNumberColumn {
                    Layout.fillHeight: true
                    month: grid.month
                    year: grid.year
                    locale: FiliI18n.locale
                    delegate: Text {
                        required property int weekNumber
                        text: weekNumber
                        color: FiliTheme.ardoise
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeSmall }
                    }
                }
                MonthGrid {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    locale: FiliI18n.locale
                    month: cal.shown.getMonth()
                    year: cal.shown.getFullYear()
                    delegate: Rectangle {
                        required property var model
                        readonly property bool isToday: model.today
                        color: isToday ? FiliTheme.nuit3 : "transparent"
                        radius: FiliTheme.radiusControl
                        Text {
                            anchors.centerIn: parent
                            text: parent.model.day
                            color: parent.isToday ? FiliTheme.voile : parent.model.month === grid.month ? FiliTheme.brume : FiliTheme.nuit4
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: parent.isToday ? FiliTheme.weightAccent : Font.Normal }
                        }
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
            // Timer / stopwatch: click = choose, stop or acknowledge, right click = +5 min on the timer
            PanelButton {
                objectName: "timer"
                glyph: ""
                label: cal.timerText !== "" ? cal.timerText : FiliI18n.tr("Timer / stopwatch")
                detail: ({ idle: FiliI18n.tr("choose"), stopwatch: FiliI18n.tr("stop"), active: FiliI18n.tr("cancel · right click +5 min"), done: FiliI18n.tr("dismiss") })[cal.timerClass] ?? ""
                sel: cal.timerClass !== "idle"
                onClicked: b => {
                    if (b === Qt.RightButton) {
                        FiliTheme.run(FiliTheme.bin + "/bar-timer add");
                    } else {
                        // The duration choice opens in the fili-launcher: close the calendar first
                        cal.pinned = false;
                        cal.visible = false;
                        FiliTheme.run(FiliTheme.bin + "/bar-timer click");
                    }
                }
            }
        }
    }
}
