// Personal alerts: new Proton mails / imminent Proton Calendar event (hidden otherwise, see BarState), click = open and clear
import QtQuick
import qs
import qs.bar

BarModule {
    Row {
        BarScript { objectName: "mail"; value: BarState.mail; color: FiliTheme.voile; click: FiliTheme.bin + "/bar-alert open mail" }
        BarScript { objectName: "whatsapp"; value: BarState.whatsapp; click: FiliTheme.bin + "/bar-alert open whatsapp" }
        BarScript { objectName: "cal"; value: BarState.cal; color: FiliTheme.sable; click: FiliTheme.bin + "/bar-alert open cal" }
    }
}
