// Click and fili-tooltip area of a fili-bar module: shell commands per button and wheel, or signals
// (onLeftClicked...). tip: text or card (see FiliTooltip); tipInfo: card requested on hover only (FiliInfo:
// network, power, display), which replaces tip; nothing is polled continuously.
import QtQuick
import Quickshell
import qs

MouseArea {
    id: area
    property var tip
    property string tipInfo
    property string click
    property string rclick
    property string mclick
    property string scrollUp
    property string scrollDown
    // Super held during the last press (needs the bar to receive modifiers; false otherwise)
    property bool meta: false
    signal leftClicked
    signal rightClicked
    signal middleClicked
    signal wheelUp
    signal wheelDown

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: (click || rclick) ? Qt.PointingHandCursor : Qt.ArrowCursor

    // Panel open: niri takes the keyboard focus away from the fili-panel as soon as the bar is clicked and the click (press then
    // release) is lost, hence two clicks. So the action runs on press, and the release does not replay it.
    property bool early: false
    onPressed: m => { meta = (m.modifiers & Qt.MetaModifier) !== 0; down(m.button); }
    onClicked: m => { meta = (m.modifiers & Qt.MetaModifier) !== 0; up(m.button); }
    // Wheel: one mouse notch = 120; the touchpad sends a burst of small deltas, accumulated so as not to fire
    // one action per event (volume from 0 to 100 % in one gesture)
    property real wheelAcc: 0
    onWheel: w => {
        const d = w.angleDelta.y;
        if (d === 0)
            return;
        if (wheelAcc * d < 0)
            wheelAcc = 0;
        wheelAcc += d;
        while (Math.abs(wheelAcc) >= 120) {
            roll(wheelAcc > 0);
            wheelAcc -= wheelAcc > 0 ? 120 : -120;
        }
    }

    function down(button) {
        early = FiliShell.anyOpen;
        if (early)
            press(button);
    }
    function up(button) {
        if (early)
            early = false;
        else
            press(button);
    }
    // Click and wheel (also called by the tests)
    function press(button) {
        FiliTooltip.hide();
        if (button === Qt.LeftButton) {
            FiliTheme.run(click);
            leftClicked();
        } else if (button === Qt.RightButton) {
            FiliTheme.run(rclick);
            rightClicked();
        } else {
            FiliTheme.run(mclick);
            middleClicked();
        }
    }
    function roll(up) {
        if (up) {
            FiliTheme.run(scrollUp);
            wheelUp();
        } else {
            FiliTheme.run(scrollDown);
            wheelDown();
        }
    }
    onContainsMouseChanged: {
        if (!containsMouse) {
            FiliTooltip.hide(area);
            return;
        }
        if (tipInfo) {
            FiliTooltip.show(area, tip || { title: "…" });
            FiliInfo.request(tipInfo);
        } else {
            FiliTooltip.show(area, tip);
        }
    }
    onTipChanged: if (containsMouse && !tipInfo) FiliTooltip.update(area, tip)

    Connections {
        target: FiliInfo
        enabled: area.tipInfo !== "" && area.containsMouse
        function onReady(topic, card) {
            if (topic === area.tipInfo)
                FiliTooltip.update(area, card);
        }
    }
}
