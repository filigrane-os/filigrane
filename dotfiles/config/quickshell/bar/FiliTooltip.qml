pragma Singleton
// fili-tooltip: the fili-bar's single information card, under the hovered item (after 400 ms), inspired by the
// Omarchy panels but read-only: the actions stay on the clicks, recalled by the help line.
// Standard: title on the left, content on the right (same layout as PanelInfo). Content: text (script output, Pango markup
// removed, <tt> = fixed width) or card { title, rows: [[label, value]...], text, hint }. A row can carry a gauge under its value:
// [label, value, { value: 0..1, mark: 0..1 }] (mark: a tick, for example the expected usage at a steady pace).
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

Singleton {
    id: tip
    property Item target: null
    property var card: ({})
    // Grace period after a fili-panel closes (ms), during which no card opens
    readonly property int cooldown: 1500

    function normalize(c) {
        if (typeof c === "string")
            c = { text: c };
        c = Object.assign({}, c ?? {});
        if (c.text) {
            c.mono = c.mono ?? c.text.indexOf("<tt>") >= 0;
            c.text = c.text.replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
        }
        return c;
    }
    function empty(c) {
        return !c || (!c.title && !c.text && !(c.rows && c.rows.length));
    }
    function show(item, content) {
        const c = normalize(content);
        // Nothing during a fili-panel, nor right after it closes (the mouse is still on the clicked icon: the card would
        // pop up at once and look like a bug): leave the icon, then come back after the grace period
        if (empty(c) || FiliShell.anyOpen || Date.now() < FiliShell.panelClosedAt + cooldown) {
            hide(item);
            return;
        }
        card = c;
        if (target !== item) {
            target = item;
            popup.visible = false;
            delay.restart();
        }
    }
    // Update the displayed card (data that arrived after the hover) without restarting the delay
    function update(item, content) {
        if (item === target)
            card = normalize(content);
    }
    function hide(item) {
        if (item && item !== target)
            return;
        delay.stop();
        popup.visible = false;
        target = null;
    }

    Timer {
        id: delay
        interval: 400
        onTriggered: if (tip.target && !tip.empty(tip.card)) popup.visible = true
    }

    PopupWindow {
        id: popup
        visible: false
        anchor.item: tip.target
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        implicitWidth: body.implicitWidth + 28
        implicitHeight: body.implicitHeight + 22
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: FiliTheme.nuit
            border.color: FiliTheme.border
            border.width: FiliTheme.borderWidth
            radius: FiliTheme.radiusWindow

            ColumnLayout {
                id: body
                anchors.centerIn: parent
                spacing: FiliTheme.space2
                // Card standard: title on the left, content (label / value rows, or text) on the right
                RowLayout {
                    spacing: FiliTheme.space4
                    Text {
                        visible: !!tip.card.title
                        Layout.alignment: Qt.AlignTop
                        Layout.maximumWidth: 160
                        elide: Text.ElideRight
                        text: tip.card.title ?? ""
                        color: FiliTheme.voile
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: FiliTheme.space2
                        GridLayout {
                            visible: !!(tip.card.rows && tip.card.rows.length)
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 3
                            Repeater {
                                model: (tip.card.rows ?? []).reduce((a, r) => a.concat([{ t: r[0], key: true }, { t: r[1], key: false, gauge: r[2] ?? null }]), [])
                                ColumnLayout {
                                    id: cell
                                    required property var modelData
                                    spacing: FiliTheme.space1
                                    Layout.alignment: Qt.AlignTop
                                    Text {
                                        text: cell.modelData.t
                                        color: cell.modelData.key ? FiliTheme.ardoise : FiliTheme.brume
                                        Layout.maximumWidth: cell.modelData.key ? 140 : 420
                                        elide: Text.ElideRight
                                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                    }
                                    // Gauge: voile, sable from 80 %, cendre from 95 %; thin mark in brume
                                    Item {
                                        readonly property var g: cell.modelData.gauge
                                        visible: !!g
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 180
                                        Layout.bottomMargin: 2
                                        implicitHeight: 4
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: FiliTheme.radiusMark
                                            color: FiliTheme.nuit3
                                        }
                                        Rectangle {
                                            readonly property real v: Math.max(0, Math.min(1, parent.g?.value ?? 0))
                                            width: parent.width * v
                                            height: parent.height
                                            radius: FiliTheme.radiusMark
                                            color: v >= 0.95 ? FiliTheme.cendre : v >= 0.8 ? FiliTheme.sable : FiliTheme.voile
                                        }
                                        Rectangle {
                                            readonly property real m: parent.g?.mark ?? -1
                                            visible: m >= 0 && m <= 1
                                            x: Math.round(parent.width * m) - 1
                                            y: -2
                                            width: 2
                                            height: parent.height + 4
                                            color: FiliTheme.brume
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: !!tip.card.text
                            text: tip.card.text ?? ""
                            color: FiliTheme.brume
                            font.family: tip.card.mono ? FiliTheme.mono : FiliTheme.font
                            font.pixelSize: tip.card.mono ? FiliTheme.sizeList : FiliTheme.size
                        }
                    }
                }
                Rectangle {
                    visible: !!tip.card.hint
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 1
                    color: FiliTheme.nuit3
                }
                Text {
                    visible: !!tip.card.hint
                    text: tip.card.hint ?? ""
                    color: FiliTheme.ardoise
                    font { family: FiliTheme.font; pixelSize: FiliTheme.sizeList }
                }
            }
        }
    }
}
