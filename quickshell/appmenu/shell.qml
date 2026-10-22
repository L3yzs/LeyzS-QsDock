//@ pragma IconTheme Papirus
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

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

    // pywal @color9 buradan okunur; dosya değişince otomatik güncellenir
    property color accentColor: "#b06ab3"
    property string searchText: ""
    // arama çubuğu ilk açılışta PASİF - klavyeden bir tuşa basılana kadar
    // odaklanmıyor, cursor/border animasyonu görünmüyor
    property bool searchActive: false
    // panel açılır açılmaz imlecin altında kalan satırın otomatik hover
    // görünmesini engellemek için - fare gerçekten hareket edene kadar false
    property bool hoverReady: false

    // ================= DOCK SABITLERI =================
    // Satira sag tik -> "Dock'a sabitle". Liste dock (ve notch'taki uygulama menusu) ile ortak:
    // ~/.local/share/quickshell/dock-sabitler.json  {"ids": [...]}  (.desktop kimlikleri)
    readonly property string pinPath: Quickshell.env("HOME") + "/.local/share/quickshell/dock-sabitler.json"
    readonly property string oldPinPath: Quickshell.env("HOME") + "/.config/quickshell/dock/sabitler.json"
    property var dockPins: []
    property bool ctxOpen: false
    property var ctxEntry: null
    FileView {
        id: pinFile
        path: root.pinPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); root.dockPins = d.ids || []; } catch (e) {} }
    }
    Process {
        running: true
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\"; if [ ! -f \"$1\" ]; then if [ -f \"$2\" ]; then mv \"$2\" \"$1\"; else printf '{\"ids\": []}' > \"$1\"; fi; fi", "sh", root.pinPath, root.oldPinPath]
        onExited: pinFile.reload()
    }
    function pinId(e) { return e ? (e.id || e.name) : "" }
    function isPinned(e) { return root.dockPins.indexOf(root.pinId(e)) >= 0 }
    function togglePin(e) {
        const id = root.pinId(e)
        if (!id) return
        const l = root.dockPins.slice()
        const i = l.indexOf(id)
        if (i >= 0) l.splice(i, 1); else l.push(id)
        root.dockPins = l
        pinFile.setText(JSON.stringify({ ids: l }, null, 2) + "\n")
    }

    // en son kullanılan uygulamalar - en yeni en başta, sırayla saklanır
    FileView {
        id: recentFile
        path: Quickshell.env("HOME") + "/.cache/appmenu_recent.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: recentAdapter
            property list<string> ids: []
        }
    }

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

    // kurulu tüm uygulamalar (.desktop girdileri), gizli olanlar hariç.
    // önce isme göre sıralı, sonra en son kullanılanlar (en yeni en başta) öne alınıyor.
    readonly property var allApps: {
        const list = [...DesktopEntries.applications.values].filter(e => e.name && !e.noDisplay)
        list.sort((a, b) => a.name.localeCompare(b.name))
        // aynı isimli birden fazla .desktop girdisi olabiliyor (flatpak + native gibi);
        // sadece ilkini tutup tekilleştiriyoruz ki listede "Discord" iki kez görünmesin
        const seen = new Set()
        const deduped = []
        for (const e of list) {
            const key = e.name.toLowerCase()
            if (seen.has(key)) continue
            seen.add(key)
            deduped.push(e)
        }
        const dedupedList = deduped
        const recent = recentAdapter.ids
        if (recent.length > 0) {
            dedupedList.sort((a, b) => {
                const ia = recent.indexOf(a.name)
                const ib = recent.indexOf(b.name)
                if (ia === -1 && ib === -1) return a.name.localeCompare(b.name)
                if (ia === -1) return 1
                if (ib === -1) return -1
                return ia - ib
            })
        }
        return dedupedList
    }

    readonly property var filteredApps: {
        if (root.searchText.length === 0) return root.allApps
        const q = root.searchText.toLowerCase()
        return root.allApps.filter(e => {
            const name = (e.name || "").toLowerCase()
            const comment = (e.comment || "").toLowerCase()
            return name.includes(q) || comment.includes(q)
        })
    }

    // ================= AÇILIŞ / KAPANIŞ =================
    // Hyprland'in kendi layer animasyonunu (animations.lua'daki layersIn/Out)
    // devre dışı bırakıp animasyonu tamamen burada yönetiyoruz. Bunun için
    // pencereye sabit bir namespace veriyoruz; windowrule.lua'daki
    // hl.layer_rule bu isme bakarak "no_anim" uyguluyor.
    property bool menuOpen: false

    // Tüm menü (panel + iki yanındaki kavis) bu değerle birlikte kayıyor.
    // anchors dönüşümlerden etkilenmediği için kavisleri panele "yapıştırmak"
    // yeterli değil; aynı Translate'i üçüne de ayrı ayrı vermek gerekiyor.
    //
    // Kapalı konum SABİT bir sayı: win.implicitHeight'a bağlarsak ilk karede
    // pencere boyu henüz hesaplanmamış oluyor ve menü zeminin altından değil,
    // yarı görünür bir yerden çıkıyordu. 760 = pencere yüksekliğinden fazlası,
    // yani menü kesinlikle ekranın altında başlıyor.
    property real slideY: menuOpen ? 0 : 760

    // 270Hz'de her kareye 3.7ms bütçe düşüyor. Paneldeki ikon maskeleri
    // (OpacityMask) ve kavis Canvas'ları her karede shader çalıştırdığı için
    // bu bütçe aşılıyor ve hareket pürüzlü görünüyordu.
    //
    // Pencere artık kalıcı olduğu için dokuyu SÜREKLİ açık tutuyoruz: doku
    // menü kapalıyken, kimse görmezken bir kez oluşuyor; animasyon boyunca
    // sadece hazır doku kaydırılıyor. (Daha önce dokuyu animasyon başlarken
    // açtığımız için oluşturma maliyeti ilk kareye biniyordu.)
    property bool sliding: slideAnim.running

    Behavior on slideY {
        NumberAnimation {
            id: slideAnim
            // OutQuint sonda o kadar sert yavaşlıyor ki hareketin son
            // bölümünde kare başına düşen yol 1 pikselin altına iniyor ve
            // 270Hz'de bu "takılma" gibi algılanıyor. OutCubic daha eşit
            // dağılan bir yavaşlama veriyor.
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    // ================= KALICI PROCESS =================
    // Menü artık her açılışta sıfırdan başlamıyor. Eskiden Qt.quit() ile
    // kapandığı için her Super basışında yeni bir process doğuyor, QML sahnesi
    // baştan kuruluyor, bütün .desktop dosyaları taranıyor ve ikonlar diskten
    // okunuyordu; animasyon da bu yükün ortasında oynamaya çalıştığı için
    // takılıyordu. Şimdi process arka planda açık kalıyor, sadece pencere
    // gösterilip gizleniyor - açılışta yapılacak tek iş hazır bir sahneyi
    // kaydırmak, o yüzden hareket pürüzsüz.
    IpcHandler {
        target: "menu"
        function toggle(): void { root.route("toggle") }
        function open(): void { root.route("open") }
        function close(): void { root.closeMenu() }
    }

    // ================= QsNotch YONLENDIRME =================
    // Kontrol panelden bar olarak QsNotch seciliyse bu menu acilmaz; istek centige gider
    // ve uygulama menusu centikte acilir. Waybar / qsbar'da her sey eskisi gibi.
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
                    Quickshell.execDetached(["sh", "-c", "b=$(cat \"$HOME/.config/quickshell/bar-choice\" 2>/dev/null); if [ \"$b\" = qsisland ]; then qs -c qsisland ipc call ada \"$2\"; else qs -c qsbar2 ipc call qsnotch \"$1\"; fi", "sh", "apps", "apps"]);
                } else if (bar === "dock") {
                    // Dock seciliyse: dock genisleyip uygulama menusune donusur
                    if (root.menuOpen) root.closeMenu();
                    Quickshell.execDetached(["qs", "-c", "dock", "ipc", "call", "dock", "apps"]);
                } else if (bar === "qsbar") {
                    // qsbar seciliyse: workspace sekmesi asagi suzulup uygulama menusune donusur
                    if (root.menuOpen) root.closeMenu();
                    Quickshell.execDetached(["qs", "-c", "qsbar", "ipc", "call", "qsbar", "apps"]);
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
        if (root.menuOpen) return

        // her açılışta temiz başlangıç
        // NOT: searchInput.text de sıfırlanmalı. Process kalıcı olduğu için
        // sadece root.searchText'i temizlemek yetmiyor, kutuda yazdığın metin
        // olduğu gibi duruyordu.
        searchInput.text = ""
        root.searchText = ""
        root.searchActive = false
        list.currentIndex = -1
        list.contentY = 0

        // Önce pencereyi göster (Hyprland odağı burada devrediyor), sonra
        // bir kare bekleyip hareketi başlat.
        win.visible = true
        startTimer.start()
    }

    function closeMenu() {
        if (!root.menuOpen) return
        root.ctxOpen = false
        root.menuOpen = false
        hideTimer.start()
    }

    Timer {
        id: startTimer
        interval: 16
        onTriggered: {
            root.menuOpen = true
            panel.forceActiveFocus()
        }
    }

    // Kapanış animasyonu bitmeden gizlersek menü yarı yolda yok oluyor
    Timer {
        id: hideTimer
        interval: 340
        onTriggered: win.visible = false
    }

    function toggleMenu() {
        if (root.menuOpen) root.closeMenu()
        else root.openMenu()
    }


    function launchApp(entry) {
        // bu uygulamayı "en son kullanılanlar" listesinin en başına taşı
        const ids = recentAdapter.ids.slice()
        const idx = ids.indexOf(entry.name)
        if (idx !== -1) ids.splice(idx, 1)
        ids.unshift(entry.name)
        if (ids.length > 30) ids.length = 30
        recentAdapter.ids = ids

        entry.execute()
        root.closeMenu()
    }

    // ok tuşlarıyla seçili satırı hareket ettirip enter ile açmak için
    function moveSelection(delta) {
        const count = root.filteredApps.length
        if (count === 0) return
        let next = list.currentIndex + delta
        if (next < 0) next = 0
        if (next > count - 1) next = count - 1
        list.currentIndex = next
        list.positionViewAtIndex(next, ListView.Contain)
    }

    function activateCurrent() {
        const items = root.filteredApps
        if (items.length === 0) return
        const idx = Math.max(0, Math.min(items.length - 1, list.currentIndex))
        root.launchApp(items[idx])
    }

    PanelWindow {
        id: win
        // ================= PENCERE AÇ / KAPA =================
        // Pencere menü kapalıyken gerçekten kapanıyor. Bir süre "hep açık"
        // tutmayı denedik ama o zaman Hyprland yeni bir katman oluşumu
        // görmediği için klavye odağını menüye hiç devretmiyordu: imleç
        // menünün üstünde değilken arama yapılamıyordu.
        // Akıcılığın asıl kaynağı zaten QSG_RENDER_LOOP=threaded, o yüzden
        // pencereyi açıp kapatmak hareketi bozmuyor.
        visible: false
        focusable: true

        // Klavye odağı fareyi takip etmesin: menü açıksa klavye menüde.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Hyprland tarafında bu isme bakarak layer animasyonunu kapatıyoruz
        // (windowrule.lua -> hl.layer_rule / match.namespace)
        WlrLayershell.namespace: "quickshell:appmenu"
        // bu bir dock/taskbar DEĞİL, açılıp kapanan bir menü - ekranda kalıcı
        // yer ayırıp diğer pencereleri itmesin diye exclusionMode kapalı
        exclusionMode: ExclusionMode.Ignore

        // konum: zemine (ekran altına) yapışık, yatayda ORTALANMIŞ - Caelestia
        // tarzı "dock" konumlandırması. Kavisli köşeler panelin dışına taştığı
        // için pencereyi biraz genişletip panel'i içeride notchSize kadar
        // içeri alıyoruz (yoksa kavisi çizecek yer olmaz)
        readonly property int notchSize: 40
        readonly property int panelWidth: 550
        // ayarlar ikonunun sağında açılan tooltip'in sığması için sağa
        // fazladan boşluk - panel'in kendisi ve konumu değişmiyor, sadece
        // pencerenin (transparan) sağ tarafı genişliyor
        readonly property int rightExtra: 130

        anchors {
            bottom: true
            // sadece "bottom" anchor'ı kullanıyoruz - left/right yok, bu da
            // wlr-layer-shell'de pencereyi yatayda otomatik ORTALAR
        }
        margins {
            bottom: 0
        }

        implicitWidth: panelWidth + notchSize * 2 + rightExtra
        implicitHeight: 660

        color: "transparent"

        // sol alt köşedeki ince kanca kavis - panel rengiyle dolu bir kare çizip,
        // panelin köşesinin biraz yukarısındaki noktadan (container'ın sağ-üst
        // köşesi) bir daire "ısırarak" (destination-out) çıkarıyoruz. Sonuç:
        // panelin kenarı boyunca İNCE kalıp, sadece zemine değmeden hemen önce
        // dışa doğru kanca gibi kıvrılıp genişliyor - kalın/yuvarlak bir
        // "ısırık" değil.
        Canvas {
            id: notchLeft
            width: win.notchSize
            height: win.notchSize
            anchors.right: panel.left
            anchors.bottom: panel.bottom
            // panelle birlikte kaysın, yoksa panel inip çıkarken kavis
            // yerinde asılı kalıyor
            transform: Translate { y: root.slideY }
            layer.enabled: true
            layer.smooth: true
            renderTarget: Canvas.FramebufferObject
            // Immediate her boyayı ana iş parçacığında senkron yapıyor ve
            // animasyon sırasında kareleri düşürüyordu
            renderStrategy: Canvas.Cooperative
            Component.onCompleted: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#000000"
                ctx.fillRect(0, 0, width, height)
                ctx.globalCompositeOperation = "destination-out"
                ctx.beginPath()
                ctx.arc(0, 0, width, 0, Math.PI * 2)
                ctx.fill()
            }
        }

        Canvas {
            id: notchRight
            width: win.notchSize
            height: win.notchSize
            anchors.left: panel.right
            anchors.bottom: panel.bottom
            transform: Translate { y: root.slideY }
            layer.enabled: true
            layer.smooth: true
            renderTarget: Canvas.FramebufferObject
            renderStrategy: Canvas.Cooperative
            Component.onCompleted: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#000000"
                ctx.fillRect(0, 0, width, height)
                ctx.globalCompositeOperation = "destination-out"
                ctx.beginPath()
                ctx.arc(width, 0, width, 0, Math.PI * 2)
                ctx.fill()
            }
        }

        Rectangle {
            id: panel
            // NOT: anchors.top YOK. Panel zemine yaslı duruyor ve yüksekliği
            // listedeki satır sayısına göre hesaplanıyor; yani arama sonucu
            // azaldıkça panel YUKARIDAN küçülüyor, alt çubuk yerinde kalıyor.
            anchors.bottom: parent.bottom
            anchors.left: parent.left

            // Panel içindeki dikey yerleşim aynen şu:
            //   24 pay | arama çubuğu | 16 | liste | 16 | çizgi | 16 | alt çubuk | 24 pay
            // Önceki hesapta çizgi ile alt çubuk arasındaki 16 unutulmuştu;
            // bu yüzden panel 16px kısa kalıyor, liste aşağı kayıp çizgiye
            // yapışıyordu (üstte boşluk, altta hiç yok).
            //
            // Math.round: liste yüksekliği animasyon sırasında kesirli değerler
            // alıyor; yuvarlamazsak alt çubuk yarım piksel oynayıp titriyor.
            height: Math.round(24 + searchBar.height + 16 + list.height
                    + 16 + dividerBox.height + 16 + footer.height + 24)
            // NOT: buraya "Behavior on height" KOYMA. Animasyon listenin
            // kendisinde; panel onu anında takip ediyor. İkisi ayrı ayrı
            // animasyonlu olunca liste büyürken panel geriden geliyor ve
            // satırlar alttaki çizgiyi aşıp taşıyordu.
            // NOT: win, tek "bottom" anchor'ı ile yatayda otomatik ortalanıyor.
            // win'e sağdan rightExtra kadar pay eklendiğinde, ortalama yüzünden
            // win'in SOL kenarı da rightExtra/2 kadar sola kayar. Panel'in
            // gerçek ekran konumu değişmesin (hep aynı yerde ortalı kalsın)
            // diye bu kaymayı burada telafi ediyoruz - fazladan alan sadece
            // panelin SAĞINDA kalıyor, tooltip için.
            anchors.leftMargin: win.notchSize + win.rightExtra / 2
            width: win.panelWidth
            // sadece üst köşeler yuvarlak, alt köşeler düz - zemine yapışacak
            // (Qt 6.7+ gerektirir; eski Qt'de hepsi aynı 'radius' değerine döner)
            topLeftRadius: 16
            topRightRadius: 16
            bottomLeftRadius: 0
            bottomRightRadius: 0
            color: "#000000"
            focus: true
            clip: true
            Keys.onEscapePressed: {
                if (root.ctxOpen) { root.ctxOpen = false; return }
                // ilk esc: sadece seçili/hover'lı satırı temizle
                // ikinci esc (zaten seçim yoksa): menüyü kapat
                if (list.currentIndex !== -1) {
                    list.currentIndex = -1
                } else {
                    root.closeMenu()
                }
            }

            // ================= AÇILIŞ / KAPANIŞ ANİMASYONU =================
            // Menü zeminin altından yukarı doğru kayarak giriyor, kapanırken
            // aynı yoldan aşağı inip zeminde kayboluyor. Ölçek/solma yok:
            // saf kayma, kavislerle birlikte tek parça hareket ediyor.
            // Hyprland'in layersIn/Out animasyonu kapalı (windowrule.lua ->
            // hl.layer_rule appmenu_noanim), hareketin tamamı buradan geliyor.
            transform: Translate { y: root.slideY }
            // Kalıcı GPU dokusu: liste, ikonlar, maskeler ve metinler bir kez
            // dokuya çiziliyor, animasyon boyunca sadece bu doku kaydırılıyor.
            layer.enabled: true
            layer.smooth: true

            // panel genelinde gerçek fare hareketini yakalıyoruz - açılışta imlecin
            // zaten durduğu yer değil, GERÇEKTEN hareket ettiği an hoverReady açılıyor
            HoverHandler {
                id: panelMouseTracker
                property point initialPos: Qt.point(-1, -1)
                property bool initialized: false
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onPointChanged: {
                    if (!initialized) {
                        initialPos = point.position
                        initialized = true
                        return
                    }
                    if (root.hoverReady) return
                    const dx = point.position.x - initialPos.x
                    const dy = point.position.y - initialPos.y
                    if (Math.abs(dx) > 2 || Math.abs(dy) > 2) root.hoverReady = true
                }
            }
            // NOT: açılış artık burada tetiklenmiyor. Process kalıcı olduğu
            // için bu blok sadece bir kez (quickshell başlarken) çalışırdı;
            // her açılışta çalışan yer root.openMenu().

            // klavyeden herhangi bir yazılabilir tuşa basılınca arama çubuğunu
            // aktive edip o karakteri direkt arama kutusuna yazıyoruz.
            // yukarı/aşağı ok tuşları listede gezinir, enter seçili uygulamayı açar.
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Up) {
                    root.moveSelection(-1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Down) {
                    root.moveSelection(1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activateCurrent()
                    event.accepted = true
                    return
                }
                if (root.searchActive) return
                if (event.text.length > 0 && event.text.trim().length > 0
                        && event.key !== Qt.Key_Escape
                        && event.key !== Qt.Key_Tab) {
                    root.searchActive = true
                    root.searchText = event.text
                    searchInput.text = event.text
                    searchInput.forceActiveFocus()
                    searchInput.cursorPosition = searchInput.text.length
                    event.accepted = true
                }
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: 24

                Rectangle {
                    id: searchBar
                    anchors.top: parent.top
                    width: parent.width
                    height: 46
                    radius: 10
                    color: "#0a0a0a"
                    border.width: 2

                    // aktif olunca gri'den pywal rengine YUMUŞAKÇA geçiş yapıyor
                    // (activation), bu geçiş sırasında nefes alma (borderPulse) da
                    // zaten arka planda dönüyor - geçiş bitince sorunsuzca ona
                    // devrediyor, ayrı bir "önce fade sonra animasyon" adımı
                    // gerekmiyor, ikisi aynı anda, tek formülle hesaplanıyor
                    readonly property color inactiveColor: "#1c1c1c"
                    property real activation: root.searchActive ? 1 : 0
                    Behavior on activation { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                    property real borderPulse: 1.0
                    SequentialAnimation on borderPulse {
                        running: root.searchActive
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.45; duration: 2200; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.45; to: 1.0; duration: 2200; easing.type: Easing.InOutSine }
                    }

                    border.color: {
                        const t = activation
                        const r = inactiveColor.r + (root.accentColor.r - inactiveColor.r) * t
                        const g = inactiveColor.g + (root.accentColor.g - inactiveColor.g) * t
                        const b = inactiveColor.b + (root.accentColor.b - inactiveColor.b) * t
                        // t=0'da tam opak gri, t=1'e yaklaştıkça alfa nefes alma
                        // değerine (borderPulse) devrediyor
                        const a = 1.0 + (borderPulse - 1.0) * t
                        return Qt.rgba(r, g, b, a)
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        // arama aktifken sağda çarpı ikonuna yer açıyoruz
                        anchors.rightMargin: root.searchActive ? 34 : 14
                        spacing: 10

                        Text {
                            text: "\uf002" // nf-fa-search
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 16
                            color: root.accentColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        TextInput {
                            id: searchInput
                            width: parent.width - 26
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#e6e6e6"
                            font.pixelSize: 15
                            clip: true
                            onTextChanged: root.searchText = text

                            // odak burada olsa bile ok tuşları/enter panel yerine
                            // buradan garanti şekilde yakalansın
                            Keys.onUpPressed: (event) => { root.moveSelection(-1); event.accepted = true }
                            Keys.onDownPressed: (event) => { root.moveSelection(1); event.accepted = true }
                            Keys.onReturnPressed: (event) => { root.activateCurrent(); event.accepted = true }
                            Keys.onEnterPressed: (event) => { root.activateCurrent(); event.accepted = true }
                        }
                    }

                    Text {
                        // "Uygulama ara..." - sadece boşken görünür, yazınca kaybolur
                        anchors.left: parent.left
                        anchors.leftMargin: 40
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.t("Uygulama Ara", "Search Apps")
                        color: "#7a7a7a"
                        font.pixelSize: 15
                        visible: opacity > 0
                        opacity: searchInput.text.length === 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    // arama aktifken sağ uçta beliren çarpı - tıklayınca arama
                    // temizlenip aktiflik kapanıyor
                    Text {
                        id: clearSearchBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf00d" // nf-fa-close
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 14
                        color: clearSearchArea.containsMouse ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.6)
                        visible: opacity > 0
                        opacity: root.searchActive ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 100 } }

                        MouseArea {
                            id: clearSearchArea
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.text = ""
                                root.searchText = ""
                                root.searchActive = false
                                searchInput.focus = false
                                panel.forceActiveFocus()
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    anchors.top: searchBar.bottom
                    anchors.topMargin: 16
                    width: parent.width
                    // sabit değerler - satır yüksekliğini küçültüp 2 satır daha
                    // sığdırdık, hâlâ basit/öngörülebilir kalıyor
                    readonly property int rowH: 36
                    readonly property int rowSpacing: 7
                    readonly property int rowUnit: rowH + rowSpacing

                    // DİKKAT: üst sınır panel'in değil PENCERE'nin boyundan
                    // hesaplanıyor. Panel artık liste boyuna bakıyor; buradan
                    // da panele bakarsak birbirini besleyen bir döngü oluşur.
                    readonly property real rawAvailable: win.implicitHeight
                        - searchBar.height - footer.height - dividerBox.height - 16 * 3 - 48 - 16
                    readonly property int maxRows: Math.max(1, Math.floor(rawAvailable / rowUnit))

                    // Kaç satır varsa o kadar yer kaplıyor; liste uzunsa üst
                    // sınırda durup kaydırmaya geçiyor.
                    readonly property int visibleRows: Math.max(1, Math.min(list.count, maxRows))
                    height: visibleRows * rowUnit - rowSpacing
                    // Tek animasyon kaynağı burası: panel bu değeri anında
                    // takip ettiği için liste hiçbir an panelin dışına taşmıyor.
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    clip: true
                    model: root.filteredApps
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: -1

                    // scroll (hem ok tuşu hem fare tekerleği) artık her zaman
                    // yumuşak - sertçe/aniden zıplamıyor
                    Behavior on contentY {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }


                    // hover ile currentIndex değiştiğinde ListView otomatik scroll
                    // etmesin - scroll sadece ok tuşlarındaki manuel positionViewAtIndex
                    // çağrısıyla (moveSelection) olsun
                    highlightFollowsCurrentItem: false
                    // model değiştiğinde: eğer AKTİF ARAMA yapılıyorsa (metin girildiyse)
                    // en üstteki sonuç otomatik seçili/hover görünsün. Panel ilk
                    // açıldığında / arama boşken hiçbir şey otomatik seçili olmasın
                    // (bu ayrı bir düzeltmeydi, bozmuyoruz)
                    onModelChanged: {
                        currentIndex = (root.searchText.length > 0 && root.filteredApps.length > 0) ? 0 : -1
                        contentY = 0
                    }
                    Component.onCompleted: contentY = 0
                    spacing: rowSpacing
                    topMargin: 0
                    bottomMargin: 0
                    // fare tekerleğiyle kaydırma zaten Flickable'ın varsayılan davranışı

                    // arama sonuçları değişince satırlar sertçe değil, hafifçe
                    // büyüyerek/solarak yumuşakça belirip kaybolsun; kalanlar
                    // da boşluğu doldururken yumuşakça kaysın
                    // Bu animasyonlar SADECE arama yaparken çalışır. İlk açılışta
                    // (model DesktopEntries'den dolarken) çalışırlarsa 12 satır için
                    // birden animasyon tetikleniyor; bu hem menünün geç açılmasına
                    // hem de listenin konumunun kaymasına sebep oluyordu.
                    add: Transition {
                        enabled: root.searchActive
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    }
                    remove: Transition {
                        enabled: root.searchActive
                        NumberAnimation { property: "opacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
                    }
                    displaced: Transition {
                        enabled: root.searchActive
                        NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
                    }

                    delegate: Rectangle {
                        id: appRow
                        width: list.width
                        height: list.rowH
                        radius: 8
                        color: (list.currentIndex === index) ? "#232323" : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        HoverHandler {
                            id: hoverHandler
                            onHoveredChanged: {
                                // panel açılır açılmaz imleç zaten bir satırın üstündeyse
                                // o satır otomatik "seçili" görünmesin - kullanıcı fareyi
                                // gerçekten oynatana kadar hover'ı yok sayıyoruz
                                if (!root.hoverReady) return
                                if (hovered) list.currentIndex = index
                                else if (list.currentIndex === index) list.currentIndex = -1
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 14

                            Item {
                                width: 32
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter

                                IconImage {
                                    id: appIcon
                                    anchors.fill: parent
                                    implicitSize: 28
                                    asynchronous: true
                                    visible: false
                                    source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                                }

                                Rectangle {
                                    id: appIconMask
                                    anchors.fill: parent
                                    radius: 8
                                    visible: false
                                }

                                OpacityMask {
                                    anchors.fill: parent
                                    source: appIcon
                                    maskSource: appIconMask
                                    visible: appIcon.status === Image.Ready && appIcon.source != ""
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !(appIcon.status === Image.Ready && appIcon.source != "")
                                    text: "\uf2d0" // nf-fa-window_maximize, genel uygulama ikonu
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: 14
                                    color: "#8a8a8a"
                                }
                            }

                            Text {
                                width: parent.width - 28 - 14 - (rowPin.on ? 24 : 0)
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelData.name
                                color: (list.currentIndex === index) ? root.accentColor : "#e6e6e6"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                font.pixelSize: 15
                            }
                        }

                        // dock'a sabitliyse sagda kucuk pywal raptiye ("pit" diye belirir)
                        Text {
                            id: rowPin
                            readonly property bool on: root.isPinned(modelData)
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf08d" // nf-fa-thumb_tack
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 13
                            color: root.accentColor
                            opacity: on ? 1 : 0
                            scale: on ? 1 : 0.2
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (m) => {
                                if (m.button === Qt.RightButton) {
                                    const p = appRow.mapToItem(content, m.x, m.y)
                                    ctxMenu.openAt(modelData, p.x, p.y)
                                } else root.launchApp(modelData)
                            }
                        }
                    }
                }

                // ================= SAG TIK MENUSU: Dock'a sabitle / Dock'tan kaldir =================
                MouseArea {
                    anchors.fill: parent
                    z: 50
                    enabled: root.ctxOpen
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: root.ctxOpen = false
                }
                Rectangle {
                    id: ctxMenu
                    z: 51
                    function openAt(e, px, py) {
                        root.ctxEntry = e
                        x = Math.max(0, Math.min(content.width - width, px))
                        y = Math.max(0, Math.min(content.height - height, py))
                        root.ctxOpen = true
                    }
                    readonly property bool pinned: root.isPinned(root.ctxEntry)
                    width: ctxRow.implicitWidth + 24
                    height: 36
                    radius: 10
                    color: "#0d0d0d"
                    border.width: 1
                    border.color: "#222222"
                    opacity: root.ctxOpen ? 1 : 0
                    visible: opacity > 0.01
                    scale: root.ctxOpen ? 1 : 0.88
                    transformOrigin: Item.TopLeft
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    Row {
                        id: ctxRow
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf08d"
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 13
                            color: root.accentColor
                            rotation: ctxMenu.pinned ? 45 : 0
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ctxMenu.pinned ? root.t("Dock'tan kaldır", "Unpin from dock") : root.t("Dock'a sabitle", "Pin to dock")
                            font.pixelSize: 13
                            color: ctxMa.containsMouse ? root.accentColor : "#e6e6e6"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                    MouseArea {
                        id: ctxMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.togglePin(root.ctxEntry); root.ctxOpen = false }
                    }
                }

                // ================= SONUÇ YOK =================
                // Arama hiçbir uygulamayla eşleşmediğinde liste alanı bomboş
                // kalıyordu. Aynı alanın tam ortasında pywal renginde kısa bir
                // bilgi metni gösteriyoruz.
                Text {
                    anchors.horizontalCenter: list.horizontalCenter
                    anchors.verticalCenter: list.verticalCenter
                    text: root.t("Sonuç bulunamadı", "No results")
                    font.pixelSize: 13
                    color: root.accentColor
                    opacity: (root.searchText.length > 0 && root.filteredApps.length === 0) ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutSine } }
                }

                Item {
                    id: dividerBox
                    anchors.bottom: footer.top
                    anchors.bottomMargin: 16
                    width: parent.width
                    height: 1
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: root.accentColor
                    }
                }

                Row {
                    id: footer
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 40
                    spacing: 12

                    Item {
                        width: 36
                        height: 36
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 2

                        // AnimatedImage kullanıyoruz: sıradan Image bir GIF'in
                        // sadece ilk karesini gösterir, animasyonu oynatmaz.
                        AnimatedImage {
                            id: avatarImg
                            anchors.fill: parent
                            source: "file://" + (root.settings.avatar || (Quickshell.env("HOME") + "/.face"))   // settings.json "avatar": "/yol/resim.gif"
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            asynchronous: true
                            smooth: true
                            antialiasing: true
                            // playing varsayılan olarak true, elle belirtiyoruz
                            playing: true
                            // ================= EN YÜKSEK KALİTE =================
                            // sourceSize BİLEREK BOŞ BIRAKILDI. Sabit bir değer
                            // (ör. 256) verirsek Qt her kareyi o boyuta göre
                            // decode eder; GIF'in gerçek çözünürlüğü daha
                            // büyükse detay kaybedilir, daha küçükse gereksiz
                            // büyütme (bulanıklaşma) olur. Boş bırakınca Qt
                            // GIF'i KENDİ orijinal çözünürlüğünde decode edip
                            // 34px'lik daireye ölçekliyor - mümkün olan en
                            // net sonuç bu.
                            //
                            // NOT: GIF çok büyükse (900px+ kare) bu biraz daha
                            // fazla bellek/CPU kullanır. Panel açılışında
                            // fark edilir bir gecikme olursa sourceSize'ı
                            // GIF'in gerçek boyutunun yarısına sabitlemek
                            // iyi bir orta yol olur.
                        }

                        Rectangle {
                            id: avatarMaskShape
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                            // maskenin kenarı pürüzlü olunca resim de
                            // pikselli görünüyordu
                            antialiasing: true
                            smooth: true
                            layer.enabled: true
                            layer.smooth: true
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: avatarImg
                            maskSource: avatarMaskShape
                            visible: avatarImg.status === Image.Ready
                            antialiasing: true
                            layer.enabled: true
                            layer.smooth: true
                        }

                        // pfp yüklenemezse basit fallback
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "#2a2a2a"
                            visible: avatarImg.status !== Image.Ready
                            Text {
                                anchors.centerIn: parent
                                text: "\uf007" // nf-fa-user
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 15
                                color: "#9a9a9a"
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 2
                        width: parent.width - 34 - 34 - 34 - parent.spacing * 3
                        text: root.userName
                        color: root.accentColor
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }

                    // hyprland.lua'yı kitty+nano ile açan kısayol - gri hover yok,
                    // sadece sembol kendisi hover'da pywal rengiyle parlıyor
                    Item {
                        width: 36
                        height: 36
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 2

                        Text {
                            id: terminalIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenterOffset: 5
                            anchors.verticalCenterOffset: -1
                            text: "󰓎"
                            font.pixelSize: 22
                            scale: 1.0
                            transformOrigin: Item.Center

                            // 0 = tam oled siyahı, 1 = tam pywal rengi - ikisi
                            // arasında nefes alıyor (siyah zaten (0,0,0) olduğu
                            // için accent'i mix ile çarpmak yeterli)
                            property real breatheMix: 1.0
                            // zıplarken tam büyüdüğü an bu 1'e çıkıp sarıya
                            // karışıyor, küçülürken 0'a inip normale dönüyor
                            property real bounceFlash: 0.0
                            color: {
                                const base = Qt.rgba(root.accentColor.r * breatheMix, root.accentColor.g * breatheMix, root.accentColor.b * breatheMix, 1.0)
                                const yr = 1.0, yg = 0.82, yb = 0.15 // sarı
                                return Qt.rgba(
                                    base.r + (yr - base.r) * bounceFlash,
                                    base.g + (yg - base.g) * bounceFlash,
                                    base.b + (yb - base.b) * bounceFlash,
                                    1.0
                                )
                            }

                            SequentialAnimation {
                                id: terminalBounce
                                ParallelAnimation {
                                    NumberAnimation { target: terminalIcon; property: "scale"; to: 1.3; duration: 240; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: terminalIcon; property: "bounceFlash"; to: 1.0; duration: 240; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: terminalIcon; property: "scale"; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                                    NumberAnimation { target: terminalIcon; property: "bounceFlash"; to: 0.0; duration: 320; easing.type: Easing.OutQuad }
                                }
                            }

                            // yavaş, yumuşak nefes alma - siyah <-> pywal
                            SequentialAnimation {
                                id: terminalBreathe
                                loops: Animation.Infinite
                                NumberAnimation { target: terminalIcon; property: "breatheMix"; to: 0.2; duration: 1400; easing.type: Easing.InOutSine }
                                NumberAnimation { target: terminalIcon; property: "breatheMix"; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                            }
                        }

                        // nefes alma, zıplama animasyonu (240+320=560ms) BİTTİKTEN
                        // sonra başlasın diye gecikmeli tetikleniyor
                        Timer {
                            id: terminalBreatheDelay
                            interval: 560
                            onTriggered: terminalBreathe.start()
                        }

                        HoverHandler {
                            id: terminalHover
                            onHoveredChanged: {
                                if (hovered) {
                                    terminalBounce.restart()
                                    terminalBreatheDelay.restart()
                                } else {
                                    terminalBreatheDelay.stop()
                                    terminalBreathe.stop()
                                    terminalIcon.breatheMix = 1.0
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["firefox", "https://animecix.tv/"])
                        }
                    }

                    Item {
                        id: settingsBox
                        width: 34
                        height: 34
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 2

                        Text {
                            id: settingsIcon
                            anchors.centerIn: parent
                            text: "\uf013" // nf-fa-cog
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 17
                            scale: 1.0
                            rotation: 0
                            transformOrigin: Item.Center

                            property real breatheMix: 1.0
                            color: Qt.rgba(root.accentColor.r * breatheMix, root.accentColor.g * breatheMix, root.accentColor.b * breatheMix, 1.0)

                            SequentialAnimation {
                                id: settingsBounce
                                NumberAnimation { target: settingsIcon; property: "scale"; to: 1.3; duration: 240; easing.type: Easing.OutQuad }
                                NumberAnimation { target: settingsIcon; property: "scale"; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                            }
                            NumberAnimation {
                                id: settingsSpin
                                target: settingsIcon
                                property: "rotation"
                                from: 0
                                to: 360
                                duration: 700
                                easing.type: Easing.InOutCubic
                            }
                            SequentialAnimation {
                                id: settingsBreathe
                                loops: Animation.Infinite
                                NumberAnimation { target: settingsIcon; property: "breatheMix"; to: 0.2; duration: 1400; easing.type: Easing.InOutSine }
                                NumberAnimation { target: settingsIcon; property: "breatheMix"; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                            }
                        }

                        // nefes alma, zıplama (560ms) VE dönme (700ms) - hangisi
                        // daha uzunsa - bittikten sonra başlasın
                        Timer {
                            id: settingsBreatheDelay
                            interval: 700
                            onTriggered: settingsBreathe.start()
                        }

                        HoverHandler {
                            id: settingsHover
                            onHoveredChanged: {
                                if (hovered) {
                                    settingsBounce.restart()
                                    settingsIcon.rotation = 0
                                    settingsSpin.restart()
                                    settingsBreatheDelay.restart()
                                } else {
                                    settingsBreatheDelay.stop()
                                    settingsBreathe.stop()
                                    settingsIcon.breatheMix = 1.0
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // sistemde ayrı bir "ayarlar" uygulaması yok -
                            // asıl "beyin" hyprland.lua olduğu için doğrudan
                            // onu kitty+nano ile açıyoruz
                            onClicked: Quickshell.execDetached(["bash", "-c", "kitty nano ~/.config/hypr/hyprland.lua"])
                        }
                    }
                }
            }
        }
    }
}
