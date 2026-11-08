// Date and clock. Hover = card (date, time zone, next events), click (left or right) = calendar pinned as a panel
// (wheel: previous/next month, middle click: current month)
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.bar

BarModule {
    id: clockItem
    implicitWidth: clockText.implicitWidth + (clockIcon.visible ? clockIcon.implicitWidth + FiliTheme.labelGap : 0) + 2 * FiliTheme.pad
    implicitHeight: FiliTheme.barHeight
    SystemClock { id: clock; precision: SystemClock.Minutes }
    // Running timer or stopwatch (bar-timer, state read by BarState): replaces the date
    readonly property var timerState: BarState.timer
    readonly property bool timing: timerState["class"] !== "idle"
    // Hover card: date, time, time zone, week, then the next agenda events (BarState.agenda)
    readonly property var card: {
        const d = clock.date;
        const off = -d.getTimezoneOffset();
        const hm = n => String(n).padStart(2, "0");
        const utc = "UTC" + (off < 0 ? "−" : "+") + hm(Math.floor(Math.abs(off) / 60)) + ":" + hm(Math.abs(off) % 60);
        const day = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(d.getFullYear(), 0, 0)) / 864e5);
        // ISO week: the one of the Thursday of the week
        const thu = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3 - (d.getDay() + 6) % 7);
        const week = Math.floor((thu - new Date(thu.getFullYear(), 0, 1)) / 864e5 / 7) + 1;
        const rows = [
            [FiliI18n.tr("Local time"), FiliI18n.locale.toString(d, "HH:mm")],
            [FiliI18n.tr("Time zone"), Qt.formatDateTime(d, "tttt") + " (" + Qt.formatDateTime(d, "t") + ", " + utc + ")"],
            [FiliI18n.tr("Week"), FiliI18n.tr("%1 · day %2 of the year", week, day)]
        ];
        if (timing)
            rows.push([FiliI18n.tr("Timer"), timerState.text.trim()]);
        const today = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const ev = BarState.agenda;
        if (ev === null)
            return { title: FiliI18n.locale.toString(d, "dddd d MMMM yyyy"), rows: rows, hint: FiliI18n.tr("click: calendar") };
        if (ev.length === 0)
            rows.push([FiliI18n.tr("Agenda"), FiliI18n.tr("no upcoming event")]);
        for (const e of ev) {
            const s = new Date(e.start * 1000);
            const n = Math.round((new Date(s.getFullYear(), s.getMonth(), s.getDate()).getTime() - today) / 864e5);
            const when = n === 0 ? FiliI18n.tr("Today") : n === 1 ? FiliI18n.tr("Tomorrow") : FiliI18n.locale.toString(s, "ddd d MMM");
            rows.push([when + " " + FiliI18n.locale.toString(s, "HH:mm"), e.title + (e.place ? "  ·  " + e.place : "")]);
        }
        return { title: FiliI18n.locale.toString(d, "dddd d MMMM yyyy"), rows: rows, hint: FiliI18n.tr("click: calendar") };
    }
    onCardChanged: if (clockMouse.containsMouse) FiliTooltip.update(clockMouse, card)
    // Calendar icon before the date, like the other modules (the timer carries its own)
    BarLabel {
        id: clockIcon
        visible: !clockItem.timing
        anchors { verticalCenter: parent.verticalCenter; right: clockText.left; rightMargin: FiliTheme.labelGap }
        text: String.fromCodePoint(0xf073)
        color: FiliTheme.ardoise
    }
    BarLabel {
        id: clockText
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: clockIcon.visible ? (clockIcon.implicitWidth + FiliTheme.labelGap) / 2 : 0
        text: clockItem.timing ? clockItem.timerState.text : FiliI18n.locale.toString(clock.date, "ddd dd MMM  HH:mm")
        color: !clockItem.timing ? FiliTheme.brume : clockItem.timerState["class"] === "done" ? FiliTheme.cendre : FiliTheme.sable
        // Fixed-width digits: the clock does not shift every second
        font.family: clockItem.timing ? FiliTheme.mono : FiliTheme.font
        font.weight: Font.Normal
    }
    MouseArea {
        id: clockMouse
        objectName: "clock"
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onContainsMouseChanged: if (containsMouse) FiliTooltip.show(this, clockItem.card); else FiliTooltip.hide(this)
        onClicked: m => press(m.button)
        // Click (also called by the tests)
        function press(button) {
            FiliTooltip.hide();
            if (button === Qt.MiddleButton) {
                cal.shift = 0;
            } else {
                cal.pinned = !cal.pinned;
                if (cal.pinned) {
                    cal.shift = 0;
                    cal.show();
                } else {
                    cal.visible = false;
                }
            }
        }
        onWheel: w => cal.shift += w.angleDelta.y > 0 ? -1 : 1
    }
    // Pinned calendar: a click elsewhere on the screen closes it. Transparent window under the bar, with a hole at
    // the calendar's place (centred under the clock, 4 px under the bar) so that its buttons stay clickable.
    PanelWindow {
        id: dismiss
        visible: cal.pinned && cal.visible && !FiliTheme.testing
        screen: bar.screen
        anchors { top: true; bottom: true; left: true; right: true }
        margins.top: FiliTheme.barHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "fili-calendar-dismiss"
        color: "transparent"
        mask: Region {
            width: dismiss.width
            height: dismiss.height
            Region {
                x: Math.max(0, clockItem.mapToItem(null, clockItem.width / 2, 0).x - cal.implicitWidth / 2)
                y: 4
                width: cal.implicitWidth
                height: cal.implicitHeight
                intersection: Intersection.Subtract
            }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: FiliShell.popupOpened("")
        }
    }
    FiliCalendar {
        id: cal
        anchor.item: clockItem
        today: clock.date
    }
}
