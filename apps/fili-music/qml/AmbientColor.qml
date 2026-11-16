// The dominant colour of a cover, for tinting what sits around it: the image is shrunk to a small canvas and its pixels
// averaged, weighted by saturation so that a coloured cover wins over its grey borders. `color` is transparent until the
// image is read (or when there is none), so a tint made of it simply does not show.
import QtQuick

Item {
    id: ambient
    // file:// URL of the cover ("" when none)
    property string source: ""
    property color color: "transparent"
    readonly property int grid: 12
    width: 0
    height: 0
    // Not `visible: false`: a canvas of a hidden item is never painted
    opacity: 0

    onSourceChanged: {
        color = "transparent";
        if (source !== "")
            canvas.loadImage(source);
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
            }
            ambient.color = w > 0 ? Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1) : "transparent";
        }
    }
}
