pragma Singleton
// Fiches des fili-tooltip et fili-panel ({ title, hint, rows: [[libellé, valeur]...] }), sans lancer de processus:
// réseau, alimentation et moniteur demandés à bar-stats (FiliShell.request), écrans composés ici (sorties de niri et
// luminosité). request(SUJET), puis ready(SUJET, fiche).
import QtQuick
import Quickshell

Singleton {
    id: info
    signal ready(string topic, var card)

    function request(topic) {
        if (topic === "display")
            Niri.request("Outputs", o => info.ready("display", info.display(o ?? {}, FiliShell.stats.display?.screen ?? -1)));
        else
            FiliShell.request("info " + topic);
    }

    // Une ligne par sortie (marque, modèle, définition, fréquence, échelle), puis la luminosité
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
