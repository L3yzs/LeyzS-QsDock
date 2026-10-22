import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
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
    property string accentColor: "#5aa0ff"
    property bool wifiExpanded: false
    property bool wifiRadioOn: false
    property bool wifiHardwarePresent: true
    property bool ethernetConnected: false
    property string ethernetDevice: ""
    property bool wifiConnected: false
    property int connectedSignal: 100
    property bool airplaneModeOn: false

    // ===== LISTE GECISI =====
    // Kutularin sagindaki seride basilinca bu degisir: "wifi" | "bt"
    property string listView: "wifi"
    readonly property bool wifiListShown: listView === "wifi"
    readonly property bool btListShown: listView === "bt"

    onListViewChanged: {
        if (listView === "bt") {
            btRadioProc.running = true;
            if (btRadioOn) btListProc.running = true;
        } else {
            wifiListProc.running = true;
        }
    }

    // ===== BLUETOOTH DURUMU =====
    property bool btRadioOn: false
    property bool btHardwarePresent: true
    property bool btExpanded: false
    property string btConnectingMac: ""

    // ================= WAYBAR İLE PAYLAŞIM =================
    // Waybar'daki wifi modülü uçak modunu kendi başına güvenilir şekilde
    // tespit edemiyor (rfkill/nmcli çıktıları ortama göre değişebiliyor).
    // Durumu zaten burada biliyoruz: bir dosyaya yazıp modülün okumasını
    // sağlıyoruz. Yazdıktan sonra waybar'a sinyal gönderip anında
    // güncellenmesini de tetikliyoruz, 5 saniyelik aralığı beklemesin.
    onAirplaneModeOnChanged: {
        airplaneStateWriter.command = [
            "sh", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && printf '%s' '"
            + (airplaneModeOn ? "1" : "0")
            + "' > \"$HOME/.cache/quickshell/airplane_mode\"; pkill -RTMIN+9 waybar 2>/dev/null || true"
        ];
        airplaneStateWriter.running = true;
    }

    Process { id: airplaneStateWriter }

    property string connectingSsid: ""

    function wifiIcon(signal) {
        if (signal >= 75) return "\u{F0928}";
        if (signal >= 50) return "\u{F0925}";
        if (signal >= 25) return "\u{F0922}";
        return "\u{F091F}";
    }
    property string selectedSsid: ""
    property bool showPasswordPrompt: false

    property bool contextMenuVisible: false
    property real contextMenuX: 0
    property real contextMenuY: 0
    property string contextMenuSsid: ""
    property bool contextMenuInUse: false
    property bool contextMenuSecured: false
    property bool contextMenuKnown: false
    property bool contextMenuIsEthernet: false
    property bool contextMenuIsBt: false
    property string contextMenuMac: ""
    property string contextMenuBtName: ""

    property string pendingSsid: ""
    property bool pendingSecured: false

    function shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function reloadColors() {
        walProc.running = true;
    }

    Process {
        id: walProc
        command: ["sh", "-c", "cat ~/.cache/wal/colors.json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    accentColor = data.colors.color9;
                } catch (e) {
                    accentColor = "#5aa0ff";
                }
            }
        }
    }

    ListModel {
        id: connectedWifiModel
    }

    ListModel {
        id: otherWifiModel
    }

    ListModel {
        id: connectedBtModel
    }

    ListModel {
        id: otherBtModel
    }

    // Daha once eslesmis ama su an bagli olmayan cihazlar
    ListModel {
        id: pairedBtModel
    }

    Process {
        id: wifiListProc
        command: ["sh", "-c", "echo '--WIFI--'; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no; echo '--KNOWN--'; nmcli -t -f NAME,TYPE connection show"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = this.text;
                var wifiPart = raw.split("--WIFI--")[1] || "";
                wifiPart = wifiPart.split("--KNOWN--")[0] || "";
                var knownPart = raw.split("--KNOWN--")[1] || "";

                var knownNames = {};
                var knownLines = knownPart.trim().split("\n");
                for (var k = 0; k < knownLines.length; k++) {
                    var kparts = knownLines[k].split(":");
                    if (kparts.length < 2) continue;
                    if (kparts[1].indexOf("wireless") !== -1 || kparts[1] === "wifi") {
                        knownNames[kparts[0]] = true;
                    }
                }

                var lines = wifiPart.trim().split("\n");
                var seen = {};

                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(":");
                    if (parts.length < 4) continue;
                    var inUse = parts[0].indexOf("*") !== -1;
                    var ssid = parts[1];
                    var signal = parseInt(parts[2]) || 0;
                    var secured = parts[3] !== "" && parts[3] !== "--";
                    if (ssid === "") continue;
                    var known = knownNames.hasOwnProperty(ssid);

                    if (inUse && connectingSsid !== "" && ssid === connectingSsid) {
                        connectingSsid = "";
                    }

                    if (!(ssid in seen) || inUse || (!seen[ssid].inUse && signal > seen[ssid].signal)) {
                        seen[ssid] = { ssid: ssid, signal: signal, secured: secured, inUse: inUse, known: known };
                    }
                }

                var list = [];
                for (var key in seen) {
                    list.push(seen[key]);
                }
                list.sort(function(a, b) {
                    if (a.inUse !== b.inUse) return a.inUse ? -1 : 1;
                    return b.signal - a.signal;
                });

                var connected = false;
                var connSignal = 100;
                var connectedItem = null;
                var others = [];

                for (var j = 0; j < list.length; j++) {
                    if (list[j].inUse) {
                        connected = true;
                        connSignal = list[j].signal;
                        connectedItem = list[j];
                    } else {
                        others.push(list[j]);
                    }
                }

                if (connectedItem) {
                    if (connectedWifiModel.count > 0 && connectedWifiModel.get(0).ssid === connectedItem.ssid) {
                        connectedWifiModel.setProperty(0, "signal", connectedItem.signal);
                    } else {
                        connectedWifiModel.clear();
                        connectedWifiModel.append(connectedItem);
                    }
                } else {
                    connectedWifiModel.clear();
                }

                otherWifiModel.clear();
                for (var o = 0; o < others.length; o++) {
                    otherWifiModel.append(others[o]);
                }

                wifiConnected = connected;
                connectedSignal = connSignal;
            }
        }

        onExited: {
            command = ["sh", "-c", "echo '--WIFI--'; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no; echo '--KNOWN--'; nmcli -t -f NAME,TYPE connection show"];
        }
    }

    Process {
        id: wifiRescanTriggerProc
        command: ["sh", "-c", "nmcli device wifi rescan"]
        running: false
    }

    Timer {
        id: wifiRescanRefreshTimer
        interval: 1800
        repeat: false
        onTriggered: {
            wifiListProc.running = true;
        }
    }

    Process {
        id: wifiRadioProc
        command: ["sh", "-c", "nmcli radio wifi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                wifiRadioOn = this.text.trim() === "enabled";
            }
        }
    }

    Process {
        id: wifiHwProc
        command: ["sh", "-c", "nmcli -t -f TYPE device status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                var present = false;
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].trim() === "wifi") {
                        present = true;
                        break;
                    }
                }
                wifiHardwarePresent = present;
            }
        }
    }

    Process {
        id: wifiRadioToggleProc
        running: false
        onExited: {
            wifiRadioProc.running = true;
            wifiListProc.running = true;
        }
    }

    // ================= BLUETOOTH =================
    // bluetoothctl uzerinden: gucu oku, cihazlari listele, bagla/kes.

    Process {
        id: btRadioProc
        running: true
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -m1 'Powered:' | awk '{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim();
                btHardwarePresent = (t === "yes" || t === "no");
                btRadioOn = (t === "yes");
                if (!btRadioOn) {
                    connectedBtModel.clear();
                    otherBtModel.clear();
                }
            }
        }
    }

    Process {
        id: btToggleProc
        running: false
        onExited: {
            btRadioProc.running = true;
            btListProc.running = true;
        }
    }

    // Cikti satirlari: durum|mac|pil|isim
    //   durum: conn (bagli) | paired (eslesmis) | new (eslesmemis)
    //   pil  : yuzde ya da bos
    Process {
        id: btListProc
        running: false
        command: ["sh", "-c",
            "bluetoothctl devices 2>/dev/null | while read -r _ mac name; do " +
            "  info=$(bluetoothctl info \"$mac\" 2>/dev/null); " +
            "  st=new; " +
            "  echo \"$info\" | grep -q 'Paired: yes' && st=paired; " +
            "  echo \"$info\" | grep -q 'Connected: yes' && st=conn; " +
            "  bat=$(echo \"$info\" | grep -m1 'Battery Percentage' | sed 's/.*(\\([0-9]*\\)).*/\\1/'); " +
            "  echo \"$st|$mac|$bat|$name\"; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                connectedBtModel.clear();
                otherBtModel.clear();
                pairedBtModel.clear();
                var lines = text.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i].trim();
                    if (ln === "") continue;
                    var p = ln.split("|");
                    if (p.length < 4) continue;
                    var nm = p.slice(3).join("|");

                    // Ismi cozulmemis cihazlar MAC adresini isim olarak dondurur
                    // (6B-74-44-FC-9F-2D gibi). Bunlar etraftaki yabanci cihazlar,
                    // listeyi kirletiyorlar - eslesmemislerse gizle.
                    var isUnnamed = nm.replace(/-/g, ":").toUpperCase() === p[1].toUpperCase();
                    var isPaired = (p[0] === "paired" || p[0] === "conn");
                    if (isUnnamed && !isPaired) continue;

                    var entry = {
                        mac: p[1],
                        name: nm,
                        battery: p[2],
                        paired: isPaired
                    };
                    if (p[0] === "conn") {
                        connectedBtModel.append(entry);
                    } else if (p[0] === "paired") {
                        pairedBtModel.append(entry);
                    } else {
                        otherBtModel.append(entry);
                    }
                }
            }
        }
    }

    Process {
        id: btActionProc
        running: false
        onExited: {
            btConnectingMac = "";
            btListProc.running = true;
        }
    }

    function btConnect(mac) {
        btConnectingMac = mac;
        btActionProc.command = ["sh", "-c", "bluetoothctl connect " + shQuote(mac)];
        btActionProc.running = true;
    }

    // Eslesmemis cihazlari bulmak icin kisa bir tarama.
    // bluetoothctl scan on surekli calisir; --timeout ile kendi kapanir.
    Process {
        id: btScanProc
        running: false
        command: ["sh", "-c", "bluetoothctl --timeout 8 scan on >/dev/null 2>&1"]
        onExited: btListProc.running = true
    }

    property bool btScanning: btScanProc.running

    // Bluetooth gorunumu acikken kendi kendine tarasin
    Timer {
        interval: 10000
        running: panel.visible && root.btListShown && btRadioOn
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!btScanProc.running) btScanProc.running = true;
        }
    }

    function btDisconnect(mac) {
        btActionProc.command = ["sh", "-c", "bluetoothctl disconnect " + shQuote(mac)];
        btActionProc.running = true;
    }

    Process {
        id: airplaneProc
        running: false
        onExited: {
            ethernetProc.running = true;
            wifiRadioProc.running = true;
            if (wifiExpanded) {
                wifiListProc.running = true;
            }
        }
    }

    Process {
        id: ethernetProc
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                var connected = false;
                var device = "";
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(":");
                    if (parts[1] === "ethernet") {
                        device = parts[0];
                        if (parts[2] === "connected") {
                            connected = true;
                        }
                        break;
                    }
                }
                ethernetConnected = connected;
                ethernetDevice = device;
            }
        }
    }

    Process {
        id: connectProc
        running: false
        onExited: {
            wifiListProc.running = true;
            connectingSsid = "";
        }
    }

    Process {
        id: quickConnectProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var success = this.text.indexOf("QSRESULT:0") !== -1;
                if (!success) {
                    if (pendingSecured) {
                        selectedSsid = pendingSsid;
                        showPasswordPrompt = true;
                        passField.text = "";
                        passField.forceActiveFocus();
                        connectingSsid = "";
                    } else {
                        connectProc.command = ["sh", "-c", "nmcli device wifi connect " + shQuote(pendingSsid)];
                        connectProc.running = true;
                    }
                } else {
                    connectingSsid = "";
                }
                wifiListProc.running = true;
            }
        }
    }

    function tryConnect(ssid, secured) {
        pendingSsid = ssid;
        pendingSecured = secured;
        connectingSsid = ssid;
        quickConnectProc.command = ["sh", "-c", "nmcli connection up " + shQuote(ssid) + " >/dev/null 2>&1; echo QSRESULT:$?"];
        quickConnectProc.running = true;
    }

    Process {
        id: disconnectProc
        running: false
        onExited: {
            wifiListProc.running = true;
        }
    }

    Process {
        id: forgetProc
        running: false
        onExited: {
            wifiListProc.running = true;
        }
    }

    Process {
        id: ethernetActionProc
        running: false
        onExited: {
            ethernetProc.running = true;
        }
    }

    function disconnectEthernet() {
        contextMenuVisible = false;
        ethernetActionProc.command = ["sh", "-c", "nmcli device disconnect " + shQuote(ethernetDevice)];
        ethernetActionProc.running = true;
    }

    function reconnectEthernet() {
        contextMenuVisible = false;
        ethernetActionProc.command = ["sh", "-c", "nmcli device connect " + shQuote(ethernetDevice)];
        ethernetActionProc.running = true;
    }

    Timer {
        id: colorPollTimer
        interval: 400
        running: true
        repeat: true
        onTriggered: reloadColors()
    }

    Timer {
        interval: 4000
        running: panel.visible
        repeat: true
        onTriggered: {
            ethernetProc.running = true;
            wifiRadioProc.running = true;
            wifiHwProc.running = true;
            if (wifiExpanded) {
                wifiListProc.running = true;
            }
            btRadioProc.running = true;
            if (btListShown && btRadioOn) {
                btListProc.running = true;
            }
        }
    }

    // ================= AÇILIŞ / KAPANIŞ ANİMASYONU =================
    // Panel ekranın SAĞ alt köşesinde: kapalıyken sağa (pencere genişliğinden
    // fazlası kadar) itiliyor, açılınca 0'a gelip yerine oturuyor. Yani ses
    // menüsünün aynadaki hali.
    //
    // Hyprland'in kendi layer animasyonu windowrule.lua'daki hl.layer_rule
    // ile kapatıldığı için hareketin tamamı buradan geliyor.
    property bool menuOpen: false
    property real slideX: menuOpen ? 0 : 420

    Behavior on slideX {
        NumberAnimation {
            id: slideAnim
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    function openPanel() {
        if (root.menuOpen) return;
        panel.visible = true;
        btRadioProc.running = true;
        if (root.btListShown) btListProc.running = true;
        panelStartTimer.start();
    }

    function closePanel() {
        if (!root.menuOpen) return;
        root.menuOpen = false;
        panelHideTimer.start();
    }

    function togglePanel() {
        if (root.menuOpen) root.closePanel();
        else root.openPanel();
    }

    Timer {
        id: panelStartTimer
        // pencere haritalansın, sonra hareket başlasın
        interval: 16
        onTriggered: root.menuOpen = true
    }

    Timer {
        id: panelHideTimer
        // kapanış animasyonu bitmeden gizlersek panel yarı yolda yok oluyor
        interval: 340
        onTriggered: panel.visible = false
    }

    PanelWindow {
        id: panel
        visible: false
        focusable: true

        // Hyprland tarafında bu isme bakarak layer animasyonunu kapatıyoruz
        // (windowrule.lua -> hl.layer_rule / match.namespace)
        WlrLayershell.namespace: "quickshell:wifipanel"

        anchors {
            bottom: true
            right: true
        }

        implicitWidth: 348
        implicitHeight: 620

        color: "transparent"

        margins {
            bottom: 8
            // NOT: sağ boşluk BURADA değil, contentBox'un kendi sağ
            // margin'inde. Pencere sağ kenardan içeride başlarsa panel de en
            // fazla oraya kadar kayabiliyor ve kapanırken kenarda ince bir
            // şerit görünüyor. Pencereyi ekranın gerçek kenarına yaslayıp
            // boşluğu içeriye vererek panelin tamamen dışarı çıkmasını
            // sağlıyoruz.
            right: 0
        }

        onVisibleChanged: {
            if (visible) {
                keyCatcher.forceActiveFocus();
                ethernetProc.running = true;
                wifiRadioProc.running = true;
                wifiHwProc.running = true;
            } else {
                showPasswordPrompt = false;
                contextMenuVisible = false;
                connectingSsid = "";
            }
        }

        Connections {
            target: root
            function onWifiRadioOnChanged() {
                wifiExpanded = wifiRadioOn;
                if (wifiRadioOn) {
                    wifiAnim.restart();
                    wifiListProc.command = ["sh", "-c", "echo '--WIFI--'; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no; echo '--KNOWN--'; nmcli -t -f NAME,TYPE connection show"];
                    wifiListProc.running = true;
                    wifiRescanTriggerProc.running = true;
                    wifiRescanRefreshTimer.restart();
                } else {
                    showPasswordPrompt = false;
                    contextMenuVisible = false;
                    connectingSsid = "";
                }
            }
        }

        IpcHandler {
            target: "wifiPanel"

            function toggle(): void {
                root.togglePanel();
            }

            function show(): void {
                root.openPanel();
            }

            function hide(): void {
                root.closePanel();
            }

            function reloadColors(): void {
                root.reloadColors();
            }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: {
                root.closePanel();
            }

            Rectangle {
                id: contentBox
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                // pencereden alınan sağ boşluk buraya taşındı
                anchors.rightMargin: 8
                width: parent.width - 8

                // sağdan içeri sürüklenerek geliyor, kapanırken aynı yoldan
                // sağa doğru kayıp ekran dışında kayboluyor
                transform: Translate { x: root.slideX }
                // 270Hz'de her kareye 3.7ms bütçe düşüyor; liste ve ikonlar
                // kare kare çizilmesin diye animasyon boyunca tek doku olarak
                // kaydırılıyor
                layer.enabled: true
                layer.smooth: true
                // 16 ust + 16 alt kenar boslugu = 32. Onceden 36 yaziyordu ve
                // artan 4 piksel ColumnLayout'un sonunda kalip alt boslugu
                // 20'ye cikariyordu; tavan ile zemin esit degildi.
                height: Math.min(mainColumn.implicitHeight + 32, parent.height)
                color: "#000000"
                radius: 12
                clip: true
                Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: mainColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    Row {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 8

                        Rectangle {
                            width: (parent.width - 16) / 3
                            height: 70
                            radius: 10
                            color: (wifiRadioOn && wifiHardwarePresent) ? "#262626" : "#141414"
                            clip: true

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: wifiIconText
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -13
                                property string iconText: "\u{F092D}"
                                text: iconText
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 22
                                color: !wifiHardwarePresent ? "#ff4b4b" : (wifiIconText.iconText === "\u{F092D}" ? "#6e6e6e" : accentColor)

                                Component.onCompleted: {
                                    iconText = (wifiRadioOn && wifiHardwarePresent) ? wifiIcon(connectedSignal) : "\u{F092D}";
                                }

                                Behavior on color { ColorAnimation { duration: 120 } }

                                transform: Translate {
                                    id: wifiTranslate
                                    y: 0
                                }

                                Connections {
                                    target: root
                                    function onWifiRadioOnChanged() {
                                        if (wifiRadioOn) {
                                            wifiAnim.restart();
                                        } else {
                                            wifiAnim.stop();
                                            wifiTranslate.y = 0;
                                            wifiIconText.opacity = 1;
                                            wifiIconText.iconText = "\u{F092D}";
                                        }
                                    }
                                }

                                SequentialAnimation {
                                    id: wifiAnim
                                    running: false

                                    NumberAnimation {
                                        target: wifiTranslate
                                        property: "y"
                                        to: 50
                                        duration: 220
                                        easing.type: Easing.InCubic
                                    }

                                    PauseAnimation { duration: 100 }

                                    PropertyAction {
                                        target: wifiIconText
                                        property: "iconText"
                                        value: wifiIcon(connectedSignal)
                                    }
                                    PropertyAction {
                                        target: wifiTranslate
                                        property: "y"
                                        value: -50
                                    }

                                    NumberAnimation {
                                        target: wifiTranslate
                                        property: "y"
                                        to: 0
                                        duration: 260
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            // Hover sadece SOL bolgede (radyo alani)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                color: "#ffffff"
                                opacity: wifiHover.containsMouse ? 0.06 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: wifiHover
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                hoverEnabled: true
                                onClicked: {
                                    var turningOn = !wifiRadioOn;
                                    wifiRadioToggleProc.command = ["sh", "-c", "nmcli radio wifi " + (wifiRadioOn ? "off" : "on")];
                                    wifiRadioToggleProc.running = true;
                                    if (turningOn) {
                                        wifiExpanded = true;
                                        wifiAnim.restart();
                                    }
                                }
                            }

                            // ---- Ayrac cizgi (aktifken gizlenir) ----
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1
                                height: parent.height - 28
                                color: "#2f2f2f"
                                opacity: root.wifiListShown ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }

                            // ---- Liste seridi: tavandan zemine ----
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 26
                                // clip yuvarlak koseyi kirpmadigi icin kose yaricapini
                                // seridin kendisine veriyoruz (sol taraf duz kalsin)
                                radius: parent.radius
                                topLeftRadius: 0
                                bottomLeftRadius: 0
                                // Kalici arka plan yok: serit kutuyla ayni renkte durur,
                                // parlama yalnizca imlec uzerine gelince olur.
                                color: parent.color

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    color: "#ffffff"
                                    opacity: wifiStripHover.containsMouse ? 0.06 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf105"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    // radyo kapaliyken aktif olsa bile sonuk dursun
                                    color: root.wifiListShown ? (wifiRadioOn ? accentColor : "#7a7a7a") : "#5c5c5c"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: wifiStripHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.listView = "wifi";
                                        contextMenuVisible = false;
                                    }
                                }
                            }

                        }

                        Rectangle {
                            width: (parent.width - 16) / 3
                            height: 70
                            radius: 10
                            color: (btRadioOn && btHardwarePresent) ? "#262626" : "#141414"
                            clip: true

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -13
                                text: "\uf293"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 22
                                color: !btHardwarePresent ? "#ff4b4b" : (btRadioOn ? accentColor : "#6e6e6e")
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            // Hover sadece SOL bolgede
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                color: "#ffffff"
                                opacity: btHover.containsMouse ? 0.06 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: btHover
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                hoverEnabled: true
                                onClicked: {
                                    var turningOn = !btRadioOn;
                                    btToggleProc.command = ["sh", "-c", "bluetoothctl power " + (btRadioOn ? "off" : "on")];
                                    btToggleProc.running = true;
                                    if (turningOn) {
                                        btExpanded = true;
                                        root.listView = "bt";
                                    }
                                }
                            }

                            // ---- Ayrac cizgi (aktifken gizlenir) ----
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 26
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1
                                height: parent.height - 28
                                color: "#2f2f2f"
                                opacity: root.btListShown ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }

                            // ---- Liste seridi: tavandan zemine ----
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 26
                                radius: parent.radius
                                topLeftRadius: 0
                                bottomLeftRadius: 0
                                color: parent.color

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    color: "#ffffff"
                                    opacity: btStripHover.containsMouse ? 0.06 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf105"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    color: root.btListShown ? (btRadioOn ? accentColor : "#7a7a7a") : "#5c5c5c"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: btStripHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.listView = "bt";
                                        btExpanded = true;
                                        contextMenuVisible = false;
                                        showPasswordPrompt = false;
                                        if (btRadioOn) btListProc.running = true;
                                    }
                                }
                            }

                        }

                        Rectangle {
                            width: (parent.width - 16) / 3
                            height: 70
                            radius: 10
                            color: airplaneModeOn ? "#262626" : "#141414"
                            clip: true

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: airIcon
                                anchors.centerIn: parent
                                text: "\uf072"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 22
                                color: airplaneModeOn ? accentColor : "#6e6e6e"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                transform: Translate {
                                    id: airTranslate
                                    x: 0
                                }

                                SequentialAnimation {
                                    id: flyAnim
                                    running: false

                                    NumberAnimation {
                                        target: airTranslate
                                        property: "x"
                                        to: -15
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                    NumberAnimation {
                                        target: airTranslate
                                        property: "x"
                                        to: 65
                                        duration: 500
                                        easing.type: Easing.InOutQuad
                                    }
                                    PropertyAction {
                                        target: airTranslate
                                        property: "x"
                                        value: -65
                                    }
                                    NumberAnimation {
                                        target: airTranslate
                                        property: "x"
                                        to: 0
                                        duration: 550
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "#ffffff"
                                opacity: airHover.containsMouse ? 0.06 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: airHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    airplaneModeOn = !airplaneModeOn;
                                    if (airplaneModeOn) {
                                        flyAnim.restart();
                                        var cmd = "nmcli radio wifi off; rfkill block bluetooth;";
                                        if (ethernetConnected && ethernetDevice !== "") {
                                            cmd += " nmcli device disconnect " + shQuote(ethernetDevice) + ";";
                                        }
                                        airplaneProc.command = ["sh", "-c", cmd];
                                        airplaneProc.running = true;
                                    } else {
                                        airplaneProc.command = ["sh", "-c", "nmcli radio wifi on; rfkill unblock bluetooth;"];
                                        airplaneProc.running = true;
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (root.wifiListShown && wifiExpanded && wifiConnected) ? 40 : 0
                        Layout.topMargin: (root.wifiListShown && wifiExpanded && wifiConnected) ? 2 : 0
                        visible: root.wifiListShown && wifiExpanded && wifiConnected
                        opacity: (root.wifiListShown && wifiExpanded && wifiConnected) ? 1 : 0

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 480; easing.type: Easing.OutQuint }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 560; easing.type: Easing.OutQuint }
                        }

                        sourceComponent: Item {
                            anchors.fill: parent
                            Rectangle {
                                width: parent.width
                                height: 40
                                radius: 8
                                color: "#262626"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Repeater {
                                        model: connectedWifiModel
                                        delegate: Item {
                                            width: parent.width
                                            height: parent.height

                                            Row {
                                                anchors.fill: parent
                                                spacing: 10
                                                Text {
                                                    text: wifiIcon(model.signal)
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 14
                                                    color: accentColor
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: model.ssid
                                                    color: "#e8e8e8"
                                                    font.pixelSize: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 90
                                                    elide: Text.ElideRight
                                                }
                                                
                                                Text {
                                                    id: connectedLabel
                                                    text: root.t("Bağlı", "Connected")
                                                    font.family: "sans-serif"
                                                    font.pixelSize: 11
                                                    color: accentColor
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 40
                                                    rightPadding: -1
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            MouseArea {
                                                id: connectedRowHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.RightButton
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        var pos = mapToItem(keyCatcher, mouse.x, mouse.y);
                                                        contextMenuIsEthernet = false;
                                                        contextMenuIsBt = false;
                                                        contextMenuSsid = model.ssid;
                                                        contextMenuInUse = true;
                                                        contextMenuSecured = model.secured;
                                                        contextMenuKnown = model.known;
                                                        contextMenuX = pos.x;
                                                        contextMenuY = pos.y;
                                                        contextMenuVisible = true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (root.wifiListShown && wifiExpanded) ? (Math.min(otherWifiModel.count, 5) * 40 + Math.max(0, Math.min(otherWifiModel.count, 5) - 1) * 4 + ((otherWifiModel.count > 0) ? 8 : 0)) : 0
                        Layout.topMargin: (root.wifiListShown && wifiExpanded && otherWifiModel.count > 0) ? -3 : 0
                        opacity: (root.wifiListShown && wifiExpanded && otherWifiModel.count > 0) ? 1 : 0
                        // visible verilmezse 0 yukseklikte bile duzende yer tutup
                        // 14 piksellik bosluk birakiyor
                        visible: root.wifiListShown && wifiExpanded && otherWifiModel.count > 0
                        active: root.wifiListShown && wifiExpanded

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 480; easing.type: Easing.OutQuint }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 420; easing.type: Easing.OutQuint }
                        }

                        sourceComponent: Item {
                            anchors.fill: parent
                            Rectangle {
                                width: parent.width
                                height: parent.height
                                radius: 8
                                color: "#141414"

                                ListView {
                                    id: wifiListView
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    clip: true
                                    model: otherWifiModel
                                    spacing: 4

                                    delegate: Item {
                                        width: wifiListView.width
                                        height: 40

                                        Rectangle {
                                            id: rowBgRect
                                            width: parent.width
                                            height: 40
                                            radius: 6
                                            
                                            color: (showPasswordPrompt && selectedSsid === ssid) ? "#262626" : ((connectingSsid === ssid) ? "#141414" : "#141414")
                                            
                                            Behavior on color { 
                                                enabled: connectingSsid !== ssid && !(showPasswordPrompt && selectedSsid === ssid) && !pulseAnim.running
                                                ColorAnimation { duration: 120 } 
                                            }

                                            SequentialAnimation {
                                                id: pulseAnim
                                                running: connectingSsid === ssid && !(showPasswordPrompt && selectedSsid === ssid)
                                                loops: Animation.Infinite
                                                alwaysRunToEnd: false

                                                ColorAnimation {
                                                    target: rowBgRect
                                                    property: "color"
                                                    to: "#262626"
                                                    duration: 1200
                                                    easing.type: Easing.InOutSine
                                                }
                                                ColorAnimation {
                                                    target: rowBgRect
                                                    property: "color"
                                                    to: "#141414"
                                                    duration: 1200
                                                    easing.type: Easing.InOutSine
                                                }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: parent.radius
                                                color: "#ffffff"
                                                opacity: rowHover.containsMouse ? 0.05 : 0
                                                Behavior on opacity { 
                                                    NumberAnimation { 
                                                        duration: 150; 
                                                        easing.type: Easing.OutCubic 
                                                    } 
                                                }
                                            }

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                Text {
                                                    text: wifiIcon(signal)
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 14
                                                    color: "#9a9a9a"
                                                    anchors.verticalCenter: ssidText.verticalCenter
                                                }

                                                Text {
                                                    id: ssidText
                                                    text: ssid
                                                    color: "#e8e8e8"
                                                    font.pixelSize: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 90
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: secured ? "\uf023" : ""
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    color: "#6e6e6e"
                                                    anchors.verticalCenter: ssidText.verticalCenter
                                                    width: 40
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            MouseArea {
                                                id: rowHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        var pos = mapToItem(keyCatcher, mouse.x, mouse.y);
                                                        contextMenuIsEthernet = false;
                                                        contextMenuIsBt = false;
                                                        contextMenuSsid = ssid;
                                                        contextMenuInUse = false;
                                                        contextMenuSecured = secured;
                                                        contextMenuKnown = known;
                                                        contextMenuX = pos.x;
                                                        contextMenuY = pos.y;
                                                        contextMenuVisible = true;
                                                        return;
                                                    }
                                                    contextMenuVisible = false;

                                                    if (secured) {
                                                        selectedSsid = ssid;
                                                        showPasswordPrompt = true;
                                                        passField.text = "";
                                                        passField.forceActiveFocus();
                                                    } else {
                                                        connectingSsid = ssid;
                                                        connectProc.command = ["sh", "-c", "nmcli device wifi connect " + shQuote(ssid)];
                                                        connectProc.running = true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ============ BLUETOOTH: BAGLI CIHAZ ============
                    Loader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (root.btListShown && connectedBtModel.count > 0) ? 40 : 0
                        Layout.topMargin: (root.btListShown && connectedBtModel.count > 0) ? -2 : 0
                        visible: root.btListShown && connectedBtModel.count > 0
                        opacity: (root.btListShown && connectedBtModel.count > 0) ? 1 : 0
                        active: root.btListShown

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 480; easing.type: Easing.OutQuint }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 560; easing.type: Easing.OutQuint }
                        }

                        sourceComponent: Item {
                            anchors.fill: parent
                            Rectangle {
                                width: parent.width
                                height: 40
                                radius: 8
                                color: "#262626"

                                Repeater {
                                    model: connectedBtModel
                                    delegate: Item {
                                        anchors.fill: parent

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 10

                                            Text {
                                                text: "\uf293"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 14
                                                color: accentColor
                                                width: 16
                                                horizontalAlignment: Text.AlignHCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                id: btConnName
                                                text: name
                                                color: "#e8e8e8"
                                                font.pixelSize: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 136
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: battery !== "" ? root.t("Bağlı · %" + battery, "Connected · " + battery + "%") : root.t("Bağlı", "Connected")
                                                color: accentColor
                                                font.pixelSize: 11
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 90
                                                horizontalAlignment: Text.AlignRight
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    var pos = mapToItem(keyCatcher, mouse.x, mouse.y);
                                                    contextMenuIsEthernet = false;
                                                    contextMenuIsBt = true;
                                                    contextMenuMac = mac;
                                                    contextMenuBtName = name;
                                                    contextMenuInUse = true;
                                                    contextMenuKnown = true;
                                                    contextMenuSecured = false;
                                                    contextMenuX = pos.x;
                                                    contextMenuY = pos.y;
                                                    contextMenuVisible = true;
                                                    return;
                                                }
                                                contextMenuVisible = false;
                                                root.btDisconnect(mac);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ============ BLUETOOTH: DIGER CIHAZLAR ============
                    Loader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.btListShown ? (Math.min(otherBtModel.count, 5) * 40 + Math.max(0, Math.min(otherBtModel.count, 5) - 1) * 4 + ((otherBtModel.count > 0) ? 8 : 0)) : 0
                        Layout.topMargin: (root.btListShown && otherBtModel.count > 0) ? -3 : 0
                        opacity: (root.btListShown && otherBtModel.count > 0) ? 1 : 0
                        visible: root.btListShown && otherBtModel.count > 0
                        active: root.btListShown

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 480; easing.type: Easing.OutQuint }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 420; easing.type: Easing.OutQuint }
                        }

                        sourceComponent: Item {
                            anchors.fill: parent
                            Rectangle {
                                width: parent.width
                                height: parent.height
                                radius: 8
                                color: "#141414"

                                ListView {
                                    id: btListViewEl
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    clip: true
                                    model: otherBtModel
                                    spacing: 4

                                    delegate: Item {
                                        width: btListViewEl.width
                                        height: 40

                                        Rectangle {
                                            id: btRowBg
                                            width: parent.width
                                            height: 40
                                            radius: 6
                                            color: "#141414"

                                            Behavior on color {
                                                enabled: btConnectingMac !== mac && !btPulse.running
                                                ColorAnimation { duration: 120 }
                                            }

                                            SequentialAnimation {
                                                id: btPulse
                                                running: btConnectingMac === mac
                                                loops: Animation.Infinite
                                                alwaysRunToEnd: false

                                                ColorAnimation {
                                                    target: btRowBg
                                                    property: "color"
                                                    to: "#262626"
                                                    duration: 1200
                                                    easing.type: Easing.InOutSine
                                                }
                                                ColorAnimation {
                                                    target: btRowBg
                                                    property: "color"
                                                    to: "#141414"
                                                    duration: 1200
                                                    easing.type: Easing.InOutSine
                                                }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: parent.radius
                                                color: "#ffffff"
                                                opacity: btRowHover.containsMouse ? 0.05 : 0
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                                }
                                            }

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                Text {
                                                    text: "\uf293"
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 14
                                                    color: "#9a9a9a"
                                                    width: 16
                                                    horizontalAlignment: Text.AlignHCenter
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                Text {
                                                    id: btNameText
                                                    text: name
                                                    color: "#e8e8e8"
                                                    font.pixelSize: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 116
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: paired ? root.t("Eşleşmiş", "Paired") : root.t("Yeni", "New")
                                                    color: "#6e6e6e"
                                                    font.pixelSize: 10
                                                    anchors.verticalCenter: btNameText.verticalCenter
                                                    width: 60
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            MouseArea {
                                                id: btRowHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        var pos = mapToItem(keyCatcher, mouse.x, mouse.y);
                                                        contextMenuIsEthernet = false;
                                                        contextMenuIsBt = true;
                                                        contextMenuMac = mac;
                                                        contextMenuBtName = name;
                                                        contextMenuInUse = false;
                                                        contextMenuKnown = paired;
                                                        contextMenuSecured = false;
                                                        contextMenuX = pos.x;
                                                        contextMenuY = pos.y;
                                                        contextMenuVisible = true;
                                                        return;
                                                    }
                                                    contextMenuVisible = false;
                                                    root.btConnect(mac);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ============ BLUETOOTH: AYRAC ============
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (root.btListShown && pairedBtModel.count > 0) ? 1 : 0
                        // ColumnLayout ustune ve altina 14'er piksel koyuyor;
                        // negatif marjla toplam araligi makul tutuyoruz
                        Layout.topMargin: (root.btListShown && pairedBtModel.count > 0) ? -6 : 0
                        visible: root.btListShown && pairedBtModel.count > 0
                        opacity: visible ? 1 : 0

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 420; easing.type: Easing.OutQuint }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 420; easing.type: Easing.OutQuint }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            height: 1
                            color: "#2a2a2a"
                        }
                    }

                    // ============ BLUETOOTH: ESLESMIS CIHAZLAR ============
                    Loader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (root.btListShown && pairedBtModel.count > 0)
                            ? (Math.min(pairedBtModel.count, 4) * 40 + Math.max(0, Math.min(pairedBtModel.count, 4) - 1) * 4 + 8)
                            : 0
                        Layout.topMargin: (root.btListShown && pairedBtModel.count > 0) ? -6 : 0
                        opacity: (root.btListShown && pairedBtModel.count > 0) ? 1 : 0
                        visible: root.btListShown && pairedBtModel.count > 0
                        active: root.btListShown

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 480; easing.type: Easing.OutQuint }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 420; easing.type: Easing.OutQuint }
                        }

                        sourceComponent: Item {
                            anchors.fill: parent
                            Rectangle {
                                width: parent.width
                                height: parent.height
                                radius: 8
                                color: "#141414"

                                ListView {
                                    id: pairedListEl
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    clip: true
                                    model: pairedBtModel
                                    spacing: 4

                                    delegate: Item {
                                        width: pairedListEl.width
                                        height: 40

                                        Rectangle {
                                            id: pairedRowBg
                                            width: parent.width
                                            height: 40
                                            radius: 6
                                            color: "#141414"

                                            Behavior on color {
                                                enabled: btConnectingMac !== mac && !pairedPulse.running
                                                ColorAnimation { duration: 120 }
                                            }

                                            SequentialAnimation {
                                                id: pairedPulse
                                                running: btConnectingMac === mac
                                                loops: Animation.Infinite
                                                alwaysRunToEnd: false

                                                ColorAnimation {
                                                    target: pairedRowBg
                                                    property: "color"
                                                    to: "#262626"
                                                    duration: 1200
                                                    easing.type: Easing.InOutSine
                                                }
                                                ColorAnimation {
                                                    target: pairedRowBg
                                                    property: "color"
                                                    to: "#141414"
                                                    duration: 1200
                                                    easing.type: Easing.InOutSine
                                                }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: parent.radius
                                                color: "#ffffff"
                                                opacity: pairedRowHover.containsMouse ? 0.05 : 0
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                                }
                                            }

                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 10

                                                Text {
                                                    text: "\uf293"
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 14
                                                    color: "#9a9a9a"
                                                    width: 16
                                                    horizontalAlignment: Text.AlignHCenter
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                Text {
                                                    id: pairedNameText
                                                    text: name
                                                    color: "#c9c9c9"
                                                    font.pixelSize: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 116
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: root.t("Eşleşmiş", "Paired")
                                                    color: "#5c5c5c"
                                                    font.pixelSize: 10
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 60
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            MouseArea {
                                                id: pairedRowHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        var pos = mapToItem(keyCatcher, mouse.x, mouse.y);
                                                        contextMenuIsEthernet = false;
                                                        contextMenuIsBt = true;
                                                        contextMenuMac = mac;
                                                        contextMenuBtName = name;
                                                        contextMenuInUse = false;
                                                        contextMenuKnown = true;
                                                        contextMenuSecured = false;
                                                        contextMenuX = pos.x;
                                                        contextMenuY = pos.y;
                                                        contextMenuVisible = true;
                                                        return;
                                                    }
                                                    contextMenuVisible = false;
                                                    root.btConnect(mac);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (root.wifiListShown && showPasswordPrompt) ? 44 : 0
                        Layout.alignment: Qt.AlignTop
                        radius: 8
                        color: "#141414"
                        visible: root.wifiListShown && showPasswordPrompt
                        clip: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 6
                                color: "#000000"
                                border.width: 2
                                border.color: accentColor

                                SequentialAnimation on border.color {
                                    loops: Animation.Infinite
                                    running: showPasswordPrompt
                                    ColorAnimation {
                                        to: "#141414"
                                        duration: 1500
                                        easing.type: Easing.InOutSine
                                    }
                                    ColorAnimation {
                                        to: accentColor
                                        duration: 1500
                                        easing.type: Easing.InOutSine
                                    }
                                }

                                TextInput {
                                    id: passField
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    anchors.topMargin: 9
                                    anchors.bottomMargin: 7
                                    color: "#e8e8e8"
                                    font.pixelSize: 12
                                    echoMode: TextInput.Password
                                    clip: true
                                    onAccepted: {
                                        connectingSsid = selectedSsid;
                                        connectProc.command = ["sh", "-c", "nmcli device wifi connect " + shQuote(selectedSsid) + " password " + shQuote(passField.text)];
                                        connectProc.running = true;
                                        showPasswordPrompt = false;
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 6
                                color: cancelHover.containsMouse ? "#383838" : "#262626"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 1
                                    text: "✕"
                                    font.pixelSize: 11
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: cancelHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        showPasswordPrompt = false;
                                        connectingSsid = "";
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 58
                                Layout.preferredHeight: 28
                                radius: 6
                                color: connectBtnHover.containsMouse ? "#383838" : "#262626"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.t("Bağlan", "Connect")
                                    font.pixelSize: 11
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: connectBtnHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        connectingSsid = selectedSsid;
                                        connectProc.command = ["sh", "-c", "nmcli device wifi connect " + shQuote(selectedSsid) + " password " + shQuote(passField.text)];
                                        connectProc.running = true;
                                        showPasswordPrompt = false;
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (root.wifiListShown && (ethernetConnected || !wifiConnected)) ? 48 : 0
                        Layout.alignment: Qt.AlignTop
                        radius: 10
                        color: "#262626"
                        opacity: (root.wifiListShown && (ethernetConnected || !wifiConnected)) ? 1 : 0
                        visible: ethernetConnected || !wifiConnected
                        clip: true

                        Behavior on Layout.preferredHeight {
                            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            spacing: 10
                            visible: ethernetConnected

                            Text {
                                text: String.fromCodePoint(0xF0200)   // nf-md-ethernet
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 18
                                color: "#ffffff"
                                width: 18
                                height: 18
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Ethernet"
                                color: "#e8e8e8"
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            text: root.t("Bağlı", "Connected")
                            color: accentColor
                            font.pixelSize: 11
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: ethernetConnected
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            spacing: 8
                            visible: !ethernetConnected

                            Item {
                                id: iconSlot
                                width: refreshIconText.implicitWidth
                                height: refreshIconText.implicitHeight
                                anchors.verticalCenter: parent.verticalCenter

                                // FIX: translate lives on this OUTER item
                                // only, so sliding is always a plain
                                // horizontal move in screen space — it can
                                // never be composed with the inner item's
                                // rotation (which is what caused the
                                // diagonal/crooked slide before).
                                transform: Translate {
                                    id: iconSlide
                                    x: 0
                                }

                                Text {
                                    id: refreshIconText
                                    property string iconGlyph: "\u{F092D}"
                                    property bool isScanningIcon: false
                                    text: iconGlyph
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: wifiRadioOn ? 18 : 16
                                    // statusText'teki ile aynı sorun: araya
                                    // "iconColor" property'si koyup animasyonda
                                    // elle atayınca accentColor bağı kopuyor ve
                                    // ikon eski renginde donuyordu
                                    color: accentColor
                                    opacity: iconSlot.opacityLevel
                                    anchors.centerIn: parent

                                    Component.onCompleted: {
                                        iconGlyph = wifiRadioOn ? "\u{F0450}" : "\u{F092D}";
                                        isScanningIcon = wifiRadioOn;
                                    }

                                    property real animAngle: 0

                                    // FIX: rotation now only runs for the
                                    // icon that's actually the scanning
                                    // glyph (isScanningIcon), not the live
                                    // wifiRadioOn value — so the crossed-out
                                    // "no wifi" icon never spins, and the
                                    // scanning icon keeps spinning in place
                                    // even while it's sliding away.
                                    NumberAnimation on animAngle {
                                        running: refreshIconText.isScanningIcon
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 2500
                                    }

                                    transform: Rotation {
                                        origin.x: refreshIconText.width / 2
                                        origin.y: refreshIconText.height / 2
                                        angle: refreshIconText.isScanningIcon ? refreshIconText.animAngle : 0
                                    }
                                }

                                property real opacityLevel: 1

                                // FIX: swap-slide transition — exits to the
                                // left while fading out, swaps glyph/color
                                // while invisible off to the left, then
                                // enters from the left sliding back into
                                // place while fading in. Calm, slow-ish.
                                Connections {
                                    target: root
                                    function onWifiRadioOnChanged() {
                                        iconSwapAnim.restart();
                                    }
                                }

                                SequentialAnimation {
                                    id: iconSwapAnim
                                    running: false

                                    ParallelAnimation {
                                        NumberAnimation {
                                            target: iconSlide
                                            property: "x"
                                            to: -60
                                            duration: 320
                                            easing.type: Easing.InCubic
                                        }
                                        NumberAnimation {
                                            target: iconSlot
                                            property: "opacityLevel"
                                            to: 0
                                            duration: 260
                                            easing.type: Easing.InCubic
                                        }
                                    }

                                    PropertyAction {
                                        target: refreshIconText
                                        property: "iconGlyph"
                                        value: wifiRadioOn ? "\u{F0450}" : "\u{F092D}"
                                    }
                                    PropertyAction {
                                        target: refreshIconText
                                        property: "isScanningIcon"
                                        value: wifiRadioOn
                                    }

                                    ParallelAnimation {
                                        NumberAnimation {
                                            target: iconSlide
                                            property: "x"
                                            to: 0
                                            duration: 400
                                            easing.type: Easing.OutCubic
                                        }
                                        NumberAnimation {
                                            target: iconSlot
                                            property: "opacityLevel"
                                            to: 1
                                            duration: 380
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            id: statusText
                            property string statusLabel: root.t("Bağlantı Yok", "Not Connected")
                            text: statusLabel
                            // DİKKAT: burada araya "statusColor" diye bir
                            // property koymak yok. Öyle yapılınca renk hem
                            // Component.onCompleted'da hem animasyonun
                            // içindeki PropertyAction'da ELLE atanıyordu ve
                            // her atama accentColor bağını kalıcı olarak
                            // koparıyordu. Sonuç: pywal rengi sonradan
                            // değişince yazı eski renginde donup kalıyor,
                            // "bazen alıyor bazen almıyor" gibi görünüyordu.
                            color: accentColor
                            font.pixelSize: 13
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !ethernetConnected

                            Component.onCompleted: {
                                statusLabel = wifiRadioOn ? root.t("Taranıyor", "Scanning") : root.t("Bağlantı Yok", "Not Connected");
                            }

                            transform: Translate {
                                id: statusSlide
                                x: 0
                            }

                            // FIX: mirrors the icon's swap-slide, but exits
                            // to the right and enters from the right, so
                            // text and icon travel in opposite directions
                            // like a conveyor.
                            Connections {
                                target: root
                                function onWifiRadioOnChanged() {
                                    statusSwapAnim.restart();
                                }
                            }

                            SequentialAnimation {
                                id: statusSwapAnim
                                running: false

                                ParallelAnimation {
                                    NumberAnimation {
                                        target: statusSlide
                                        property: "x"
                                        to: 60
                                        duration: 320
                                        easing.type: Easing.InCubic
                                    }
                                    NumberAnimation {
                                        target: statusText
                                        property: "opacity"
                                        to: 0
                                        duration: 260
                                        easing.type: Easing.InCubic
                                    }
                                }

                                PropertyAction {
                                    target: statusText
                                    property: "statusLabel"
                                    value: wifiRadioOn ? root.t("Taranıyor", "Scanning") : root.t("Bağlantı Yok", "Not Connected")
                                }

                                ParallelAnimation {
                                    NumberAnimation {
                                        target: statusSlide
                                        property: "x"
                                        to: 0
                                        duration: 400
                                        easing.type: Easing.OutCubic
                                    }
                                    NumberAnimation {
                                        target: statusText
                                        property: "opacity"
                                        to: 1
                                        duration: 380
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#ffffff"
                            opacity: ethHover.containsMouse ? 0.05 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: ethHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    var pos = mapToItem(keyCatcher, mouse.x, mouse.y);
                                    contextMenuIsEthernet = true;
                                    contextMenuIsBt = false;
                                    contextMenuInUse = ethernetConnected;
                                    contextMenuKnown = true;
                                    contextMenuSecured = false;
                                    contextMenuSsid = "";
                                    contextMenuX = pos.x;
                                    contextMenuY = pos.y;
                                    contextMenuVisible = true;
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                visible: contextMenuVisible
                z: 9
                onClicked: contextMenuVisible = false
            }

            Rectangle {
                id: contextMenu
                // Panelin disina tasmasin: sagda/altta yer yoksa ice dogru kaydir
                x: Math.max(4, Math.min(contextMenuX, parent.width - width - 4))
                y: Math.max(4, Math.min(contextMenuY, parent.height - height - 4))
                width: 150
                height: contextMenuIsEthernet ? 36
                        : ((contextMenuInUse || contextMenuKnown) ? 64 : 36)
                radius: 8
                color: "#1a1a1a"
                border.color: "#333333"
                border.width: 1
                z: 10

                opacity: contextMenuVisible ? 1 : 0
                scale: contextMenuVisible ? 1 : 0.9
                visible: opacity > 0.01
                transformOrigin: Item.TopLeft
                Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 4

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 6
                        color: disconnectHover.containsMouse ? "#2a2a2a" : "transparent"
                        visible: contextMenuInUse

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.t("Bağlantıyı Kes", "Disconnect")
                            color: "#ffffff"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: disconnectHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (contextMenuIsBt) {
                                    contextMenuVisible = false;
                                    root.btDisconnect(contextMenuMac);
                                } else if (contextMenuIsEthernet) {
                                    disconnectEthernet();
                                } else {
                                    disconnectProc.command = ["sh", "-c", "nmcli connection down " + shQuote(contextMenuSsid)];
                                    disconnectProc.running = true;
                                    contextMenuVisible = false;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 6
                        color: reconnectHover.containsMouse ? "#2a2a2a" : "transparent"
                        visible: contextMenuIsBt ? (!contextMenuInUse && contextMenuKnown)
                                 : (contextMenuIsEthernet ? !contextMenuInUse
                                 : (!contextMenuInUse && contextMenuKnown))

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.t("Tekrar Bağlan", "Reconnect")
                            color: "#ffffff"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: reconnectHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (contextMenuIsBt) {
                                    contextMenuVisible = false;
                                    root.btConnect(contextMenuMac);
                                } else if (contextMenuIsEthernet) {
                                    reconnectEthernet();
                                } else {
                                    contextMenuVisible = false;
                                    connectingSsid = contextMenuSsid;
                                    tryConnect(contextMenuSsid, contextMenuSecured);
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 6
                        color: connectHover.containsMouse ? "#2a2a2a" : "transparent"
                        visible: !contextMenuIsEthernet && !contextMenuInUse && !contextMenuKnown

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.t("Bağlan", "Connect")
                            color: "#ffffff"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: connectHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                contextMenuVisible = false;
                                if (contextMenuIsBt) {
                                    root.btConnect(contextMenuMac);
                                    return;
                                }
                                connectingSsid = contextMenuSsid;
                                if (contextMenuSecured) {
                                    selectedSsid = contextMenuSsid;
                                    showPasswordPrompt = true;
                                    passField.text = "";
                                    passField.forceActiveFocus();
                                } else {
                                    connectProc.command = ["sh", "-c", "nmcli device wifi connect " + shQuote(contextMenuSsid)];
                                    connectProc.running = true;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 6
                        color: forgetHover.containsMouse ? "#2a2a2a" : "transparent"
                        visible: !contextMenuIsEthernet && (contextMenuInUse || contextMenuKnown)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: contextMenuIsBt ? root.t("Bu Cihazı Unut", "Forget Device") : root.t("Bağlantıyı Unut", "Forget Network")
                            color: "#ffffff"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: forgetHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (contextMenuIsBt) {
                                    forgetProc.command = ["sh", "-c",
                                        "bluetoothctl disconnect " + shQuote(contextMenuMac) +
                                        "; bluetoothctl untrust " + shQuote(contextMenuMac) +
                                        "; bluetoothctl remove " + shQuote(contextMenuMac)];
                                    forgetProc.running = true;
                                    contextMenuVisible = false;
                                    btListProc.running = true;
                                    return;
                                }
                                forgetProc.command = ["sh", "-c", "nmcli connection delete " + shQuote(contextMenuSsid)];
                                forgetProc.running = true;
                                contextMenuVisible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}