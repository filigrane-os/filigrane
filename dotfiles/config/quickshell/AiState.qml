// What the shell knows of the assistant (Rob, fili-ai): whether its interface is open or has the keyboard focus, whether it
// works, whether it waits for the user or has an unread answer. Read from $XDG_RUNTIME_DIR/fili/ai/ui.json, which the
// assistant's interface writes on each change (docs/api.md, "The assistant"), and acted upon with the fili-ai command: the
// bar, the application menu and the agent panel use this singleton and never reach into the assistant's window. The assistant
// is an application of its own (the fili-ai package, window fili-ai-window).
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: ai

    readonly property string file: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fili/ai/ui.json"
    // The interface is shown / has the keyboard focus
    property bool open: false
    property bool focused: false
    // "waiting": a permission is asked; "done": an answer was finished and not read; "": nothing
    property string attention: ""
    // An agent session of the assistant is working
    property bool busy: false

    // Takes the content of the state file (the tests, which have no file, call it directly)
    function apply(text) {
        try {
            const j = JSON.parse(text);
            if (j.v !== 1)
                return;
            open = j.open === true;
            focused = j.focused === true;
            attention = j.attention === "waiting" || j.attention === "done" ? j.attention : "";
            busy = j.busy === true;
        } catch (e) {
            // File being written: the previous state stays
        }
    }
    function reset() {
        open = false;
        focused = false;
        attention = "";
        busy = false;
    }

    FileView {
        path: FiliTheme.testing ? "" : ai.file
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: ai.apply(text())
        onLoadFailed: ai.reset()
    }

    // Commands: the assistant's own command line (`fili-ai show|hide`), which does not note the focused application
    function show() {
        FiliTheme.run(FiliTheme.tool("fili-ai") + " show");
    }
    function hide() {
        FiliTheme.run(FiliTheme.tool("fili-ai") + " hide");
    }
    function toggle() {
        open ? hide() : show();
    }
}
