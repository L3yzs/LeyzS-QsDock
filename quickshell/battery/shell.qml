import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ================= SETTINGS / AYARLAR =================
    // ~/.config/quickshell/settings.json  ->  { "lang": "en" | "tr", "name": "...", ... }
    // lang: arayuz dili / interface language (default: en)
    property var settings: ({})
    property string lang: "en"
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const s = JSON.parse(text()); root.settings = s; root.lang = s.lang === "tr" ? "tr" : "en"; } catch (e) { } }
    }
    function t(tr, en) { return root.lang === "tr" ? tr : en; }
    readonly property string userName: root.settings.name || Quickshell.env("USER") || "user"

    // ================= PYWAL RENGİ =================
    property color accentColor: "#ffffff"

    // ================= YAZI İŞLEME =================
    // Küçük puntoda hangisi daha iyi durursa onu bırak, TEK YERDEN değişir:
    //   Text.NativeRendering -> keskin ama şeffaf arkaplanda renk saçaklanması olabilir
    //   Text.QtRendering     -> saçaklanma yok, biraz daha yumuşak
    // Text.QtRendering     -> yumusak, capraz cizgiler (/ gibi) duzgun, renk sacaklanmasi yok
    // Text.NativeRendering -> keskin ama capraz cizgiler merdiven gibi kirilir
    readonly property int txtRender: Text.QtRendering

    // PreferNoHinting       -> harf sekli bozulmaz, en puruzsuz
    // PreferVerticalHinting -> hafif hizalama, ara deger
    // PreferFullHinting     -> piksel izgarasina zorlar, capraz cizgileri bozar
    readonly property int txtHinting: Font.PreferNoHinting

    // ================= YAZI TİPİ =================
    // Menüdeki tüm yazılar buradan. Denemek için tek satırı değiştir.
    //   "Inter"                  -> UI için tasarlanmış, küçük puntoda en temizi
    //   "IBM Plex Sans"          -> biraz daha karakterli, yine çok okunaklı
    //   "JetBrainsMono Nerd Font"-> mevcut, kodlama fontu (eşit genişlik)
    readonly property string uiFont: "Inter"

    FileView {
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text())
                if (data.colors && data.colors.color9) root.accentColor = data.colors.color9
            } catch (e) {}
        }
    }

    // ================= DURUM =================
    property bool menuOpen: false
    readonly property int panelWidth: 380
    property real slideX: -root.panelWidth

    property int capacity: 0
    property string batStatus: "Unknown"
    property real watt: 0
    property real hours: 0
    property int health: 100
    property int temp: 0
    property string profile: "balanced"
    property string gfxMode: "Hibrit"
    property var topApps: []
    property int ac: 0                    // adaptor takili mi (1/0)
    property string wattSrc: "battery"    // watt pilden mi sistemden mi

    // guc modu: power-profiles-daemon (powerprofilesctl get/set)
    property string epp: "balanced"

    // Koruma modunda (Lenovo conservation) durum "Not charging" gelir ama
    // adaptor takilidir - simsek ikonu yine gorunmeli.
    readonly property bool charging: root.batStatus === "Charging"
                                     || root.batStatus === "Full"
                                     || (root.ac === 1 && root.batStatus === "Not charging")

    readonly property string profileLabel: {
        if (root.epp === "powersaver") return root.t("Tasarruf", "Saver");
        if (root.epp === "perf") return root.t("Performans", "Performance");
        return root.t("Denge", "Balanced");
    }
    readonly property int profileIndex: {
        if (root.epp === "powersaver") return 0;
        if (root.epp === "perf") return 2;
        return 1;
    }
    readonly property int gfxIndex: root.gfxMode === "Hibrit" ? 1 : 0

    readonly property string timeText: {
        if (root.batStatus === "Full") return root.t("Dolu", "Full");
        if (root.batStatus === "Charging") return root.t("Şarj oluyor", "Charging");
        if (root.batStatus === "Not charging" && root.ac === 1) return root.t("Koruma modu", "Conservation");
        if (root.ac === 1 && root.hours <= 0) return root.t("Fişte", "Plugged in");
        if (root.hours <= 0) return "—";
        const h = Math.floor(root.hours);
        const m = Math.round((root.hours - h) * 60);
        return h + root.t("s  ", "h  ") + m + root.t("d", "m");
    }

    // ================= VERİ =================
    readonly property string dataScript: Quickshell.env("HOME") + "/.config/quickshell/battery/battery-data.sh"

    Process {
        id: dataProc
        running: false
        command: ["sh", root.dataScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim());
                    if (typeof d.cap !== "number") return;
                    root.capacity  = d.cap;
                    root.batStatus = d.status;
                    root.watt      = d.watt;
                    root.hours     = d.hours;
                    root.health    = d.health;
                    root.temp      = d.temp;
                    root.profile   = d.profile;
                    root.gfxMode   = d.gfx;
                    root.topApps   = d.apps || [];
                    root.ac        = d.ac || 0;
                    root.wattSrc   = d.wattSrc || "battery";
                } catch (e) {}
            }
        }
    }

    // Guc modu okuyucu: powerprofilesctl get -> powersaver / balanced / perf
    Process {
        id: eppProc
        running: false
        command: ["sh", "-c", "p=$(powerprofilesctl get 2>/dev/null); case \"$p\" in (power-saver) echo powersaver;; (performance) echo perf;; (*) echo balanced;; esac"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                if (v.length > 0) root.epp = v;
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.menuOpen
        triggeredOnStart: true
        onTriggered: { dataProc.running = true; eppProc.running = true; }
    }

    // ================= GÜÇ PROFİLİ (power-profiles-daemon) =================
    // 0 = tasarruf, 1 = denge, 2 = performans
    // powerprofilesctl set power-saver / balanced / performance
    function setProfile(i) {
        const args = ["powersaver", "balanced", "perf"];
        const eppNames = ["powersaver", "balanced", "perf"];
        root.epp = eppNames[i];
        Quickshell.execDetached(["powerprofilesctl", "set", ["power-saver", "balanced", "performance"][i]]);
        profileDelay.restart();
    }
    Timer {
        id: profileDelay
        interval: 500
        onTriggered: { dataProc.running = true; eppProc.running = true; }
    }

    onEppChanged: if (batWin.visible) profLabel.flash()
    onGfxModeChanged: if (batWin.visible) gfxLabel.flash()

    // ================= AÇ / KAPAT =================
    function openMenu() {
        root.menuOpen = true;
        batWin.visible = true;
        dataProc.running = true;
        eppProc.running = true;
        slideAnim.to = 8;
        slideAnim.restart();
    }
    function closeMenu() {
        root.menuOpen = false;
        slideAnim.to = -root.panelWidth;
        slideAnim.restart();
        hideTimer.restart();
    }
    function toggleMenu() { root.menuOpen ? root.closeMenu() : root.openMenu() }

    NumberAnimation {
        id: slideAnim
        target: root
        property: "slideX"
        duration: 320
        easing.type: Easing.OutCubic
    }
    Timer {
        id: hideTimer
        interval: 340
        onTriggered: if (!root.menuOpen) batWin.visible = false
    }

    IpcHandler {
        target: "battery"
        function toggle(): void { root.route("toggle") }
        function open(): void { root.route("open") }
        function close(): void { root.closeMenu() }
    }

    // ================= QsNotch YONLENDIRME =================
    // Kontrol panelden bar olarak QsNotch seciliyse bu menu acilmaz; istek centige gider
    // ve batarya menusu centikte acilir. Waybar / qsbar'da her sey eskisi gibi.
    // Bar secimi her istekte dosyadan okunur (degisiklik aninda gecerli olur).
    property string pendingAction: ""
    Process {
        id: barCheck
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/bar-choice\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const a = root.pendingAction;
                root.pendingAction = "";
                const bar = this.text.trim();
                if ((bar === "qsnotch" || bar === "qsisland")) {
                    if (root.menuOpen) root.closeMenu();
                    Quickshell.execDetached(["sh", "-c", "b=$(cat \"$HOME/.config/quickshell/bar-choice\" 2>/dev/null); if [ \"$b\" = qsisland ]; then qs -c qsisland ipc call ada \"$2\"; else qs -c qsbar2 ipc call qsnotch \"$1\"; fi", "sh", "battery", "bat"]);
                } else if (bar === "dock") {
                    // Dock seciliyken batarya paneli dock'ta acilir (dock batarya paneline donusur)
                    if (root.menuOpen) root.closeMenu();
                    Quickshell.execDetached(["qs", "-c", "dock", "ipc", "call", "dock", "bat"]);
                } else if (bar === "qsbar") {
                    // qsbar seciliyse: sagdaki ana sekme batarya menusune donusur
                    if (root.menuOpen) root.closeMenu();
                    Quickshell.execDetached(["qs", "-c", "qsbar", "ipc", "call", "qsbar", "battery"]);
                } else if (a === "open") root.openMenu();
                else root.toggleMenu();
            }
        }
    }
    function route(action) {
        if (barCheck.running) return;                   // ust uste basislari yut
        root.pendingAction = action;
        barCheck.running = true;
    }

    // ============ KAYAN GÖSTERGELİ İKON SIRASI ============
    component IcoRow: Item {
        id: ir
        property var glyphs: []
        property int activeIndex: 0
        property bool interactive: true
        signal picked(int index)

        readonly property int btn: 36
        readonly property int gap: 14

        implicitWidth: glyphs.length * btn + (glyphs.length - 1) * gap
        implicitHeight: btn

        Rectangle {
            id: pill
            width: ir.btn
            height: ir.btn
            radius: width / 2
            x: ir.activeIndex * (ir.btn + ir.gap)
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
            border.width: 1.5
            border.color: root.accentColor
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
            Behavior on border.color { ColorAnimation { duration: 200 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Row {
            spacing: ir.gap
            Repeater {
                model: ir.glyphs
                delegate: Item {
                    required property int index
                    required property var modelData
                    width: ir.btn
                    height: ir.btn

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.family: "Symbols Nerd Font"
                        renderType: root.txtRender
                        font.hintingPreference: root.txtHinting
                        font.pixelSize: 17
                        color: index === ir.activeIndex ? root.accentColor : "#6b6b6b"
                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: ir.interactive
                        cursorShape: ir.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: ir.picked(index)
                    }
                }
            }
        }
    }

    // ============ DEĞİŞİNCE DEĞERİ GÖSTEREN YAZI ============
    component SwapLabel: Item {
        id: sl
        property string label: ""
        property string value: ""
        property bool showValue: false

        implicitWidth: Math.max(labelText.implicitWidth, valueText.implicitWidth)
        implicitHeight: 18

        function flash() {
            sl.showValue = true;
            backTimer.restart();
        }
        Timer {
            id: backTimer
            interval: 1000
            onTriggered: sl.showValue = false
        }
        Text {
            id: labelText
            anchors.centerIn: parent
            text: sl.label
            color: "#666666"
            font.family: root.uiFont
            renderType: root.txtRender
            font.hintingPreference: root.txtHinting
            font.pixelSize: 13
            opacity: sl.showValue ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
        }
        Text {
            id: valueText
            anchors.centerIn: parent
            text: sl.value
            color: root.accentColor
            font.family: root.uiFont
            renderType: root.txtRender
            font.hintingPreference: root.txtHinting
            font.pixelSize: 13
            opacity: sl.showValue ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // ================= PANEL =================
    PanelWindow {
        id: batWin
        anchors { bottom: true; right: true }
        margins.bottom: 0
        margins.right: root.slideX
        implicitWidth: root.panelWidth
        implicitHeight: panel.height + 16
        color: "transparent"
        visible: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:battery"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore

        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            onActivated: root.closeMenu()
        }

        Rectangle {
            id: panel
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.right: parent.right
            width: parent.width - 8
            height: content.implicitHeight + 44
            radius: 16
            color: "#000000"
            focus: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 10
                radius: 14
                color: "transparent"
                border.width: 1
                border.color: "#1c1c1e"
            }

            ColumnLayout {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 22
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    ColumnLayout {
                        Layout.preferredWidth: 126
                        spacing: 0

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 95
                            implicitHeight: 42

                            Rectangle {
                                width: 88; height: 42; radius: 9
                                anchors.left: parent.left
                                color: "transparent"
                                border.width: 2
                                border.color: "#4d4d4d"

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 4
                                    width: Math.max(4, (parent.width - 8) * root.capacity / 100)
                                    height: parent.height - 8
                                    radius: 5
                                    color: root.accentColor
                                    Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: root.charging
                                    text: "\uf0e7"
                                    font.family: "Symbols Nerd Font"
                                    renderType: root.txtRender
                                    font.hintingPreference: root.txtHinting
                                    font.pixelSize: 19
                                    color: "#000000"
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4; height: 14; radius: 2
                                color: "#4d4d4d"
                            }
                        }

                        Item { Layout.preferredHeight: 12 }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 2
                            Text {
                                text: root.capacity
                                color: "#f2f2f2"
                                font.family: root.uiFont
                                renderType: root.txtRender
                                font.hintingPreference: root.txtHinting
                                font.pixelSize: 34
                            }
                            Text {
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 5
                                text: "%"
                                color: "#737373"
                                font.family: root.uiFont
                                renderType: root.txtRender
                                font.hintingPreference: root.txtHinting
                                font.pixelSize: 15
                            }
                        }

                        Item { Layout.preferredHeight: 4 }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.timeText
                            color: root.accentColor
                            font.family: root.uiFont
                            renderType: root.txtRender
                            font.hintingPreference: root.txtHinting
                            font.pixelSize: 14
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            SwapLabel {
                                id: profLabel
                                anchors.horizontalCenter: profRow.horizontalCenter
                                anchors.top: parent.top
                                label: root.t("Güç Profili", "Power Profile")
                                value: root.profileLabel
                            }
                            IcoRow {
                                id: profRow
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                anchors.top: parent.top
                                anchors.topMargin: 28
                                glyphs: ["\uf06c", "\uf1de", "\uf0e7"]
                                activeIndex: root.profileIndex
                                onPicked: (i) => { root.setProfile(i); profLabel.flash(); }
                            }
                        }

                        Item { Layout.preferredHeight: 46 }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            SwapLabel {
                                id: gfxLabel
                                anchors.horizontalCenter: gfxRow.horizontalCenter
                                anchors.top: parent.top
                                label: root.t("Grafik Modu", "Graphics Mode")
                                value: root.gfxMode === "Hibrit" ? root.t("Hibrit", "Hybrid") : root.gfxMode
                            }
                            IcoRow {
                                id: gfxRow
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                anchors.top: parent.top
                                anchors.topMargin: 28
                                glyphs: ["\uf2db", "\uf074", "\uf108"]
                                activeIndex: root.gfxIndex
                                interactive: false
                            }
                        }

                        Item { Layout.preferredHeight: 24 }
                    }
                }

                Item { Layout.preferredHeight: 22 }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#1c1c1e" }

                Item { Layout.preferredHeight: 14 }

                Text {
                    text: root.t("En Çok Tüketen", "Top Consumers")
                    color: "#595959"
                    font.family: root.uiFont
                    renderType: root.txtRender
                    font.hintingPreference: root.txtHinting
                    font.pixelSize: 12
                }

                Item { Layout.preferredHeight: 12 }

                // Her zaman 3 satir cizilir. Veri 3'ten azsa satir bos kalir
                // ama yerini korur, boylece panel yuksekligi oynamaz.
                Repeater {
                    model: 3
                    delegate: RowLayout {
                        required property int index
                        readonly property var app: (root.topApps && root.topApps.length > index)
                                                   ? root.topApps[index] : null
                        Layout.fillWidth: true
                        Layout.bottomMargin: 10
                        spacing: 12

                        Text {
                            Layout.preferredWidth: 80
                            text: app ? app.name : ""
                            elide: Text.ElideRight
                            color: "#d8d8d8"
                            font.family: root.uiFont
                            renderType: root.txtRender
                            font.hintingPreference: root.txtHinting
                            font.pixelSize: 13
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 3
                            radius: 2
                            color: "#1f1f21"
                            Rectangle {
                                width: app ? parent.width * Math.min(1, app.r) : 0
                                height: parent.height
                                radius: 2
                                color: root.accentColor
                                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            Layout.preferredWidth: 52
                            horizontalAlignment: Text.AlignRight
                            text: app ? app.w.toFixed(1) + "W" : ""
                            color: root.accentColor
                            font.family: root.uiFont
                            renderType: root.txtRender
                            font.hintingPreference: root.txtHinting
                            font.pixelSize: 12
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.watt.toFixed(1) + "W"
                        color: root.accentColor
                        font.family: root.uiFont
                        renderType: root.txtRender
                        font.hintingPreference: root.txtHinting
                        font.pixelSize: 12
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        spacing: 0
                    Text {
                        text: root.t("Sağlık/", "Health/")
                        color: root.accentColor
                        font.family: root.uiFont
                        renderType: root.txtRender
                        font.hintingPreference: root.txtHinting
                        font.pixelSize: 12
                    }
                    Text {
                        text: root.health + ""
                        color: root.accentColor
                        font.family: root.uiFont
                        renderType: root.txtRender
                        font.hintingPreference: root.txtHinting
                        font.pixelSize: 12
                    }
                    }
                }
            }
        }
    }
}
