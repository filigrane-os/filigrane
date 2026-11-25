// fili-calendar: calendar then timer / stopwatch under the clock of the fili-bar (ISO weeks on the left): hover = shown
// (stays open while the mouse is on it), right click = pinned, wheel = month ±1
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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

    // The agenda around the month shown (fili-cal, JSON): the events by day, to mark the days that have some, and the ones of the
    // day that is selected (today at first)
    property var byDay: ({})
    property date selectedDay: new Date()
    readonly property string selectedKey: iso(selectedDay)
    readonly property var dayEvents: byDay[selectedKey] ?? []
    // The first day of the grid the MonthGrid draws (the week of the 1st), and the one after the last
    readonly property date gridStart: {
        const first = new Date(shown.getFullYear(), shown.getMonth(), 1);
        const lead = (first.getDay() - FiliI18n.locale.firstDayOfWeek + 7) % 7;
        return new Date(first.getFullYear(), first.getMonth(), 1 - lead);
    }
    readonly property date gridEnd: new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + 42)
    function iso(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }
    // Days of a long event are not spread: an event is on the day it starts
    function reload() {
        if (FiliTheme.testing)
            return;
        agendaProc.command = [FiliTheme.tool("fili-cal"), "list", "--json", "--from", iso(gridStart), "--to", iso(gridEnd)];
        agendaProc.running = true;
    }
    onGridStartChanged: if (visible) reload()
    onVisibleChanged: {
        if (visible) {
            selectedDay = new Date();
            shift = 0;
            reload();
        }
    }
    Process {
        id: agendaProc
        stdout: StdioCollector {
            onStreamFinished: {
                const by = {};
                try {
                    for (const e of JSON.parse(text)) {
                        const day = String(e.start).slice(0, 10);
                        (by[day] = by[day] ?? []).push(e);
                    }
                } catch (err) {
                }
                cal.byDay = by;
            }
        }
    }
    // Agenda on a day (the window comes to the front, or starts there)
    function openAgenda(d) {
        cal.pinned = false;
        cal.visible = false;
        FiliTheme.run(FiliTheme.tool("fili-cal") + " --goto " + iso(d));
    }
    function join(id) {
        cal.pinned = false;
        cal.visible = false;
        FiliTheme.run(FiliTheme.tool("fili-cal") + " join " + id);
    }
    readonly property int listRows: Math.min(4, Math.max(1, dayEvents.length))

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
    anchor.edges: FiliTheme.popupEdges
    anchor.gravity: FiliTheme.popupEdges
    anchor.margins.top: FiliTheme.barGap("top", 4)
    anchor.margins.bottom: FiliTheme.barGap("bottom", 4)
    anchor.margins.left: FiliTheme.barGap("left", 4)
    anchor.margins.right: FiliTheme.barGap("right", 4)
    implicitWidth: 260
    implicitHeight: 276 + 60 + 2 * FiliTheme.space1 + 22 + listRows * 24 + (dayEvents.length > 4 ? 16 : 0) + FiliTheme.space1
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
                        id: dayCell
                        required property var model
                        readonly property bool isToday: model.today
                        readonly property string key: cal.iso(model.date)
                        readonly property int count: cal.byDay[key]?.length ?? 0
                        readonly property bool selected: key === cal.selectedKey
                        color: isToday ? FiliTheme.nuit3 : dayHover.containsMouse ? FiliTheme.alpha(FiliTheme.nuit3, 0.5) : "transparent"
                        border.width: selected ? 1 : 0
                        border.color: FiliTheme.voile
                        radius: FiliTheme.radiusControl
                        // One dot for each of the first three events of the day: the days that have something are seen at once
                        Row {
                            visible: dayCell.count > 0 && dayCell.model.month === grid.month
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
                            spacing: 2
                            Repeater {
                                model: Math.min(3, dayCell.count)
                                Rectangle { width: 3; height: 3; radius: 1.5; color: FiliTheme.voile }
                            }
                        }
                        MouseArea {
                            id: dayHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: cal.selectedDay = dayCell.model.date
                            onDoubleClicked: cal.openAgenda(dayCell.model.date)
                        }
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: dayCell.count > 0 ? -2 : 0
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
            // The events of the selected day: click one to open Agenda on that day, the camera joins its meeting
            Text {
                Layout.fillWidth: true
                text: FiliI18n.locale.toString(cal.selectedDay, "dddd d MMMM")
                elide: Text.ElideRight
                color: FiliTheme.ardoise
                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall; weight: FiliTheme.weightAccent }
            }
            Text {
                visible: cal.dayEvents.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                verticalAlignment: Text.AlignVCenter
                text: FiliI18n.tr("Nothing planned")
                color: FiliTheme.ardoise
                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
            }
            Repeater {
                model: cal.dayEvents.slice(0, 4)
                Rectangle {
                    id: evRow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    radius: FiliTheme.radiusControl
                    color: evArea.containsMouse ? FiliTheme.nuit3 : "transparent"
                    MouseArea {
                        id: evArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: cal.openAgenda(cal.selectedDay)
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                        spacing: FiliTheme.space2
                        Text {
                            text: evRow.modelData.all_day ? FiliI18n.tr("All day") : String(evRow.modelData.start).slice(11, 16)
                            color: FiliTheme.ardoise
                            Layout.preferredWidth: 40
                            font { family: FiliTheme.mono; pixelSize: FiliTheme.sizeSmall }
                        }
                        Text {
                            text: evRow.modelData.title
                            color: FiliTheme.brume
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        }
                        // The camera of a video meeting (Teams, Meet, Zoom…)
                        Rectangle {
                            visible: (evRow.modelData.join ?? "") !== ""
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 18
                            radius: 9
                            color: joinArea.containsMouse ? FiliTheme.alpha(FiliTheme.voile, 0.85) : FiliTheme.voile
                            Text {
                                anchors.centerIn: parent
                                text: "\uf03d"
                                color: FiliTheme.nuit
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                            MouseArea {
                                id: joinArea
                                anchors.fill: parent
                                hoverEnabled: true
                                objectName: "join-" + evRow.modelData.id
                                onClicked: cal.join(evRow.modelData.id)
                            }
                        }
                    }
                }
            }
            Text {
                visible: cal.dayEvents.length > 4
                Layout.fillWidth: true
                text: FiliI18n.tr("+%1 more", cal.dayEvents.length - 4)
                color: FiliTheme.ardoise
                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                MouseArea { anchors.fill: parent; onClicked: cal.openAgenda(cal.selectedDay) }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: FiliTheme.nuit3
            }
            // New event or reminder: one line in the launcher ("tomorrow 14:30 Dentist", "+30m Take the bread out")
            PanelButton {
                objectName: "new-event"
                glyph: "\uf271"
                label: FiliI18n.tr("New event or reminder")
                onClicked: {
                    // The line is typed in the fili-launcher: close the calendar first
                    cal.pinned = false;
                    cal.visible = false;
                    FiliTheme.run(FiliTheme.bin + "/bar-event add");
                }
            }
            // Open Agenda (fili-cal) on its window; a second launch brings the open one to the front
            PanelButton {
                objectName: "open-agenda"
                glyph: "\uf073"
                label: FiliI18n.tr("Open Agenda")
                onClicked: {
                    cal.pinned = false;
                    cal.visible = false;
                    FiliTheme.run(FiliTheme.bin + "/fili-cal");
                }
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
