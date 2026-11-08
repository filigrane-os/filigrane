pragma Singleton
// Filigrane (brand.md): night background, mist text, voile accent; no other bright colour, desaturated states.
// Light mode (fili-theme light, chosen in the displays fili-panel): the names keep their role of the dark mode
// (nuit = background, brume = text, voile = accent) and take the light shades: paper background, nuit text, dark
// ardoise accent, darkened states (contrast ≥ 4.8:1 on paper)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme
    // "dark" (default) or "light", read from the fili-theme state and re-read as soon as it changes (the tests set it)
    property string mode: "dark"
    readonly property bool light: mode === "light"
    // Accent colour (name), read from the fili-theme state like the mode
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
    // Optional global settings: ~/.config/filigrane/theme.toml (sections [theme], [theme.dark], [theme.light],
    // [theme.accents]; keys in English, see fili-file/theme.toml). Re-read as soon as they change; the values
    // below are the defaults (a test keeps them identical to those of fili-file); an invalid value is ignored.
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
        const lines = text.split("\n");
        for (let n = 0; n < lines.length; n++) {
            const line = stripComment(lines[n]).trim();
            const h = /^\[(.+)\]$/.exec(line);
            if (h) {
                sec = h[1].trim();
                continue;
            }
            const i = line.indexOf("=");
            if (i < 0)
                continue;
            const k = line.slice(0, i).trim();
            let v = line.slice(i + 1).trim();
            // An array can span several lines: gather them up to the closing bracket
            while (v.startsWith("[") && !v.endsWith("]") && n + 1 < lines.length)
                v += " " + stripComment(lines[++n]).trim();
            if (!out[sec])
                out[sec] = {};
            out[sec][k] = v.startsWith("[") && v.endsWith("]") ? v.slice(1, -1).split(",").map(x => x.trim().replace(/^"|"$/g, "").trim()).filter(x => x) : v.replace(/^"|"$/g, "").trim();
        }
        return out;
    }
    // Keys valid for the mode: [theme.<mode>] takes precedence over [theme]
    function resolve(p, isLight) {
        const out = {};
        for (const sec of ["theme", isLight ? "theme.light" : "theme.dark"])
            for (const k in (p[sec] || {}))
                out[k] = p[sec][k];
        return out;
    }
    // Value of the user for the key, else def; the type of def decides what is valid (integer, colour, text)
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
    // Accent shades: those of [theme.accents] (4 valid colours) complete or replace the defaults
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
    // FileView does not see a file appear in a missing folder
    Component.onCompleted: if (!testing) Quickshell.execDetached(["mkdir", "-p", stateFile.replace(/\/[^/]*$/, "")])

    readonly property color nuit: ov("background", light ? "#f3f1ec" : "#1c222b")
    readonly property color nuitProfond: ov("background_deep", light ? "#f8f7f3" : "#181d25")
    readonly property color nuit2: ov("surface", light ? "#e9e6df" : "#232b36")
    readonly property color nuit3: ov("surface_hover", light ? "#dfdbd2" : "#2d3744")
    readonly property color nuit4: ov("surface_active", light ? "#cdc8bd" : "#3c4858")
    readonly property color ardoise: ov("muted", "#5f7894")
    readonly property color border: ov("border", light ? "#cdc8bd" : "#3c4858")
    readonly property color brume2: ov("text_secondary", light ? "#4f5e70" : "#a9b8c8")
    // Accent colour (fili-theme accent): [dark, vivid dark, light, vivid light]; default = sable in dark, ardoise in light
    readonly property var accentTones: tones({ default: ["#d2bf92", "#e0d1ab", "#4f6884", "#3d5470"], voile: ["#9dbbd6", "#b9d0e4", "#3f5a78", "#2f4a66"], ardoise: ["#7f9ab6", "#9ab2ca", "#4f6884", "#3d5470"], sauge: ["#a3bfa8", "#bcd3c0", "#4a7354", "#385a42"], sable: ["#d2bf92", "#e0d1ab", "#80662b", "#654f1f"], cendre: ["#c98f93", "#d9a8ab", "#9a4f55", "#7d3c42"], brume: ["#dbe7f4", "#f3f1ec", "#4f5e70", "#1c222b"] })
    readonly property var tone: accentTones[accent] || accentTones.default
    // Name of the colour actually shown: without a choice (or an unknown name), sable in dark, ardoise in light
    readonly property string accentName: accent !== "default" && accentTones[accent] ? accent : (light ? "ardoise" : "sable")
    readonly property color voile: ov("accent", light ? tone[2] : tone[0])
    readonly property color voileVif: ov("accent_bright", light ? tone[3] : tone[1])
    readonly property color brume: ov("text", light ? "#1c222b" : "#dbe7f4")
    readonly property color sable: ov("warning", light ? "#80662b" : "#d2bf92")
    readonly property color cendre: ov("danger", light ? "#9a4f55" : "#c98f93")
    readonly property color sauge: ov("success", light ? "#4a7354" : "#a3bfa8")
    // Colour c with opacity a (translucent veils)
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property string font: ov("font", "Jost")
    readonly property string mono: ov("mono", "JetBrains Mono")
    // Type scale (tokens.md): system 14, view (lists) 13, small (secondary, tooltips, subheadings) 12,
    // label 11; title ≥ 18 (the only step where Light is allowed); accent = Jost SemiBold 600
    readonly property int size: ov("size", 14)
    readonly property int sizeList: ov("size_list", 13)
    readonly property int sizeSmall: ov("size_small", 12)
    readonly property int sizeLabel: ov("size_label", 11)
    readonly property int sizeTitle: ov("size_title", 18)
    readonly property int weightAccent: ov("weight_accent", Font.DemiBold)
    // Radii: marks and gauges 2, controls / rows / cards 6, layer windows 10
    readonly property int borderWidth: ov("border_width", 1)
    readonly property int radiusMark: ov("radius_mark", 2)
    readonly property int radiusControl: ov("radius_control", 6)
    readonly property int radiusWindow: ov("radius_window", 10)
    // Spacing: related items 4, between controls 8, between groups 12, tab edge 16, panel margin 20, alert 24
    readonly property int space1: ov("space_1", 4)
    readonly property int space2: ov("space_2", 8)
    readonly property int space3: ov("space_3", 12)
    readonly property int space4: ov("space_4", 16)
    readonly property int space5: ov("space_5", 20)
    readonly property int space6: ov("space_6", 24)
    readonly property int barHeight: ov("bar_height", 24)
    // fili-bar rhythm, a single one for all the modules (no gap of its own for groups): margin of each module
    // (the gap between two texts is therefore 2 × pad), minimum cell of a lone icon (its stroke is ~10 px: same
    // visible margin), space between the label (CPU, RAM) and its value
    readonly property int pad: ov("pad", 7)
    readonly property int iconCell: ov("icon_cell", 24)
    readonly property int labelGap: ov("label_gap", 5)
    // Text reduced to a single icon (private-use code point of Nerd Font / Fili Icons)
    function isIcon(t) {
        return /^([\uE000-\uF8FF]|[\uDB80-\uDBBF][\uDC00-\uDFFF])$/.test(t);
    }

    // fili-bar rule: icon (or label) in slate before the value in white. "<icon> value" is split here;
    // a state (sable, cendre, voile...) colours the whole module, only the neutral (brume, brume2) greys the icon.
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

    // Icon of an audio output from its PipeWire properties: headset (wired or Bluetooth), Bluetooth speaker,
    // display (HDMI, DisplayPort); "" for loudspeakers (the caller keeps the icon graded by volume)
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

    // Scripts and binaries of the distribution (~/.local/bin; FILI_BIN for the tests)
    readonly property string bin: Quickshell.env("FILI_BIN") || Quickshell.env("HOME") + "/.local/bin"

    // Test mode (tests/fili-shell/run.sh): windows hidden, commands recorded instead of run
    readonly property bool testing: Quickshell.env("FILI_TEST") === "1"
    property var ran: []

    // Run a detached shell command (actions of the clicks), from $HOME: a deleted current directory would make
    // foot and others fail ("failed to get current working directory"). Command, output and errors in
    // $XDG_RUNTIME_DIR/fili-shell-run.log (tmpfs) to understand a click that runs nothing
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
