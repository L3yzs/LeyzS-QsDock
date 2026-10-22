import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import Quickshell.Services.Mpris
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

    // waybar başlarken dosya hiç yoksa diye, açılışta bir kere yazıyoruz
    Component.onCompleted: { root.updateWaybarStatus(); Qt.callLater(root.exportList); }

    // ================= PYWAL RENGİ =================
    property color accentColor: "#ffffff"

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

    // ================= BAGLANTI BORULARI =================
    // Kutular arasindaki 8px bosluklarda, kutulari birbirine baglayan kisa
    // duz siyah borular. Borular kutularin ARKASINDA durup biraz icine girer;
    // boylece sadece bosluktaki kismi gorunur ve kutulara kaynamis gibi durur.
    // Kutular acilip kapanirken farkli hizlarda kaydigi icin her boru iki
    // kutunun anlik konumuna gore uzayip kisaliyor, hic kopmuyor.
    readonly property int pipeThick: 12

    component VPipe: Rectangle {
        property real cx: 0
        property real topY: 0
        property real bottomY: 0
        property bool active: true
        property real phase: 0
        z: -2
        x: Math.round(cx - width / 2)
        y: topY - 4
        width: root.pipeThick
        height: Math.max(0, bottomY - topY + 8)
        visible: active && bottomY - topY > 0.5
        color: "#000000"
    }
    component HPipe: Rectangle {
        property real cy: 0
        property real leftX: 0
        property real rightX: 0
        property bool active: true
        property real phase: 0
        z: -2
        y: Math.round(cy - height / 2)
        x: leftX - 4
        height: root.pipeThick
        width: Math.max(0, rightX - leftX + 8)
        visible: active && rightX - leftX > 0.5
        color: "#000000"
    }

    // ================= AYARLAR =================
    // DND durumu sıradan bir property olduğu için quickshell kapanınca
    // kayboluyordu. Diske yazıp açılışta geri okuyoruz: PC kapanıp açılsa,
    // panel yeniden başlasa bile son bırakıldığı halde kalıyor.
    property bool dndEnabled: false
    property bool dndLoaded: false

    readonly property string dndStatePath: Quickshell.env("HOME") + "/.cache/quickshell/dnd_state"

    // Kayıtlı durumu açılışta okuyoruz. FileView bu iş için güvenilir
    // çalışmadı (dosyayı okumadan geçiyordu), o yüzden doğrudan cat ile
    // okuyup çıktısını topluyoruz.
    Process {
        id: dndLoadProcess
        running: true
        command: ["sh", "-c", "cat '" + root.dndStatePath + "' 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.dndEnabled = text.trim() === "1";
                root.dndLoaded = true;
                root.updateWaybarStatus();
            }
        }
    }

    // DİKKAT: command'i binding olarak bırakmıyoruz. running=true dendiğinde
    // binding henüz güncellenmemiş olabiliyor ve diske ESKİ değer yazılıyordu.
    // Bu yüzden komut, kaydetme anında elle kuruluyor (updateWaybarStatus'ta
    // olduğu gibi).
    Process {
        id: dndSaveProcess
    }

    function saveDndState() {
        dndSaveProcess.command = [
            "sh", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && printf '%s' '"
            + (root.dndEnabled ? "1" : "0") + "' > '" + root.dndStatePath + "'"
        ];
        dndSaveProcess.running = true;
    }

    readonly property int toastDurationMs: 3000
    // Aynı anda gelen toast'lar arasındaki çıkış gecikmesi. Öndeki kartın
    // çıkış animasyonu (toastExitMs) + listenin kapanması kadar bekliyoruz ki
    // sıradaki kart ancak öndeki tamamen gidip yeri kapandıktan sonra çıksın.
    readonly property int toastStaggerMs: 380
    readonly property int toastWidth: 340

    // ================= GİRİŞ ANİMASYONU TAKİBİ =================
    // Yeni bildirim gelince grup listesi baştan hesaplanıyor ve ListView
    // TÜM kartları yok edip yeniden kuruyor. Hepsi sıfır yükseklikten
    // doğarsa panel önce çöküp sonra büyüyor. Bu yüzden daha önce
    // gösterilmiş bildirimleri hatırlıyoruz: onlar anında tam boyutta
    // gelir, sadece gerçekten yeni olan kart süzülerek belirir.
    property var seenIds: ({})
    property var seenGroups: ({})

    function isSeen(id) {
        return root.seenIds[id] === true;
    }

    function markSeen(id) {
        root.seenIds[id] = true;
    }

    // Grup daha önce ekranda var mıydı? Varsa o grubun baş kartı, içeriği
    // yeni bildirimle değişse bile animasyonsuz gelir: kartın yeri zaten
    // duruyordu, sıfırdan açılırsa panel önce çöküp sonra büyüyor.
    function isGroupSeen(key) {
        return root.seenGroups[key] === true;
    }

    function markGroupSeen(key) {
        root.seenGroups[key] = true;
    }

    // Grubun baş kartının bilinen yüksekliği. Aynı uygulamadan gelen
    // bildirimler benzer boyda olduğu için, yeni kart daha ilk karede
    // doğru ölçüyle doğsun diye saklıyoruz.
    property var groupHeights: ({})

    function knownGroupHeight(key) {
        const h = root.groupHeights[key];
        return (h && h > 1) ? h : 64;
    }

    function rememberGroupHeight(key, h) {
        if (h > 1) root.groupHeights[key] = h;
    }

    // ================= BİLDİRİM GRUPLAMA =================
    // Aynı uygulamadan gelen bildirimleri tek bir "yığın" kartında topluyoruz.
    // Hangi grupların açık (expanded) olduğunu appName -> bool şeklinde tutuyoruz.
    property var expandedGroups: ({})

    function toggleGroup(key) {
        const copy = Object.assign({}, root.expandedGroups);
        copy[key] = !copy[key];
        root.expandedGroups = copy;
    }

    function isGroupExpanded(key) {
        return root.expandedGroups[key] === true;
    }

    // notifCount'a bağlı: bildirim eklenince/silinince yeniden hesaplanır
    function buildGroups() {
        const list = notifServer.trackedNotifications.values;
        const groups = [];
        const indexByKey = {};
        for (let i = 0; i < list.length; i++) {
            const n = list[i];
            const key = n.appName || "unknown";
            if (indexByKey[key] === undefined) {
                indexByKey[key] = groups.length;
                groups.push({ key: key, items: [n] });
            } else {
                groups[indexByKey[key]].items.push(n);
            }
        }
        return groups;
    }

    // QML renkleri bazen "#aarrggbb" (9 hane) döner; RichText/HTML bunu
    // anlamadığı için alfa kısmını atıp "#rrggbb" haline getiriyoruz.
    function hexColor(c) {
        const s = c.toString();
        return s.length === 9 ? "#" + s.substring(3) : s;
    }

    // ================= İKON ÇÖZÜMLEME =================    // Bazı uygulamalar (ör. GPU Screen Recorder) bildirimde "appIcon" alanını
    // hiç doldurmuyor; onun yerine "desktop-entry" ipucunu ya da sadece
    // uygulama adını gönderiyorlar. Bu yüzden tek bir alana bakmak yerine
    // sırayla: appIcon -> desktop entry -> appName -> ad'ın son parçası
    // şeklinde deneyip ilk bulduğumuz gerçek ikon yolunu döndürüyoruz.
    function resolveIconSource(appIcon, appName, desktopEntry) {
        // 1) Bildirimin kendi verdiği ikon (mutlak yol olabilir)
        if (appIcon && appIcon !== "") {
            if (appIcon.startsWith("file://") || appIcon.startsWith("/"))
                return appIcon;
            const direct = Quickshell.iconPath(appIcon, true);
            if (direct && direct !== "") return direct;
        }

        // 2) Aday isimler: desktop-entry ipucu, uygulama adı ve bunların
        //    sadeleştirilmiş halleri (ör. "com.dec05eba.gpu_screen_recorder"
        //    -> "gpu_screen_recorder" -> "gpu-screen-recorder")
        const raw = [];
        if (desktopEntry && desktopEntry !== "") raw.push(desktopEntry);
        if (appName && appName !== "") raw.push(appName);

        const candidates = [];
        for (let i = 0; i < raw.length; i++) {
            const v = raw[i];
            candidates.push(v);
            candidates.push(v.toLowerCase());
            const tail = v.split(".").pop();
            if (tail && tail !== v) {
                candidates.push(tail);
                candidates.push(tail.toLowerCase());
                candidates.push(tail.toLowerCase().replace(/_/g, "-"));
            }
            candidates.push(v.toLowerCase().replace(/ /g, "-"));
        }

        // 2a) Önce .desktop dosyalarından gerçek ikon adını bulmayı dene
        for (let i = 0; i < candidates.length; i++) {
            try {
                const entry = DesktopEntries.heuristicLookup(candidates[i]);
                if (entry && entry.icon) {
                    const p = Quickshell.iconPath(entry.icon, true);
                    if (p && p !== "") return p;
                }
            } catch (e) {}
        }

        // 2b) Olmadıysa adayları doğrudan ikon teması adı gibi dene
        for (let i = 0; i < candidates.length; i++) {
            const p = Quickshell.iconPath(candidates[i], true);
            if (p && p !== "") return p;
        }

        // 3) Hiçbiri tutmadı - çağıran taraf zil ikonuna düşecek
        return "";
    }

    // ================= BİLDİRİM SUNUCUSU =================
    NotificationServer {
        id: notifServer
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true
        keepOnReload: true

        onNotification: notification => {
            notification.tracked = true
            root.notifTimes[notification.id] = Date.now()
            // Dock seciliyken balonu dock gosteriyor (dock bildirim kutusuna donusur)
            if (!root.dndEnabled && (root.barSel !== "dock" && root.barSel !== "qsisland")) {
                root.pushToast(notification)
            }
            root.updateWaybarStatus()
            Qt.callLater(root.exportList)
        }
    }

    // ================= QsNotch ICIN DISA AKTARIM =================
    // Bildirim sunucusu sistemde tek olabildigi icin QsNotch bildirimleri
    // buradan okuyor: liste her degistiginde kucuk bir JSON'a yaziliyor,
    // centik silme / temizleme / rahatsiz etme icin asagidaki IPC'leri cagiriyor.
    property var notifTimes: ({})
    readonly property string listPath: Quickshell.env("HOME") + "/.cache/quickshell/notif-list.json"
    function exportList() {
        const list = notifServer.trackedNotifications.values;
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const n = list[i];
            let img = n.image || "";
            // image://qsimage/... sadece bu surecte gecerli; disari yalnizca dosya yolu
            if (img !== "" && !(img.startsWith("file://") || img.startsWith("/"))) img = "";
            let icon = "";
            try { icon = root.resolveIconSource(n.appIcon, n.appName, n.desktopEntry) || ""; } catch (e) {}
            let hasDefault = false;
            const acts = n.actions || [];
            for (let k = 0; k < acts.length; k++) if (acts[k].identifier === "default") hasDefault = true;
            out.push({
                id: n.id, app: n.appName || root.t("Bildirim", "Notification"), summary: n.summary || "", body: n.body || "",
                image: img, icon: icon, time: root.notifTimes[n.id] || Date.now(), action: hasDefault
            });
        }
        const json = JSON.stringify({ dnd: root.dndEnabled, items: out });
        listWriter.command = ["sh", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && printf '%s' \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"",
            "sh", json, root.listPath];
        listWriter.running = true;
    }
    Process { id: listWriter; running: false }
    function findNotif(id) {
        const list = notifServer.trackedNotifications.values;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return null;
    }

    // ================= WAYBAR DURUM BİLDİRİMİ =================
    // waybar'daki zil ikonunun rengini (sarı/normal) ve DND durumunu
    // canlı yansıtmak için: durumu küçük bir JSON dosyasına yazıp,
    // waybar'a özel bir sinyal (RTMIN+8) gönderiyoruz - waybar bunu
    // görünce modülü ANINDA yeniden okuyor, poll beklemesine gerek yok.
    readonly property int notifCount: notifServer.trackedNotifications.values.length

    onNotifCountChanged: { root.updateWaybarStatus(); Qt.callLater(root.exportList); }

    onDndEnabledChanged: {
        root.updateWaybarStatus();
        Qt.callLater(root.exportList);
        if (root.dndLoaded) root.saveDndState();
    }

    function updateWaybarStatus() {
        const cls = root.notifCount > 0
            ? (root.dndEnabled ? "dnd-notification" : "notification")
            : (root.dndEnabled ? "dnd-none" : "none")
        // ÖNEMLİ: waybar {icon} yer tutucusu ikonu "class" değil "alt"
        // alanına bakarak seçiyor - bunu unutmuşum, ikonun hiç değişmemesinin
        // asıl sebebi buydu. İkisini de aynı değerle yazıyoruz.
        const json = JSON.stringify({ text: "", alt: cls, class: cls, tooltip: root.notifCount + root.t(" Bildirim", " Notifications") })
        const escaped = json.replace(/'/g, "'\\''")
        statusWriter.command = [
            "bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && printf '%s\\n' '" + escaped + "' > \"$HOME/.cache/quickshell/notif-status.json\" && pkill -RTMIN+8 waybar 2>/dev/null"
        ]
        statusWriter.running = true
    }

    Process {
        id: statusWriter
        running: false
    }

    // ================= TOAST KUYRUĞU =================
    ListModel { id: toastModel }

    readonly property int toastExitMs: 220

    function pushToast(notification) {
        if (historyWin.visible) return;
        // Aynı bildirim güncellenip tekrar gelirse (aynı id) kuyrukta iki
        // kopya oluşuyor ve kimlik araması ilk bulduğunu siliyor - yanlış
        // toast kayboluyordu. Yenisini eklemeden önce eskisini düşürüyoruz.
        for (let i = toastModel.count - 1; i >= 0; i--) {
            if (toastModel.get(i).notifId === notification.id) {
                toastModel.remove(i);
            }
        }
        toastModel.append({
            notifId: notification.id,
            appName: notification.appName || root.t("Bildirim", "Notification"),
            appIcon: notification.appIcon || "",
            desktopEntry: notification.desktopEntry || "",
            image: notification.image || "",
            summary: notification.summary || "",
            body: notification.body || "",
            removing: false
        });
        toastLimiter.createObject(root, { notifId: notification.id });
    }

    function startToastExit(i) {
        if (i < 0 || i >= toastModel.count) return;
        // Zaten çıkışa geçmişse tekrar tetikleme: aynı toast için iki kez
        // çıkış başlarsa iki kez silme denenir ve yanlış öğe kaldırılır
        // (kullanıcı X'e basarken süresi de dolmuş olabiliyor).
        if (toastModel.get(i).removing) return;
        const id = toastModel.get(i).notifId;
        toastModel.setProperty(i, "removing", true);
        toastExitTimer.createObject(root, { notifId: id });
    }

    Component {
        id: toastExitTimer
        Timer {
            // DİKKAT: index değil KİMLİK saklanıyor. Çıkış animasyonu sürerken
            // başka bir toast kaldırılırsa indeksler kayıyor ve sabit tutulan
            // index yanlış öğeyi siliyordu - art arda birkaç bildirim gelince
            // toast'ların birbirine girmesinin sebebi buydu.
            property int notifId: -1
            interval: root.toastExitMs
            running: true
            onTriggered: {
                for (let i = 0; i < toastModel.count; i++) {
                    if (toastModel.get(i).notifId === notifId) {
                        toastModel.remove(i);
                        break;
                    }
                }
                destroy();
            }
        }
    }

    Component {
        id: toastLimiter
        Timer {
            property int notifId: -1
            interval: root.toastDurationMs
            running: true
            onTriggered: {
                for (let i = 0; i < toastModel.count; i++) {
                    if (toastModel.get(i).notifId === notifId) {
                        // Art arda gelen toast'lar aynı anda yok olmasın:
                        // en alttaki (en son gelen) ilk çıkar, yukarıdakiler
                        // sırayla onu takip eder. Alttaki gidince üsttekiler
                        // zaten aşağı kayıyor, bu yüzden akış aşağı doğru
                        // ilerliyormuş gibi görünüyor.
                        const delay = (toastModel.count - 1 - i) * root.toastStaggerMs;
                        if (delay > 0) {
                            toastStaggerTimer.createObject(root, { notifId: notifId, interval: delay });
                        } else {
                            root.startToastExit(i);
                        }
                        break;
                    }
                }
                destroy();
            }
        }
    }

    // Sıradaki toast'ın çıkışını geciktiren yardımcı zamanlayıcı
    Component {
        id: toastStaggerTimer
        Timer {
            property int notifId: -1
            running: true
            onTriggered: {
                for (let i = 0; i < toastModel.count; i++) {
                    if (toastModel.get(i).notifId === notifId) {
                        root.startToastExit(i);
                        break;
                    }
                }
                destroy();
            }
        }
    }

    function dismissToastAt(index) {
        root.startToastExit(index);
    }

    // Tümünü temizlerken kartlar bir anda yok olmasın: önce hepsi birlikte
    // erisin, animasyon bitince gerçekten kaldırılsınlar.
    property bool clearingAll: false
    // ikinci aşama: kartlar solduktan sonra yükseklikleri de kapanır
    property bool clearCollapsing: false

    function clearAllNotifications() {
        if (root.clearingAll) return;
        if (notifServer.trackedNotifications.values.length === 0) return;
        root.clearingAll = true;
        clearFadeTimer.start();
    }

    // 1. adım: solma bitti, şimdi yer kapansın
    Timer {
        id: clearFadeTimer
        interval: 460
        onTriggered: {
            root.clearCollapsing = true;
            clearRemoveTimer.start();
        }
    }

    // 2. adım: yer de kapandı, artık modelden kaldırılabilir
    Timer {
        id: clearRemoveTimer
        interval: 400
        onTriggered: {
            const list = notifServer.trackedNotifications.values;
            for (let i = list.length - 1; i >= 0; i--) {
                list[i].tracked = false;
            }
            root.clearingAll = false;
            root.clearCollapsing = false;
        }
    }

    // ================= IPC HANDLER =================
    // ================= AÇILIŞ / KAPANIŞ ANİMASYONU =================
    // Panel zeminin altından yukarı kayarak açılıyor, kapanırken aynı yoldan
    // aşağı inip kayboluyor (app menüsüyle aynı his).
    // Hyprland'in kendi layer animasyonu windowrule.lua'daki hl.layer_rule
    // ile kapatıldığı için hareketin tamamı buradan geliyor.
    property bool panelOpen: false
    // Kapalı konum: panelin kendi boyu kadar aşağıda. Sabit 640 verilince
    // panel (çoğu zaman ~220px) gereğinden çok yol kat ediyor ve aynı sürede
    // daha hızlı görünüyordu; mesafeyi panele bağlayınca hız hoparlör
    // menüsündeki hisle aynı oluyor.
    property real slideY: panelOpen ? 0 : (panel.height + 24)
    // Sure acikca set ediliyor: panelOpen'a baglanirsa binding, degisiklik
    // animasyona ulasmadan once okunuyor ve acilis/kapanis yer degistiriyor.
    property int slideDuration: 420

    Behavior on slideY {
        NumberAnimation {
            id: panelSlideAnim
            duration: root.slideDuration
            easing.type: Easing.OutCubic
        }
    }

    // ================= SPOTIFY MEDYA KARTI =================
    // Sadece Spotify: Mpris'teki oyunculardan adi/dbus adi "spotify" olan.
    // Firefox/YouTube gibi diger medya kaynaklari gosterilmez.
    readonly property var spotifyPlayer: {
        const ps = Mpris.players.values;
        for (let i = 0; i < ps.length; i++) {
            const p = ps[i];
            const ident = (p.identity || "").toLowerCase();
            const dbus = (p.dbusName || "").toLowerCase();
            if (ident.indexOf("spotify") >= 0 || dbus.indexOf("spotify") >= 0) return p;
        }
        return null;
    }
    readonly property bool mediaShown: root.spotifyPlayer !== null
        && (root.spotifyPlayer.trackTitle || "") !== ""

    // Kart panelin USTUNDE durdugu icin kapanirken daha uzun yol gitmeli.
    // Panelle ayni anda yola cikip ayni anda varsin diye kaymayi orantili
    // buyutuyoruz: acilirken kart panelin arkasindan yukari cikiyor gibi.
    readonly property real mediaSlideY: (panel.height + 24) > 0
        ? root.slideY * (panel.height + 24 + mediaCard.height + 8) / (panel.height + 24)
        : 0

    // ================= CALAN PLAYLIST =================
    // MPRIS playlist bilgisini vermiyor. Spotify'in icindeki Spicetify
    // eklentisi (leyzsPlaylist.js) bilgiyi 127.0.0.1:38145'e yolluyor; bu
    // dosyanin yanindaki kucuk python dinleyici de her degisikligi tek satir
    // JSON olarak basiyor. Dinleyiciyi quickshell kendisi baslatiyor.
    property string plType: ""
    property string plName: ""
    property string plImage: ""
    readonly property bool playlistShown: root.mediaShown && root.plName !== ""
    // playlist kapagi buyutulmus mu (kapaga tiklayinca)
    property bool plZoom: false
    function plBigArt(u) {
        // mozaik kapaklar 300px geliyor; buyuk halde 640px olani iste
        return (u || "").replace("mosaic.scdn.co/300/", "mosaic.scdn.co/640/")
                        .replace("ab67616d00004851", "ab67616d0000b273")
                        .replace("ab67616d00001e02", "ab67616d0000b273");
    }

    readonly property string plScript: {
        const u = Qt.resolvedUrl("spotify-playlist-listener.py").toString();
        return decodeURIComponent(u.replace(/^file:\/\//, ""));
    }

    Process {
        id: plListener
        running: true
        command: ["python3", root.plScript]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const j = JSON.parse(data);
                    root.plType = j.type || "";
                    root.plName = j.name || "";
                    root.plImage = j.image || "";
                } catch (e) {}
            }
        }
        // kapanirsa (port mesgul vs.) birkac saniye sonra tekrar dene
        onExited: plRestart.start()
    }
    Timer {
        id: plRestart
        interval: 4000
        onTriggered: plListener.running = true
    }

    // ================= SPOTIFY SES SEVIYESI (PipeWire) =================
    // Sadece Spotify'in kendi ses akisi: sistem sesine dokunmaz.
    readonly property var spotifyNode: {
        const ns = Pipewire.nodes.values;
        for (let i = 0; i < ns.length; i++) {
            const n = ns[i];
            if (!n || !n.isStream) continue;
            const pr = n.properties || {};
            const hay = ((n.name || "") + " " + (n.description || "") + " "
                + (pr["application.name"] || "") + " " + (pr["application.process.binary"] || "")).toLowerCase();
            if (hay.indexOf("spotify") >= 0) return n;
        }
        return null;
    }
    // stream node'larinin ozellikleri (application.name vs.) ancak takip
    // edilince dolu geliyor; ses akislari az oldugu icin hepsini izliyoruz
    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(n => n && n.isStream)
    }
    readonly property bool spVolReady: root.spotifyNode !== null && root.spotifyNode.audio !== null
    readonly property real spVolume: root.spVolReady ? root.spotifyNode.audio.volume : 0
    readonly property bool spMuted: root.spVolReady && root.spotifyNode.audio.muted
    function setSpotifyVolume(v) {
        if (!root.spVolReady) return;
        const c = Math.max(0, Math.min(1, v));
        root.spWanted = c;
        root.spotifyNode.audio.volume = c;
        if (c > 0 && root.spotifyNode.audio.muted) root.spotifyNode.audio.muted = false;
        // Spotify'in kendi ses ayarina da yaz: yeni akis acinca bunu kullaniyor
        const pl = root.spotifyPlayer;
        if (pl && pl.volumeSupported && pl.canControl) {
            try { pl.volume = c; } catch (e) {}
        }
    }

    // Spotify sarki degisince / ileri sarilinca ses akisini yeniden acip
    // sesi 100'e cekiyor. Kullanicinin istedigi seviyeyi hatirliyoruz;
    // bu olaylardan hemen sonraki kisa surede ses kendiliginden degisirse
    // geri koyuyoruz. Disarida (Spotify'in kendi cubugundan vs.) yapilan
    // degisiklikler ise yeni istenen seviye sayiliyor.
    property real spWanted: -1
    property bool spGuard: false
    function armVolumeGuard() { root.spGuard = true; spGuardTimer.restart(); }
    Timer {
        id: spGuardTimer
        interval: 2500
        onTriggered: root.spGuard = false
    }
    Timer {
        id: spReapply
        interval: 60
        onTriggered: {
            if (root.spVolReady && root.spWanted >= 0
                    && Math.abs(root.spotifyNode.audio.volume - root.spWanted) > 0.005)
                root.spotifyNode.audio.volume = root.spWanted;
        }
    }
    onSpotifyNodeChanged: { root.armVolumeGuard(); spReapply.restart(); }
    onSpVolReadyChanged: if (root.spVolReady) { root.armVolumeGuard(); spReapply.restart(); }
    Connections {
        target: root.spVolReady ? root.spotifyNode.audio : null
        function onVolumeChanged() {
            const v = root.spotifyNode.audio.volume;
            if (root.spWanted < 0) return;
            if (root.spGuard) {
                if (Math.abs(v - root.spWanted) > 0.005) spReapply.restart();
            } else if (Math.abs(v - root.spWanted) > 0.005) {
                root.spWanted = v;
            }
        }
    }

    // Playlist karti media kartinin da ustunde: kayma yolu ikisini de kapsasin
    readonly property real playlistSlideY: (panel.height + 24) > 0
        ? root.slideY * (panel.height + 24 + mediaCard.height + 8 + playlistCard.height + 8) / (panel.height + 24)
        : 0

    function hiResArt(u) {
        if (!u) return "";
        // i.scdn.co kapak boyut kodlari: 4851=64px, 1e02=300px, b273=640px
        return u.replace("ab67616d00004851", "ab67616d0000b273")
                .replace("ab67616d00001e02", "ab67616d0000b273");
    }

    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec || 0));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    function openHistory() {
        if (root.panelOpen) return;
        root.slideDuration = 420;
        historyWin.visible = true;
        panelStartTimer.start();
    }

    function closeHistory() {
        if (!root.panelOpen) return;
        root.slideDuration = 260;
        root.panelOpen = false;
        panelHideTimer.start();
    }

    function toggleHistory() {
        if (root.panelOpen) root.closeHistory();
        else root.openHistory();
    }

    Timer {
        id: panelStartTimer
        // pencere haritalansın, sonra hareket başlasın
        interval: 16
        onTriggered: root.panelOpen = true
    }

    Timer {
        id: panelHideTimer
        // kapanış animasyonu bitmeden gizlersek panel yarı yolda yok oluyor
        interval: 280
        onTriggered: historyWin.visible = false
    }

    // secili bar (kontrol panelinden): "dock" ise balonlar ve panel dock'ta
    property string barSel: ""
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/bar-choice"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.barSel = text().trim()
    }

    // ---- Dock seciliyken bildirim paneli dock'ta acilir ----
    // (kontrol panelindeki bar secimi "dock" ise bu panel acilmaz, dock bildirim paneline donusur)
    Process {
        id: barCheck
        property string want: ""
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/bar-choice\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "qsbar") Quickshell.execDetached(["qs", "-c", "qsbar", "ipc", "call", "qsbar", "notif"]);
                else if (this.text.trim() === "qsisland") Quickshell.execDetached(["qs", "-c", "qsisland", "ipc", "call", "ada", "notif"]);
                else if (this.text.trim() === "dock") Quickshell.execDetached(["qs", "-c", "dock", "ipc", "call", "dock", "notif"]);
                else if (barCheck.want === "toggle") root.toggleHistory();
                else root.openHistory();
            }
        }
    }
    function routeOpen(w) {
        if (root.panelOpen) { if (w === "toggle") root.closeHistory(); return; }
        barCheck.want = w;
        barCheck.running = true;
    }

    IpcHandler {
        target: "notifcenter"
        function toggle(): void { root.routeOpen("toggle") }
        function show(): void { root.routeOpen("show") }
        function hide(): void { root.closeHistory() }
        // ---- QsNotch ----
        function dismiss(id: int): void { const n = root.findNotif(id); if (n) n.tracked = false; }
        function dismissApp(app: string): void {
            const list = notifServer.trackedNotifications.values;
            for (let i = list.length - 1; i >= 0; i--) if ((list[i].appName || root.t("Bildirim", "Notification")) === app) list[i].tracked = false;
        }
        function clearAll(): void {
            const list = notifServer.trackedNotifications.values;
            for (let i = list.length - 1; i >= 0; i--) list[i].tracked = false;
        }
        // varsayilan eylemi calistir (tiklayinca uygulamaya gitsin) ve bildirimi kaldir
        function invoke(id: int): void {
            const n = root.findNotif(id);
            if (!n) return;
            const acts = n.actions || [];
            for (let k = 0; k < acts.length; k++) if (acts[k].identifier === "default") { acts[k].invoke(); break; }
            if (n.tracked) n.tracked = false;
        }
        function setDnd(on: bool): void { root.dndEnabled = on }
        function toggleDnd(): void { root.dndEnabled = !root.dndEnabled }
        function refresh(): void { root.exportList() }
    }

    // ================= TOAST PENCERESİ (TAM KONTROL ALANI) =================
    PanelWindow {
        id: toastWin
        // Tüm ekranı kaplayan şeffaf katman sayesinde animasyonlar dışarı taşarken kesilmez
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notif-toast"
        exclusionMode: ExclusionMode.Ignore
        // ÖNEMLİ: pencere artık tüm ekranı kapladığı için, bu satır olmadan
        // GÖRÜNMEZ olsa bile TÜM EKRANIN fare tıklamalarını yakalıyordu -
        // "hiçbir yere tıklayamıyorum, sanki pencere hâlâ açık" hissi tam
        // buydu. Artık sadece toastList'in kendi sınırları tıklanabilir,
        // ekranın geri kalanındaki tüm tıklamalar normal şekilde altındaki
        // pencerelere geçiyor.
        mask: Region { item: toastList }

        ListView {
            id: toastList
            // Sağ alt köşeye konumlandırıyoruz - kenar boşlukları
            // bildirim merkeziyle (ve hoparlör menüsüyle) aynı olsun ki
            // toast kapanıp panel açıldığında aynı hizada dursunlar
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.bottomMargin: 8
            anchors.rightMargin: 8
            width: root.toastWidth
            height: contentHeight
            // Kart kaldırıldıktan sonra üstteki HIZLICA onun yerine geçsin.
            // Uzun bir animasyon verilince kart yavaş yavaş aşağı süzülüyor,
            // istenen "yerine geçme" hissi kayboluyordu. Kısa tutuyoruz ki
            // asıl görünen animasyon kartın kendi çıkışı olsun.
            Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
            clip: false
            interactive: false
            spacing: 10
            verticalLayoutDirection: ListView.TopToBottom
            model: toastModel

            // NOT: displaced Transition YOK. Liste zaten alta sabit olduğu
            // için bir kart gidince kalanlar kendiliğinden aşağı kayıyor;
            // ayrıca displaced eklenince hareket ikiye bölünüp yavaşlıyordu.

            delegate: Rectangle {
                id: toastCard
                width: toastList.width
                height: toastLayout.implicitHeight + 24
                radius: 14
                // Üzerine gelince hafifçe açılsın - tıklanabilir olduğu belli olsun
                color: toastHover.hovered ? "#181818" : "#0a0a0a"
                Behavior on color { ColorAnimation { duration: 140 } }

                HoverHandler {
                    id: toastHover
                    cursorShape: Qt.PointingHandCursor
                }

                // Tam alttan yukarı süzülme ve aşağı inerek kaybolma mesafesi
                property real slideOffset: 60
                property bool isRemoving: removing
                opacity: 0
                transform: Translate { y: toastCard.slideOffset }

                Component.onCompleted: {
                    opacity = 1;
                    slideOffset = 0;
                }

                onIsRemovingChanged: {
                    if (isRemoving) {
                        opacity = 0;
                        slideOffset = 60;
                    }
                }

                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on slideOffset { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 10

                    // Avatar/ikon: önce bildirimin kendi görseli (ör. Discord
                    // profil resmi), yoksa uygulama ikonu, o da yoksa zil.
                    // Sabit piksel tahmini yerine, satır sayısı ne olursa
                    // olsun yazı bloğuyla gerçek dikey ortada kalsın diye
                    // AlignVCenter kullanıyoruz.
                    Item {
                        width: 38
                        height: 38
                        Layout.alignment: Qt.AlignVCenter

                        Image {
                            id: notifAvatar
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            source: image !== "" ? image : ""
                            visible: status === Image.Ready
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: notifAvatar.width
                                    height: notifAvatar.height
                                    radius: notifAvatar.width / 2
                                }
                            }
                        }
                        IconImage {
                            id: notifAppIcon
                            anchors.centerIn: parent
                            implicitSize: 26
                            asynchronous: true
                            visible: !notifAvatar.visible && status === Image.Ready && source != ""
                            source: notifAvatar.visible ? "" : root.resolveIconSource(appIcon, appName, desktopEntry)
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !notifAvatar.visible && !notifAppIcon.visible
                            text: "\uf0f3"
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 16
                            color: root.accentColor
                        }
                    }

                    ColumnLayout {
                        id: toastLayout
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: root.t("Yeni bildirim", "New notification")
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: root.accentColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: appName
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (summary !== "" ? ("<font color='" + root.hexColor(root.accentColor) + "'><b>" + summary + ":</b></font> ") : "") + body
                            textFormat: Text.RichText
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                            color: "#9a9a9a"
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }

                // Kapatma (X) butonu - sağ üst köşe, pywal renkli, hover ve
                // tıklamada zıplama efektli
                Item {
                    id: closeBtn
                    width: 22
                    height: 22
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    z: 2

                    Text {
                        id: closeIcon
                        anchors.centerIn: parent
                        text: "\uf00d"
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 13
                        color: closeHover.hovered ? root.accentColor : "#7a7a7a"
                        scale: 1.0
                        transformOrigin: Item.Center
                        Behavior on color { ColorAnimation { duration: 130 } }

                        SequentialAnimation {
                            id: closeBounce
                            NumberAnimation { target: closeIcon; property: "scale"; to: 1.35; duration: 160; easing.type: Easing.OutQuad }
                            NumberAnimation { target: closeIcon; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                        }
                    }
                    HoverHandler { id: closeHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            closeBounce.restart();
                            root.dismissToastAt(index);
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    // X butonunun arkasında kalmasın, tıklama önceliği X'te olsun
                    z: 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.dismissToastAt(index);
                        root.openHistory();
                    }
                }
            }
        }
    }

    // ================= GEÇMİŞ PANELİ =================
    PanelWindow {
        id: historyWin
        // Hoparlör menüsüyle aynı konumlandırma - sadece sol yerine sağ alt köşe
        anchors { bottom: true; right: true }
        // NOT: alt boşluk BURADA değil, panel'in kendi bottomMargin'inde.
        // Pencere ekranın zemininden yukarıda bitiyorsa panel de gerçek
        // zemine inemiyor, o boşlukta kesiliyor ve açılırken yarım görünüyor.
        // Pencereyi ekranın dibine yaslayıp boşluğu panele vererek panelin
        // tamamen aşağı çıkabilmesini sağlıyoruz. (Hoparlör menüsünde de
        // aynı sorunu yaşamıştık.)
        margins { bottom: 0; right: 8 }
        implicitWidth: 360
        // 568 = bildirim paneli (en fazla 560 + 8 alt bosluk)
        // +160 = ustteki Spotify karti (~142) ve aradaki 8px bosluk
        // +68 = en ustteki playlist/ses kartlari (52) ve 8px bosluk
        implicitHeight: 568 + 160 + 68
        color: "transparent"
        visible: false
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland tarafında bu isme bakarak layer animasyonunu kapatıyoruz
        // (windowrule.lua -> hl.layer_rule / match.namespace)
        WlrLayershell.namespace: "quickshell:notifcenter"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore

        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            onActivated: {
                if (root.plZoom) root.plZoom = false;
                else root.closeHistory();
            }
        }
        onVisibleChanged: if (!visible) { root.plZoom = false; plBig.reset(); }

        // ================= BORULAR (kutular arasi) =================
        // Yatay konumlar sabit ve simetrik: ust sira iki esit kutunun
        // ortalari. Alttaki borular da ayni hizada, ust uste gelir.
        readonly property real pipeXL: Math.round((width - 8) / 4)
        readonly property real pipeXR: Math.round(width - (width - 8) / 4)
        // kutularin ANLIK (kayma dahil) ust/alt kenarlari
        readonly property real rowBottom: playlistCard.y + 52 + root.playlistSlideY
        readonly property real mediaTop: mediaCard.y + root.mediaSlideY
        readonly property real mediaBottom: mediaCard.y + mediaCard.height + root.mediaSlideY
        readonly property real panelTop: panel.y + root.slideY

        // playlist <-> ses kutusu
        HPipe {
            active: root.playlistShown
            cy: playlistCard.y + 26 + root.playlistSlideY
            leftX: playlistCard.x + playlistCard.width
            rightX: volumeCard.x
            phase: 0
        }
        // ust sira -> media karti
        VPipe {
            active: root.playlistShown
            cx: historyWin.pipeXL
            topY: historyWin.rowBottom
            bottomY: historyWin.mediaTop
            phase: 0.12
        }
        VPipe {
            active: root.mediaShown
            cx: historyWin.pipeXR
            topY: historyWin.rowBottom
            bottomY: historyWin.mediaTop
            phase: 0.12
        }
        // media karti -> bildirim paneli
        VPipe {
            active: root.mediaShown
            cx: historyWin.pipeXL
            topY: historyWin.mediaBottom
            bottomY: historyWin.panelTop
            phase: 0.3
        }
        VPipe {
            active: root.mediaShown
            cx: historyWin.pipeXR
            topY: historyWin.mediaBottom
            bottomY: historyWin.panelTop
            phase: 0.3
        }

        // ================= SPOTIFY KARTI (panelin ustunde) =================
        // Bildirim paneliyle ayni zemin (#000000) ve ayni kose (10). Aralarinda
        // 8px bosluk var, iki ayri kutu gibi duruyorlar. Spotify kapaliyken
        // ya da calan sarki yokken kart hic gorunmuyor.
        Rectangle {
            id: mediaCard
            z: -1
            anchors.bottom: panel.top
            anchors.bottomMargin: 8
            anchors.right: parent.right
            width: parent.width
            readonly property var player: root.spotifyPlayer
            height: root.mediaShown ? Math.round(mediaColumn.implicitHeight + 24) : 0
            visible: root.mediaShown
            radius: 10
            color: "#000000"
            transform: Translate { y: root.mediaSlideY }
            layer.enabled: true
            layer.smooth: true

            // surukleme sirasinda gosterilen konum (saniye)
            property bool dragging: false
            property real dragPos: 0
            readonly property real len: (player && player.length > 0) ? player.length : 0
            readonly property real pos: dragging ? dragPos : (player ? player.position : 0)
            readonly property real ratio: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0

            // ===== Sarki degisince gecis animasyonu =====
            // Kapak hafif kucukten yaylanarak buyur, yazilar sagdan kayarak
            // gelir, plak bir anlik hizlanip "yeni plak" hissi verir.
            readonly property string trackKey: player ? ((player.trackTitle || "") + "|" + (player.trackArtist || "")) : ""
            onTrackKeyChanged: {
                root.armVolumeGuard();
                spReapply.restart();
                if (historyWin.visible && trackKey !== "|" && trackKey !== "") trackAnim.restart();
            }
            ParallelAnimation {
                id: trackAnim
                NumberAnimation { target: coverBox; property: "scale"; from: 0.8; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                NumberAnimation { target: coverBox; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: coverBox; property: "rotation"; from: -6; to: 0; duration: 460; easing.type: Easing.OutBack }
                SequentialAnimation {
                    PauseAnimation { duration: 60 }
                    ParallelAnimation {
                        NumberAnimation { target: infoShift; property: "x"; from: 18; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        NumberAnimation { target: infoCol; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
                    }
                }
                NumberAnimation { target: vinylBox; property: "boost"; from: 620; to: 0; duration: 800; easing.type: Easing.OutCubic }
            }

            // Mpris konumu kendiliginden yenilenmiyor; acikken ve calarken
            // yarim saniyede bir guncelliyoruz
            Timer {
                interval: 500
                repeat: true
                running: mediaCard.player !== null && mediaCard.player.isPlaying && historyWin.visible
                onTriggered: mediaCard.player.positionChanged()
            }

            // ================= DONEN PLAK (sag ust) =================
            // Siyah plak, ince oluklar, iki yanda hafif isik yansimasi (donerken
            // dondugu belli olsun diye), ortada pywal renkli etiket ve deligi.
            Item {
                id: vinylBox
                // kapakla ayni hizada, kapagin dikey ortasinda, sagdan 22px iceride
                width: 56
                height: 56
                anchors.right: parent.right
                anchors.rightMargin: 26
                y: 12 + (76 - height) / 2
                z: 2

                // ===== Calma / durma animasyonu =====
                // Calarken plak doner ve pikap kolu plagin uzerine iner.
                // Durunca plak gercek pikap gibi yavaslayarak durur, kol
                // kalkip kenara cekilir, plak hafifce kuculup soner.
                // Tekrar calinca once kol iner, plak hizlanarak doner.
                readonly property bool playing: mediaCard.player !== null && mediaCard.player.isPlaying
                // derece / saniye (3.2 sn'de bir tur)
                property real speed: playing ? 112.5 : 0
                Behavior on speed {
                    NumberAnimation {
                        duration: vinylBox.playing ? 700 : 1400
                        easing.type: vinylBox.playing ? Easing.InQuad : Easing.OutCubic
                    }
                }

                // sarki degisince bir anlik ekstra hiz (yeni plak hissi)
                property real boost: 0
                // plak elle cevriliyor mu (scratch ile ileri/geri sarma)
                property bool scratching: false
                // bir tam tur kac saniye sarsin
                readonly property real secPerTurn: 10

                FrameAnimation {
                    running: historyWin.visible && !vinylBox.scratching && (vinylBox.speed + vinylBox.boost) > 0.05
                    onTriggered: vinyl.rotation = (vinyl.rotation + (vinylBox.speed + vinylBox.boost) * frameTime) % 360
                }

                // pikap kolu: sagda, plagin disinda bir pivottan iner/kalkar
                Item {
                    id: tonearm
                    x: vinylBox.width + 3
                    y: -3
                    width: 0; height: 0
                    z: 3
                    rotation: vinylBox.playing ? 19 : -6
                    Behavior on rotation {
                        NumberAnimation {
                            duration: 520
                            easing.type: vinylBox.playing ? Easing.OutBack : Easing.OutCubic
                        }
                    }
                    // kol
                    Rectangle {
                        x: -1
                        y: 0
                        width: 2
                        height: 34
                        radius: 1
                        color: "#9a9a9a"
                    }
                    // igne kafasi
                    Rectangle {
                        x: -3
                        y: 32
                        width: 6
                        height: 7
                        radius: 1.5
                        color: "#cfcfcf"
                    }
                    // pivot
                    Rectangle {
                        x: -4
                        y: -4
                        width: 8
                        height: 8
                        radius: 4
                        color: "#3a3a3a"
                        border.width: 1
                        border.color: "#6a6a6a"
                    }
                }

            // Plak 2 kat cozunurlukte cizilip yariya kucultuluyor: donerken
            // kenarlarda piksel piksel tirtik olusmasin diye (tek kat
            // cizilince dis cerceve testere disi gibi gorunuyordu)
            Canvas {
                id: vinyl
                width: vinylBox.width * 2
                height: vinylBox.height * 2
                anchors.centerIn: parent
                // durunca hafifce kuculup soner (2x cizim -> 0.5 normal boy)
                scale: vinylBox.playing ? 0.5 : 0.44
                opacity: vinylBox.playing ? 1 : 0.55
                Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                smooth: true
                antialiasing: true

                Connections {
                    target: root
                    function onAccentColorChanged() { vinyl.requestPaint(); }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    const w = width, h = height;
                    const cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2;
                    ctx.reset();

                    // plak govdesi
                    ctx.beginPath();
                    ctx.arc(cx, cy, R - 2, 0, Math.PI * 2);
                    ctx.fillStyle = "#111111";
                    ctx.fill();

                    // dis cerceve: grimsi ince kenar
                    ctx.beginPath();
                    ctx.arc(cx, cy, R - 3, 0, Math.PI * 2);
                    ctx.lineWidth = 2;
                    ctx.strokeStyle = "#3a3a3a";
                    ctx.stroke();

                    // oluklar
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = "#262626";
                    for (let r = R - 7; r > R * 0.42; r -= 4) {
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.stroke();
                    }

                    // isik yansimasi (karsilikli iki yay)
                    ctx.lineWidth = 4;
                    ctx.strokeStyle = "rgba(255,255,255,0.16)";
                    ctx.beginPath();
                    ctx.arc(cx, cy, R * 0.72, -2.4, -1.7);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.arc(cx, cy, R * 0.72, 0.74, 1.44);
                    ctx.stroke();

                    // pywal renkli etiket
                    ctx.beginPath();
                    ctx.arc(cx, cy, R * 0.38, 0, Math.PI * 2);
                    ctx.fillStyle = root.accentColor;
                    ctx.fill();

                    // etiketteki kucuk koyu nokta: donusu gozle takip etmek icin
                    ctx.beginPath();
                    ctx.arc(cx + R * 0.22, cy - R * 0.1, R * 0.06, 0, Math.PI * 2);
                    ctx.fillStyle = "rgba(0,0,0,0.35)";
                    ctx.fill();

                    // orta delik
                    ctx.beginPath();
                    ctx.arc(cx, cy, R * 0.09, 0, Math.PI * 2);
                    ctx.fillStyle = "#000000";
                    ctx.fill();
                }
            }

            // ===== Plagi elle cevirip sarma (DJ scratch) =====
            // Basili tutup saat yonunde cevir -> ileri, tersine -> geri.
            // Cevirirken plak parmagi takip eder, ilerleme cubugu ve sure
            // canli kayar; birakinca sarki o konuma gider.
            MouseArea {
                id: scratchArea
                anchors.fill: parent
                z: 5
                hoverEnabled: true
                preventStealing: true
                cursorShape: vinylBox.scratching ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real lastAng: 0
                property real accum: 0
                property real startPos: 0

                function ang(mx, my) {
                    return Math.atan2(my - height / 2, mx - width / 2) * 180 / Math.PI;
                }
                function finish() {
                    if (!vinylBox.scratching) return;
                    const p = mediaCard.player;
                    if (p && Math.abs(accum) > 3) { root.armVolumeGuard(); p.position = mediaCard.dragPos; }
                    mediaCard.dragging = false;
                    vinylBox.scratching = false;
                    scratchPop.restart();
                }

                onPressed: mouse => {
                    const p = mediaCard.player;
                    if (!p || !p.canSeek || mediaCard.len <= 0) { mouse.accepted = false; return; }
                    lastAng = ang(mouse.x, mouse.y);
                    accum = 0;
                    startPos = p.position;
                    mediaCard.dragPos = startPos;
                    mediaCard.dragging = true;
                    vinylBox.scratching = true;
                }
                onPositionChanged: mouse => {
                    if (!vinylBox.scratching) return;
                    const a = ang(mouse.x, mouse.y);
                    let d = a - lastAng;
                    if (d > 180) d -= 360;
                    if (d < -180) d += 360;
                    lastAng = a;
                    accum += d;
                    vinyl.rotation = (vinyl.rotation + d + 360) % 360;
                    mediaCard.dragPos = Math.max(0, Math.min(mediaCard.len - 1,
                        startPos + accum / 360 * vinylBox.secPerTurn));
                }
                onReleased: finish()
                onCanceled: finish()
            }

            // birakinca plak minik bir "tik" ile yerine oturur
            SequentialAnimation {
                id: scratchPop
                NumberAnimation { target: vinylBox; property: "scale"; to: 1.08; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: vinylBox; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
            }
            }

            ColumnLayout {
                id: mediaColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Albüm kapagi
                    Item {
                        id: coverBox
                        width: 76; height: 76
                        transformOrigin: Item.Center
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: "#141414"
                            visible: !coverImg.visible
                            Text {
                                anchors.centerIn: parent
                                text: ""
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 24
                                color: root.accentColor
                            }
                        }
                        Image {
                            id: coverImg
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            // Spotify 300px kapak veriyor; ayni resmin 640px halini
                            // istiyoruz, 2x boyda cozup mipmap ile kucultuyoruz
                            source: root.hiResArt(mediaCard.player ? (mediaCard.player.trackArtUrl || "") : "")
                            sourceSize.width: 152
                            sourceSize.height: 152
                            smooth: true
                            mipmap: true
                            visible: status === Image.Ready
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: coverImg.width
                                    height: coverImg.height
                                    radius: 8
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: infoCol
                        transform: Translate { id: infoShift }
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        // sag ustteki donen plaga yer birak
                        Layout.rightMargin: 74
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: mediaCard.player ? (mediaCard.player.trackTitle || "") : ""
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: root.accentColor
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: mediaCard.player ? (mediaCard.player.trackArtist || "") : ""
                            font.pixelSize: 12
                            color: "#9a9a9a"
                            elide: Text.ElideRight
                        }

                        // Kontroller: onceki / oynat-duraklat / sonraki
                        RowLayout {
                            Layout.topMargin: 6
                            Layout.leftMargin: -2
                            spacing: 4

                            Repeater {
                                model: [
                                    { glyph: "", act: "prev" },
                                    { glyph: "play",   act: "toggle" },
                                    { glyph: "", act: "next" }
                                ]
                                delegate: Item {
                                    width: 22; height: 22
                                    readonly property bool isToggle: modelData.act === "toggle"
                                    Text {
                                        id: ctlIcon
                                        anchors.centerIn: parent
                                        text: parent.isToggle
                                            ? ((mediaCard.player && mediaCard.player.isPlaying) ? "" : "")
                                            : modelData.glyph
                                        font.family: "Symbols Nerd Font"
                                        font.pixelSize: parent.isToggle ? 17 : 14
                                        // sadece ustune gelince pywal, yoksa beyaz
                                        color: ctlHover.hovered ? root.accentColor : "#ffffff"
                                        Behavior on color { ColorAnimation { duration: 130 } }
                                        transformOrigin: Item.Center
                                    }
                                    SequentialAnimation {
                                        id: ctlBounce
                                        NumberAnimation { target: ctlIcon; property: "scale"; to: 1.3; duration: 120; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: ctlIcon; property: "scale"; to: 1.0; duration: 180; easing.type: Easing.OutBack }
                                    }
                                    HoverHandler { id: ctlHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const p = mediaCard.player;
                                            if (!p) return;
                                            ctlBounce.restart();
                                            if (modelData.act === "prev" && p.canGoPrevious) p.previous();
                                            else if (modelData.act === "next" && p.canGoNext) p.next();
                                            else if (modelData.act === "toggle" && p.canTogglePlaying) p.togglePlaying();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Ilerleme cubugu: dolu kisim vurgu renginde, top ses
                // cubugundaki gibi gri halka + vurgu renkli nokta.
                // Tutup surukleyince sarki o noktaya sarilir.
                Item {
                    id: progressArea
                    Layout.fillWidth: true
                    height: 18
                    readonly property int knob: 16

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: progressArea.knob / 2
                        width: parent.width - progressArea.knob
                        height: 4
                        radius: 2
                        color: "#2a2a2a"

                        Rectangle {
                            width: parent.width * mediaCard.ratio
                            height: parent.height
                            radius: 2
                            color: root.accentColor
                        }
                    }

                    Rectangle {
                        id: knobRect
                        width: progressArea.knob + (seekArea.containsMouse || mediaCard.dragging ? 2 : 0)
                        height: width
                        radius: width / 2
                        // dis halka pywal rengi, ici siyah
                        color: root.accentColor
                        anchors.verticalCenter: parent.verticalCenter
                        x: (progressArea.width - progressArea.knob) * mediaCard.ratio - (width - progressArea.knob) / 2
                        Behavior on width { NumberAnimation { duration: 120 } }
                        Rectangle {
                            anchors.centerIn: parent
                            // ince pywal halka: ic siyah daire buyutuldu
                            width: parent.width - 4
                            height: width
                            radius: width / 2
                            color: "#000000"
                        }
                    }

                    MouseArea {
                        id: seekArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: mediaCard.player !== null && mediaCard.player.canSeek && mediaCard.len > 0
                        function ratioAt(mx) {
                            const w = progressArea.width - progressArea.knob;
                            return w > 0 ? Math.max(0, Math.min(1, (mx - progressArea.knob / 2) / w)) : 0;
                        }
                        onPressed: mouse => {
                            mediaCard.dragPos = ratioAt(mouse.x) * mediaCard.len;
                            mediaCard.dragging = true;
                        }
                        onPositionChanged: mouse => {
                            if (mediaCard.dragging) mediaCard.dragPos = ratioAt(mouse.x) * mediaCard.len;
                        }
                        onReleased: mouse => {
                            const p = mediaCard.player;
                            const target = ratioAt(mouse.x) * mediaCard.len;
                            if (p) { root.armVolumeGuard(); p.position = target; }
                            mediaCard.dragPos = target;
                            mediaCard.dragging = false;
                        }
                        onCanceled: mediaCard.dragging = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -4
                    Text {
                        text: root.fmtTime(mediaCard.pos)
                        font.pixelSize: 11
                        color: "#7a7a7a"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.fmtTime(mediaCard.len)
                        font.pixelSize: 11
                        color: "#7a7a7a"
                    }
                }
            }
        }

        // ================= PLAYLIST KARTI (Spotify kartinin ustunde, sol) =================
        // Ayni zemin, ayni kose, ayni 8px bosluk. Sadece icerigi kadar genis.
        Rectangle {
            id: playlistCard
            z: -1
            anchors.bottom: mediaCard.top
            anchors.bottomMargin: 8
            anchors.left: parent.left
            height: root.playlistShown ? 52 : 0
            // Ses kutusuyla birebir esit: (genislik - aradaki 8px) / 2
            width: Math.floor((parent.width - 8) / 2)
            visible: root.playlistShown
            radius: 10
            color: "#000000"
            transform: Translate { y: root.playlistSlideY }
            layer.enabled: true
            layer.smooth: true
            Connections {
                target: root
                function onPlNameChanged() {
                    plNameText.x = 0;
                    if (plMarquee.running) plMarquee.restart();
                    if (historyWin.visible) plSwap.restart();
                }
            }
            ParallelAnimation {
                id: plSwap
                NumberAnimation { target: plRow; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: plShift; property: "y"; from: 8; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }

            Row {
                id: plRow
                transform: Translate { id: plShift }
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                // playlist kapagi (yoksa turune gore ikon). Tikla -> buyur.
                Item {
                    id: plThumb
                    width: 36; height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    // buyuk kart acikken kucugu gizle: oradan ucup gitmis gibi
                    // kartin son kisminda yumusak gecis (kart birden yok olmasin)
                    opacity: plBig.t >= 0.12 ? 0 : 1 - plBig.t / 0.12
                    scale: plThumbHover.hovered && !root.plZoom ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    HoverHandler { id: plThumbHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        z: 3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.plZoom = !root.plZoom
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: "#141414"
                        visible: !plImg.visible
                        Text {
                            anchors.centerIn: parent
                            text: root.plType === "liked" ? ""
                                : root.plType === "album" ? ""
                                : root.plType === "artist" ? ""
                                : root.plType === "radio" ? ""
                                : ""
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 15
                            color: root.accentColor
                        }
                    }
                    Image {
                        id: plImg
                        anchors.fill: parent
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 72
                        sourceSize.height: 72
                        smooth: true
                        mipmap: true
                        source: root.plImage
                        visible: status === Image.Ready && root.plImage !== ""
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: plImg.width
                                height: plImg.height
                                radius: 7
                            }
                        }
                    }
                }

                Column {
                    id: plTexts
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: plNameBox.width
                        elide: Text.ElideRight
                        text: root.plType === "album" ? root.t("Çalan albüm", "Playing album")
                            : root.plType === "artist" ? root.t("Çalan sanatçı", "Playing artist")
                            : root.plType === "radio" ? root.t("Çalan radyo", "Playing radio")
                            : root.t("Çalan playlist", "Playing playlist")
                        font.pixelSize: 11
                        color: "#7a7a7a"
                    }
                    // Isim kutuya sigmazsa kesilmiyor: yavasca sola kayip sonunu
                    // gosteriyor, bekleyip basa donuyor (kayan yazi)
                    Item {
                        id: plNameBox
                        width: playlistCard.width - 8 - 36 - 10 - 12
                        height: plNameText.implicitHeight
                        clip: true
                        readonly property real overflow: Math.max(0, plNameText.implicitWidth - width)

                        Text {
                            id: plNameText
                            text: root.plName
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: root.accentColor
                        }

                        SequentialAnimation {
                            id: plMarquee
                            running: historyWin.visible && plNameBox.overflow > 0
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) plNameText.x = 0
                            PauseAnimation { duration: 1800 }
                            NumberAnimation {
                                target: plNameText; property: "x"
                                to: -plNameBox.overflow
                                duration: Math.max(600, plNameBox.overflow * 35)
                                easing.type: Easing.InOutSine
                            }
                            PauseAnimation { duration: 1400 }
                            NumberAnimation {
                                target: plNameText; property: "x"
                                to: 0
                                duration: Math.max(600, plNameBox.overflow * 35)
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }
            }
        }

        // ================= SPOTIFY SES KUTUSU (playlist kartinin yaninda) =================
        // Ayni zemin/kose, playlist kartiyla 8px bosluk, kalan genisligi dolduruyor.
        // Sadece Spotify'in sesini degistirir. Tekerlek: %5 adim, ikon: sessize al.
        Rectangle {
            id: volumeCard
            z: -1
            anchors.bottom: mediaCard.top
            anchors.bottomMargin: 8
            anchors.left: root.playlistShown ? playlistCard.right : parent.left
            anchors.leftMargin: root.playlistShown ? 8 : 0
            anchors.right: parent.right
            height: root.mediaShown ? 52 : 0
            visible: root.mediaShown
            radius: 10
            color: "#000000"
            transform: Translate { y: root.playlistSlideY }
            layer.enabled: true
            layer.smooth: true

            property bool dragging: false
            property real dragVal: 0
            readonly property real shown: dragging ? dragVal : (root.spMuted ? 0 : Math.min(1, root.spVolume))

            // Ayar yapilirken ikonun yerinde yuzde gorunur; birakinca kisa bir
            // sure sonra yuzde solup ikon geri gelir.
            property bool showPct: false
            function poke() { showPct = true; pctHide.restart(); }
            Timer {
                id: pctHide
                interval: 900
                onTriggered: if (!volumeCard.dragging) volumeCard.showPct = false
            }
            onDraggingChanged: if (!dragging) pctHide.restart()

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const step = event.angleDelta.y > 0 ? 0.05 : (event.angleDelta.y < 0 ? -0.05 : 0);
                    if (step !== 0) {
                        root.setSpotifyVolume(Math.round((root.spVolume + step) * 20) / 20);
                        volumeCard.poke();
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 18
                spacing: 8
                opacity: root.spVolReady ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // hoparlor ikonu: tikla -> sessize al / ac
                Item {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 20
                    Text {
                        anchors.centerIn: parent
                        text: Math.round(volumeCard.shown * 100)
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: root.accentColor
                        opacity: volumeCard.showPct ? 1 : 0
                        scale: volumeCard.showPct ? 1 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    }
                    Text {
                        id: volIcon
                        anchors.centerIn: parent
                        opacity: volumeCard.showPct ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        text: String.fromCodePoint(
                            (root.spMuted || volumeCard.shown <= 0.001) ? 0xF0581
                            : volumeCard.shown < 0.34 ? 0xF057F
                            : volumeCard.shown < 0.67 ? 0xF0580 : 0xF057E)
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 17
                        color: volIconHover.hovered ? root.accentColor : (root.spMuted ? "#7a7a7a" : "#ffffff")
                        Behavior on color { ColorAnimation { duration: 130 } }
                        SequentialAnimation {
                            id: volBounce
                            NumberAnimation { target: volIcon; property: "scale"; to: 1.3; duration: 140; easing.type: Easing.OutQuad }
                            NumberAnimation { target: volIcon; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                        }
                    }
                    HoverHandler { id: volIconHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.spVolReady) return;
                            volBounce.restart();
                            root.spotifyNode.audio.muted = !root.spotifyNode.audio.muted;
                        }
                    }
                }

                // ses cubugu (ilerleme cubuguyla ayni stil)
                Item {
                    id: volArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    readonly property real knob: 12

                    Rectangle {
                        x: volArea.knob / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - volArea.knob
                        height: 4
                        radius: 2
                        color: "#2a2a2a"
                        Rectangle {
                            width: parent.width * volumeCard.shown
                            height: parent.height
                            radius: 2
                            color: root.accentColor
                            Behavior on width {
                                enabled: !volumeCard.dragging
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                    Rectangle {
                        width: volArea.knob + (volSeek.containsMouse || volumeCard.dragging ? 2 : 0)
                        height: width
                        radius: width / 2
                        color: root.accentColor
                        anchors.verticalCenter: parent.verticalCenter
                        x: (volArea.width - volArea.knob) * volumeCard.shown - (width - volArea.knob) / 2
                        Behavior on width { NumberAnimation { duration: 120 } }
                        Behavior on x {
                            enabled: !volumeCard.dragging
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 4
                            height: width
                            radius: width / 2
                            color: "#000000"
                        }
                    }
                    MouseArea {
                        id: volSeek
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        function valAt(mx) {
                            return Math.max(0, Math.min(1, (mx - volArea.knob / 2) / (volArea.width - volArea.knob)));
                        }
                        onPressed: mouse => {
                            volumeCard.dragVal = valAt(mouse.x);
                            volumeCard.dragging = true;
                            volumeCard.showPct = true;
                            root.setSpotifyVolume(volumeCard.dragVal);
                        }
                        onPositionChanged: mouse => {
                            if (!volumeCard.dragging) return;
                            volumeCard.dragVal = valAt(mouse.x);
                            root.setSpotifyVolume(volumeCard.dragVal);
                        }
                        onReleased: volumeCard.dragging = false
                        onCanceled: volumeCard.dragging = false
                    }
                }

            }
        }

        // ================= BUYUK PLAYLIST KAPAGI =================
        // Kucuk kapaga tiklayinca oradan duzgunce buyuyup kartlarin ustune
        // oturur. Basili tutup saga/sola surukleyince kart gibi doner:
        // birakinca hizina gore biraz daha doner ve en yakin yuzune (on yuz:
        // kapak, arka yuz: pywal renkli kart sirti) yumusakca oturur.
        // Surukemeden tiklayinca / Esc ile ayni yoldan geri kuculur.
        //
        // Kalite: kart tek bir katman (layer) olarak 2x cozunurlukte ve
        // mipmap ile ciziliyor; kenarlarda 3px saydam pay birakildigi icin
        // donerken / kuculurken kenarlar tirtikli olmuyor.
        Item {
            id: plBig
            z: 50
            readonly property int edge: 3          // kenar yumusatma payi
            readonly property int pad: 10
            readonly property int art: 210
            readonly property int cardW: art + pad * 2
            readonly property int cardH: art + pad * 2 + 30
            width: cardW + edge * 2
            height: cardH + edge * 2
            visible: t > 0.001

            // 0 = kucuk kapagin yerinde, 1 = buyumus halde.
            // Binding degil, acikca animasyonla suruluyor: yarida tersine
            // cevrilince kaldigi yerden doner, panel kapaninca da sifirlanabilir.
            property real t: 0
            NumberAnimation {
                id: growAnim
                target: plBig
                property: "t"
            }
            function animateT(to, fullDur, easing) {
                growAnim.stop();
                growAnim.to = to;
                // kalan yol kadar sure: yarida donunce hiz bozulmasin
                growAnim.duration = Math.max(1, Math.round(fullDur * Math.abs(to - t)));
                growAnim.easing.type = easing;
                growAnim.start();
            }
            function reset() {
                growAnim.stop();
                spinAnim.stop();
                t = 0;
                spin = 0;
            }

            // baslangic: kucuk kapagin merkezi
            property real sx: 0
            property real sy: 0
            function measure() {
                // yoldayken yeniden olcme: baslangic noktasi ziplamasin
                if (t > 0.001) return;
                const pt = plThumb.mapToItem(plBig.parent, plThumb.width / 2, plThumb.height / 2);
                sx = pt.x; sy = pt.y;
            }
            Connections {
                target: root
                function onPlZoomChanged() {
                    if (root.plZoom) {
                        plBig.measure();
                        if (plBig.t <= 0.001) { spinAnim.stop(); plBig.spin = 0; }
                        plBig.animateT(1, 480, Easing.OutQuint);
                    } else {
                        // kapanirken en kisa yoldan on yuze donerek kuculsun
                        plBig.settle(Math.round(plBig.spin / 360) * 360, 380);
                        plBig.animateT(0, 380, Easing.InOutCubic);
                    }
                }
            }

            // bitis: kartlarin ustunde ortada; yer yoksa en uste yaslanir
            readonly property real fx: (parent.width - width) / 2
            readonly property real fy: Math.max(4, playlistCard.y - 10 - height)

            readonly property real cx: sx + (fx + width / 2 - sx) * t
            readonly property real cy: sy + (fy + height / 2 - sy) * t - Math.sin(t * Math.PI) * 14
            // durunca tam piksele oturt (yarim pikselde yazi/resim bulaniklasiyor)
            x: t >= 0.999 ? Math.round(cx - width / 2) : cx - width / 2
            y: t >= 0.999 ? Math.round(cy - height / 2) : cy - height / 2
            scale: t >= 0.999 ? 1 : (36 / art) + (1 - 36 / art) * t
            transformOrigin: Item.Center
            opacity: t < 0.12 ? t / 0.12 : 1

            // ---- donus ----
            property real spin: 0                 // kullanicinin cevirdigi aci
            // Acilirken / kapanirken kendi etrafinda tam tur doner (ortada kart
            // sirti gorunur); tam acilinca elle cevirme (spin) devreye girer.
            readonly property real angle: spin + 360 * (1 - t)
            readonly property bool front: Math.cos(angle * Math.PI / 180) >= 0

            NumberAnimation {
                id: spinAnim
                target: plBig
                property: "spin"
                easing.type: Easing.OutCubic
                // aci buyuyup gitmesin; ayni goruntu (mod 360) korunuyor
                onStopped: if (Math.abs(plBig.spin) >= 360) plBig.spin = plBig.spin % 360
            }
            function settle(to, dur) {
                spinAnim.stop();
                spinAnim.to = to;
                spinAnim.duration = dur;
                spinAnim.start();
            }

            // Donen kisim ayri bir katman: fare alani bunun DISINDA kaldigi
            // icin donerken (90 derecede bile) fare koordinatlari bozulmuyor.
            Item {
                id: plSpinLayer
                anchors.fill: parent
                // Doku kartla birebir ayni boyutta: durunca keskin (2x + mipmap
                // durgunken bulaniklastiriyordu); donerken kenarlar 4x MSAA ile yumusak
                layer.enabled: plBig.visible
                layer.smooth: true
                layer.samples: 4
                transform: Rotation {
                    origin.x: plSpinLayer.width / 2
                    origin.y: plSpinLayer.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: plBig.angle
                }

            Item {
                id: plBigFace
                x: plBig.edge; y: plBig.edge
                width: plBig.cardW; height: plBig.cardH

                // ---- on yuz ----
                Rectangle {
                    anchors.fill: parent
                    visible: plBig.front
                    radius: 14
                    antialiasing: true
                    color: "#000000"
                    border.width: 1
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)

                    Item {
                        x: plBig.pad; y: plBig.pad
                        width: plBig.art; height: plBig.art
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            antialiasing: true
                            color: "#141414"
                            visible: !plBigImg.visible
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: root.plType === "liked" ? "" : ""
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 64
                                color: root.accentColor
                            }
                        }
                        Image {
                            id: plBigImg
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            source: root.plBigArt(root.plImage)
                            // 640'lik kapak karttaki gercek boyutuna CPU'da yuksek kaliteyle
                            // kucultulerek yukleniyor (GPU'da kucultmekten daha keskin)
                            sourceSize.width: plBig.art
                            sourceSize.height: plBig.art
                            smooth: true
                            mipmap: false
                            visible: status === Image.Ready && root.plImage !== ""
                            layer.enabled: true
                            layer.smooth: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: plBigImg.width
                                    height: plBigImg.height
                                    radius: 10
                                    antialiasing: true
                                }
                            }
                        }
                    }
                    Text {
                        renderType: Text.NativeRendering
                        x: plBig.pad
                        width: plBig.art
                        y: plBig.pad + plBig.art + 7
                        horizontalAlignment: Text.AlignHCenter
                        text: root.plName
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: root.accentColor
                        elide: Text.ElideRight
                    }
                }

                // ---- arka yuz: kart sirti ----
                Rectangle {
                    anchors.fill: parent
                    visible: !plBig.front
                    radius: 14
                    antialiasing: true
                    color: root.accentColor
                    // arkadan bakildigi icin yatayda aynalaniyor; boylece
                    // icerik (logo, cerceve) duz okunuyor
                    transform: Scale { origin.x: plBig.cardW / 2; xScale: -1 }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 7
                        radius: 10
                        antialiasing: true
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.rgba(0, 0, 0, 0.35)
                    }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -10
                        text: ""
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 64
                        color: "#000000"
                    }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 22
                        text: root.userName
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 2
                        color: Qt.rgba(0, 0, 0, 0.6)
                    }
                }
            }

            }

            // ---- surukleyerek cevirme ----
            MouseArea {
                anchors.fill: parent
                enabled: root.plZoom && plBig.t > 0.98
                preventStealing: true
                cursorShape: pressed && dragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real px: 0
                property real lastX: 0
                property real lastT: 0
                property real vel: 0          // derece / sn
                property bool dragged: false
                readonly property real degPerPx: 0.75

                onPressed: mouse => {
                    spinAnim.stop();
                    px = mouse.x; lastX = mouse.x; lastT = Date.now();
                    vel = 0; dragged = false;
                }
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    if (!dragged && Math.abs(mouse.x - px) < 4) return;
                    dragged = true;
                    const now = Date.now();
                    const dx = mouse.x - lastX;
                    const dt = Math.max(1, now - lastT);
                    plBig.spin += dx * degPerPx;
                    // ani sicramalari yumusatarak hiz takibi
                    vel = vel * 0.6 + (dx * degPerPx / dt * 1000) * 0.4;
                    lastX = mouse.x; lastT = now;
                }
                onReleased: {
                    if (!dragged) { root.plZoom = false; return; }
                    // birakinca hizina gore biraz daha doner, en yakin yuzde durur
                    const stale = Date.now() - lastT > 80;
                    const v = stale ? 0 : Math.max(-1400, Math.min(1400, vel));
                    const target = Math.round((plBig.spin + v * 0.28) / 180) * 180;
                    const dist = Math.abs(target - plBig.spin);
                    plBig.settle(target, Math.max(320, Math.min(900, dist * 3.2)));
                }
                onCanceled: plBig.settle(Math.round(plBig.spin / 180) * 180, 320)
            }
        }

        Rectangle {
            id: panel
            anchors.bottom: parent.bottom
            // pencereden alınan alt boşluk buraya taşındı
            anchors.bottomMargin: 8
            anchors.right: parent.right
            width: parent.width
            // Taban yükseklik HER ZAMAN geçerli. Eskiden bildirim varken 0'a
            // düşürülüyordu; tek bildirim 220px'den kısa olduğu için panel
            // ilk bildirim geldiğinde büzülüyordu. Artık boş haldeki boyut
            // korunuyor, panel sadece içerik 220px'i aştığında büyüyor.
            property real minHeight: 220
            Behavior on minHeight { NumberAnimation { duration: 380; easing.type: Easing.InOutSine } }

            height: Math.round(Math.min(560, Math.max(minHeight, panelColumn.implicitHeight + 32)))
            // NOT: burada "Behavior on height" YOK. Kartların kendi açılma
            // animasyonu zaten yüksekliği yumuşakça değiştiriyor; panele ayrı
            // bir animasyon konunca panel içeriğin gerisinde kalıyor ve
            // aradaki farkta alttaki kart kırpılıp yarım görünüyordu.
            // Hoparlör menüsüyle aynı görünüm: 10 radius, tam siyah zemin
            radius: 10
            color: "#000000"
            focus: true

            // Zeminin altından yukarı kayarak geliyor, kapanırken aynı yoldan
            // aşağı inip kayboluyor. Ölçek/solma yok: saf kayma.
            transform: Translate { y: root.slideY }
            // 270Hz'de her kareye 3.7ms bütçe düşüyor; liste ve ikonlar kare
            // kare çizilmesin diye animasyon boyunca tek doku olarak kaydırılıyor
            layer.enabled: true
            layer.smooth: true

                ColumnLayout {
                id: panelColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text { text: root.t("Bildirimler", "Notifications"); font.pixelSize: 15; font.weight: Font.Medium; color: root.accentColor; Layout.fillWidth: true }

                    // ================= RAHATSIZ ETME =================
                    // Zil = bildirimler açık, üstü çizgili zil = rahatsız etme açık.
                    // Tıklayınca zil gerçekten çalmış gibi sallanıyor ve
                    // iki ikon birbirine çapraz geçişle dönüşüyor.
                    Item {
                        id: dndToggle
                        width: 26; height: 26

                        Item {
                            id: bellWrap
                            anchors.fill: parent
                            // üst noktadan sallansın, asılı bir zil gibi
                            transformOrigin: Item.Top

                            Text {
                                id: bellIcon
                                anchors.centerIn: parent
                                text: "\uf0f3"
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 16
                                transformOrigin: Item.Center
                                color: dndHover.hovered ? root.accentColor : "#8a8a8a"
                                Behavior on color { ColorAnimation { duration: 140 } }
                                opacity: root.dndEnabled ? 0 : 1
                                scale: root.dndEnabled ? 0.7 : 1
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                            }

                            Text {
                                id: bellSlashIcon
                                anchors.centerIn: parent
                                text: "\uf1f6"
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 16
                                transformOrigin: Item.Center
                                color: root.accentColor
                                opacity: root.dndEnabled ? 1 : 0
                                scale: root.dndEnabled ? 1 : 0.7
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                            }
                        }

                        SequentialAnimation {
                            id: bellShake
                            NumberAnimation { target: bellWrap; property: "rotation"; to: -16; duration: 90; easing.type: Easing.OutCubic }
                            NumberAnimation { target: bellWrap; property: "rotation"; to: 13; duration: 110; easing.type: Easing.InOutSine }
                            NumberAnimation { target: bellWrap; property: "rotation"; to: -8; duration: 100; easing.type: Easing.InOutSine }
                            NumberAnimation { target: bellWrap; property: "rotation"; to: 4; duration: 90; easing.type: Easing.InOutSine }
                            NumberAnimation { target: bellWrap; property: "rotation"; to: 0; duration: 130; easing.type: Easing.OutBack }
                        }

                        HoverHandler { id: dndHover; cursorShape: Qt.PointingHandCursor }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.dndEnabled = !root.dndEnabled;
                                bellShake.restart();
                            }
                        }
                    }

                    Item {
                        width: 26; height: 26
                        Text {
                            id: trashIcon
                            anchors.centerIn: parent
                            text: "\uf1f8"
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 15
                            color: trashHover.hovered ? root.accentColor : "#8a8a8a"
                            scale: 1.0
                            transformOrigin: Item.Center
                            Behavior on color { ColorAnimation { duration: 130 } }
                            SequentialAnimation {
                                id: trashBounce
                                NumberAnimation { target: trashIcon; property: "scale"; to: 1.35; duration: 180; easing.type: Easing.OutQuad }
                                NumberAnimation { target: trashIcon; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
                            }
                        }
                        HoverHandler { id: trashHover }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { trashBounce.restart(); root.clearAllNotifications(); } }
                    }
                }

                Item {
                    id: notifContentArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Alt satır (Rahatsız Etme Aktif) görünür olsun olmasın
                    // yeri hep ayrılıyor - yoksa DND açılıp kapandıkça içerik
                    // alanı büyüyüp küçülüyor ve "Bildirim Yok" yazısı kayıyordu
                    Layout.preferredHeight: notifServer.trackedNotifications.values.length > 0
                        ? Math.min(400, notifList.contentHeight) + 10 + counterBar.height
                        : 60 + 10 + counterBar.height

                    // "Bildirim Yok" yazısı için sabit referans alan: alt satır
                    // görünsün görünmesin hep aynı yerde durur, yazı kaymaz
                    Item {
                        id: emptyArea
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: counterBar.top
                        anchors.bottomMargin: 10

                        Text {
                            anchors.centerIn: parent
                            text: root.t("Bildirim Yok", "No Notifications")
                            font.pixelSize: 12
                            color: "#5a5a5a"
                            // Temizlemenin ikinci aşamasında kartlar zaten
                            // görünmez oluyor; yazıyı modelin boşalmasını
                            // beklemeden o anda getiriyoruz ki geç kalmasın
                            opacity: (notifServer.trackedNotifications.values.length === 0
                                      || root.clearCollapsing) ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutSine } }
                        }
                    }

                    Item {
                        id: listArea
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        // Sadece rahatsız etme geçişi animasyonlu olsun diye
                        // alttan bırakılan payı ayrı bir değerde tutuyoruz.
                        // Yüksekliğin tamamına animasyon konursa, kart açılıp
                        // panel büyürken alan geride kalıp kartları kırpıyor.
                        property real bottomGap: (root.dndEnabled || root.notifCount > 0)
                            ? counterBar.height + 10
                            : 4
                        Behavior on bottomGap { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        height: parent.height - bottomGap
                        clip: true

                        ListView {
                        id: notifList
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Math.round(Math.min(parent.height, contentHeight))
                        clip: true
                        // spacing YOK: gruplar arası boşluk son kartın kendi alt
                        // aralığından geliyor. Sabit spacing kullanılınca, kapanan
                        // grup sıfıra inip listeden düştüğü anda o boşluk da bir
                        // anda kayboluyor ve alttaki gruplar "çat" diye sıçrıyordu.
                        spacing: 0
                        model: (root.notifCount, root.buildGroups())
                        boundsBehavior: Flickable.StopAtBounds

                        // NOT: add/remove Transition YOK. Model her değişimde
                        // baştan kurulduğu için bu geçişler mevcut kartlara da
                        // uygulanıp panelin tamamını yanıp söndürüyordu.
                        // Kartların kendi giriş/çıkış animasyonu zaten var.
                        displaced: Transition { NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.InOutSine } }

                        // ================= GRUP (YIĞIN) KARTI =================
                        // Aynı uygulamadan birden fazla bildirim varsa, tepedeki
                        // kart görünür, arkasında ince "peek" şeritleri yığın
                        // hissi verir. + basılınca hepsi normal liste gibi açılır,
                        // - basılınca tekrar üst üste toplanır.
                        delegate: Item {
                        id: groupItem
                        width: notifList.width
                        property var group: modelData
                        readonly property bool multi: group.items.length > 1
                        // en yeni üstte olacak şekilde sabit sıra
                        readonly property var orderedItems: group.items.slice().reverse()
                        property bool expanded: multi && root.isGroupExpanded(group.key)
                        readonly property int peekCount: Math.min(group.items.length - 1, 2)
                        // Şeritler baş kartın alt kenarına göre yerleşiyor,
                        // bu yüzden onun yüksekliğini burada tutuyoruz
                        property real headHeight: root.knownGroupHeight(group.key)
                        readonly property int peekOffset: 7
                        // kartların kendi yüksekliğine dahil edilen alt aralık
                        readonly property int cardGap: 8
                        // Toplu haldeyken üstteki kart hover olunca arkadaki
                        // yığın şeritleri de aynı tonu alsın, tek parça hissi versin
                        property bool stackHovered: false

                        // Yığın şeritlerinin eklediği ekstra yükseklik - açılıp
                        // kapanırken bu da yumuşakça eriyip geri gelsin.
                        // Toplu silmede de kapanıyor ki geride boşluk kalmasın.
                        property real peekExtra: (multi && !expanded && !root.clearCollapsing
                                                  && !groupCollapsing) ? peekCount * peekOffset : 0
                        // Şeritlerin açtığı yer de kartların toplanma ritmine
                        // uysun: kapanırken onlar bindikten sonra yer açılsın
                        Behavior on peekExtra {
                            SequentialAnimation {
                                PauseAnimation {
                                    duration: (groupItem.expanded || root.clearingAll || root.clearCollapsing
                                               || groupItem.groupCollapsing || groupItem.groupDismissing)
                                        ? 0
                                        : (groupItem.orderedItems.length - 1) * 70
                                }
                                NumberAnimation { duration: 340; easing.type: Easing.InOutSine }
                            }
                        }

                        // ===== BU UYGULAMANIN TÜM BİLDİRİMLERİNİ SİLME =====
                        // Karttaki çöp kutusu bu grubu siler. Genel temizlemeyle
                        // aynı ritim: önce solar, sonra yer kapanır, en son
                        // modelden kaldırılır.
                        property bool groupDismissing: false
                        property bool groupCollapsing: false

                        function dismissGroup() {
                            if (groupItem.groupDismissing) return;
                            groupItem.groupDismissing = true;
                            groupFadeTimer.start();
                        }

                        Timer {
                            id: groupFadeTimer
                            interval: 380
                            onTriggered: {
                                groupItem.groupCollapsing = true;
                                groupRemoveTimer.start();
                            }
                        }

                        Timer {
                            id: groupRemoveTimer
                            interval: 340
                            onTriggered: {
                                const items = groupItem.group.items;
                                for (let i = items.length - 1; i >= 0; i--) {
                                    items[i].tracked = false;
                                }
                            }
                        }


                        // Çöp kutusuyla temizlerken grubun tamamı (kartlar +
                        // arkadaki yığın şeritleri) tek parça halinde solsun
                        opacity: (root.clearingAll || groupDismissing) ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }

                        // NOT: burada "Behavior on height" YOK - yükseklik zaten
                        // içerideki kartların kendi animasyonlarından geliyor.
                        // İkisi birden olursa animasyon animasyonu kovalıyor ve
                        // açılma gecikmeli/lastikli görünüyordu.
                        // Son kartın alt aralığı grubun içinde kalıyor; gruplar
                        // arası boşluk bu sayede oluşuyor ve grup kapanırken
                        // kartlarla aynı ritimde eriyor
                        implicitHeight: cardColumn.implicitHeight + peekExtra
                        height: implicitHeight

                        // ================= ARKADAKİ YIĞIN =================
                        // Her şerit, baş kartın alt kenarından bir tık daha
                        // aşağı taşan ve iki yandan biraz daralan bir kart
                        // gibi duruyor. Üst kısmı baş kartın arkasında kaldığı
                        // için gerçekten üst üste binmiş kağıtlar hissi veriyor.
                        // 2 bildirim -> 1 şerit, 3 ve üstü -> 2 şerit.
                        Repeater {
                            model: groupItem.multi ? groupItem.peekCount : 0
                            delegate: Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: groupItem.headHeight - height + (index + 1) * groupItem.peekOffset
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: (index + 1) * 8
                                anchors.rightMargin: (index + 1) * 8
                                height: 16
                                radius: 10
                                // Alttaki kartlar geriye doğru koyulaşıyor:
                                // en üstteki baş karta yakın, alttaki daha sönük
                                color: groupItem.stackHovered
                                    ? (index === 0 ? "#262626" : "#1e1e1e")
                                    : (index === 0 ? "#1c1c1c" : "#151515")
                                Behavior on color { ColorAnimation { duration: 140 } }
                                opacity: (groupItem.expanded || root.clearingAll
                                          || groupItem.groupDismissing) ? 0 : 1
                                // Açılırken hemen kaybolur; kapanırken ise kartlar
                                // üst üste binmeyi bitirene kadar bekler, sonra
                                // yığın belirir - sıralama böylece okunaklı oluyor
                                Behavior on opacity {
                                    SequentialAnimation {
                                        PauseAnimation {
                                            // temizlemede bekleme yok: kartlarla
                                            // birlikte gitsinler, yoksa en sonda
                                            // ekranda gri şerit kalıyor
                                            duration: (groupItem.expanded || root.clearingAll
                                                       || groupItem.groupDismissing)
                                                ? 0
                                                : (groupItem.orderedItems.length - 1) * 70 + 120
                                        }
                                        NumberAnimation { duration: 300; easing.type: Easing.InOutSine }
                                    }
                                }
                                z: -1 - index
                            }
                        }

                        Column {
                            id: cardColumn
                            width: parent.width
                            // spacing YOK: kartlar arası boşluk her kartın kendi
                            // yüksekliğine dahil edildi. Column spacing'i sabit
                            // olduğu için, kapanan kart sıfıra inip görünmez
                            // olduğu anda boşluğu da bir anda kayboluyor ve
                            // kalan kartlar "çat" diye sıçrıyordu.
                            spacing: 0

                            Repeater {
                                // Gruptaki TÜM bildirimler her zaman oluşturuluyor
                                // (en yeni üstte). Toplu haldeyken baş kart dışındakiler
                                // yüksekliği 0'a inip saydamlaşıyor - böylece açılma
                                // ve kapanma gerçek bir animasyon oluyor, kartlar
                                // birden "pat" diye belirmiyor.
                                model: groupItem.orderedItems

                                delegate: Item {
                                id: cardSlot
                                width: cardColumn.width
                                property var notif: modelData
                                readonly property bool isHead: index === 0
                                // Grupta normalde görünür olmalı mı? (baş kart ya da grup açık)
                                readonly property bool inGroup: isHead || groupItem.expanded
                                // Silme iki aşamalı: önce solar (dismissing),
                                // sonra bıraktığı yer kapanır (collapsing).
                                // Aynı anda yapılınca fade hiç fark edilmiyordu.
                                property bool dismissing: false
                                property bool collapsing: false
                                readonly property bool shown: inGroup && !dismissing && !collapsing && !root.clearingAll

                                clip: true
                                // Kart gizliyken implicitHeight ölçümü sıfırlanırsa
                                // açılma animasyonu 0'dan 0'a olur ve hiç görünmez.
                                // Bu yüzden son geçerli yüksekliği saklıyoruz.
                                property real measuredH: root.knownGroupHeight(groupItem.group.key)
                                Connections {
                                    target: cardRect
                                    function onImplicitHeightChanged() {
                                        if (cardRect.implicitHeight > 1)
                                            cardSlot.measuredH = Math.round(cardRect.implicitHeight);
                                    }
                                }
                                // Daha önce gösterilmiş kart anında tam boyutta gelir.
                                // Gerçekten yeni olan kart ise ilk karede kapalı
                                // (0 yükseklik, saydam) doğar; bir kare sonra
                                // "entered" true olunca Behavior devreye girer ve
                                // kart yumuşakça açılıp belirir.
                                // entered  -> YÜKSEKLİK için: baş kartın yeri zaten
                                //             durduğundan orada yükseklik animasyonu
                                //             yapılmaz, yoksa panel çöküp büyüyor.
                                // faded     -> GÖRÜNÜM için: içerik yeni olduğu sürece
                                //             kart her durumda solarak belirir.
                                property bool entered: cardSlot.notif
                                    ? (root.isSeen(cardSlot.notif.id)
                                       || (isHead && root.isGroupSeen(groupItem.group.key)))
                                    : true
                                property bool faded: cardSlot.notif ? root.isSeen(cardSlot.notif.id) : true

                                onMeasuredHChanged: {
                                    if (cardSlot.isHead) {
                                        groupItem.headHeight = measuredH;
                                        root.rememberGroupHeight(groupItem.group.key, measuredH);
                                    }
                                }
                                Component.onCompleted: {
                                    if (cardRect.implicitHeight > 1)
                                        measuredH = Math.round(cardRect.implicitHeight);
                                    if (cardSlot.isHead) {
                                        groupItem.headHeight = measuredH;
                                        root.rememberGroupHeight(groupItem.group.key, measuredH);
                                    }

                                    const isNewCard = cardSlot.notif && !root.isSeen(cardSlot.notif.id);
                                    if (isNewCard)
                                        root.markSeen(cardSlot.notif.id);
                                    if (cardSlot.isHead)
                                        root.markGroupSeen(groupItem.group.key);

                                    if (isNewCard) {
                                        Qt.callLater(function() {
                                            // içerik her yeni bildirimde solarak gelir
                                            cardSlot.faded = true;
                                            // yükseklik animasyonu ise yalnızca kartın
                                            // yeri gerçekten yoksa oynatılır
                                            cardSlot.entered = true;
                                        });
                                    }
                                }

                                // Yükseklik sadece "collapsing" aşamasında kapanır,
                                // opaklık ise ondan önce solar
                                readonly property int gap: groupItem.cardGap

                                // ===== KADEMELİ SIRALANMA =====
                                // Kartlar hep birlikte değil, sırayla hareket etsin:
                                // açılırken en üstteki önce iner, kapanırken en
                                // alttaki önce kalkıp üstündekinin arkasına girer.
                                // Silme/temizlemede kademe olmaz, hepsi birlikte gider.
                                readonly property int stagger: 70
                                readonly property int animDelay: (dismissing || root.clearingAll || root.clearCollapsing)
                                    ? 0
                                    : (groupItem.expanded
                                        ? Math.max(0, index - 1) * stagger
                                        : (groupItem.orderedItems.length - 1 - index) * stagger)
                                // Açıklık oranı: 0 = kapalı, 1 = tam açık.
                                // Animasyon yüksekliğin kendisine değil bu orana
                                // uygulanıyor. Yoksa kart yeniden oluşurken ölçüm
                                // varsayılandan gerçek değere geçerken de animasyon
                                // tetikleniyor ve panel önce küçülüp sonra büyüyordu.
                                property real openFactor: (entered && inGroup && !collapsing
                                                           && !root.clearCollapsing
                                                           && !groupItem.groupCollapsing) ? 1 : 0
                                Behavior on openFactor {
                                    SequentialAnimation {
                                        PauseAnimation { duration: cardSlot.animDelay }
                                        NumberAnimation { duration: 340; easing.type: Easing.InOutSine }
                                    }
                                }

                                // Kartın gerçek ölçüsü doğrudan okunuyor; measuredH
                                // sadece kart gizliyken ölçüm sıfırlanırsa devreye
                                // giren yedek. Önceden measuredH varsayılanı (64)
                                // ilk karede kullanıldığı için yeni gelen kartın
                                // yarısı görünüp sonra tamamlanıyordu.
                                // Kartın iç düzeni henüz hesaplanmamışsa
                                // implicitHeight sadece dolgu payı kadar (20px)
                                // çıkıyor ve kart ince bir şerit gibi görünüyordu.
                                // Bu yüzden düzenin gerçekten ölçülüp ölçülmediğine
                                // bakıyoruz, kartın toplam boyuna değil.
                                readonly property real cardH: cardLayout.implicitHeight > 1
                                    ? cardRect.implicitHeight
                                    : measuredH
                                height: Math.round((cardH + gap) * openFactor)
                                // DİKKAT: buraya "faded" konmuyor. Yeni bildirim
                                // gelirken kartın zemini de saydamlaşırsa arkadaki
                                // yığın şeridi açıkta kalıp gri bir çizgi gibi
                                // görünüyor. Zemin hep opak; içerik (cardLayout)
                                // kendi içinde solarak değişiyor.
                                opacity: (inGroup && !dismissing && !root.clearingAll
                                          && !groupItem.groupDismissing) ? 1 : 0
                                // yüksekliği sıfırlanan kart Column'da boşluk
                                // bırakmasın diye animasyon bitince gizleniyor
                                visible: height > 0.5

                                Behavior on opacity {
                                    SequentialAnimation {
                                        PauseAnimation { duration: cardSlot.animDelay }
                                        NumberAnimation {
                                            duration: root.clearingAll ? 450 : (cardSlot.dismissing ? 380 : 340)
                                            easing.type: Easing.InOutSine
                                        }
                                    }
                                }

                                // 1. adım: kart tamamen solduktan sonra yerini kapat
                                Timer {
                                    id: fadeTimer
                                    interval: 390
                                    onTriggered: {
                                        cardSlot.collapsing = true;
                                        removeTimer.start();
                                    }
                                }
                                // 2. adım: yer kapandıktan sonra modelden gerçekten kaldır
                                Timer {
                                    id: removeTimer
                                    interval: 250
                                    onTriggered: if (cardSlot.notif) cardSlot.notif.tracked = false
                                }

                                Rectangle {
                                id: cardRect
                                anchors.top: parent.top
                                width: parent.width
                                // alttaki gap kadar boşluk kartın dışında kalıyor
                                implicitHeight: cardLayout.implicitHeight + 20
                                height: implicitHeight
                                radius: 10
                                property var notif: cardSlot.notif
                                readonly property bool isHead: cardSlot.isHead
                                // Sadece birden fazla bildirim içeren gruplar tıklanabilir:
                                // tek bildirimlik kartta hover/tıklama boşuna his vermesin.
                                readonly property bool clickable: groupItem.multi

                                color: (clickable && cardHover.hovered) ? "#1f1f1f" : "#141414"
                                Behavior on color { ColorAnimation { duration: 140 } }

                                // Açılırken yukarıdan süzülüp yerine oturur; kapanırken
                                // üstündeki kartın arkasına doğru kayarak biner.
                                // Kayma da kademeli gecikmeye uyuyor ki kartlar
                                // teker teker üst üste gelmiş gibi görünsün.
                                transform: Translate {
                                    y: cardSlot.inGroup ? 0 : -18
                                    Behavior on y {
                                        SequentialAnimation {
                                            PauseAnimation { duration: cardSlot.animDelay }
                                            NumberAnimation { duration: 340; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }

                                // Kayarken hafifçe de küçülüyor: üst kenardan
                                // büzüldüğü için arkadaki yığına giriyormuş,
                                // açılırken de oradan çıkıyormuş gibi duruyor
                                transformOrigin: Item.Top
                                scale: cardSlot.inGroup ? 1 : 0.93
                                Behavior on scale {
                                    SequentialAnimation {
                                        PauseAnimation { duration: cardSlot.animDelay }
                                        NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
                                    }
                                }

                                HoverHandler {
                                    id: cardHover
                                    enabled: cardRect.clickable
                                    cursorShape: Qt.PointingHandCursor
                                    onHoveredChanged: if (cardRect.isHead) groupItem.stackHovered = hovered
                                }

                                // Kartın geneline tıklama: grubu aç/kapa.
                                // RowLayout bundan sonra geldiği için X butonunun
                                // kendi MouseArea'sı üstte kalır, çakışma olmaz.
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: cardRect.clickable
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleGroup(groupItem.group.key)
                                }

                                RowLayout {
                                    id: cardLayout
                                    // Yeni bildirim geldiğinde kartın yeri sabit
                                    // kalır, sadece içindeki metin ve ikon solarak
                                    // yenisiyle değişir
                                    opacity: cardSlot.faded ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 340; easing.type: Easing.InOutSine } }
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 10
                                    spacing: 10

                                    Item {
                                        width: 40; height: 40
                                        // metin bloğuna göre dikeyde ortalı dursun,
                                        // ayrıca göz kararı bir tık aşağı çekilsin
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.topMargin: 4
                                        Image {
                                            id: histAvatar
                                            anchors.fill: parent
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectCrop
                                            source: cardRect.notif.image || ""
                                            visible: status === Image.Ready
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: histAvatar.width
                                                    height: histAvatar.height
                                                    radius: histAvatar.width / 2
                                                }
                                            }
                                        }
                                        IconImage {
                                            id: appIconImg
                                            anchors.centerIn: parent
                                            implicitSize: 30
                                            asynchronous: true
                                            visible: !histAvatar.visible && status === Image.Ready && source != ""
                                            source: histAvatar.visible ? "" : root.resolveIconSource(cardRect.notif.appIcon, cardRect.notif.appName, cardRect.notif.desktopEntry)
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !histAvatar.visible && !appIconImg.visible
                                            text: "\uf0f3"
                                            font.family: "Symbols Nerd Font"
                                            font.pixelSize: 17
                                            color: "#8a8a8a"
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            spacing: 6
                                            Text { text: cardRect.notif.appName || root.t("Bildirim", "Notification"); font.pixelSize: 12; color: root.accentColor }
                                            Text { text: root.t("· Az Önce", "· Just now"); font.pixelSize: 11; color: "#5a5a5a" }
                                            Rectangle {
                                                visible: cardRect.isHead && groupItem.multi && !groupItem.expanded
                                                radius: 7
                                                color: "#242424"
                                                implicitWidth: Math.max(16, countBadgeText.implicitWidth + 8)
                                                implicitHeight: 14
                                                Text {
                                                    id: countBadgeText
                                                    anchors.centerIn: parent
                                                    text: groupItem.group.items.length
                                                    font.pixelSize: 10
                                                    color: root.accentColor
                                                }
                                            }
                                        }
                                        Text { Layout.fillWidth: true; text: cardRect.notif.summary || ""; font.pixelSize: 13; font.weight: Font.Medium; color: root.accentColor; elide: Text.ElideRight; visible: text !== "" }
                                        Text { Layout.fillWidth: true; text: cardRect.notif.body || ""; font.pixelSize: 12; color: "#9a9a9a"; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; visible: text !== "" }
                                    }

                                    // Sağ üstteki tek buton: X. Bu uygulamadan
                                    // gelen bildirimlerin TAMAMINI siler.
                                    // (Eskiden burada iki buton vardı: X tek
                                    // bildirimi, yanındaki çöp kutusu grubu
                                    // siliyordu. Tek butona indirildi.)
                                    Item {
                                        Layout.alignment: Qt.AlignTop
                                        width: 18; height: 18

                                        Text {
                                            id: groupCloseIcon
                                            anchors.centerIn: parent
                                            text: "\uf00d"
                                            font.family: "Symbols Nerd Font"
                                            font.pixelSize: 13
                                            color: closeHover.hovered ? root.accentColor : "#6a6a6a"
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }
                                        HoverHandler { id: closeHover }

                                        // basınca hafif bir sıçrama
                                        SequentialAnimation {
                                            id: groupCloseBounce
                                            NumberAnimation { target: groupCloseIcon; property: "scale"; to: 1.3; duration: 150; easing.type: Easing.OutQuad }
                                            NumberAnimation { target: groupCloseIcon; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                groupCloseBounce.restart();
                                                groupItem.dismissGroup();
                                            }
                                        }
                                    }
                                }
                                }
                                }
                            }
                        }
                        }
                    }
                    }

                    // Alt orta satır: rahatsız etme açıksa uyarı yazısı,
                    // kapalıysa bildirim sayacı. İkisi çapraz geçişle
                    // birbirinin yerini alıyor.
                    Item {
                        id: counterBar
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 18
                        // sayaç yalnızca bildirim varken anlamlı olduğu için
                        // satır ya DND açıkken ya da bildirim varken görünüyor
                        opacity: (root.dndEnabled || root.notifCount > 0) ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.t("Rahatsız Etme Aktif", "Do Not Disturb On")
                            font.pixelSize: 12
                            color: root.accentColor
                            opacity: root.dndEnabled ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutSine } }
                        }

                        Text {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.notifCount + root.t(" Bildirim", " Notifications")
                            font.pixelSize: 12
                            color: root.accentColor
                            opacity: (!root.dndEnabled && root.notifCount > 0) ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutSine } }
                        }
                    }
                }
            }
        }


    }
}