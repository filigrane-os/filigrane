// Wi-Fi: click = impala panel (SSID, connection), right click = network menu (IP, ping, speed)
import QtQuick
import qs
import qs.bar

BarScript {
    objectName: "network"
    panel: "network"
    panelSource: Qt.resolvedUrl("NetworkPanel.qml")
    stat: "net"; hideEmpty: false
    colors: ({ disconnected: FiliTheme.cendre })
    hover.onLeftClicked: togglePanel()
    rclick: "setsid -f " + FiliTheme.bin + "/menu network"
    tipInfo: "network"
}
