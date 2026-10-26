// fili-shell (Quickshell): un seul processus pour la fili-bar (FiliBar.qml), ses fili-tooltip et fili-calendar,
// les fili-notification et le fili-notification-center (FiliNotification.qml) et le fili-launcher (FiliLauncher.qml),
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
        FiliLauncher.open;
        FiliShell.fifo;
    }

    Connections {
        target: FiliShell
        function onCommand(target, action, args) {
            if (target === "panel")
                FiliPanel.summon(action);
            else if (target === "reload")
                Quickshell.reload(false);
        }
    }
}
