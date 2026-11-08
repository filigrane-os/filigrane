pragma Singleton
// Cards of the fili-tooltip and fili-panel ({ title, hint, rows: [[label, value]...] }), without starting a process:
// network, power and monitor requested from bar-stats (FiliShell.request), displays composed here (niri outputs and
// brightness). request(TOPIC), then ready(TOPIC, card).
import QtQuick
import Quickshell
import qs

Singleton {
    id: info
    signal ready(string topic, var card)

    function request(topic) {
        if (topic === "display")
            Niri.request("Outputs", o => info.ready("display", info.display(o ?? {}, FiliShell.stats.display?.screen ?? -1)));
        else
            FiliShell.request("info " + topic);
    }

    // One line per output (make, model, resolution, refresh rate, scale), then the brightness
    function display(outputs, screen) {
        const rows = Object.values(outputs).sort((a, b) => a.name.localeCompare(b.name)).map(o => {
            const m = o.modes?.[o.current_mode ?? 0] ?? {};
            return [o.name, (o.make ?? "") + " " + (o.model ?? "") + "  ·  " + FiliI18n.tr("%1×%2 at %3 Hz, scale %4", m.width, m.height, Math.round((m.refresh_rate ?? 0) / 1000), FiliI18n.num(o.logical?.scale ?? 1, (o.logical?.scale ?? 1) % 1 ? 2 : 0))];
        });
        if (screen >= 0)
            rows.push([FiliI18n.tr("Brightness"), screen + " %"]);
        return { title: FiliI18n.tr("Displays"), hint: FiliI18n.tr("click: displays panel · wheel: brightness"), rows: rows };
    }

    Connections {
        target: FiliShell
        function onInfo(topic, data) {
            info.ready(topic, data);
        }
    }
}
