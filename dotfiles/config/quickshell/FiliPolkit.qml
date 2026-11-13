pragma Singleton
// fili-polkit: the authentication window of the whole system. The fili-shell is the polkit agent of the session
// (Quickshell.Services.Polkit): when a program needs an administrator (a Settings page that changes the firewall, a
// disk to mount, `pkexec`...), polkit asks the agent and this window opens in the middle of the screen, above
// everything, with the reason, the account and what PAM asks for: a password, or nothing to type when the answer is
// a fingerprint or a key (PAM decides the means; the window shows its messages and waits). Enter confirms, Esc or
// Cancel refuses; a wrong answer is said in words and asked again. Nothing runs while no request is pending.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.bar
import qs.controls

Singleton {
    id: root
    // The request being answered (an AuthFlow), null when there is none. Tests give their own object.
    property var testFlow: null
    readonly property var flow: testFlow ?? (agentLoader.item ? agentLoader.item.flow : null)
    readonly property bool open: flow !== null
    // Said by the window: who is asking, in words
    readonly property string account: flow?.selectedIdentity?.displayName ?? flow?.selectedIdentity?.name ?? ""

    // The agent registers itself on the session; never in the tests (it would take the place of the real one)
    Loader {
        id: agentLoader
        active: !FiliTheme.testing
        sourceComponent: PolkitAgent {}
    }

    function submit(text) {
        if (flow && flow.isResponseRequired)
            flow.submit(text);
    }
    function cancel() {
        if (flow)
            flow.cancelAuthenticationRequest();
    }

    PanelWindow {
        id: win
        visible: root.open && !FiliTheme.testing
        // No anchors: the compositor centres the window
        implicitWidth: card.width
        implicitHeight: card.height
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fili-polkit"
        // Exclusive: the password goes here and nowhere else
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.cancel()
            Rectangle {
                id: card
                width: 380
                height: body.implicitHeight + 2 * FiliTheme.space5
                color: FiliTheme.nuit
                border { color: FiliTheme.border; width: FiliTheme.borderWidth }
                radius: FiliTheme.radiusWindow

                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space5 }
                    spacing: FiliTheme.space2
                    Text {
                        Layout.fillWidth: true
                        text: FiliI18n.tr("Authentication required")
                        color: FiliTheme.voile
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size; weight: FiliTheme.weightAccent }
                    }
                    // What for, as the program words it ("Change the firewall")
                    Text {
                        objectName: "polkit-message"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.flow?.message ?? ""
                        color: FiliTheme.brume
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.account !== ""
                        elide: Text.ElideRight
                        text: FiliI18n.tr("Account: %1", root.account)
                        color: FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }

                    // The question of PAM ("Password:"), when it asks for something to type
                    Text {
                        Layout.topMargin: FiliTheme.space1
                        Layout.fillWidth: true
                        visible: root.flow?.isResponseRequired ?? false
                        text: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "")
                        color: FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                    }
                    Rectangle {
                        id: field
                        objectName: "polkit-field"
                        Layout.fillWidth: true
                        visible: root.flow?.isResponseRequired ?? false
                        implicitHeight: 28
                        radius: FiliTheme.radiusControl
                        color: FiliTheme.nuit2
                        border { color: input.activeFocus ? FiliTheme.voile : FiliTheme.nuit4; width: FiliTheme.borderWidth }
                        TextInput {
                            id: input
                            anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            focus: true
                            // The password stays hidden unless PAM says the answer may be shown
                            echoMode: (root.flow?.responseVisible ?? false) ? TextInput.Normal : TextInput.Password
                            color: FiliTheme.brume
                            selectionColor: FiliTheme.voile
                            selectedTextColor: FiliTheme.nuit
                            font { family: FiliTheme.font; pixelSize: FiliTheme.size }
                            Accessible.name: root.flow?.inputPrompt ?? ""
                            onAccepted: {
                                root.submit(text);
                                text = "";
                            }
                            // A new question (a wrong password, a second factor) starts with an empty field and the focus
                            Connections {
                                target: root
                                function onFlowChanged() { input.text = ""; input.forceActiveFocus(); }
                            }
                            Connections {
                                target: root.flow
                                function onIsResponseRequiredChanged() { input.text = ""; input.forceActiveFocus(); }
                            }
                        }
                    }
                    // Nothing to type: the means is not a password (fingerprint, key); PAM's message tells what to do
                    Text {
                        objectName: "polkit-wait"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        visible: root.flow !== null && !root.flow.isResponseRequired && !root.flow.failed
                        text: FiliI18n.tr("Waiting for authentication…")
                        color: FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }
                    // PAM's own words (an instruction, or an error), and a wrong answer said in words
                    Text {
                        objectName: "polkit-info"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        visible: text !== ""
                        text: root.flow?.failed ? FiliI18n.tr("Authentication failed. Try again.") : (root.flow?.supplementaryMessage ?? "")
                        color: root.flow?.failed || (root.flow?.supplementaryIsError ?? false) ? FiliTheme.cendre : FiliTheme.brume2
                        font { family: FiliTheme.font; pixelSize: FiliTheme.sizeSmall }
                    }

                    RowLayout {
                        Layout.topMargin: FiliTheme.space2
                        Layout.fillWidth: true
                        spacing: FiliTheme.space2
                        Item { Layout.fillWidth: true }
                        PanelButton {
                            objectName: "polkit-cancel"
                            Layout.fillWidth: false
                            Layout.preferredWidth: 80
                            label: FiliI18n.tr("Cancel")
                            onClicked: root.cancel()
                        }
                        PanelButton {
                            objectName: "polkit-ok"
                            Layout.fillWidth: false
                            Layout.preferredWidth: 100
                            visible: root.flow?.isResponseRequired ?? false
                            label: FiliI18n.tr("Authenticate")
                            onClicked: {
                                root.submit(input.text);
                                input.text = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
