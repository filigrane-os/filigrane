// Workspaces of the screen: click = go to the workspace, wheel = previous/next (no wrap-around).
// Numbered across the displays (Settings > Workspaces): a named workspace shows its name; the unnamed ones (the empty
// workspace niri keeps at the end of each display, or one a window was moved to) show a dot, and the empty one only
// while it is active: its local index ("2") would clash with workspace "2" of another display.
// Clicks and the wheel act on the display of this bar (niri's focus-workspace N and focus-workspace-up/down act on the
// display that has the focus), hence focus-monitor first.
import QtQuick
import qs
import qs.bar

BarModule {
    BarRow {
        Repeater {
            model: {
                const all = Niri.workspaces;
                const numbered = all.some(w => /^[0-9]+$/.test(w.name ?? ""));
                const wins = Object.values(Niri.windows);
                return all.filter(w => w.output === bar.screen.name).map(w => Object.assign({}, w, {
                    label: w.name ?? (numbered ? "\u2022" : String(w.idx))
                })).filter(w => !numbered || w.name || w.is_active || wins.some(x => x.workspace_id === w.id));
            }
            Rectangle {
                required property var modelData
                objectName: "ws-" + modelData.id
                property alias hover: wsHover
                property alias text: ws.text
                implicitWidth: FiliTheme.barVertical ? FiliTheme.barWidth : ws.implicitWidth + 2 * FiliTheme.pad
                implicitHeight: FiliTheme.barHeight
                color: modelData.is_active || wsHover.containsMouse ? FiliTheme.barHover : "transparent"
                BarLabel {
                    id: ws
                    anchors.centerIn: parent
                    // A named workspace shows its name (numbered across the displays: Settings > Workspaces)
                    text: parent.modelData.label
                    color: parent.modelData.is_active || wsHover.containsMouse ? FiliTheme.barText : FiliTheme.barMuted
                }
                Rectangle {
                    visible: parent.modelData.is_active
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 2
                    color: FiliTheme.barAccent
                }
                BarHover {
                    id: wsHover
                    anchors.fill: parent
                    // Windows of the workspace (app, title)
                    tip: {
                        const id = parent.modelData.id;
                        const wins = Object.values(Niri.windows).filter(w => w.workspace_id === id);
                        return {
                            title: parent.modelData.label === "\u2022" ? FiliI18n.tr("Unnumbered workspace") : FiliI18n.tr("Workspace %1", parent.modelData.label),
                            rows: wins.length ? wins.map(w => [w.app_id ?? "", w.title ?? ""]) : [["", FiliI18n.tr("no window")]],
                            hint: FiliI18n.tr("click: go there · wheel: previous / next")
                        };
                    }
                    onLeftClicked: Niri.onOutput(bar.screen.name, "focus-workspace " + parent.modelData.idx)
                    onWheelUp: Niri.onOutput(bar.screen.name, "focus-workspace-up")
                    onWheelDown: Niri.onOutput(bar.screen.name, "focus-workspace-down")
                }
            }
        }
    }
}
