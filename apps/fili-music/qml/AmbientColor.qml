// The dominant colour of a cover, for tinting what sits around it: the image is shrunk to a small canvas and its pixels
// averaged, weighted by saturation so that a coloured cover wins over its grey borders. `color` is transparent until the
// image is read (or when there is none), so a tint made of it simply does not show. `colors` are the three main colours of
// the cover, apart from each other (the first the strongest); a cover with fewer colours gets shades of its main one.
import QtQuick

Item {
    id: ambient
    // file:// URL of the cover ("" when none)
    property string source: ""
    property color color: "transparent"
    property var colors: [Qt.rgba(0, 0, 0, 0), Qt.rgba(0, 0, 0, 0), Qt.rgba(0, 0, 0, 0)]
    readonly property int grid: 16
    width: 0
    height: 0
    // Not `visible: false`: a canvas of a hidden item is never painted
    opacity: 0

    onSourceChanged: {
        color = "transparent";
        colors = [Qt.rgba(0, 0, 0, 0), Qt.rgba(0, 0, 0, 0), Qt.rgba(0, 0, 0, 0)];
        if (source === "")
            return;
        // A cover the canvas already holds sends no imageLoaded again (the same cover back, a refresh): paint it at once
        if (canvas.isImageLoaded(source))
            canvas.requestPaint();
        else
            canvas.loadImage(source);
    }
    function mix(c, to, amount) {
        return Qt.rgba(c.r + (to - c.r) * amount, c.g + (to - c.g) * amount, c.b + (to - c.b) * amount, 1);
    }
    Canvas {
        id: canvas
        width: ambient.grid
        height: ambient.grid
        renderTarget: Canvas.Image
        onImageLoaded: requestPaint()
        onPaint: {
            if (ambient.source === "" || !isImageLoaded(ambient.source))
                return;
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(ambient.source, 0, 0, width, height);
            const px = ctx.getImageData(0, 0, width, height).data;
            let r = 0, g = 0, b = 0, w = 0;
            // Hue families (12 of 30 degrees) with their weighted sums, for the three main colours
            const fam = [];
            for (let f = 0; f < 12; f++)
                fam.push({ r: 0, g: 0, b: 0, w: 0 });
            for (let i = 0; i < px.length; i += 4) {
                const mx = Math.max(px[i], px[i + 1], px[i + 2]), mn = Math.min(px[i], px[i + 1], px[i + 2]);
                // Near black and near white carry no hue; saturation weighs the rest (squared: strong colours dominate)
                if (px[i + 3] < 128 || mx < 30 || mn > 235)
                    continue;
                const sat = (mx - mn) / mx;
                const k = 0.05 + sat * sat;
                r += px[i] * k;
                g += px[i + 1] * k;
                b += px[i + 2] * k;
                w += k;
                // Greys have no hue: they weigh in the average colour only
                if (sat < 0.12)
                    continue;
                let h = mx === mn ? 0 : mx === px[i] ? ((px[i + 1] - px[i + 2]) / (mx - mn) + 6) % 6 : mx === px[i + 1] ? (px[i + 2] - px[i]) / (mx - mn) + 2 : (px[i] - px[i + 1]) / (mx - mn) + 4;
                const f = fam[Math.floor(h * 2) % 12];
                f.r += px[i] * k;
                f.g += px[i + 1] * k;
                f.b += px[i + 2] * k;
                f.w += k;
            }
            if (w <= 0) {
                ambient.color = "transparent";
                ambient.colors = [Qt.rgba(0, 0, 0, 0), Qt.rgba(0, 0, 0, 0), Qt.rgba(0, 0, 0, 0)];
                return;
            }
            ambient.color = Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1);
            // Strongest families first; one counts as a new colour only when it differs enough from the ones kept
            const main = fam.filter(f => f.w > 0).sort((a, b) => b.w - a.w).map(f => Qt.rgba(f.r / f.w / 255, f.g / f.w / 255, f.b / f.w / 255, 1));
            const kept = [];
            for (const c of main) {
                if (kept.every(o => Math.hypot(o.r - c.r, o.g - c.g, o.b - c.b) > 0.28))
                    kept.push(c);
                if (kept.length === 3)
                    break;
            }
            if (kept.length === 0)
                kept.push(ambient.color);
            // Missing colours: a lighter and a darker shade of the first
            if (kept.length < 2)
                kept.push(ambient.mix(kept[0], 1, 0.35));
            if (kept.length < 3)
                kept.push(ambient.mix(kept[0], 0, 0.4));
            ambient.colors = kept;
        }
    }
}
