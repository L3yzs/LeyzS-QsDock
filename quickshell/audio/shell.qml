import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire

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

    // ================= AÇILIŞ / KAPANIŞ =================
    // Menü artık her seferinde sıfırdan başlamıyor: process arka planda açık
    // kalıyor, sadece pencere gösterilip gizleniyor. Eskiden Qt.quit() ile
    // kapandığı için her açılışta QML sahnesi baştan kuruluyor ve ses
    // aygıtları yeniden sorgulanıyordu; animasyon da bu yükün ortasında
    // oynadığı için takılıyordu.
    property bool menuOpen: false

    // Menü ekranın SOL alt köşesinde: kapalıyken tamamen sola itiliyor,
    // açılınca 0'a gelip yerine oturuyor. Mesafe panelin kendi genişliğine
    // bağlı; sabit bir sayı verilince dar/geniş panelde kapalı konum ya
    // eksik ya fazla kalıyordu.
    property real slideX: menuOpen ? 0 : -(panel.width + 40)

    Behavior on slideX {
        NumberAnimation {
            id: slideAnim
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    IpcHandler {
        target: "audiomenu"
        function toggle(): void { root.route("toggle") }
        function open(): void { root.route("open") }
        function close(): void { root.closeMenu() }
    }

    // ================= QsNotch YONLENDIRME =================
    // Kontrol panelden bar olarak QsNotch seciliyse bu menu acilmaz; istek centige gider
    // ve ses menusu centikte acilir. Waybar / qsbar'da her sey eskisi gibi.
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
                    Quickshell.execDetached(["sh", "-c", "b=$(cat \"$HOME/.config/quickshell/bar-choice\" 2>/dev/null); if [ \"$b\" = qsisland ]; then qs -c qsisland ipc call ada \"$2\"; else qs -c qsbar2 ipc call qsnotch \"$1\"; fi", "sh", "audio", "audio"]);
                } else if (bar === "dock") {
                    // Dock seciliyken ses paneli dock'ta acilir (dock ses paneline donusur)
                    if (root.menuOpen) root.closeMenu();
                    Quickshell.execDetached(["qs", "-c", "dock", "ipc", "call", "dock", "audio"]);
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

    function openMenu() {
        if (root.menuOpen) return;

        // her açılışta temiz başlangıç - process kalıcı olduğu için eski
        // arama metni olduğu gibi duruyordu
        searchInput.text = "";

        // önce pencereyi göster (Hyprland klavye odağını burada devrediyor),
        // sonra bir kare bekleyip hareketi başlat
        win.visible = true;
        startTimer.start();
    }

    function closeMenu() {
        if (!root.menuOpen) return;
        root.menuOpen = false;
        hideTimer.start();
    }

    function toggleMenu() {
        if (root.menuOpen) root.closeMenu();
        else root.openMenu();
    }

    Timer {
        id: startTimer
        interval: 16
        onTriggered: {
            root.menuOpen = true;
            panel.forceActiveFocus();
        }
    }

    // Kapanış animasyonu bitmeden gizlersek menü yarı yolda yok oluyor
    Timer {
        id: hideTimer
        interval: 340
        onTriggered: win.visible = false
    }

    // pywal @color9 buradan okunur; dosya değişince otomatik güncellenir
    property color accentColor: "#b06ab3"
    property string searchText: ""
    property bool showingApps: false
    // pipewire'da 1.0 = normal %100 seviye. Bazı uygulamalar (ör. Spotify)
    // kendi iç seviyesini düşük tutabiliyor; bu yüzden 1.5'e kadar (%150)
    // güçlendirme (boost) izni veriyoruz ki slider'ı sona çekince gerçekten
    // yüksek sesle karşılaşılsın.
    property real maxVolume: 1.5

    FileView {
        id: walFile
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text())
                if (data.colors && data.colors.color9)
                    root.accentColor = data.colors.color9
            } catch (e) {
                console.log("wal renkleri okunamadı:", e)
            }
        }
    }

    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // pipewire description bazen genel bir isim olabiliyor (ör. "audio-src");
    // gerçek uygulama adını properties'ten almaya çalışıyoruz.
    function nodeDisplayName(node) {
        const appName = node.properties ? node.properties["application.name"] : null
        if (appName && appName.length > 0) return appName
        return node.description || node.name
    }

    // uygulamanın ikon teması ismi; yoksa boş döner (fallback text ikon gösterilir)
    function streamIconName(node) {
        if (!node.properties) return ""
        const iconName = node.properties["application.icon-name"]
        if (iconName && iconName.length > 0) return iconName
        const appId = node.properties["application.id"]
        if (appId && appId.length > 0) return appId
        return ""
    }

    // basit tip tespiti -> ikon
    function nodeIcon(node) {
        const n = (node.name + " " + node.description).toLowerCase()
        if (n.includes("hdmi") || n.includes("displayport"))
            return "\uf108" // nf-fa-desktop
        if (n.includes("bluez") || n.includes("headset") || n.includes("headphone"))
            return "\uf025" // nf-fa-headphones
        if (node.isStream)
            return "\uf001" // nf-fa-music, uygulama akışları için
        return "\uf028" // nf-fa-volume_up
    }

    // searchText'e bağlı DEĞİL - sadece cihaz listesi değişince güncellenir.
    // Böylece yazarken ListView'ın modeli sabit kalır, delegate'ler yeniden
    // yaratılmaz; filtreleme aşağıda delegate seviyesinde (height/visible ile) yapılır.
    readonly property var sinks: {
        const out = []
        const list = Pipewire.nodes.values
        for (let i = 0; i < list.length; i++) {
            const node = list[i]
            if (!node.audio || node.isStream) continue
            out.push(node)
        }
        return out
    }

    // ses çıkışı veren uygulamalar (spotify vb.) - stream node'ları
    readonly property var streams: {
        const out = []
        const list = Pipewire.nodes.values
        for (let i = 0; i < list.length; i++) {
            const node = list[i]
            if (!node.audio || !node.isStream) continue
            out.push(node)
        }
        return out
    }

    // toggle'a göre gösterilecek liste
    readonly property var currentList: root.showingApps ? root.streams : root.sinks

    // her satırın yüksekliği moda göre değişiyor (uygulama modunda slider için daha uzun)
    readonly property int rowHeight: root.showingApps ? 56 : 50
    // panelde aynı anda tam olarak en fazla 4 satır görünsün, gerisi scroll ile gelsin
    readonly property int visibleRows: 4
    readonly property int maxListHeight: root.visibleRows * root.rowHeight + (root.visibleRows - 1) * 8

    // Wayland penceresinin (layer-shell surface) GERÇEK boyutu sabit kalmalı;
    // moda göre her seferinde resize edersek compositor bazen eski karenin
    // kalıntısını (ghost/artifact) tam temizleyemiyor. Bu yüzden pencereyi hep
    // iki modun da en büyüğüne göre sabit tutuyoruz, sadece içteki panel
    // Rectangle'ı dinamik küçültüp büyütüyoruz.
    readonly property int maxListHeightSinks: root.visibleRows * 50 + (root.visibleRows - 1) * 8
    readonly property int maxListHeightApps: root.visibleRows * 56 + (root.visibleRows - 1) * 8
    readonly property int fixedWindowListHeight: Math.max(maxListHeightSinks, maxListHeightApps)

    function matchesSearch(node) {
        if (root.searchText.length === 0) return true
        const label = root.nodeDisplayName(node).toLowerCase()
        return label.includes(root.searchText.toLowerCase())
    }

    // hoparlör <-> uygulama listesi geçişinin yönünü belirler ve animasyonu başlatır
    function toggleView() {
        const goingToApps = !root.showingApps
        // uygulamalara geçerken: mevcut liste sola çıkar, yenisi sağdan gelir
        // geri dönerken: tam tersi - mevcut liste sağa çıkar, yenisi soldan gelir
        viewSwitchAnim.exitTo = goingToApps ? -list.width : list.width
        viewSwitchAnim.enterFrom = goingToApps ? list.width : -list.width
        viewSwitchAnim.start()
    }

    PanelWindow {
        id: win
        // Pencere menü kapalıyken gerçekten kapanıyor: Hyprland yeni bir
        // katman oluşumu görmezse klavye odağını menüye devretmiyor ve imleç
        // menünün üstünde değilken arama yapılamıyor.
        visible: false
        focusable: true

        // Hyprland tarafında bu isme bakarak layer animasyonunu kapatıyoruz
        // (windowrule.lua -> hl.layer_rule / match.namespace), böylece
        // açılış/kapanış hareketinin tamamı buradan geliyor
        WlrLayershell.namespace: "quickshell:audiomenu"

        anchors {
            bottom: true
            left: true
        }

        margins {
            bottom: 8
            // NOT: sol boşluk BURADA değil, panel'in kendi leftMargin'inde.
            // Pencere sol kenardan içeride başlarsa panel de en fazla oraya
            // kadar kayabiliyor ve kapanırken kenarda bir şerit görünüyordu.
            // Pencereyi ekranın gerçek kenarına yaslayıp boşluğu panele
            // vererek panelin tamamen dışarı çıkmasını sağlıyoruz.
            left: 0
        }

        implicitWidth: 368
        implicitHeight: 24 + 40 + 8 + root.fixedWindowListHeight
        width: implicitWidth
        height: implicitHeight

        color: "transparent"

        Rectangle {
            id: panel
            anchors.left: parent.left
            // pencereden alınan sol boşluk buraya taşındı
            anchors.leftMargin: 8
            anchors.bottom: parent.bottom
            width: parent.width - 8
            height: 24 + 40 + 8 + list.height
            radius: 10
            color: "#000000"
            border.width: 0
            focus: true
            Keys.onEscapePressed: root.closeMenu()

            // ================= AÇILIŞ / KAPANIŞ ANİMASYONU =================
            // Menü soldan içeri sürüklenerek geliyor, kapanırken aynı yoldan
            // sola doğru kayıp ekran dışında kayboluyor.
            transform: Translate { x: root.slideX }
            // Kayarken panelin sol kenarı ekran sınırında kırpıldığı için
            // yuvarlak köşe kesik görünüyordu; hafif bir solma bu geçişi
            // yumuşatıyor.
            opacity: root.menuOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            // Kalıcı GPU dokusu: 270Hz'de her kareye 3.7ms bütçe düşüyor,
            // liste ve ikonlar kare kare çizilince bu bütçe aşılıyor.
            // Doku bir kez oluşuyor, animasyon boyunca sadece kaydırılıyor.
            layer.enabled: true
            layer.smooth: true
            // kayan/animasyonlu içerik hiçbir zaman kutunun (yuvarlak köşeler dahil)
            // dışına taşmasın diye panel'i kendi sınırlarına göre kırpıyoruz
            clip: true

            // pencere (win) artık sabit boyutlu olduğu için burada height animasyonu
            // güvenli - wayland yüzeyi hiç resize olmuyor, sadece bu iç dikdörtgen
            // büyüyüp küçülüyor. Ama panel İLK açılırken (veriler daha yüklenirken)
            // bu animasyon aktif olursa "kasarak açılma" hissi veriyor, o yüzden
            // kısa bir süre kapalı tutup sonra açıyoruz.
            property bool animateHeight: false
            Behavior on height {
                enabled: panel.animateHeight
                NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
            }

            opacity: 0
            scale: 0.97
            transformOrigin: Item.BottomLeft
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Component.onCompleted: {
                opacity = 1
                scale = 1
                heightAnimEnableTimer.start()
            }

            Timer {
                id: heightAnimEnableTimer
                interval: 300
                onTriggered: panel.animateHeight = true
            }

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                clip: true

                Rectangle {
                    id: searchBar
                    width: parent.width
                    height: 40
                    radius: 8
                    color: "#1a1a1a"

                    Text {
                        id: searchIcon
                        text: "\uf002" // nf-fa-search
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 15
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12

                        // yavaş "nefes alma" efekti: beyaz <-> pywal accent rengi arasında
                        // sürekli, yumuşak geçişlerle döngüye giriyor
                        SequentialAnimation on color {
                            loops: Animation.Infinite
                            ColorAnimation { to: root.accentColor; duration: 2200; easing.type: Easing.InOutSine }
                            ColorAnimation { to: "#ffffff"; duration: 2200; easing.type: Easing.InOutSine }
                        }
                    }

                    TextInput {
                        id: searchInput
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: searchIcon.right
                        anchors.leftMargin: 10
                        anchors.right: divider.left
                        anchors.rightMargin: 10
                        color: "#e6e6e6"
                        font.pixelSize: 14
                        focus: true
                        clip: true
                        onTextChanged: root.searchText = text

                        Text {
                            text: root.showingApps ? root.t("Uygulama ara", "Search apps") : root.t("Ses çıkışı ara", "Search outputs")
                            color: "#5a5a5a"
                            font.pixelSize: 14
                            visible: searchInput.text.length === 0
                        }

                        Keys.onEscapePressed: root.closeMenu()
                    }

                    Rectangle {
                        id: divider
                        width: 1
                        height: 18
                        color: "#3a3a3a"
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: toggleBtn.left
                        anchors.rightMargin: 8
                    }

                    Rectangle {
                        id: toggleBtn
                        width: 26
                        height: 26
                        radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        color: "transparent"
                        scale: 1

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#ffffff"
                            opacity: toggleArea.containsMouse ? 0.08 : 0
                            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            id: menuIcon
                            anchors.centerIn: parent
                            text: "\uf0c9" // nf-fa-bars, 3 çizgi
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 14
                            color: root.showingApps ? root.accentColor : "#8a8a8a"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        SequentialAnimation {
                            id: menuSpinAnim
                            PropertyAction { target: menuIcon; property: "rotation"; value: 0 }
                            NumberAnimation { target: menuIcon; property: "rotation"; to: 360; duration: 380; easing.type: Easing.OutCubic }
                        }

                        // tıklanınca hafifçe büyüyüp yumuşakça eski boyutuna dönsün
                        SequentialAnimation {
                            id: menuPopAnim
                            NumberAnimation { target: toggleBtn; property: "scale"; to: 1.25; duration: 110; easing.type: Easing.OutCubic }
                            NumberAnimation { target: toggleBtn; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
                        }

                        MouseArea {
                            id: toggleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.toggleView()
                                menuSpinAnim.start()
                                menuPopAnim.start()
                            }
                        }
                    }
                }

                SequentialAnimation {
                    id: viewSwitchAnim
                    property real exitTo: 0
                    property real enterFrom: 0
                    // mevcut liste, gidilecek yöne göre sola ya da sağa kayıp çıksın
                    NumberAnimation { target: list; property: "x"; to: viewSwitchAnim.exitTo; duration: 190; easing.type: Easing.InCubic }
                    // liste değişsin, yeni liste henüz görünmeden karşı taraftan ışınlansın
                    ScriptAction {
                        script: {
                            root.showingApps = !root.showingApps
                            list.x = viewSwitchAnim.enterFrom
                        }
                    }
                    // yeni liste karşı yönden sürüklenerek içeri gelsin
                    NumberAnimation { target: list; property: "x"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                }

                ListView {
                    id: list
                    x: 0
                    width: parent.width
                    height: Math.min(contentHeight, root.maxListHeight)
                    clip: true
                    model: root.currentList

                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic }
                    }

                    delegate: Item {
                        id: rowDelegate
                        width: list.width
                        property bool matches: root.matchesSearch(modelData)
                        // Bu satırdan önce görünen başka bir satır varsa üstüne 8px boşluk ekle,
                        // yoksa (ilk görünen satırsa veya gizliyse) boşluk ekleme.
                        property bool gapBefore: {
                            if (!matches) return false
                            for (let i = index - 1; i >= 0; i--) {
                                if (root.matchesSearch(root.currentList[i]))
                                    return true
                            }
                            return false
                        }
                        property int rowHeight: root.rowHeight
                        height: (matches ? rowDelegate.rowHeight : 0) + (gapBefore ? 8 : 0)
                        visible: height > 0
                        clip: height < 58
                        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        Rectangle {
                            id: rowBg
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: rowDelegate.matches ? rowDelegate.rowHeight : 0
                            radius: 8
                            property bool selected: !root.showingApps && modelData.id === Pipewire.defaultAudioSink?.id
                            property bool hovered: false
                            color: selected ? "#2e2e2e" : (hovered ? "#1e1e1e" : "#161616")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Rectangle {
                                    width: 30
                                    height: 30
                                    radius: 6
                                    color: rowBg.selected ? "#383838" : "#1f1f1f"
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    IconImage {
                                        id: appIcon
                                        anchors.centerIn: parent
                                        implicitSize: 18
                                        asynchronous: true
                                        visible: root.showingApps && status === Image.Ready && source != ""
                                        source: root.showingApps ? Quickshell.iconPath(root.streamIconName(modelData), true) : ""
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !appIcon.visible
                                        text: root.nodeIcon(modelData)
                                        font.family: "Symbols Nerd Font"
                                        font.pixelSize: 15
                                        color: (root.showingApps || rowBg.selected) ? root.accentColor : "#c7c7c7"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 30 - 12 - (root.showingApps ? 42 : 0)
                                    spacing: 4

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: root.nodeDisplayName(modelData)
                                        color: rowBg.selected ? "#fafafa" : "#c7c7c7"
                                        font.pixelSize: 13
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    Text {
                                        visible: !root.showingApps
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: modelData.audio.channels.length + root.t(" kanal", " channels")
                                        color: "#6b6b6b"
                                        font.pixelSize: 11
                                    }

                                    Item {
                                        id: volumeSlider
                                        visible: root.showingApps
                                        width: parent.width
                                        height: 14

                                        readonly property real fraction: Math.max(0, Math.min(1, (modelData.audio ? modelData.audio.volume : 0) / root.maxVolume))

                                        Rectangle {
                                            id: track
                                            width: parent.width
                                            height: 4
                                            radius: 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: "#2a2a2a"

                                            Rectangle {
                                                height: parent.height
                                                radius: 2
                                                color: root.accentColor
                                                width: track.width * volumeSlider.fraction
                                            }
                                        }

                                        Rectangle {
                                            id: thumb
                                            width: 12
                                            height: 12
                                            radius: 6
                                            color: sliderArea.containsMouse || sliderArea.pressed ? root.accentColor : "#ffffff"
                                            border.width: 2
                                            border.color: root.accentColor
                                            anchors.verticalCenter: track.verticalCenter
                                            x: Math.max(0, Math.min(track.width - width, track.width * volumeSlider.fraction - width / 2))
                                            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        }

                                        MouseArea {
                                            id: sliderArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            preventStealing: true
                                            function setVolume(x) {
                                                const v = Math.max(0, Math.min(1, x / width)) * root.maxVolume
                                                if (modelData.audio) modelData.audio.volume = v
                                            }
                                            onPressed: (mouse) => setVolume(mouse.x)
                                            onPositionChanged: (mouse) => { if (pressed) setVolume(mouse.x) }
                                        }
                                    }
                                }

                                Text {
                                    visible: root.showingApps
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round(Math.max(0, Math.min(1, (modelData.audio ? modelData.audio.volume : 0) / root.maxVolume)) * 100) + "%"
                                    color: "#8a8a8a"
                                    font.pixelSize: 11
                                }
                            }

                            HoverHandler {
                                // satır arkaplanının gri hover'ı her iki modda da çalışsın;
                                // MouseArea yerine HoverHandler kullanıyoruz ki uygulama
                                // modunda slider'ın sürükleme etkileşimini bloklamasın.
                                onHoveredChanged: rowBg.hovered = hovered
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.showingApps
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Pipewire.preferredDefaultAudioSink = modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
