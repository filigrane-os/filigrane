pragma Singleton
// Filigrane (brand.md): fond nuit, texte brume, accent voile; aucune autre couleur vive, états désaturés.
// Mode clair (fili-theme light, choisi dans le fili-panel écrans): les noms gardent leur rôle du mode sombre
// (nuit = fond, brume = texte, voile = accent) et prennent les teintes claires: fond papier, texte nuit, accent
// ardoise foncé, états assombris (contraste ≥ 4,8:1 sur papier)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme
    // "dark" (défaut) ou "light", lu dans l'état de fili-theme et relu dès qu'il change (les tests le fixent)
    property string mode: "dark"
    readonly property bool light: mode === "light"
    // Couleur d'accentuation (nom), lue dans l'état de fili-theme comme le mode
    property string accent: "default"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/filigrane/theme"
    FileView {
        path: theme.testing ? "" : theme.stateFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: theme.mode = text().trim() === "light" ? "light" : "dark"
        onLoadFailed: theme.mode = "dark"
    }
    FileView {
        path: theme.testing ? "" : theme.stateFile.replace(/theme$/, "accent")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: theme.accent = text().trim()
        onLoadFailed: theme.accent = "default"
    }
    // Réglages globaux facultatifs: ~/.config/filigrane/theme.toml (sections [theme], [theme.dark], [theme.light],
    // [theme.accents]; clés en anglais, voir fili-file/theme.toml). Relus dès qu'ils changent; les valeurs
    // ci-dessous sont les défauts (un test les garde identiques à ceux de fili-file); une valeur invalide est ignorée.
    property var parsed: ({})
    readonly property var user: resolve(parsed, light)
    FileView {
        path: theme.testing ? "" : (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/filigrane/theme.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: theme.parsed = theme.parseToml(text())
        onLoadFailed: theme.parsed = ({})
    }
    function stripComment(line) {
        let q = false;
        for (let i = 0; i < line.length; i++) {
            if (line[i] === '"')
                q = !q;
            else if (line[i] === "#" && !q)
                return line.slice(0, i);
        }
        return line;
    }
    function parseToml(text) {
        const out = {};
        let sec = "";
        for (const raw of text.split("\n")) {
            const line = stripComment(raw).trim();
            const h = /^\[(.+)\]$/.exec(line);
            if (h) {
                sec = h[1].trim();
                continue;
            }
            const i = line.indexOf("=");
            if (i < 0)
                continue;
            const k = line.slice(0, i).trim();
            const v = line.slice(i + 1).trim();
            if (!out[sec])
                out[sec] = {};
            out[sec][k] = v.startsWith("[") && v.endsWith("]") ? v.slice(1, -1).split(",").map(x => x.trim().replace(/^"|"$/g, "").trim()).filter(x => x) : v.replace(/^"|"$/g, "").trim();
        }
        return out;
    }
    // Clés valables pour le mode: [theme.<mode>] passe devant [theme]
    function resolve(p, isLight) {
        const out = {};
        for (const sec of ["theme", isLight ? "theme.light" : "theme.dark"])
            for (const k in (p[sec] || {}))
                out[k] = p[sec][k];
        return out;
    }
    // Valeur de l'utilisateur pour la clé, sinon def; le type de def décide de ce qui est valable (entier, couleur, texte)
    function ov(key, def) {
        const v = user[key];
        if (typeof v !== "string")
            return def;
        if (typeof def === "number")
            return /^\d+$/.test(v) ? Number(v) : def;
        if (typeof def === "string" && def.charAt(0) === "#")
            return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) ? v : def;
        return v ? v : def;
    }
    // Teintes d'accentuation: celles de [theme.accents] (4 couleurs valides) complètent ou remplacent les défauts
    function tones(base) {
        const out = {};
        for (const k in base)
            out[k] = base[k];
        const extra = parsed["theme.accents"] || {};
        for (const k in extra)
            if (Array.isArray(extra[k]) && extra[k].length === 4 && extra[k].every(c => /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(c)))
                out[k] = extra[k];
        return out;
    }
    // FileView ne voit pas naître un fichier dans un dossier absent
    Component.onCompleted: if (!testing) Quickshell.execDetached(["mkdir", "-p", stateFile.replace(/\/[^/]*$/, "")])

    readonly property color nuit: ov("background", light ? "#f3f1ec" : "#1c222b")
    readonly property color nuitProfond: ov("background_deep", light ? "#f8f7f3" : "#181d25")
    readonly property color nuit2: ov("surface", light ? "#e9e6df" : "#232b36")
    readonly property color nuit3: ov("surface_hover", light ? "#dfdbd2" : "#2d3744")
    readonly property color nuit4: ov("surface_active", light ? "#cdc8bd" : "#3c4858")
    readonly property color ardoise: ov("muted", "#5f7894")
    readonly property color border: ov("border", light ? "#cdc8bd" : "#3c4858")
    readonly property color brume2: ov("text_secondary", light ? "#4f5e70" : "#a9b8c8")
    // Couleur d'accentuation (fili-theme accent): [sombre, sombre vif, clair, clair vif]; défaut = sable en sombre, ardoise en clair
    readonly property var accentTones: tones({ default: ["#d2bf92", "#e0d1ab", "#4f6884", "#3d5470"], voile: ["#9dbbd6", "#b9d0e4", "#3f5a78", "#2f4a66"], ardoise: ["#7f9ab6", "#9ab2ca", "#4f6884", "#3d5470"], sauge: ["#a3bfa8", "#bcd3c0", "#4a7354", "#385a42"], sable: ["#d2bf92", "#e0d1ab", "#80662b", "#654f1f"], cendre: ["#c98f93", "#d9a8ab", "#9a4f55", "#7d3c42"], brume: ["#dbe7f4", "#f3f1ec", "#4f5e70", "#1c222b"] })
    readonly property var tone: accentTones[accent] || accentTones.default
    readonly property color voile: ov("accent", light ? tone[2] : tone[0])
    readonly property color voileVif: ov("accent_bright", light ? tone[3] : tone[1])
    readonly property color brume: ov("text", light ? "#1c222b" : "#dbe7f4")
    readonly property color sable: ov("warning", light ? "#80662b" : "#d2bf92")
    readonly property color cendre: ov("danger", light ? "#9a4f55" : "#c98f93")
    readonly property color sauge: ov("success", light ? "#4a7354" : "#a3bfa8")
    // Couleur c avec l'opacité a (voiles translucides)
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property string font: ov("font", "Jost")
    readonly property string mono: ov("mono", "JetBrains Mono")
    // Échelle typographique (tokens.md): système 14, vue (listes) 13, petit (secondaire, infobulles, intertitres) 12,
    // étiquette 11; titre ≥ 18 (seul palier où le Light est permis); accent = Jost SemiBold 600
    readonly property int size: ov("size", 14)
    readonly property int sizeList: ov("size_list", 13)
    readonly property int sizeSmall: ov("size_small", 12)
    readonly property int sizeLabel: ov("size_label", 11)
    readonly property int sizeTitle: ov("size_title", 18)
    readonly property int weightAccent: ov("weight_accent", Font.DemiBold)
    // Rayons: repères et jauges 2, contrôles / lignes / fiches 6, fenêtres de couche 10
    readonly property int borderWidth: ov("border_width", 1)
    readonly property int radiusMark: ov("radius_mark", 2)
    readonly property int radiusControl: ov("radius_control", 6)
    readonly property int radiusWindow: ov("radius_window", 10)
    // Espacements: éléments liés 4, entre contrôles 8, entre groupes 12, bord d'onglet 16, marge de panneau 20, alerte 24
    readonly property int space1: ov("space_1", 4)
    readonly property int space2: ov("space_2", 8)
    readonly property int space3: ov("space_3", 12)
    readonly property int space4: ov("space_4", 16)
    readonly property int space5: ov("space_5", 20)
    readonly property int space6: ov("space_6", 24)
    readonly property int barHeight: ov("bar_height", 24)
    // Rythme de la fili-bar, un seul pour tous les modules (pas d'écart propre aux groupes): marge de chaque module
    // (l'écart entre deux textes vaut donc 2 × pad), cellule minimale d'une icône seule (son trait fait ~10 px: de
    // même marge visible), espace entre l'étiquette (CPU, RAM) et sa valeur
    readonly property int pad: ov("pad", 7)
    readonly property int iconCell: ov("icon_cell", 24)
    readonly property int labelGap: ov("label_gap", 5)
    // Texte réduit à une seule icône (code privé Nerd Font / Fili Icons)
    function isIcon(t) {
        return /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF])$/.test(t);
    }

    // Règle de la fili-bar: icône (ou étiquette) en ardoise devant la valeur en blanc. "<icône> valeur" est coupé ici;
    // un état (sable, cendre, voile...) colore tout le module, seul le neutre (brume, brume2) grise l'icône.
    function glyph(t) {
        const m = /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF]) (.+)$/.exec(t);
        return m ? m[1] : "";
    }
    function value(t) {
        const m = /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF]) (.+)$/.exec(t);
        return m ? m[2] : t;
    }
    function iconColor(c) {
        return Qt.colorEqual(c, brume) || Qt.colorEqual(c, brume2) ? ardoise : c;
    }

    // Icône d'une sortie audio d'après ses propriétés PipeWire: casque (filaire ou Bluetooth), enceinte Bluetooth,
    // écran (HDMI, DisplayPort); "" pour des haut-parleurs (l'appelant garde l'icône graduée selon le volume)
    function sinkGlyph(p) {
        if (!p)
            return "";
        const s = [p["device.form-factor"], p["device.icon-name"], p["device.icon_name"], p["device.profile.name"],
                   p["node.name"], p["alsa.name"]].join(" ").toLowerCase();
        const head = /head(phone|set)|hands-?free|earbud/.test(s);
        if (p["device.api"] === "bluez5" || s.indexOf("bluez") >= 0 || s.indexOf("bluetooth") >= 0)
            return String.fromCodePoint(/speaker|car|portable/.test(s) && !head ? 0xf09a2 : 0xf0970);
        if (head)
            return String.fromCodePoint(0xf025);
        if (/hdmi|displayport/.test(s))
            return String.fromCodePoint(0xf0379);
        return "";
    }

    // Scripts et binaires de la distribution (~/.local/bin; FILI_BIN pour les tests)
    readonly property string bin: Quickshell.env("FILI_BIN") || Quickshell.env("HOME") + "/.local/bin"

    // Mode test (tests/fili-shell/run.sh): fenêtres masquées, commandes enregistrées au lieu d'être lancées
    readonly property bool testing: Quickshell.env("FILI_TEST") === "1"
    property var ran: []

    // Lance une commande shell détachée (actions des clics), depuis $HOME: un dossier courant supprimé ferait
    // échouer foot et d'autres ("failed to get current working directory"). Commande, sortie et erreurs dans
    // $XDG_RUNTIME_DIR/fili-shell-run.log (tmpfs) pour comprendre un clic qui ne lance rien
    function run(cmd) {
        if (!cmd)
            return;
        if (testing) {
            ran = ran.concat([cmd]);
            return;
        }
        Quickshell.execDetached(["sh", "-c", 'cd "$HOME" 2>/dev/null; l="${XDG_RUNTIME_DIR:-/tmp}/fili-shell-run.log"; echo "$(date +%T) $1" >> "$l"; sh -c "$1" >> "$l" 2>&1 || echo "  -> code $?" >> "$l"', "sh", cmd]);
    }
}
