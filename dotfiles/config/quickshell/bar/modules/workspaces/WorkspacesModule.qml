// Workspaces of the screen: click = go to the workspace, wheel = previous/next (no wrap-around)
import QtQuick
import qs
import qs.bar

BarModule {
    BarRow {
        Repeater {
            model: Niri.workspaces.filter(w => w.output === bar.screen.name)
            Rectangle {
                required property var modelData
                implicitWidth: FiliTheme.barVertical ? FiliTheme.barWidth : ws.implicitWidth + 2 * FiliTheme.pad
                implicitHeight: FiliTheme.barHeight
                color: modelData.is_active || wsHover.containsMouse ? FiliTheme.nuit3 : "transparent"
                BarLabel {
                    id: ws
                    anchors.centerIn: parent
                    text: parent.modelData.idx
                    color: parent.modelData.is_active || wsHover.containsMouse ? FiliTheme.brume : FiliTheme.ardoise
                }
                Rectangle {
                    visible: parent.modelData.is_active
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 2
                    color: FiliTheme.voile
                }
                BarHover {
                    id: wsHover
                    anchors.fill: parent
                    // Windows of the workspace (app, title)
                    tip: {
                        const id = parent.modelData.id;
                        const wins = Object.values(Niri.windows).filter(w => w.workspace_id === id);
                        return {
                            title: FiliI18n.tr("Workspace %1", parent.modelData.idx),
                            rows: wins.length ? wins.map(w => [w.app_id ?? "", w.title ?? ""]) : [["", FiliI18n.tr("no window")]],
                            hint: FiliI18n.tr("click: go there · wheel: previous / next")
                        };
                    }
                    onLeftClicked: Niri.action("focus-workspace", String(parent.modelData.idx))
                    onWheelUp: Niri.action("focus-workspace-up")
                    onWheelDown: Niri.action("focus-workspace-down")
                }
            }
        }
    }
}
