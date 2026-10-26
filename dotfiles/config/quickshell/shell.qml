// Shell Filigrane (Quickshell): barre, notifications et sélecteur de menu en un seul processus, à la place de
// Waybar, mako et fuzzel. Rendu logiciel (QT_QUICK_BACKEND=software, posé par niri): sans contexte OpenGL, environ
// moitié moins de mémoire; aucune animation hors du clignotement de la sauvegarde (brand.md, budget ressources).
// Commandes externes: fili-shell (Control.qml). Recharger: menu › Style › Reload shell.
//@ pragma Env QT_QUICK_BACKEND=software
//@ pragma Env QSG_RENDER_LOOP=basic
import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    // Instanciés au démarrage (singletons sinon chargés au premier usage)
    Component.onCompleted: {
        Notifs.dnd;
        Picker.open;
        Control.fifo;
    }

    Connections {
        target: Control
        function onCommand(name, args) {
            if (name === "reload")
                Quickshell.reload(false);
        }
    }
}
