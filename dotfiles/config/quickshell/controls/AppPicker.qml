// Picker of an application: a dialog over the whole window it sits in, search field on top, a list of the entries
// that match (name or detail), Enter or a click picks the selected one, Esc, Cancel or a click outside closes. The
// caller gives the entries and decides what a choice does:
//   AppPicker { open: view.adding; entries: [{ id, name, detail, icon }]; onPicked: e => ...; onClosed: view.adding = false }
// `icon` is an icon name or an absolute path; without one the row shows a square. The dialog is reparented over the
// window (never clipped by a scrolling page); declare it in a layout, it takes no room there.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs

Item {
    id: picker
    property bool open: false
    property string title: ""
    property string placeholder: ""
    property string emptyText: ""
    // [{ id, name, detail, icon }]
    property var entries: []
    property string query: ""
    property int index: 0
    signal picked(var entry)
    signal closed

    // Entries matching the query, by name then detail
    readonly property var matches: {
        const q = query.trim().toLowerCase();
        return entries.filter(e => q === "" || (e.name ?? "").toLowerCase().indexOf(q) >= 0 || (e.detail ?? "").toLowerCase().indexOf(q) >= 0);
    }
    function choose(i) {
        const e = matches[i];
        if (e)
            picked(e);
    }
    onOpenChanged: {
        query = "";
        index = 0;
    }
    onQueryChanged: index = 0

    Layout.preferredHeight: 0
    Layout.fillWidth: true

    Item {
        id: dialog
        objectName: "picker-dialog"
        visible: picker.open
        parent: picker.Window.window ? picker.Window.window.contentItem : picker
        anchors.fill: parent
        z: 100
        // Dim what is behind; a click outside the box closes
        Rectangle {
            anchors.fill: parent
            radius: FiliTheme.radiusWindow
            color: FiliTheme.alpha(FiliTheme.nuit, 0.8)
            MouseArea { anchors.fill: parent; onClicked: picker.closed() }
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * FiliTheme.space5, 420)
            height: Math.min(parent.height - 2 * FiliTheme.space5, 440)
            radius: FiliTheme.radiusWindow
            color: FiliTheme.nuit2
            border { color: FiliTheme.border; width: FiliTheme.borderWidth }
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                anchors { fill: parent; margins: FiliTheme.space4 }
                spacing: FiliTheme.space2
                Text {
                    text: picker.title
                    color: FiliTheme.brume
                    font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: FiliTheme.radiusControl
                    color: FiliTheme.nuit
                    border { width: 1; color: search.activeFocus ? FiliTheme.nuit4 : FiliTheme.nuit3 }
                    TextInput {
                        id: search
                        objectName: "picker-search"
                        anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: FiliTheme.brume
                        selectionColor: FiliTheme.nuit4
                        selectedTextColor: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                        text: picker.query
                        onTextEdited: picker.query = text
                        Connections {
                            target: dialog
                            function onVisibleChanged() {
                                if (dialog.visible) {
                                    search.text = "";
                                    search.forceActiveFocus();
                                }
                            }
                        }
                        Keys.onEscapePressed: e => { picker.closed(); e.accepted = true; }
                        Keys.onDownPressed: picker.index = Math.min(picker.matches.length - 1, picker.index + 1)
                        Keys.onUpPressed: picker.index = Math.max(0, picker.index - 1)
                        Keys.onTabPressed: e => { picker.index = Math.min(picker.matches.length - 1, picker.index + 1); e.accepted = true; }
                        Keys.onBacktabPressed: e => { picker.index = Math.max(0, picker.index - 1); e.accepted = true; }
                        onAccepted: picker.choose(picker.index)
                        Text {
                            visible: !search.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: picker.placeholder
                            color: FiliTheme.ardoise
                            font: search.font
                        }
                    }
                }
                ListView {
                    id: list
                    objectName: "picker-list"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: picker.open ? picker.matches : []
                    currentIndex: picker.index
                    highlightMoveDuration: 0
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        objectName: "pick-" + modelData.id
                        width: list.width
                        height: 34
                        radius: FiliTheme.radiusControl
                        color: row.index === picker.index ? FiliTheme.nuit3 : hover.containsMouse ? FiliTheme.alpha(FiliTheme.nuit3, 0.6) : "transparent"
                        RowLayout {
                            anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                            spacing: FiliTheme.space2
                            Item {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                IconImage {
                                    anchors.fill: parent
                                    visible: source != ""
                                    source: row.modelData.icon && !row.modelData.icon.startsWith("/") ? Quickshell.iconPath(row.modelData.icon, true)
                                        : row.modelData.icon ? "file://" + row.modelData.icon : ""
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !row.modelData.icon
                                    text: "□"
                                    color: FiliTheme.ardoise
                                    font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                color: FiliTheme.brume
                                elide: Text.ElideRight
                                font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            }
                            Text {
                                Layout.maximumWidth: list.width * 0.45
                                text: row.modelData.detail ?? ""
                                color: FiliTheme.ardoise
                                elide: Text.ElideRight
                                font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                            }
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.choose(row.index)
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: picker.emptyText
                        color: FiliTheme.ardoise
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PanelButton {
                        objectName: "picker-cancel"
                        Layout.fillWidth: false
                        Layout.preferredWidth: 90
                        label: FiliI18n.tr("Cancel")
                        onClicked: picker.closed()
                    }
                }
            }
        }
    }
}
