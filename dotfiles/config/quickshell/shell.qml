// fili-shell (Quickshell): un seul processus pour la fili-bar (FiliBar.qml), ses fili-tooltip et fili-calendar,
// les fili-notification et le fili-notification-center (FiliNotification.qml), le fili-launcher (FiliLauncher.qml) et le tiroir fili-chat (FiliChat.qml),
// à la place de Waybar, mako et fuzzel. Rendu logiciel (QT_QUICK_BACKEND=software, posé par niri): sans contexte OpenGL, environ
// moitié moins de mémoire; aucune animation hors du clignotement de la sauvegarde (brand.md, budget ressources).
// Commandes externes: client ~/.local/bin/fili-shell (FiliShell.qml). Recharger: menu › Style › Reload shell.
//@ pragma Env QT_QUICK_BACKEND=software
//@ pragma Env QSG_RENDER_LOOP=basic
import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens
        FiliBar {}
    }

    // Instanciés au démarrage (singletons sinon chargés au premier usage)
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
