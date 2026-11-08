// fili-shell (Quickshell): a single process for the fili-bar (bar/FiliBar.qml), its fili-tooltip and fili-calendar,
// the fili-notification and the fili-notification-center (FiliNotification.qml), the fili-launcher (FiliLauncher.qml) and the fili-chat drawer (FiliChat.qml),
// in place of Waybar, mako and fuzzel. Software rendering (QT_QUICK_BACKEND=software, set by niri): no OpenGL context, about
// half the memory; no animation except the blinking of the backup (brand.md, resource budget).
// External commands: client ~/.local/bin/fili-shell (FiliShell.qml). Reload: menu › Style › Reload shell.
//@ pragma Env QT_QUICK_BACKEND=software
//@ pragma Env QSG_RENDER_LOOP=basic
import QtQuick
import Quickshell
import qs.bar
import qs.bar.modules.appmenu

ShellRoot {
    Variants {
        model: Quickshell.screens
        FiliBar {}
    }

    // Instantiated at start (singletons are otherwise loaded on first use)
    Component.onCompleted: {
        FiliNotification.dnd;
        FiliSound.notify;
        FiliLauncher.open;
        FiliChat.open;
        FiliChatAbout.open;
        FiliAudioSwitch.open;
        FiliShell.fifo;
        FiliHotkeys.startup();
    }

    Connections {
        target: FiliShell
        function onCommand(target, action, args) {
            if (target === "panel")
                FiliPanel.summon(action);
            else if (target === "appmenu")
                AppMenu.summon(action);
            else if (target === "hotkeys")
                FiliHotkeys.toggle();
            else if (target === "chat")
                FiliChat.act(action || "toggle", args);
            else if (target === "about")
                FiliAbout.toggle();
            else if (target === "settings")
                FiliSettings.toggle(action);
            else if (target === "reload")
                Quickshell.reload(false);
        }
    }
}
