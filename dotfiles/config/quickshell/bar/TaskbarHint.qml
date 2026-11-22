pragma Singleton
// Hint mode of the taskbar (Mod+Alt+digits): every window has a number, always shown in the bar (TaskbarNumbers). Holding Mod+Alt
// and typing a number (niri binds Mod+Alt+0..9 to `fili-shell taskbar N`) waits for the whole number; releasing Mod / Alt
// (or Enter) focuses the window, Esc cancels, Backspace erases the last digit. The taskbar of the screen that has the
// focus takes the keyboard to see the release. Without a key for a moment the mode ends by itself (see the timer), so a missed
// release never keeps the keyboard.
import QtQuick
import Quickshell
import qs

Singleton {
    id: hint
    property bool active: false
    // Digits typed: the number of the window
    property string typed: ""
    // Display that has the focus: its taskbar takes the keyboard (the display of the focused window)
    readonly property string output: {
        const wsId = Niri.focused?.workspace_id ?? -1;
        const ws = Niri.workspaces.find(w => w.id === wsId) ?? Niri.workspaces.find(w => w.is_focused);
        return ws ? ws.output : (TaskbarLayout.screens[0]?.name ?? "");
    }

    function begin() {
        if (TaskbarLayout.screens.length === 0)
            return;
        typed = "";
        active = true;
        FiliTooltip.hide();
        FiliShell.popupOpened("taskbar-hint");
        idle.restart();
    }
    function cancel() {
        active = false;
        typed = "";
        idle.stop();
    }
    // Digit typed (a character; anything but a digit is ignored); starts the mode when it is not started
    function type(ch) {
        if (!/^[0-9]$/.test(ch))
            return;
        if (!active)
            begin();
        if (!active)
            return;
        typed += ch;
        idle.restart();
    }
    function erase() {
        typed = typed.slice(0, -1);
        idle.restart();
    }
    // Niri id of the window the digits designate, or null (nothing typed, no such number)
    function resolve(digits) {
        return digits === "" ? null : TaskbarNumbers.windowOf(parseInt(digits));
    }
    // Focus the window and leave the mode
    function commit() {
        const id = resolve(typed);
        cancel();
        if (id !== null)
            Niri.action("focus-window", "--id", String(id));
    }
    // Does a number still match what was typed? (the others are dimmed)
    function matches(n) {
        return typed === "" || String(n).startsWith(typed);
    }

    Timer {
        id: idle
        // Nothing typed: the mode gives up after 6 s. Digits typed: after 1.2 s without a key it goes to the window anyway, so a
        // release that the bar did not see (a very quick tap) never keeps the keyboard
        interval: hint.typed === "" ? 6000 : 1200
        onTriggered: hint.typed === "" ? hint.cancel() : hint.commit()
    }
}
