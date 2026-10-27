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
            return [o.name, (o.make ?? "") + " " + (o.model ?? "") + "  ·  " + m.width + "×" + m.height + " à " + Math.round((m.refresh_rate ?? 0) / 1000) + " Hz, échelle " + (o.logical?.scale ?? 1)];
        });
        if (screen >= 0)
            rows.push(["Luminosité", screen + " %"]);
        return { title: "Écrans", hint: "clic: panneau écrans · molette: luminosité", rows: rows };
    }

    Connections {
        target: FiliShell
        function onInfo(topic, data) {
            info.ready(topic, data);
        }
    }
}
