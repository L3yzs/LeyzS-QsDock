//@ pragma IconTheme Papirus
// QsDock — sol ortada, gizlenen dikey dock (LeyzS)
// ~/.config/quickshell/dock/shell.qml  ->  qs -c dock
// Kontrol panelinde "Dock" secilince sadece bu calisir (notch / qsbar / waybar kapanir).
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

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

    // ================= AYARLAR =================
    readonly property var dockOutputs: root.settings.dockOutputs || []   // settings.json "dockOutputs": ["HDMI-A-1"]; bos ya da hicbiri bagli degilse tum ekranlar
    readonly property string fontName: "JetBrainsMono Nerd Font"
    readonly property int dockW: 62                        // govde genisligi (dikey)
    readonly property int barH: 60                         // yatay dock yuksekligi
    // ================= YON: dikey (sol) / yatay (alt orta) =================
    // Arch'a cift tik: dock asagi kayar, yilan gibi koseden donup alta yatar (ya da tersi)
    property bool horiz: false
    FileView {
        path: Quickshell.env("HOME") + "/.local/share/quickshell/dock-yon"
        onLoaded: root.horiz = text().trim() === "yatay"
    }
    Process { id: yonYaz }
    function saveYon() {
        yonYaz.command = ["sh", "-c", "mkdir -p \"$HOME/.local/share/quickshell\"; echo " + (root.horiz ? "yatay" : "dikey") + " > \"$HOME/.local/share/quickshell/dock-yon\""];
        yonYaz.running = true;
    }
    property bool morphing: false          // yilan gecisi suruyor
    property bool toH: true                // gecis yonu: dikeyden yataya mi
    property real snakeT: 0                // 0..1 (dikey -> yatay)
    property real snakeHV: 600             // dikey govde boyu (gecis icin)
    property real snakeWB: 700             // yatay govde eni (gecis icin)
    signal orientFlip()
    NumberAnimation {
        id: snakeAnim
        target: root; property: "snakeT"
        duration: 1150
        // tek parca egri: yavas baslar, akar, sonda azicik tasip yerine oturur (eskiden 3 ayri parcaydi,
        // her koseye gelince durup yeniden kalkiyordu -> takilma hissi)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.5, 0.0, 0.18, 1.07, 1, 1]
        onFinished: { root.flipHold = true; flipHoldT.restart(); root.morphing = false; root.saveYon(); rezervTimer.restart(); }
    }
    // yilan bitince bar hemen kaybolmasin: birkac saniye gorunsun, sonra normal sekilde saklansin
    property bool flipHold: false
    Timer { id: flipHoldT; interval: 2500; onTriggered: root.flipHold = false
    }
    onHorizChanged: if (!root.morphing) rezervTimer.restart()
    function toggleOrient() {
        if (root.morphing) return;
        if (root.dmode !== "") root.closeMode();
        root.toH = !root.horiz;
        root.morphing = true;
        root.orientFlip();                 // pencereler olculeri kaydeder, yon degisir, animasyon baslar
    }
    readonly property int cell: 42                         // ikon kutusu
    readonly property int gap: 8
    readonly property int fil: 22                          // kenara baglanan ic kavis
    readonly property int hideDelay: 90                    // fare cikinca (gecislerdeki anlik kopmalari yutacak kadar) hemen saklanir
    readonly property string pinPath: Quickshell.env("HOME") + "/.local/share/quickshell/dock-sabitler.json"
    readonly property string oldPinPath: Quickshell.env("HOME") + "/.config/quickshell/dock/sabitler.json"
    readonly property string cmdMenu: "qs -p \"$HOME/.config/quickshell/appmenu/shell.qml\" ipc call menu toggle"
    readonly property string cmdWifi: "quickshell -p ~/.config/quickshell/wifi-panel ipc call wifiPanel toggle"
    readonly property string cmdNotif: "quickshell -p ~/.config/quickshell/notifications ipc call notifcenter toggle"
    readonly property string cmdAudio: "qs -p \"$HOME/.config/quickshell/audio/shell.qml\" ipc call audiomenu toggle"
    readonly property string cmdBattery: "qs -c battery ipc call battery toggle || (setsid -f qs -c battery -d; sleep 1; qs -c battery ipc call battery toggle)"
    readonly property string cmdDnd: "quickshell -p ~/.config/quickshell/notifications ipc call notifcenter toggleDnd"

    function g(cp) { return String.fromCodePoint(cp); }

    // ================= PYWAL =================
    property color accent: "#5b8def"
    FileView {
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); if (d.colors && d.colors.color9) root.accent = d.colors.color9; } catch (e) {} }
    }

    // ================= SABITLER (uygulama menusunde sag tik -> Dock'a sabitle) =================
    property var pins: []
    FileView {
        id: pinFile
        path: root.pinPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); root.pins = d.ids || []; } catch (e) {} }
    }
    Process {
        running: true
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\"; if [ ! -f \"$1\" ]; then if [ -f \"$2\" ]; then mv \"$2\" \"$1\"; else printf '{\"ids\": []}' > \"$1\"; fi; fi", "sh", root.pinPath, root.oldPinPath]
        onExited: pinFile.reload()
    }
    function togglePin(id) {
        if (!id) return;
        const l = root.pins.slice(), i = l.indexOf(id);
        if (i >= 0) l.splice(i, 1); else l.push(id);
        root.pins = l;
        pinFile.setText(JSON.stringify({ ids: l }, null, 2) + "\n");
    }

    // ================= UYGULAMALAR =================
    // ust kisim: sabitler (sirasiyla). alt kisim: sabit olmayan ama su an acik olanlar.
    function entryForId(id) {
        let e = DesktopEntries.byId(id);
        if (!e) e = DesktopEntries.heuristicLookup(id);
        return e;
    }
    function keyOf(appId) {
        const e = DesktopEntries.heuristicLookup(appId);
        return e ? e.id : appId;
    }
    readonly property var apps: {
        const pinned = [], running = [], by = {};
        for (const id of root.pins) {
            const e = root.entryForId(id);
            const k = e ? e.id : id;
            if (by[k]) continue;
            const o = { key: k, pinId: id, entry: e, pinned: true, wins: [] };
            by[k] = o; pinned.push(o);
        }
        const tl = ToplevelManager.toplevels.values;
        for (let i = 0; i < tl.length; i++) {
            const t = tl[i];
            if (!t || !t.appId) continue;
            const k = root.keyOf(t.appId);
            let o = by[k];
            if (!o) {
                const e = DesktopEntries.heuristicLookup(t.appId);
                o = { key: k, pinId: e ? e.id : "", entry: e, pinned: false, wins: [], appId: t.appId };
                by[k] = o; running.push(o);
            }
            o.wins.push(t);
        }
        return { pinned: pinned, running: running };
    }
    // Hyprland'de gercek kucultme yok: pencere gorunmez "special:kucuk" workspace'ine tasinir
    function hdsp(cmd) { Quickshell.execDetached(["hyprctl", "dispatch", cmd]); }
    function minOf(o) {
        const ids = [];
        for (const t of o.wins) if (t.appId) ids.push(t.appId.toLowerCase());
        for (const m of root.minWins) if (ids.indexOf(m.cls) >= 0) return m;
        return null;
    }
    function launch(o) {
        if (o.wins.length === 0) { if (o.entry) o.entry.execute(); return; }
        // kucultulmus penceresi varsa: bulundugun workspace'e geri getir ve odakla
        const mn = root.minOf(o);
        if (mn) {
            root.hdsp('hl.dsp.window.move({ window = "address:' + mn.addr + '", workspace = "' + root.hFocusWs + '", follow = true })');
            root.hdsp('hl.dsp.focus({ window = "address:' + mn.addr + '" })');
            fsTimer.restart();
            return;
        }
        // zaten odakta: Win11 gibi kucult
        for (const t of o.wins) if (t.activated && o.wins.length === 1) {
            root.hdsp('hl.dsp.window.move({ workspace = "special:kucuk", follow = false })');
            fsTimer.restart();
            return;
        }
        if (o.wins.length === 1) { o.wins[0].activate(); return; }
        // birden fazla pencere: her tikta siradakine gec
        let cur = -1;
        for (let i = 0; i < o.wins.length; i++) if (o.wins[i].activated) cur = i;
        o.wins[(cur + 1) % o.wins.length].activate();
    }

    // ================= SAAT / AG / BILDIRIM =================
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var aylar: [root.t("Oca", "Jan"), root.t("Şub", "Feb"), root.t("Mar", "Mar"), root.t("Nis", "Apr"), root.t("May", "May"), root.t("Haz", "Jun"), root.t("Tem", "Jul"), root.t("Ağu", "Aug"), root.t("Eyl", "Sep"), root.t("Eki", "Oct"), root.t("Kas", "Nov"), root.t("Ara", "Dec")]
    readonly property var gunler: [root.t("Pazar", "Sunday"), root.t("Pazartesi", "Monday"), root.t("Salı", "Tuesday"), root.t("Çarşamba", "Wednesday"), root.t("Perşembe", "Thursday"), root.t("Cuma", "Friday"), root.t("Cumartesi", "Saturday")]
    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    property string netKind: "none"                        // wifi | eth | none
    property string ssid: ""
    property int signal: 0
    Process {
        id: netProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^ethernet:connected' && echo ETH; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text;
                if (t.indexOf("ETH") === 0) { root.netKind = "eth"; root.ssid = "Ethernet"; return; }
                const m = t.match(/^yes:(.*):(\d+)\s*$/m);
                if (m) { root.netKind = "wifi"; root.ssid = m[1].replace(/\\:/g, ":"); root.signal = parseInt(m[2]) || 0; }
                else { root.netKind = "none"; root.ssid = root.t("Bağlı değil", "Not connected"); }
            }
        }
    }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: netProc.running = true }
    readonly property string wifiIcon: root.netKind === "none" ? root.g(0xF092D)
                                     : root.signal > 75 ? root.g(0xF0928) : root.signal > 50 ? root.g(0xF0925)
                                     : root.signal > 25 ? root.g(0xF0922) : root.g(0xF091F)
    // bildirimler: senin bildirim merkezin ~/.cache/quickshell/notif-list.json'a yazar
    property int notifCount: 0
    property bool dnd: false
    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/notif-list.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); root.dnd = !!d.dnd; root.nItems = d.items || []; root.notifCount = root.nItems.length; root.nCheckNew(); } catch (e) {} }
    }

    // ================= SES =================
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    readonly property real vol: root.sink && root.sink.audio ? root.sink.audio.volume : 0
    readonly property bool muted: root.sink && root.sink.audio ? root.sink.audio.muted : false
    function setVol(v) {
        if (!root.sink || !root.sink.audio) return;
        v = Math.max(0, Math.min(1, v));
        if (root.muted && v > 0) root.sink.audio.muted = false;
        root.sink.audio.volume = v;
    }
    function toggleMute() { if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted; }
    readonly property string volIcon: (root.muted || root.vol <= 0.001) ? root.g(0xF075F)
                                    : root.vol < 0.34 ? root.g(0xF057F) : root.vol < 0.67 ? root.g(0xF0580) : root.g(0xF057E)

    // ================= PIL =================
    readonly property var batDev: UPower.displayDevice
    readonly property real batPct: {
        if (!root.batDev) return -1;
        const p = root.batDev.percentage;
        return p <= 1 ? p * 100 : p;
    }
    readonly property bool charging: !UPower.onBattery

    // ================= MUZIK (once Spotify) =================
    readonly property var player: {
        const ps = Mpris.players.values;
        let any = null;
        for (let i = 0; i < ps.length; i++) {
            const id = ((ps[i].identity || "") + " " + (ps[i].dbusName || "")).toLowerCase();
            if (id.indexOf("spotify") >= 0) return ps[i];
            if (!any && ps[i].trackTitle) any = ps[i];
        }
        return any;
    }
    readonly property bool hasMusic: root.player !== null && (root.player.trackTitle || "") !== ""
    // Sarki gecerken Spotify bilgileri bir anligina bosaltiyor: ekranda gosterilenler son dolu degerde
    // kalir, muzik "bitti" sayilmasi icin de 2 sn bos kalmasi gerekir (yoksa plak ve panel kapanip aciliyordu)
    property bool musicOn: false
    onHasMusicChanged: { if (root.hasMusic) { musicOffTimer.stop(); root.musicOn = true; } else musicOffTimer.restart(); }
    Timer { id: musicOffTimer; interval: 2000; onTriggered: root.musicOn = root.hasMusic }
    Component.onCompleted: { root.musicOn = root.hasMusic; rezervTimer.restart(); }
    property string dispTitle: ""
    property string dispArtist: ""
    property string dispArt: ""
    function syncTrack() {
        if (!root.player) return;
        const t = root.player.trackTitle || "", a = root.player.trackArtist || "", u = root.player.trackArtUrl || "";
        if (t !== "" && t !== root.dispTitle) { root.dispTitle = t; root.dispArtist = a; }
        else if (t !== "" && a !== "") root.dispArtist = a;
        if (u !== "") root.dispArt = u;
    }
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { root.syncTrack(); }
        function onTrackArtistChanged() { root.syncTrack(); }
        function onTrackArtUrlChanged() { root.syncTrack(); }
    }
    onPlayerChanged: root.syncTrack()
    readonly property bool playing: root.player !== null && root.player.isPlaying
    readonly property string trackTitle: root.dispTitle
    readonly property string trackArt: root.dispArt
    readonly property real trackLen: root.player && root.player.length > 0 ? root.player.length : 0
    property real trackPos: 0
    property real posHoldUntil: 0
    // sarki degisince halka hemen basa doner (Spotify ilk saniyede eski konumu verebiliyor)
    onTrackTitleChanged: { root.trackPos = 0; root.posHoldUntil = Date.now() + 1600; }
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.hasMusic && root.trackLen > 0
        onTriggered: {
            if (!root.player) return;
            root.player.positionChanged();
            const np = root.player.position;
            if (Date.now() < root.posHoldUntil && np > 3) return;
            root.trackPos = np;
        }
    }
    readonly property real trackFrac: root.trackLen > 0 ? Math.max(0, Math.min(1, root.trackPos / root.trackLen)) : 0
    function hiResArt(u) {
        if (!u) return "";
        // i.scdn.co kapak boyut kodlari: 4851=64px, 1e02=300px, b273=640px
        return u.replace("ab67616d00004851", "ab67616d0000b273").replace("ab67616d00001e02", "ab67616d0000b273");
    }
    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec || 0));
        return Math.floor(s / 60) + ":" + ((s % 60) < 10 ? "0" : "") + (s % 60);
    }

    // ---- calan playlist: bildirim merkezinin dinleyicisi ~/.cache/quickshell/spotify-playlist.json'a yazar ----
    property string plType: ""
    property string plName: ""
    property string plImage: ""
    readonly property bool plShown: root.musicOn && root.plName !== ""
    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/spotify-playlist.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.plType = j.type || ""; root.plName = j.name || ""; root.plImage = j.image || "";
            } catch (e) {}
        }
    }

    // ---- Spotify'in kendi ses akisi (PipeWire): sistem sesine dokunmaz ----
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
    PwObjectTracker { objects: Pipewire.nodes.values.filter(n => n && n.isStream) }
    readonly property bool spVolReady: root.spotifyNode !== null && root.spotifyNode.audio !== null
    readonly property real spVolume: root.spVolReady ? root.spotifyNode.audio.volume : 0
    readonly property bool spMuted: root.spVolReady && root.spotifyNode.audio.muted
    function setSpotifyVolume(v) {
        if (!root.spVolReady) return;
        const c = Math.max(0, Math.min(1, v));
        root.spotifyNode.audio.volume = c;
        if (c > 0 && root.spotifyNode.audio.muted) root.spotifyNode.audio.muted = false;
        const pl = root.player;
        if (pl && pl.volumeSupported && pl.canControl) { try { pl.volume = c; } catch (e) {} }
    }


    // ================= DUVAR KAGIDI MODU =================
    // Win+W (wallpaper menun, kontrol panelde Dock seciliyse buraya yonlendirir) -> dock genisleyip
    // dikey bir duvar kagidi menusune donusur; secince ya da kapatinca yine dock olur.
    // Ayni klasor, ayni kucuk resim onbellegi ve ayni set-wallpaperr.sh (notch'taki gibi).
    // settings.json: "wallpaperDir": "~/Pictures/Wallpapers", "wallpaperScript": "/path/set-wallpaper.sh"
    // Script yoksa: awww / swww ile duvar kagidi + varsa pywal (wal -i)
    readonly property string wallScript: root._evYolu(root.settings.wallpaperScript) || (Quickshell.env("HOME") + "/.config/hypr/scripts/wallpapers/set-wallpaperr.sh")
    readonly property string wallDir: root._evYolu(root.settings.wallpaperDir) || (Quickshell.env("HOME") + "/.config/wallpapers")
    function _evYolu(p) { return p ? String(p).replace(/^~(?=\/|$)/, Quickshell.env("HOME")) : ""; }
    readonly property int wallW: 300
    // yatay dock: duvar kagidi yatay serit, uygulamalar Win11 baslat menusu gibi izgara
    readonly property int wallHW: 860
    readonly property int wallHH: 270
    readonly property int appHW: 620
    readonly property int appHH: 584
    // dock'un donustugu menu: "" (normal dock) | "walls" (duvar kagidi) | "apps" (uygulamalar)
    property string dmode: ""
    readonly property bool wallMode: root.dmode !== ""      // (eski ad) herhangi bir menu acik mi
    function closeMode() { root.dmode = ""; }
    property string lastMode: "walls"
    onDmodeChanged: if (root.dmode !== "") root.lastMode = root.dmode
    readonly property int morphW: root.lastMode === "ezan" ? root.ezW : (root.lastMode === "dash" ? root.dashW : (root.lastMode === "net" ? root.netW : (root.lastMode === "notif" ? root.notifW : (root.lastMode === "toast" ? root.toastW : (root.lastMode === "bat" ? root.batW : (root.lastMode === "audio" ? root.audioW : (root.horiz && root.lastMode === "walls" ? root.wallHW : (root.horiz && root.lastMode === "apps" ? root.appHW : root.wallW))))))))
    function openEzan() {
        if (!root.ezAcik) return;                          // namaz vakitleri ayarlardan kapali
        if (root.dmode === "ezan") { root.closeMode(); return; }
        root.dmode = "ezan";
    }
    // kapanis sirasi: once menu solar (wallMode), sonra dock buzulur (wallShape), en son pencere daralir (wallWide)
    property bool wallShape: false
    property bool wallWide: false
    onWallModeChanged: {
        if (root.wallMode) { wallShapeOff.stop(); wallWideOff.stop(); root.wallShape = true; root.wallWide = true; }
        else { wallShapeOff.restart(); wallWideOff.restart(); }
    }
    // bildirim kutusu kapanirken: once kutu haliyle kenara kayar, sekil ancak ekran disindayken dock'a doner
    Timer { id: wallShapeOff; interval: root.toastClosing ? 320 : 80; onTriggered: root.wallShape = false }
    // dock buzulmesini bitirene kadar acik kalir, sonra (ustunde degilsen) her zamanki gibi gizlenir
    Timer { id: wallWideOff; interval: 420; onTriggered: { root.wallWide = false; root.toastClosing = false; } }
    property var wallAll: []
    property string wallCur: ""
    // listenin sirasi icin "aktif" olan: sadece menu acilirken guncellenir. Uygulayinca liste yeniden
    // siralanip kartlar yer degistirmesin (Enter'a basinca kartlar dagiliyordu), oldugu gibi kapansin.
    property string wallOrderCur: ""
    property string wallQuery: ""
    property int wallSel: 0
    property bool wallLoading: false
    signal wallsOpened()
    signal wallsReordered()
    // ayni duvar kagidi mi: tam yol ya da (yol farkli yazilmissa, ~ / sembolik baglanti) dosya adi
    function wallSame(a, b) {
        if (!a || !b) return false;
        if (a === b) return true;
        return a.split("/").pop() === b.split("/").pop();
    }
    // dock yeniden baslayinca da hangisinin aktif oldugu hemen bilinsin (eskiden ilk tarama bitene
    // kadar bos kaliyordu: aktif olan basa gelmiyor, secim en soldan basliyordu)
    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/current_wallpaper"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const t = text().trim(); if (t.length > 0) root.wallCur = t; }
    }
    readonly property var wallList: {
        let l = root.wallAll.slice();
        const ci = l.findIndex(w => root.wallSame(w.path, root.wallOrderCur));
        if (ci > 0) { const c = l.splice(ci, 1)[0]; l.unshift(c); }
        if (root.wallQuery.length === 0) return l;
        const q = root.wallQuery.toLowerCase();
        return l.filter(w => w.name.toLowerCase().includes(q));
    }
    // kural: su an uygulanmis duvar kagidi her zaman basta durur ama secim karesi ona asla gidemez
    function wallOk(i) { const w = root.wallList[i]; return !!w && !root.wallSame(w.path, root.wallCur); }
    function wallFirst() { for (let i = 0; i < root.wallList.length; i++) if (root.wallOk(i)) return i; return 0; }
    function wallFix() { if (!root.wallOk(root.wallSel)) root.wallSel = root.wallFirst(); }
    onWallListChanged: root.wallFix()
    onWallCurChanged: root.wallFix()
    onWallQueryChanged: root.wallSel = root.wallFirst()
    Process {
        id: wallScan
        command: ["bash", "-c",
            "c=$HOME/.cache/quickshell; " +
            // onizleme surumu degisti (eski uretimde simsiyah cikanlar vardi): bir kereligine hepsini yeniden uret
            "[ \"$(cat \"$c/.thv\" 2>/dev/null)\" = 2 ] || { rm -rf \"$c/thumbs\" \"$c/thumbs-hq\"; mkdir -p \"$c\"; echo 2 > \"$c/.thv\"; }; " +
            "mkdir -p \"$c/thumbs\"; rm -f \"$c/.thq\"; find \"$c\" -maxdepth 1 -name .thlock -mmin +10 -exec rmdir {} \\; 2>/dev/null; " +
            "if [ -s \"$c/current_wallpaper\" ]; then printf 'CUR|%s\\n' \"$(cat \"$c/current_wallpaper\")\"; fi; " +
            "find \"$1\" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) | sort | while read -r img; do " +
            "f=$(basename \"$img\"); t=\"$c/thumbs/$f.jpg\"; t2=\"$c/thumbs-hq/$f.jpg\"; mkdir -p \"$c/thumbs-hq\"; " +
            "ok() { [ -f \"$1\" ] && [ \"$1\" -nt \"$img\" ] && [ \"$(stat -c%s \"$1\" 2>/dev/null || echo 0)\" -gt 2048 ]; }; " +
            "th=\"$img\"; ok \"$t\" && th=\"$t\"; " +
            "hq=\"$img\"; ok \"$t2\" && hq=\"$t2\"; " +
            "printf 'W|%s|%s|%s|%s\\n' \"${f%.*}\" \"$img\" \"$th\" \"$hq\"; " +
            "[ \"$th\" = \"$img\" ] && printf '%s\\t%s\\t320\\n' \"$img\" \"$t\" >> \"$c/.thq\"; " +
            "[ \"$hq\" = \"$img\" ] && printf '%s\\t%s\\t720\\n' \"$img\" \"$t2\" >> \"$c/.thq\"; done; " +
            // eksik onizlemeler: menu acilirken CPU'yu bogmasin diye tek tek, dusuk oncelikle, arka planda
            "if [ -s \"$c/.thq\" ] && mkdir \"$c/.thlock\" 2>/dev/null; then q=\"$c/.thq.$$\"; mv \"$c/.thq\" \"$q\"; " +
            "( sleep 1; while IFS=$'\\t' read -r img out sz; do p=\"$out.yarim.jpg\"; h=$((sz*9/16)); " +
            "rm -f \"$p\"; " +
            "( command -v magick >/dev/null && nice -n 19 magick \"${img}[0]\" -auto-orient -resize \"${sz}x${h}^\" -quality 92 \"$p\" 2>/dev/null ) || " +
            "( command -v ffmpegthumbnailer >/dev/null && nice -n 19 ffmpegthumbnailer -i \"$img\" -o \"$p\" -s \"$sz\" -q 10 2>/dev/null ) || " +
            "( command -v ffmpeg >/dev/null && nice -n 19 ffmpeg -v quiet -y -i \"$img\" -frames:v 1 -vf \"scale=${sz}:-2\" -q:v 3 \"$p\" 2>/dev/null ); " +
            "if [ \"$(stat -c%s \"$p\" 2>/dev/null || echo 0)\" -gt 2048 ]; then mv -f \"$p\" \"$out\"; else rm -f \"$p\"; fi; " +
            "done < \"$q\"; rm -f \"$q\"; rmdir \"$c/.thlock\" ) >/dev/null 2>&1 & " +
            "else rm -f \"$c/.thq\"; fi",
            "bash", root.wallDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let cur = "";
                for (const line of this.text.split("\n")) {
                    const p = line.split("|");
                    if (p[0] === "CUR") cur = p.slice(1).join("|");
                    else if (p[0] === "W" && p.length >= 4) out.push({ name: p[1], path: p[2], thumb: p[3], hq: p[4] || p[3] });
                }
                if (cur.length > 0) root.wallCur = cur;
                // menu acikken aktif olan yeni ogrenildiyse: basa al, gorunumu en basa getir
                if (root.dmode === "walls" && root.wallQuery.length === 0 && !root.wallSame(root.wallOrderCur, root.wallCur)) {
                    root.wallOrderCur = root.wallCur;
                    reorderLater.restart();
                }
                // liste ayniysa dokunma: yoksa tum kartlar bastan olusup resimler yeniden yukleniyordu
                // (o arada kartlar bir an simsiyah gorunuyordu)
                if (JSON.stringify(out) !== JSON.stringify(root.wallAll)) root.wallAll = out;
                root.wallLoading = false;
                root.wallFix();
            }
        }
    }
    function openWalls() {
        if (root.dmode === "walls") { root.closeMode(); return; }
        root.wallQuery = "";
        root.wallOrderCur = root.wallCur;
        root.wallSel = root.wallFirst();
        root.wallLoading = root.wallAll.length === 0;
        wallScan.running = true;
        root.dmode = "walls";
        root.wallsOpened();
    }
    Timer { id: reorderLater; interval: 0; onTriggered: { root.wallSel = root.wallFirst(); root.wallsReordered(); } }
    function closeWalls() { root.closeMode(); }
    function wallMove(d) {
        const n = root.wallList.length;
        if (n === 0) return;
        let i = root.wallSel + d;
        while (i >= 0 && i < n && !root.wallOk(i)) i += d;
        if (i >= 0 && i < n) root.wallSel = i;
    }
    function wallApply(w) {
        if (!w) return;
        root.wallCur = w.path;
        Quickshell.execDetached(["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && { if [ -f \"$1\" ]; then bash \"$1\" \"$2\"; " +
            "else { awww img \"$2\" || swww img \"$2\"; } >/dev/null 2>&1; command -v wal >/dev/null && wal -q -n -i \"$2\"; true; fi; } " +
            "&& printf '%s' \"$2\" > \"$HOME/.cache/quickshell/current_wallpaper\"",
            "bash", root.wallScript, w.path]);
        root.closeWalls();
    }


    // ================= UYGULAMA MODU =================
    // Arch dugmesi ya da uygulama menun (Dock seciliyken buraya yonlendirir) -> dock dikey uygulama menusune donusur.
    // "En son kullanilanlar" uygulama menunle ve notch'la ayni dosyadan (~/.cache/appmenu_recent.json).
    property string appQuery: ""
    property int appSel: -1
    property var appRecent: []
    signal appsOpened()
    FileView {
        id: recentFile
        path: Quickshell.env("HOME") + "/.cache/appmenu_recent.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); root.appRecent = d.ids || []; } catch (e) {} }
    }
    readonly property var allApps: {
        const list = [...DesktopEntries.applications.values].filter(e => e.name && !e.noDisplay);
        list.sort((a, b) => a.name.localeCompare(b.name));
        const seen = new Set(), out = [];
        for (const e of list) {
            const k = e.name.toLowerCase();
            if (seen.has(k)) continue;
            seen.add(k); out.push(e);
        }
        const rec = root.appRecent;
        if (rec.length > 0) out.sort((a, b) => {
            const ia = rec.indexOf(a.name), ib = rec.indexOf(b.name);
            if (ia === -1 && ib === -1) return a.name.localeCompare(b.name);
            if (ia === -1) return 1;
            if (ib === -1) return -1;
            return ia - ib;
        });
        return out;
    }
    readonly property var appList: {
        if (root.appQuery.length === 0) return root.allApps;
        const q = root.appQuery.toLowerCase();
        return root.allApps.filter(e => (e.name || "").toLowerCase().includes(q) || (e.comment || "").toLowerCase().includes(q)
                                         || (e.genericName || "").toLowerCase().includes(q));
    }
    onAppListChanged: root.appSel = root.appList.length > 0 ? 0 : -1
    function entryId(e) { return e ? (e.id || e.name || "") : ""; }
    function isPinnedEntry(e) { return !!e && (root.pins.indexOf(e.id) >= 0 || root.pins.indexOf(e.name) >= 0); }
    function togglePinEntry(e) {
        if (!e) return;
        if (root.pins.indexOf(e.name) >= 0 && root.pins.indexOf(e.id) < 0) root.togglePin(e.name);
        else root.togglePin(e.id || e.name);
    }
    function openApps() {
        if (root.dmode === "apps") { root.closeMode(); return; }
        root.appQuery = "";
        root.appSel = root.appList.length > 0 ? 0 : -1;
        root.dmode = "apps";
        root.appsOpened();
    }
    function appMove(d) {
        const n = root.appList.length;
        if (n === 0) return;
        root.appSel = Math.max(0, Math.min(n - 1, root.appSel + d));
    }
    function appLaunch(e) {
        if (!e) return;
        const ids = root.appRecent.slice();
        const i = ids.indexOf(e.name);
        if (i !== -1) ids.splice(i, 1);
        ids.unshift(e.name);
        if (ids.length > 30) ids.length = 30;
        recentFile.setText(JSON.stringify({ ids: ids }));
        e.execute();
        root.closeMode();
    }
    function appActivate() {
        const l = root.appList;
        if (l.length === 0) return;
        root.appLaunch(l[Math.max(0, Math.min(l.length - 1, root.appSel))]);
    }


    // ================= EZAN MENUSU =================
    // Senin ~/.config/quickshell/ezanmenu'nun dock hali (saate tikla): ayni olculer (236 px panel, 16 px ic
    // bosluk, 30 px satir), ayni Aladhan/Diyanet verisi ve ayni ~/.cache/ezanmenu/vakitler.json.
    readonly property var ezSehirler: root._ezSehirListesi(root.settings.prayer)
    // namaz vakti sehirleri: settings.json -> "prayer": { "country": "Turkey", "method": 13, "cities": ["Istanbul", {"name": "İstanbul", "api": "Istanbul"}] }
    function _ezSehirListesi(p) {
        const c = (p && p.cities && p.cities.length) ? p.cities : [{ name: "İstanbul", api: "Istanbul" }];
        return c.map(x => {
            const ad = typeof x === "string" ? x : (x.name || x.api || "?");
            const api = typeof x === "string" ? x : (x.api || x.name || "");
            return { ad: ad, api: api, anahtar: String(api).toLowerCase().replace(/[^a-z0-9]/g, "") || "sehir" };
        });
    }
    // settings.json -> "prayer": { "enabled": true } ile acilir (varsayilan kapali: saate tik bir sey yapmaz, internete cikmaz)
    readonly property bool ezAcik: !!(root.settings.prayer && root.settings.prayer.enabled === true)
    readonly property string ezUlke: (root.settings.prayer && root.settings.prayer.country) || "Turkey"
    readonly property int ezMetot: (root.settings.prayer && root.settings.prayer.method !== undefined) ? root.settings.prayer.method : 13
    onEzSehirlerChanged: { if (root.ezSehirIndex >= root.ezSehirler.length) root.ezSehirIndex = 0; if (!ezCekici.running) ezCekici.running = true; }
    property bool ezPywal: false                           // cami simgesine tik: yesil <-> pywal
    property color ezAccent: ezPywal ? root.accent : "#3ddc97"
    Behavior on ezAccent { ColorAnimation { duration: 350; easing.type: Easing.OutCubic } }
    readonly property color ezTray: "#151515"
    readonly property color ezRow: "#232323"
    readonly property color ezInk: "#e8e8e8"
    readonly property color ezDim: "#6f6f6f"
    readonly property color ezPast: "#454545"
    readonly property color ezTrack: "#242424"
    readonly property color ezStale: "#e0a030"
    readonly property string ezFont: "JetBrainsMono Nerd Font"
    readonly property int ezW: root.horiz ? 16 + 204 + 24 + root.ezTrayW + 16 : 236
    readonly property int ezTrayW: 240
    readonly property int ezPad: 16
    readonly property int ezRowH: 30
    readonly property int ezTrayPadV: 8
    readonly property int ezTrayPadH: 22
    property real ezContentH: 300
    readonly property int ezH: root.horiz ? root.ezRowH * 5 + root.ezTrayPadV * 2 + root.ezPad * 2 : Math.round(root.ezContentH) + root.ezPad * 2
    property int ezSehirIndex: 0
    property var ezVeri: ({})
    property int ezSimdiSn: 0
    property int ezBugun: new Date().getDate()
    property string ezVeriTarihi: ""
    readonly property var ezGunAdlari: [root.t("Pazar", "Sunday"),root.t("Pazartesi", "Monday"),root.t("Salı", "Tuesday"),root.t("Çarşamba", "Wednesday"),root.t("Perşembe", "Thursday"),root.t("Cuma", "Friday"),root.t("Cumartesi", "Saturday")]
    readonly property var ezVakitler: {
        const a = ezSehirler[ezSehirIndex].anahtar;
        return ezVeri[a] !== undefined ? ezVeri[a] : [];
    }
    readonly property bool ezVeriVar: ezVakitler.length === 5
    readonly property bool ezVeriEski: {
        if (!ezVeriVar || ezVeriTarihi === "") return false;
        return ezVeriTarihi !== Qt.formatDate(new Date(), "dd-MM-yyyy");
    }
    readonly property int ezSiradaki: {
        if (!ezVeriVar) return 0;
        for (let i = 0; i < 5; i++)
            if (ezDakika(ezVakitler[i][1]) * 60 > ezSimdiSn) return i;
        return 0;
    }
    property real ezIcerikOpacity: 1.0
    property real ezIcerikKayma: 0
    property int ezGecisYonu: 1
    readonly property int ezCityShift: 7
    readonly property real ezNoktaY: ezTrayPadV + ezSiradaki * ezRowH + ezRowH / 2
    function ezDakika(hhmm) {
        const p = String(hhmm).split(":");
        return parseInt(p[0], 10) * 60 + parseInt(p[1], 10);
    }
    function ezIki(n) { return n < 10 ? "0" + n : "" + n; }
    function ezKalan() {
        if (!ezVeriVar) return 0;
        let k = ezDakika(ezVakitler[ezSiradaki][1]) * 60 - ezSimdiSn;
        if (k < 0) k += 24 * 3600;
        return k;
    }
    function ezSaat() {
        const d = new Date();
        ezSimdiSn = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds();
        if (d.getDate() !== ezBugun) { ezBugun = d.getDate(); ezCekici.running = true; }
    }
    signal ezSehirDegisti(int yon)
    function ezSehirDegistir(yon) { root.ezSehirDegisti(yon); }
    readonly property string ezCekmeKomutu:
        'd="$HOME/.cache/ezanmenu"; mkdir -p "$d"; t=$(mktemp); ' +
        'yaz() { printf "%s" "$1" >> "$t"; }; ' +
        'yaz "{"; ilk=1; ' +
        'for c in ' + root.ezSehirler.map(s => '"' + s.anahtar + ':' + encodeURIComponent(s.api) + '"').join(' ') + '; do ' +
        '  k=${c%%:*}; s=${c#*:}; ' +
        '  u="https://api.aladhan.com/v1/timingsByCity?city=$s&country=' + encodeURIComponent(root.ezUlke) + '&method=' + root.ezMetot + '"; ' +
        '  j=$(curl -sSL --max-redirs 5 --max-time 20 --retry 2 --retry-delay 2 "$u" 2>&1); ' +
        '  case "$j" in ' +
        '    \'{"code":200\'*) : ;; ' +
        '    *) echo "HATA [$k]: ${j:-bos yanit}" >&2; rm -f "$t"; exit 1 ;; ' +
        '  esac; ' +
        '  [ $ilk -eq 1 ] || yaz ","; ilk=0; ' +
        '  printf \'"%s":\' "$k" >> "$t"; yaz "$j"; ' +
        'done; ' +
        'yaz "}"; ' +
        'mv "$t" "$d/vakitler.json"; ' +
        'echo "tamam"'
    Process {
        id: ezCekici
        command: ["sh", "-c", root.ezAcik ? root.ezCekmeKomutu : "true"]
        running: false
        onExited: (code, status) => { if (code === 0 && root.ezAcik) ezCache.reload(); }
    }
    Process {
        id: ezSilici
        command: ["sh", "-c", "rm -f \"$HOME/.cache/ezanmenu/vakitler.json\""]
        running: false
        onExited: ezCekici.running = true
    }
    FileView {
        id: ezCache
        path: Quickshell.env("HOME") + "/.cache/ezanmenu/vakitler.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.ezIsle(text())
        onLoadFailed: (error) => { if (root.ezAcik) ezCekici.running = true; }
    }
    function ezIsle(ham) {
        try {
            const j = JSON.parse(ham);
            const yeni = {};
            const temiz = (v) => String(v).split(" ")[0];
            let tarih = "";
            for (let i = 0; i < ezSehirler.length; i++) {
                const a = ezSehirler[i].anahtar;
                if (!j[a] || !j[a].data || !j[a].data.timings) continue;
                const t = j[a].data.timings;
                if (tarih === "" && j[a].data.date && j[a].data.date.gregorian)
                    tarih = String(j[a].data.date.gregorian.date);
                yeni[a] = [
                    [root.t("Sabah", "Fajr"),  temiz(t.Fajr)],
                    [root.t("Öğlen", "Dhuhr"),  temiz(t.Dhuhr)],
                    [root.t("İkindi", "Asr"), temiz(t.Asr)],
                    [root.t("Akşam", "Maghrib"),  temiz(t.Maghrib)],
                    [root.t("Yatsı", "Isha"),  temiz(t.Isha)]
                ];
            }
            ezVeri = yeni;
            ezVeriTarihi = tarih;
        } catch (e) {
            ezSilici.running = true;
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.ezSaat() }
    Timer { interval: 21600000; running: true; repeat: true; onTriggered: ezCekici.running = true }



    // ================= DASHBOARD: Arch'a tiklayinca dock sistem paneline donusur =================
    // yatayda kare-genis sade panel (alttan ortadan yukari esner)
    readonly property int dashW: root.horiz ? 600 : 360
    readonly property int dashH: root.horiz ? 492 : 626
    function openDash() {
        if (root.dmode === "dash") { root.closeMode(); return; }
        root.dmode = "dash";
    }
    property real dCpu: 0              // 0..1
    property real dRam: 0
    property real dRamUsed: 0          // GB
    property real dRamTot: 0
    property real dDisk: 0
    property real dDiskUsed: 0
    property real dDiskTot: 0
    property string dDiskName: ""
    property int dCpuTemp: -1
    property bool dGpuOk: false
    property string dGpuName: ""
    property string dGpuDrv: ""
    property real dGpu: 0
    property int dGpuTemp: -1
    property real dGpuW: -1
    property real dVramUsed: 0
    property real dVramTot: 0
    property int dGpuFan: -1
    property var dGpuHist: []          // son sicakliklar (2 sn arayla)
    property string dUptime: ""
    property var dProcs: []            // [{ n, c (0..1), r (MB) }]
    property var _cpuPrev: null

    function _dashFmtUp(sec) {
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        if (d > 0) return d + root.t("g ", "d ") + h + root.t("sa", "h");
        if (h > 0) return h + root.t("sa ", "h ") + m + root.t("dk", "m");
        return m + "dk";
    }
    function _procName(n) {
        const l = n.toLowerCase();
        // firefox'un alt surecleri tek isim altinda toplansin
        if (/^(isolated web|web content|webextensions|privileged cont|socket process|rdd process|utility process|forkserver|gpu process)/.test(l)) return "firefox";
        if (l.indexOf("firefox") === 0) return "firefox";
        if (l.indexOf("discord") === 0) return "discord";
        if (l.indexOf("spotify") === 0) return "spotify";
        if (l === "qs" || l.indexOf("quickshell") === 0) return "quickshell";
        if (l.indexOf("steamwebhelper") === 0 || l === "steam") return "steam";
        if (l.indexOf("electron") === 0) return "electron";
        return n.length > 14 ? n.slice(0, 14) : n;
    }
    function _dashParse(t) {
        const parts = t.split("@@TOP");
        const head = parts[0].split("\n");
        let memTot = 0, memAv = 0, nproc = 1, diskPick = "";
        const fsList = [];
        for (const line of head) {
            const f = line.trim().split(/\s+/);
            if (f[0] === "CPU") {
                const v = f.slice(1).map(Number);
                const idle = v[3] + v[4], tot = v.reduce((a, b) => a + b, 0);
                if (root._cpuPrev) {
                    const dt = tot - root._cpuPrev.tot, di = idle - root._cpuPrev.idle;
                    if (dt > 0) root.dCpu = Math.max(0, Math.min(1, 1 - di / dt));
                }
                root._cpuPrev = { tot: tot, idle: idle };
            } else if (f[0] === "MemTotal:") memTot = Number(f[1]);
            else if (f[0] === "MemAvailable:") memAv = Number(f[1]);
            else if (f[0] === "UP") root.dUptime = root._dashFmtUp(Number(f[1]) || 0);
            else if (f[0] === "NPROC") nproc = Number(f[1]) || 1;
            else if (f[0] === "FS" && f.length >= 4) fsList.push({ t: f[1], s: Number(f[2]), u: Number(f[3]) });
            else if (f[0] === "DISKPICK") diskPick = f.slice(1).join(" "); else if (f[0] === "CTEMP") root.dCpuTemp = Math.round(Number(f[1]) / 1000);
            else if (f[0] === "GPU") {
                const g = line.slice(4).split(",").map(s => s.trim());
                const num = s => { const x = parseFloat(s); return isNaN(x) ? -1 : x; };
                root.dGpuOk = true;
                root.dGpuName = g[0].replace(/^NVIDIA\s+/, "").replace(/GeForce\s+/, "").replace(/\s+GPU$/, "");
                root.dGpuDrv = (g[1] || "").split(".")[0];
                root.dGpu = Math.max(0, num(g[2])) / 100;
                root.dGpuTemp = Math.round(num(g[3]));
                root.dGpuW = num(g[4]);
                root.dVramUsed = Math.max(0, num(g[5])) / 1024;
                root.dVramTot = Math.max(0, num(g[6])) / 1024;
                root.dGpuFan = Math.round(num(g[7]));
                if (root.dGpuTemp >= 0) {
                    const h = root.dGpuHist.slice(-39); h.push(root.dGpuTemp); root.dGpuHist = h;
                }
            }
        }
        // disk: ~/.config/quickshell/dock/disk-yolu dosyasinda yol varsa o, yoksa en buyuk bolum
        if (fsList.length) {
            let d = diskPick ? fsList.find(x => x.t === diskPick) : null;
            if (!d) d = fsList.slice().sort((a, b) => b.s - a.s)[0];
            root.dDiskTot = d.s / 1e9; root.dDiskUsed = d.u / 1e9;
            root.dDisk = d.s > 0 ? d.u / d.s : 0;
            root.dDiskName = d.t;
        }
        if (memTot > 0) {
            root.dRamTot = memTot / 1048576; root.dRamUsed = (memTot - memAv) / 1048576;
            root.dRam = root.dRamUsed / root.dRamTot;
        }
        // surecler (top'un ikinci olcumu): PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND
        if (parts.length > 1) {
            const groups = {};
            for (const line of parts[1].split("\n")) {
                const f = line.trim().split(/\s+/);
                if (f.length < 12 || !/^\d+$/.test(f[0])) continue;
                const cpu = parseFloat(f[8].replace(",", ".")) || 0;
                let res = f[5].replace(",", ".");
                let mb = parseFloat(res) || 0;
                if (/g$/i.test(res)) mb *= 1024; else if (/t$/i.test(res)) mb *= 1048576;
                const n = root._procName(f.slice(11).join(" "));
                if (n === "top") continue;
                const gr = groups[n] || (groups[n] = { n: n, c: 0, r: 0 });
                gr.c += cpu / 100 / nproc; gr.r += mb;
            }
            const arr = Object.values(groups).sort((a, b) => (b.c - a.c) || (b.r - a.r)).slice(0, 4);
            root.dProcs = arr;
        }
    }
    Process {
        id: dashProc
        command: ["sh", "-c",
            "read -r _ a b c d e f g h _ < /proc/stat; echo \"CPU $a $b $c $d $e $f $g $h\"; " +
            "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; " +
            "echo \"UP $(cut -d' ' -f1 /proc/uptime)\"; echo \"NPROC $(nproc)\"; " +
            "df -B1 --output=target,size,used -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs -x vfat -x fuse.portal 2>/dev/null | tail -n +2 | sed 's/^/FS /'; " +
            "echo \"DISKPICK $(cat \"$HOME/.config/quickshell/dock/disk-yolu\" 2>/dev/null)\"; " +
            "for h in /sys/class/hwmon/hwmon*; do case \"$(cat $h/name 2>/dev/null)\" in coretemp|k10temp|zenpower) echo \"CTEMP $(cat $h/temp1_input)\"; break;; esac; done; " +
            "nvidia-smi --query-gpu=name,driver_version,utilization.gpu,temperature.gpu,power.draw,memory.used,memory.total,fan.speed --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/^/GPU /'; " +
            "echo @@TOP; top -b -n 2 -d 0.6 -w 256 -e m -o %CPU 2>/dev/null | awk '/^top -/{n++} n==2' | tail -n +8"]
        stdout: StdioCollector { onStreamFinished: root._dashParse(this.text) }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.dmode === "dash"
        onTriggered: if (!dashProc.running) dashProc.running = true
    }
    // guc dugmeleri: Kapat / Yeniden / Cikis ikinci tikla calisir (yanlislikla basilmasin)
    property int dashArm: -1
    Timer { id: dashArmOff; interval: 3000; onTriggered: root.dashArm = -1 }
    Connections { target: root; function onDmodeChanged() { if (root.dmode !== "dash") root.dashArm = -1; } }
    function dashPower(i) {
        const needConfirm = i >= 2;
        if (needConfirm && root.dashArm !== i) { root.dashArm = i; dashArmOff.restart(); return; }
        root.dashArm = -1;
        root.closeMode();
        const cmds = [
            ["hyprlock"],
            ["systemctl", "suspend"],
            ["sh", "-c", "hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || loginctl terminate-user \"$USER\""],
            ["systemctl", "reboot"],
            ["sh", "-c", "s=\"$HOME/.config/hypr/scripts/kapanmaefek\"; [ -x \"$s\" ] && exec \"$s\" || exec systemctl poweroff"]
        ];
        dashRun.cmd = cmds[i];
        dashRun.restart();
    }
    Timer { id: dashRun; property var cmd: []; interval: 420; onTriggered: Quickshell.execDetached(cmd) }


    // ================= AG MODU: wi-fi/ethernet simgesine tiklayinca dock ag menusune donusur =================
    readonly property int netW: root.horiz ? 680 : 330
    // yatay: solda durum + anahtarlar, sagda liste
    readonly property int netHH: 290
    readonly property int netCol: 308
    readonly property int netRx: 16 + root.netCol + 16
    function openNet() {
        if (root.dmode === "net") { root.closeMode(); return; }
        root.nPass = ""; root.nMsg = ""; root.nMsgBad = false;
        root.dmode = "net";
        netRefresh();
        if (root.nView === "bt") { root.btRefresh(); if (!btScan.running) btScan.running = true; }
        else netScan.running = true;
    }
    property bool nWifiOn: false
    property bool nBtOn: false
    property bool nBtPresent: false
    property string nWifiDev: ""
    property string nEthDev: ""
    property bool nEthOn: false            // kablo bagli ve bagli durumda
    property bool nEthPlug: false          // kablo takili (bagli ya da kesik)
    property string nEthIp: ""
    property string nWifiIp: ""
    property string nCurSsid: ""
    property int nCurSig: 0
    property var nList: []                 // [{ ssid, signal, secured, inUse, known }]
    property string nBusy: ""              // baglanilan ag
    property string nPass: ""              // sifresi sorulan ag
    property string nMsg: ""
    property bool nMsgBad: false
    Timer { id: nMsgOff; interval: 3500; onTriggered: root.nMsg = "" }
    function nSay(t, bad) { root.nMsg = t; root.nMsgBad = !!bad; nMsgOff.restart(); }

    // nmcli -t ciktisinda ":" -> "\:" kacisli; once koruyup sonra boluyoruz
    function _nSplit(line) {
        return line.replace(/\\\\/g, "\u0001").replace(/\\:/g, "\u0002").split(":")
                   .map(x => x.replace(/\u0002/g, ":").replace(/\u0001/g, "\\"));
    }
    function _netParse(t) {
        const sec = t.split("@@");
        // 1) cihazlar
        let wdev = "", edev = "", eon = false, eplug = false;
        for (const line of (sec[0] || "").trim().split("\n")) {
            const f = root._nSplit(line);
            if (f.length < 3) continue;
            if (f[1] === "wifi" && !wdev) wdev = f[0];
            if (f[1] === "ethernet" && !edev) {
                edev = f[0];
                eon = f[2] === "connected";
                eplug = f[2] !== "unavailable" && f[2] !== "unmanaged";
            }
        }
        root.nWifiDev = wdev; root.nEthDev = edev; root.nEthOn = eon; root.nEthPlug = eplug;
        // 2) wi-fi radyosu
        root.nWifiOn = (sec[1] || "").trim() === "enabled";
        // 3) kayitli baglantilar
        const known = {};
        for (const line of (sec[3] || "").trim().split("\n")) {
            const f = root._nSplit(line);
            if (f.length >= 2 && (f[1].indexOf("wireless") >= 0 || f[1] === "wifi")) known[f[0]] = true;
        }
        // 4) aglar (ayni isimden en guclusu)
        const seen = {};
        for (const line of (sec[2] || "").trim().split("\n")) {
            const f = root._nSplit(line);
            if (f.length < 4 || f[1] === "") continue;
            const it = { ssid: f[1], signal: parseInt(f[2]) || 0, secured: f[3] !== "" && f[3] !== "--",
                         inUse: f[0].indexOf("*") >= 0, known: !!known[f[1]] };
            const o = seen[it.ssid];
            if (!o || it.inUse || (!o.inUse && it.signal > o.signal)) seen[it.ssid] = it;
        }
        const list = Object.values(seen).sort((a, b) => (a.inUse !== b.inUse) ? (a.inUse ? -1 : 1) : (b.signal - a.signal));
        root.nList = root.nWifiOn ? list : [];
        const cur = list.find(x => x.inUse);
        root.nCurSsid = cur ? cur.ssid : ""; root.nCurSig = cur ? cur.signal : 0;
        if (cur && root.nBusy === cur.ssid) { root.nBusy = ""; root.nSay(root.t(cur.ssid + " ağına bağlandı", "Connected to " + cur.ssid)); }
        // 5) bluetooth
        const bt = (sec[4] || "").trim();
        root.nBtPresent = bt !== "";
        root.nBtOn = bt.indexOf("yes") >= 0;
        // 6) ip adresleri
        root.nEthIp = ""; root.nWifiIp = "";
        for (const line of (sec[5] || "").trim().split("\n")) {
            const m = line.match(/^IP (\S+) (\S+)/);
            if (!m) continue;
            const ip = m[2].split("/")[0];
            if (m[1] === edev) root.nEthIp = ip;
            if (m[1] === wdev) root.nWifiIp = ip;
        }
    }
    Process {
        id: netProc2
        command: ["sh", "-c",
            "nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null; echo @@; " +
            "nmcli radio wifi 2>/dev/null; echo @@; " +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null; echo @@; " +
            "nmcli -t -f NAME,TYPE connection show 2>/dev/null; echo @@; " +
            "bluetoothctl show 2>/dev/null | grep -m1 'Powered:'; echo @@; " +
            "for d in $(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: '$2==\"connected\"{print $1}'); do " +
            "a=$(nmcli -g IP4.ADDRESS device show \"$d\" 2>/dev/null | head -1); [ -n \"$a\" ] && echo \"IP $d $a\"; done"]
        stdout: StdioCollector { onStreamFinished: root._netParse(this.text) }
    }
    function netRefresh() { if (!netProc2.running) netProc2.running = true; else netAgain.restart(); }
    Timer { id: netAgain; interval: 400; onTriggered: root.netRefresh() }
    Timer { interval: 4000; repeat: true; running: root.dmode === "net"; onTriggered: root.netRefresh() }
    // tarama: bitince listeyi tazele
    Process { id: netScan; command: ["nmcli", "device", "wifi", "rescan"]; onExited: root.netRefresh() }
    readonly property bool nScanning: netScan.running

    // eylemler (komutlar dizi olarak: sifre/isimde ozel karakter olsa da sorun yok)
    Process {
        id: netAct
        property string what: ""
        stdout: StdioCollector { id: netActOut }
        stderr: StdioCollector { id: netActErr }
        onExited: (code, status) => {
            if (netAct.what === "connect") {
                if (code === 0) { root.nPass = ""; }
                else {
                    const err = (netActErr.text + netActOut.text).toLowerCase();
                    const ssid = root.nBusy;
                    root.nBusy = "";
                    if (err.indexOf("secrets") >= 0 || err.indexOf("password") >= 0 || err.indexOf("802-11-wireless-security") >= 0)
                        root.nSay(root.t("Şifre yanlış ya da eksik", "Wrong or missing password"), true);
                    else root.nSay(root.t("Bağlanılamadı: ", "Couldn't connect: ") + ssid, true);
                }
            }
            netAct.what = "";
            root.netRefresh();
        }
    }
    function _nRun(what, cmd) {
        if (netAct.running) return;
        netAct.what = what;
        netAct.command = cmd;
        netAct.running = true;
    }
    function netConnect(it, pw) {
        if (!it) return;
        if (it.inUse) return;
        root.nBusy = it.ssid;
        if (pw !== undefined && pw !== "") root._nRun("connect", ["nmcli", "device", "wifi", "connect", it.ssid, "password", pw]);
        else if (it.known) root._nRun("connect", ["nmcli", "connection", "up", "id", it.ssid]);
        else if (!it.secured) root._nRun("connect", ["nmcli", "device", "wifi", "connect", it.ssid]);
        else { root.nBusy = ""; root.nPass = it.ssid; }   // sifre sor
    }
    function netDisconnect() {
        if (root.nWifiDev) root._nRun("down", ["nmcli", "device", "disconnect", root.nWifiDev]);
    }
    function netForget(ssid) { root._nRun("forget", ["nmcli", "connection", "delete", "id", ssid]); root.nSay(root.t(ssid + " unutuldu", "Forgot " + ssid)); }
    function netToggleWifi() { root.nWifiOn = !root.nWifiOn; root._nRun("radio", ["nmcli", "radio", "wifi", root.nWifiOn ? "on" : "off"]); }
    function netToggleEth() {
        if (!root.nEthDev) return;
        root._nRun("eth", ["nmcli", "device", root.nEthOn ? "disconnect" : "connect", root.nEthDev]);
    }
    function netToggleBt() {
        root.nBtOn = !root.nBtOn;
        root._nRun("bt", ["sh", "-c", root.nBtOn ? "rfkill unblock bluetooth; sleep 0.3; bluetoothctl power on" : "bluetoothctl power off"]);
        if (!root.nBtOn) root.bList = [];
    }


    // ---- ag menusu: alt liste Wi-Fi aglari mi, Bluetooth cihazlari mi ----
    property string nView: "wifi"
    function netShow(v) {
        root.nView = v;
        root.nPass = "";
        if (v === "bt") { root.btRefresh(); if (root.nBtOn && !btScan.running) btScan.running = true; }
        else if (root.nWifiOn && !netScan.running) netScan.running = true;
    }
    property var bList: []                 // [{ mac, name, paired, conn, icon, bat }]
    property string bBusy: ""
    function _btParse(t) {
        const out = [];
        for (const line of t.trim().split("\n")) {
            const f = line.split("|");
            if (f.length < 6) continue;
            const name = f.slice(5).join("|").trim();
            if (!name || name.replace(/-/g, ":").toUpperCase() === f[0].toUpperCase()) continue;   // isimsiz cihazlari gosterme
            out.push({ mac: f[0], paired: f[1] === "yes", conn: f[2] === "yes", icon: f[3], bat: parseInt(f[4]) || -1, name: name });
        }
        out.sort((a, b) => (b.conn - a.conn) || (b.paired - a.paired) || a.name.localeCompare(b.name));
        root.bList = out;
        if (root.bBusy !== "" && out.some(d => d.mac === root.bBusy && d.conn)) root.bBusy = "";
    }
    Process {
        id: btProc
        command: ["sh", "-c",
            "bluetoothctl devices 2>/dev/null | while read -r _ mac name; do " +
            "i=$(bluetoothctl info \"$mac\" 2>/dev/null); " +
            "p=$(echo \"$i\" | grep -m1 'Paired:' | awk '{print $2}'); " +
            "c=$(echo \"$i\" | grep -m1 'Connected:' | awk '{print $2}'); " +
            "ic=$(echo \"$i\" | grep -m1 'Icon:' | awk '{print $2}'); " +
            "b=$(echo \"$i\" | grep -m1 'Battery Percentage' | sed 's/.*(\\([0-9]*\\)).*/\\1/'); " +
            "echo \"$mac|$p|$c|$ic|$b|$name\"; done"]
        stdout: StdioCollector { onStreamFinished: root._btParse(this.text) }
    }
    function btRefresh() { if (!btProc.running) btProc.running = true; }
    Timer { interval: 3000; repeat: true; running: root.dmode === "net" && root.nView === "bt"; onTriggered: root.btRefresh() }
    Process { id: btScan; command: ["bluetoothctl", "--timeout", "10", "scan", "on"]; onExited: root.btRefresh() }
    readonly property bool bScanning: btScan.running
    Process {
        id: btAct
        property string what: ""
        property string mac: ""
        onExited: (code, status) => {
            if (btAct.what === "connect" && code !== 0) {
                const d = root.bList.find(x => x.mac === btAct.mac);
                root.nSay(root.t("Bağlanılamadı", "Couldn't connect") + (d ? ": " + d.name : ""), true);
            }
            if (btAct.what === "connect") root.bBusy = "";
            btAct.what = "";
            root.btRefresh();
        }
    }
    function _btRun(what, mac, cmd) {
        if (btAct.running) return;
        btAct.what = what; btAct.mac = mac;
        btAct.command = cmd;
        btAct.running = true;
    }
    function btConnect(d) {
        if (!d || d.conn) return;
        root.bBusy = d.mac;
        if (d.paired) root._btRun("connect", d.mac, ["bluetoothctl", "connect", d.mac]);
        else root._btRun("connect", d.mac, ["sh", "-c", "bluetoothctl --timeout 15 pair \"$0\" && bluetoothctl trust \"$0\" && bluetoothctl connect \"$0\"", d.mac]);
    }
    function btDisconnect(d) { if (d) root._btRun("down", d.mac, ["bluetoothctl", "disconnect", d.mac]); }
    function btForget(d) { if (d) { root._btRun("forget", d.mac, ["bluetoothctl", "remove", d.mac]); root.nSay(root.t(d.name + " kaldırıldı", "Removed " + d.name)); } }
    function btIcon(ic) {
        if (!ic) return 0xF00AF;
        if (ic.indexOf("headset") >= 0) return 0xF02CE;
        if (ic.indexOf("audio") >= 0 || ic.indexOf("headphone") >= 0) return 0xF02CB;
        if (ic.indexOf("mouse") >= 0) return 0xF037D;
        if (ic.indexOf("keyboard") >= 0) return 0xF030C;
        if (ic.indexOf("phone") >= 0) return 0xF011C;
        if (ic.indexOf("gaming") >= 0) return 0xF05BA;
        if (ic.indexOf("computer") >= 0) return 0xF0322;
        if (ic.indexOf("video") >= 0) return 0xF0502;
        return 0xF00AF;
    }


    // ================= BILDIRIM MODU: zile tiklayinca dock bildirim paneline donusur =================
    readonly property int notifW: root.horiz ? 700 : 340
    readonly property int notifHH: 400
    function openNotif() {
        if (root.dmode === "notif") { root.closeMode(); return; }
        root.nNow = new Date();
        root.dmode = "notif";
    }
    property var nItems: []                // notif-list.json'daki bildirimler (en yeni ustte)
    property var nGroupOpen: ({})
    property date nNow: new Date()
    Timer { interval: 30000; repeat: true; running: root.dmode === "notif"; onTriggered: root.nNow = new Date() }
    readonly property var nGroups: {
        const g = [], idx = {};
        const items = root.nItems.slice().sort((a, b) => (b.time || 0) - (a.time || 0));
        for (const n of items) {
            if (idx[n.app] === undefined) { idx[n.app] = g.length; g.push({ app: n.app, icon: n.icon || "", items: [n] }); }
            else { g[idx[n.app]].items.push(n); if (!g[idx[n.app]].icon && n.icon) g[idx[n.app]].icon = n.icon; }
        }
        return g;
    }
    function notifCall(args) {
        Quickshell.execDetached(["quickshell", "-p", Quickshell.env("HOME") + "/.config/quickshell/notifications", "ipc", "call", "notifcenter"].concat(args));
    }
    // ekrandan hemen gitsin; bildirim merkezi listeyi yazinca zaten esitlenir
    function nDismiss(id) { root.nItems = root.nItems.filter(n => n.id !== id); root.notifCount = root.nItems.length; root.notifCall(["dismiss", String(id)]); }
    function nDismissApp(app) { root.nItems = root.nItems.filter(n => n.app !== app); root.notifCount = root.nItems.length; root.notifCall(["dismissApp", app]); }
    function nClear() { if (root.nItems.length === 0) return; root.nItems = []; root.notifCount = 0; root.notifCall(["clearAll"]); }
    function nInvoke(n) {
        if (!n) return;
        root.nItems = root.nItems.filter(x => x.id !== n.id); root.notifCount = root.nItems.length;
        root.notifCall(["invoke", String(n.id)]);
        if (n.action) root.closeMode();
    }
    function nToggleDnd() { root.dnd = !root.dnd; root.notifCall(["setDnd", root.dnd ? "true" : "false"]); }
    function nToggleGroup(app) { const c = Object.assign({}, root.nGroupOpen); c[app] = !c[app]; root.nGroupOpen = c; }
    function nAgo(t) {
        const s = Math.max(0, Math.floor((root.nNow.getTime() - (t || 0)) / 1000));
        if (s < 60) return root.t("şimdi", "now");
        if (s < 3600) return Math.floor(s / 60) + root.t(" dk", " min");
        if (s < 86400) return Math.floor(s / 3600) + root.t(" sa", " h");
        return Math.floor(s / 86400) + root.t(" gün", " d");
    }
    // govdedeki html/markup'i temizle
    function nPlain(t) {
        return (t || "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "")
                        .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").trim();
    }


    // ================= BILDIRIM GELINCE: dock kisa sureligine bildirim kutusuna donusur =================
    readonly property int toastW: 330
    readonly property int toastH: 104
    readonly property bool toastMode: root.dmode === "toast"
    property var tN: null                  // gosterilen bildirim
    property var nSeen: ({})
    property bool nSeenInit: false
    function nCheckNew() {
        const items = root.nItems;
        if (!root.nSeenInit) { for (const n of items) root.nSeen[n.id] = true; root.nSeenInit = true; return; }
        let fresh = null;
        for (const n of items) {
            if (root.nSeen[n.id]) continue;
            root.nSeen[n.id] = true;
            if (!fresh || (n.time || 0) > (fresh.time || 0)) fresh = n;
        }
        if (fresh && !root.dnd && Date.now() - (fresh.time || 0) < 20000) { root.nSound(); root.showToast(fresh); }
    }
    // ---- bildirim sesi: AE86 "ding ding" (rahatsiz etme acikken calmaz) ----
    // once ~/.config/quickshell/dock/bildirim.mp3, yoksa ~/Indirilenler/burda.mp3; pw-play / mpv / ffplay / paplay hangisi varsa
    property real nSoundLast: 0
    function nSound() {
        const now = Date.now();
        if (now - root.nSoundLast < 600) return;          // ust uste gelen bildirimlerde tek ding
        root.nSoundLast = now;
        Quickshell.execDetached(["bash", "-c",
            "f=\"$HOME/.config/quickshell/dock/bildirim.mp3\"; [ -f \"$f\" ] || exit 0; " +
            "if command -v pw-play >/dev/null && pw-play --media-role=Notification \"$f\" 2>/dev/null; then exit 0; fi; " +
            "if command -v mpv >/dev/null; then exec mpv --no-video --really-quiet --no-config \"$f\"; fi; " +
            "if command -v ffplay >/dev/null; then exec ffplay -nodisp -autoexit -loglevel quiet \"$f\"; fi; " +
            "command -v paplay >/dev/null && exec paplay \"$f\""]);
    }
    // gizli dock'ta: once (ekran disindayken) kutu boyuna gecilir ve tam kutu genisligi kadar
    // sola alinir, bir kare sonra kayarak gelir. Boylece yarisi ekranda "pat" diye belirmez.
    property bool toastPrep: false
    function showToast(n) {
        if (root.dmode !== "" && root.dmode !== "toast") return;     // bir menu aciksa bolme
        root.tN = n;
        root.nNow = new Date();
        if (root.dmode === "toast") { root.toastKick(); return; }
        wallShapeOff.stop(); wallWideOff.stop();
        root.toastClosing = false;
        root.toastPrep = true;
        root.lastMode = "toast";
        root.wallShape = true;
        toastGo.restart();
    }
    Timer { id: toastGo; interval: 40; onTriggered: { root.toastPrep = false; root.dmode = "toast"; root.toastKick(); } }
    signal toastKick()
    property bool toastClosing: false
    function toastClose() { if (root.dmode === "toast") { root.toastClosing = true; root.closeMode(); } }
    // bildirim listeden kalkarsa (baska yerden silindi) kutuyu kapat
    onNItemsChanged: if (root.dmode === "toast" && root.tN && !root.nItems.some(x => x.id === root.tN.id)) root.toastClose()


    // ================= BATARYA MODU: pile tiklayinca dock batarya paneline donusur =================
    // yatayda iki sutunlu genis panel
    readonly property int batW: root.horiz ? 680 : 340
    readonly property int batH: root.horiz ? 318 : 560
    readonly property int batCol: Math.floor((root.batW - 48) / 2)
    readonly property int batRx: 16 + root.batCol + 16
    function openBat() {
        if (root.dmode === "bat") { root.closeMode(); return; }
        root.dmode = "bat";
    }
    property int bCap: -1
    property string bStatus: "Unknown"
    property real bWatt: 0
    property real bHours: 0
    property int bHealth: 100
    property int bTemp: 0
    property string bGfx: "Hibrit"
    property var bApps: []
    property int bAc: 0
    property string bEpp: "balanced"
    readonly property bool bCharging: root.bStatus === "Charging" || root.bStatus === "Full" || (root.bAc === 1 && root.bStatus === "Not charging")
    readonly property int bProfIdx: root.bEpp === "powersaver" ? 0 : (root.bEpp === "perf" ? 2 : 1)
    readonly property string bTimeText: {
        if (root.bStatus === "Full") return root.t("Dolu", "Full");
        if (root.bStatus === "Charging") return root.t("Şarj oluyor", "Charging");
        if (root.bStatus === "Not charging" && root.bAc === 1) return root.t("Koruma modu", "Conservation mode");
        if (root.bAc === 1 && root.bHours <= 0) return root.t("Fişte", "Plugged in");
        if (root.bHours <= 0) return root.t("Hesaplanıyor…", "Calculating…");
        return root._bHm(root.bHours) + root.t(" kaldı", " left");
    }
    function _bHm(h) { const hh = Math.floor(h), mm = Math.round((h - hh) * 60); return hh > 0 ? hh + root.t(" sa ", " h ") + mm + root.t(" dk", " min") : mm + root.t(" dk", " min"); }
    Process {
        id: batProc
        command: ["sh", "-c", "sh \"$HOME/.config/quickshell/battery/battery-data.sh\" 2>/dev/null; echo; echo \"EPP $(p=$(powerprofilesctl get 2>/dev/null); case \"$p\" in (power-saver) echo powersaver;; (performance) echo perf;; (*) echo balanced;; esac)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text;
                const m = t.match(/EPP\s+(\S+)/);
                if (m) root.bEpp = m[1];
                const j = t.slice(0, t.indexOf("EPP")).trim();
                try {
                    const d = JSON.parse(j);
                    if (typeof d.cap !== "number") return;
                    root.bCap = d.cap; root.bStatus = d.status || "Unknown";
                    root.bWatt = d.watt || 0; root.bHours = d.hours || 0;
                    root.bHealth = d.health || 0; root.bTemp = d.temp || 0;
                    root.bGfx = d.gfx || "Hibrit"; root.bApps = d.apps || []; root.bAc = d.ac || 0;
                } catch (e) { }
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.dmode === "bat"
        onTriggered: if (!batProc.running) batProc.running = true
    }
    function setBatProfile(i) {
        const names = ["powersaver", "balanced", "perf"];
        root.bEpp = names[i];
        Quickshell.execDetached(["powerprofilesctl", "set", ["power-saver", "balanced", "performance"][i]]);
        batAgain.restart();
    }
    Timer { id: batAgain; interval: 600; onTriggered: if (!batProc.running) batProc.running = true }


    // ================= SES MODU: hoparlore tiklayinca dock ses paneline donusur =================
    // yatayda: solda baslik + ana ses karti + sekmeler, sagda liste
    readonly property int audioW: root.horiz ? 680 : 340
    readonly property int audioH: root.horiz ? 252 : 560
    readonly property int audCol: 308
    function openAudio() {
        if (root.dmode === "audio") { root.closeMode(); return; }
        root.dmode = "audio";
    }
    property string aTab: "out"            // out | in | app
    readonly property real aMaxApp: 1.5    // uygulama sesi %150'ye kadar (ses menundeki gibi)
    PwObjectTracker { objects: root.dmode === "audio" ? Pipewire.nodes.values : [] }
    readonly property var aSource: Pipewire.defaultAudioSource
    PwObjectTracker { objects: root.aSource ? [root.aSource] : [] }
    readonly property var aOuts: {
        const out = [];
        for (const n of Pipewire.nodes.values) if (n.audio && !n.isStream && n.isSink !== false) out.push(n);
        return out;
    }
    readonly property var aIns: {
        const out = [];
        for (const n of Pipewire.nodes.values) if (n.audio && !n.isStream && n.isSink === false && !(n.name || "").endsWith(".monitor")) out.push(n);
        return out;
    }
    readonly property var aApps: {
        const out = [];
        for (const n of Pipewire.nodes.values) if (n.audio && n.isStream && n.isSink !== false) out.push(n);
        return out;
    }
    function aName(n) {
        if (!n) return "";
        const p = n.properties || {};
        if (n.isStream) return p["application.name"] || n.description || n.name;
        return n.description || p["node.nick"] || n.name;
    }
    function aKind(n) {
        const s = ((n.name || "") + " " + (n.description || "")).toLowerCase();
        if (s.indexOf("hdmi") >= 0 || s.indexOf("displayport") >= 0) return "hdmi";
        if (s.indexOf("bluez") >= 0) return "bt";
        if (s.indexOf("headset") >= 0 || s.indexOf("headphone") >= 0 || s.indexOf("kulakl") >= 0) return "head";
        if (s.indexOf("usb") >= 0) return "usb";
        return "spk";
    }
    function aIcon(n, input) {
        if (input) return 0xF036C;
        const k = root.aKind(n);
        return k === "hdmi" ? 0xF0379 : k === "bt" ? 0xF00B0 : k === "head" ? 0xF02CB : 0xF04C3;
    }
    function aSub(n, input) {
        const k = root.aKind(n);
        const t = k === "hdmi" ? "HDMI / DisplayPort" : k === "bt" ? "Bluetooth" : k === "head" ? root.t("Kulaklık", "Headphones") : k === "usb" ? "USB" : (input ? root.t("Mikrofon", "Microphone") : root.t("Hoparlör", "Speaker"));
        return t + (n.audio ? " · " + root.t("%" + Math.round(n.audio.volume * 100), Math.round(n.audio.volume * 100) + "%") : "");
    }
    function aAppIcon(n) {
        const p = (n && n.properties) || {};
        return p["application.icon-name"] || p["application.id"] || "";
    }

    // ================= ACILIS / KAPANIS =================
    property bool pinnedOpen: false                       // ipc "toggle" ile hep acik tut
    // kontrol panelindeki carktan: "sabit" (her zaman gorunur) | "gizli" (kenara gelince acilir)
    property string dockMode: "gizli"
    readonly property bool alwaysOn: root.dockMode === "sabit"
    FileView {
        path: Quickshell.env("HOME") + "/.local/share/quickshell/dock-mod"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.dockMode = text().trim() === "sabit" ? "sabit" : "gizli"
    }
    // ekranin ayrilmis alanlari (monitors.lua reserved_area): dock acikken ust 0,
    // "sabit" modda sol 45 (pencereler dock'un yanindan baslar), "gizli" modda sol 0
    // ---- tam ekran: hangi monitorde tam ekran pencere var? (monitor adi -> true)
    // Tam ekranda "her zaman gorunur" dock pencerenin ustunu kapatmasin; sadece sola gelince acilsin.
    property var fsMons: ({})
    Process {
        id: fsProc
        command: ["sh", "-c", "hyprctl -j monitors 2>/dev/null; echo '@@AYIR@@'; hyprctl -j workspaces 2>/dev/null; echo '@@AYIR@@'; hyprctl -j clients 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = this.text.split("@@AYIR@@");
                    const mons = JSON.parse(parts[0]);
                    const wss = JSON.parse(parts[1]);
                    const fs = {};
                    for (const w of wss) fs[w.id] = !!w.hasfullscreen;
                    const out = {};
                    for (const m of mons) {
                        out[m.name] = !!(m.activeWorkspace && fs[m.activeWorkspace.id])
                                   || !!(m.specialWorkspace && m.specialWorkspace.id && fs[m.specialWorkspace.id]);
                    }
                    root.fsMons = out;
                    // akilli gizlenme: her monitorde gorunen pencerelerin dikdortgenleri (monitore gore)
                    // + kucultulmus (special:kucuk) pencereler + odakli workspace
                    let cls = [];
                    try { cls = JSON.parse(parts[2] || "[]"); } catch (e2) { cls = []; }
                    const rects = {}, mins = [];
                    for (const m of mons) {
                        if (m.focused) root.hFocusWs = m.activeWorkspace ? String(m.activeWorkspace.id) : root.hFocusWs;
                        const vis = [m.activeWorkspace ? m.activeWorkspace.id : -999, m.specialWorkspace && m.specialWorkspace.id ? m.specialWorkspace.id : -999];
                        const r = [];
                        for (const c of cls) {
                            if (!c.mapped || c.hidden || c.monitor !== m.id || !c.workspace || vis.indexOf(c.workspace.id) < 0) continue;
                            r.push([c.at[0] - m.x, c.at[1] - m.y, c.size[0], c.size[1]]);
                        }
                        rects[m.name] = r;
                    }
                    for (const c of cls) if (c.workspace && c.workspace.name === "special:kucuk") mins.push({ addr: c.address, cls: (c["class"] || "").toLowerCase() });
                    root.winRects = rects;
                    root.minWins = mins;
                } catch (e) { }
            }
        }
    }
    Timer { id: fsTimer; interval: 120; onTriggered: fsProc.running = true }
    property var winRects: ({})
    property var minWins: []
    property string hFocusWs: "1"
    // gizli modda: suruklenen yuzen pencereler icin olay gelmiyor, hafif bir yoklama
    Timer { interval: 700; repeat: true; running: root.dockMode === "gizli"; onTriggered: if (!fsProc.running) fsProc.running = true }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: fsProc.running = true }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev && ev.name ? ev.name : "";
            if (n === "fullscreen" || n.indexOf("workspace") === 0 || n.indexOf("focusedmon") === 0
                || n === "closewindow" || n === "openwindow" || n.indexOf("movewindow") === 0
                || n.indexOf("moveworkspace") === 0 || n.indexOf("activespecial") === 0
                || n === "changefloatingmode" || n === "activewindowv2" || n.indexOf("minimized") === 0)
                fsTimer.restart();
        }
    }
    Process { id: rezervProc }
    function rezervUygula() {
        rezervProc.running = false;
        rezervProc.command = ["sh", "-c", "\"$HOME/.local/bin/dock-reserve\" " + root.dockMode + " " + (root.horiz ? "yatay" : "dikey")];
        rezervProc.running = true;
    }
    onDockModeChanged: rezervTimer.restart()
    Timer { id: rezervTimer; interval: 150; onTriggered: root.rezervUygula() }
    property bool closing: false
    IpcHandler {
        target: "dock"
        function toggle(): void { root.pinnedOpen = !root.pinnedOpen; }
        // duvar kagidi menusu (wallpaper menun Dock seciliyken buraya yonlendirir)
        function walls(): void { root.openWalls(); }
        // ezan menusu
        function ezan(): void { root.openEzan(); }
        // uygulama menusu (uygulama menun Dock seciliyken buraya yonlendirir)
        function apps(): void { root.openApps(); }
        // sistem paneli (dashboard)
        function dash(): void { root.openDash(); }
        // ag menusu
        function net(): void { root.openNet(); }
        // bildirim paneli (bildirim merkezin Dock seciliyken buraya yonlendirir)
        function notif(): void { root.openNotif(); }
        // batarya paneli (batarya menun Dock seciliyken buraya yonlendirir)
        function bat(): void { root.openBat(); }
        // ses paneli (ses menun Dock seciliyken buraya yonlendirir)
        function audio(): void { root.openAudio(); }
        // dikey <-> yatay
        function yon(): void { root.toggleOrient(); }
        function setMode(m: string): void { root.dockMode = m === "sabit" ? "sabit" : "gizli"; }
        function close(): void { if (root.closing) return; root.closing = true; quitTimer.start(); }
    }
    Timer { id: quitTimer; interval: 520; onTriggered: Qt.quit() }

    // ================= PARCALAR =================
    // Nerd Font ikonlari kutuda yamuk duruyor: glifin gercek sinirlarini olcup tam ortaya koyar
    component CGlyph: Item {
        id: cg
        property string text: ""
        property color color: "#e6e6e6"
        property int size: 18
        width: size + 4; height: size + 4
        TextMetrics { id: cgm; font.family: root.fontName; font.pixelSize: cg.size; text: cg.text }
        Text {
            id: cgt
            text: cg.text
            color: cg.color
            font.family: root.fontName
            font.pixelSize: cg.size
            font.hintingPreference: Font.PreferNoHinting
            renderType: Text.QtRendering
            x: Math.round((cg.width - cgm.tightBoundingRect.width) / 2 - cgm.tightBoundingRect.x)
            y: Math.round((cg.height - cgm.tightBoundingRect.height) / 2 - cgm.tightBoundingRect.y - cgt.baselineOffset)
        }
    }
    // net yazi (dashboard / ag menusu): kucuk boyutta da keskin
    component NText: Text {
        color: "#ededed"
        font.family: root.fontName
        font.pixelSize: 12
        renderType: Text.NativeRendering
    }
    component Label2: Text {
        color: "#e6e6e6"
        font.family: root.fontName
        font.pixelSize: 12
        renderType: Text.QtRendering
        font.hintingPreference: Font.PreferNoHinting
    }
    // qsbar / notch'taki ethernet logosu: ekran + ayak + RJ45 fis ve kablosu (vektor)
    component EthLogo: Item {
        id: el
        property color color: "#e6e6e6"
        property int size: 18
        width: size; height: size
        Shape {
            width: 512; height: 512
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { xScale: el.size / 512; yScale: el.size / 512 }
            ShapePath {
                strokeColor: el.color; strokeWidth: 42; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                startX: 304; startY: 80
                PathLine { x: 112; y: 80 }
                PathArc { x: 64; y: 128; radiusX: 48; radiusY: 48; direction: PathArc.Counterclockwise }
                PathLine { x: 64; y: 288 }
                PathArc { x: 112; y: 336; radiusX: 48; radiusY: 48; direction: PathArc.Counterclockwise }
                PathLine { x: 400; y: 336 }
                PathArc { x: 448; y: 288; radiusX: 48; radiusY: 48; direction: PathArc.Counterclockwise }
                PathLine { x: 448; y: 272 }
            }
            ShapePath {
                strokeColor: el.color; strokeWidth: 42; fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 208; startY: 350
                PathLine { x: 208; y: 420 }
                PathMove { x: 304; y: 350 }
                PathLine { x: 304; y: 420 }
                PathMove { x: 160; y: 432 }
                PathLine { x: 352; y: 432 }
                PathMove { x: 400; y: 226 }
                PathLine { x: 400; y: 432 }
            }
            ShapePath {
                strokeColor: el.color; strokeWidth: 42; fillColor: "transparent"
                joinStyle: ShapePath.RoundJoin
                startX: 384; startY: 80
                PathLine { x: 416; y: 80 }
                PathArc { x: 432; y: 96; radiusX: 16; radiusY: 16 }
                PathLine { x: 432; y: 192 }
                PathArc { x: 416; y: 208; radiusX: 16; radiusY: 16 }
                PathLine { x: 384; y: 208 }
                PathArc { x: 368; y: 192; radiusX: 16; radiusY: 16 }
                PathLine { x: 368; y: 96 }
                PathArc { x: 384; y: 80; radiusX: 16; radiusY: 16 }
                PathMove { x: 368; y: 128 }
                PathLine { x: 432; y: 128 }
            }
        }
    }

    // dock dugmesi: ustune gelince saga kayip buyur, ipucu gosterir
    component DockBtn: Item {
        id: db
        property var w: null                    // pencere yardimcisi (ipucu / menu)
        property string tip: ""
        property bool hoverMove: true
        property bool centerH: true             // Column icinde ortala (Row icinde kapali)
        default property alias content: inner.data
        property alias outside: outer.data       // olceklenmeyen katman (pencere noktalari)
        readonly property bool hovered: dbMa.containsMouse
        signal leftClicked()
        signal rightClicked(real cy)
        signal middleClicked()
        signal wheeled(int dir)
        width: root.cell; height: root.cell
        anchors.horizontalCenter: centerH && parent && parent.objectName !== "dockGrid" ? parent.horizontalCenter : undefined
        Item {
            id: inner
            anchors.fill: parent
            // ustune gelince oldugu yerde buyur (yaylanarak)
            scale: db.hoverMove && dbMa.containsMouse ? 1.14 : 1
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        }
        Item { id: outer; anchors.fill: parent }
        MouseArea {
            id: dbMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (!db.w) return;
                if (containsMouse) db.w.showTip(db.tip, db.w.yOf(db));
                else db.w.hideTip(db.tip);
            }
            onWheel: wh => db.wheeled(wh.angleDelta.y > 0 ? 1 : (wh.angleDelta.y < 0 ? -1 : 0))
            onClicked: m => {
                if (!db.w) return;
                if (m.button === Qt.RightButton) db.rightClicked(db.w.yOf(db));
                else if (m.button === Qt.MiddleButton) db.middleClicked();
                else { db.w.closeMenus(); db.leftClicked(); }
            }
        }
    }

    component AppBtn: DockBtn {
        id: ab
        property var app
        readonly property int nWin: app ? app.wins.length : 0
        readonly property bool focused: { if (!app) return false; for (const t of app.wins) if (t.activated) return true; return false; }
        tip: app ? (app.entry ? app.entry.name : app.appId) : ""
        IconImage {
            anchors.centerIn: parent
            implicitSize: 30
            source: Quickshell.iconPath(ab.app && ab.app.entry ? ab.app.entry.icon : (ab.app ? ab.app.appId : ""), "application-x-executable")
        }
        onLeftClicked: root.launch(ab.app)
        onRightClicked: cy => ab.w.openCtx(ab.app, cy)
        // solda acik pencere noktalari (en fazla 3); odaktakinde uzun pywal cizgi (ikonla birlikte buyumez)
        // (yatayda noktalar ikonun altinda)
        outside: Grid {
            flow: root.horiz ? Grid.LeftToRight : Grid.TopToBottom
            columns: root.horiz ? 3 : 1
            x: root.horiz ? Math.round((parent.width - width) / 2) : -9
            y: root.horiz ? parent.height + 1 : Math.round((parent.height - height) / 2)
            spacing: 3
            Repeater {
                model: Math.min(3, ab.nWin)
                Rectangle {
                    required property int index
                    width: root.horiz ? (ab.focused && index === 0 ? 14 : 4) : 4
                    height: root.horiz ? 4 : (ab.focused && index === 0 ? 14 : 4)
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    radius: 2
                    color: ab.focused ? root.accent : "#bdbdbd"
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }
    }

    component Sep: Rectangle {
        width: root.horiz ? 1 : 26; height: root.horiz ? 26 : 1
        color: "#2a2a2a"
    }
    // kenara baglanan ic kavis: kare - (koseye ortali ceyrek daire). cx/cy: dairenin oldugu kose (0/1)
    component Fil: Canvas {
        property int cx: 1
        property int cy: 0
        property color fill: "#000000"
        onCxChanged: requestPaint()
        onCyChanged: requestPaint()
        onFillChanged: requestPaint()
        // kavis yaricapi: kare degilse (govdeye 1px tasan kavis) kisa kenar
        property real rad: Math.min(width, height)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            c.fillStyle = fill; c.fillRect(0, 0, width, height);
            c.globalCompositeOperation = "destination-out";
            c.beginPath(); c.arc(cx * width, cy * height, rad, 0, Math.PI * 2); c.fill();
        }
        Component.onCompleted: requestPaint()
    }

    component CtxItem: Item {
        id: ci
        property string icon: ""
        property string label: ""
        property bool danger: false
        signal picked()
        width: parent ? parent.width : 170
        height: visible ? 32 : 0
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: ciMa.containsMouse ? "#181818" : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Row {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            CGlyph { anchors.verticalCenter: parent.verticalCenter; text: ci.icon; size: 14; color: ci.danger ? "#ff6b6b" : root.accent }
            Label2 {
                anchors.verticalCenter: parent.verticalCenter
                text: ci.label
                color: ciMa.containsMouse ? (ci.danger ? "#ff6b6b" : root.accent) : "#e6e6e6"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
        MouseArea {
            id: ciMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ci.picked()
        }
    }

    Variants {
        model: {
            const sc = Quickshell.screens, pick = [], all = [];
            for (let i = 0; i < sc.length; i++) {
                all.push(sc[i]);
                if (root.dockOutputs.indexOf(sc[i].name) >= 0) pick.push(sc[i]);
            }
            return pick.length > 0 ? pick : all;
        }

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { left: true; top: true; bottom: true }
            // (genislik: normalde 420 = ipucu, menuler ve medya paneli icin pay; asagida duvar kagidi modu)
            color: "transparent"
            // pencereleri itmez: her zaman gorunurken de pencereler dock'un altindan gecer
            exclusionMode: ExclusionMode.Ignore
            // Overlay: tam ekran pencerelerin de ustunde cizilir (sola gelince tam ekranda da acilir)
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:dock"
            // duvar kagidi modunda klavye (arama, oklar, Enter, Esc) dock'ta
            WlrLayershell.keyboardFocus: root.wallMode && !root.toastMode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // pencere hep ekran genisliginde (tiklanabilir yer zaten mask ile sinirli). Eskiden duvar kagidi
            // modundan cikarken pencere daraliyordu; o yeniden boyutlanma kapanista titremeye yol aciyordu.
            implicitWidth: Math.max(420, win.screen ? win.screen.width : 1920)

            // tiklanabilir alan: sabit "zone" (gizliyken ince kenar, acikken dock'un tam yeri) + acik menuler.
            // Hareket eden dock'a degil sabit alana bakiyoruz: dock kayarken imlec alanin disinda kalip
            // dock'un acilip hemen kapanmasi (titreme) bundan oluyordu.
            mask: Region {
                item: root.wallMode && !root.toastMode ? wallCatch : zone
                Region { x: ctx.x; y: ctx.y; width: ctx.open ? ctx.width : 0; height: ctx.open ? ctx.height : 0 }
                Region { x: trayCard.x; y: trayCard.y; width: trayCard.open ? trayCard.width : 0; height: trayCard.open ? trayCard.height : 0 }
                Region { x: dock.x + volPop.x - (root.horiz ? volPop.curve : 0); y: dock.y + volPop.y - (root.horiz ? 0 : volPop.curve); width: volPop.shown ? volPop.width + (root.horiz ? volPop.curve * 2 : 0) : 0; height: volPop.shown ? volPop.height + (root.horiz ? 0 : volPop.curve * 2) : 0 }
                Region { x: dock.x + trayPop.x - (root.horiz ? trayPop.curve : 0); y: dock.y + trayPop.y - (root.horiz ? 0 : trayPop.curve); width: trayPop.shown ? trayPop.width + (root.horiz ? trayPop.curve * 2 : 0) : 0; height: trayPop.shown ? trayPop.height + (root.horiz ? 0 : trayPop.curve * 2) : 0 }
                Region { x: dock.x + mediaPop.x - (root.horiz ? mediaPop.curve : 0); y: dock.y + mediaPop.y - (root.horiz ? 0 : mediaPop.curve); width: mediaPop.shown ? mediaPop.width + (root.horiz ? mediaPop.curve * 2 : 0) : 0; height: mediaPop.shown ? mediaPop.height + (root.horiz ? 0 : mediaPop.curve * 2) : 0 }
            }

            // ---- gorunurluk ----
            property bool hovering: false
            // zone: kenar ve dock'un sabit yeri (dock kayarken de imlec icinde kalir)
            // dockHH: ikonlarin ustunde (dugmeler fareyi kendine aldiginda zone gormuyor)
            readonly property bool anyHover: zoneHH.hovered || dockHH.hovered || ctxHH.hovered || cardHH.hovered || volHH.hovered || trayHH.hovered || mediaHH.hovered
            onAnyHoverChanged: {
                if (anyHover) { hideTimer.stop(); win.hovering = true; }
                else hideTimer.restart();
            }
            Timer {
                id: hideTimer
                interval: root.hideDelay
                onTriggered: { if (win.anyHover) return; ctx.open = false; trayCard.close(); trayChev.open = false; volPop.on = false; mediaPop.on = false; win.hovering = false; }
            }
            // bu monitorde tam ekran pencere varsa "her zaman gorunur" gecersiz: sadece sola gelince acilir
            readonly property bool fsHere: win.screen ? root.fsMons[win.screen.name] === true : false
            // akilli gizlenme (gizli mod): dock'un durdugu yere hicbir pencere degmiyorsa hep gorunur,
            // bir pencere degince kayip gizlenir (kenara gelince yine acilir)
            readonly property var myRects: win.screen ? (root.winRects[win.screen.name] || []) : []
            readonly property real restW: root.horiz ? Math.round(col.implicitWidth) + 28 + root.fil * 2 : root.dockW
            readonly property real restH: root.horiz ? root.barH : Math.round(col.implicitHeight) + 24 + root.fil * 2
            readonly property real restX: root.horiz ? (win.width - restW) / 2 : 0
            readonly property real restY: root.horiz ? win.height - restH : (win.height - restH) / 2
            readonly property bool covered: {
                for (const r of win.myRects)
                    if (r[0] < win.restX + win.restW && r[0] + r[2] > win.restX && r[1] < win.restY + win.restH && r[1] + r[3] > win.restY) return true;
                return false;
            }
            readonly property bool smartShow: root.dockMode === "gizli" && !win.fsHere && !win.covered
            readonly property bool shown: !root.closing && (root.morphing || root.flipHold || win.hovering || root.pinnedOpen || (root.alwaysOn && !win.fsHere) || win.smartShow || root.wallMode || (root.wallWide && !root.toastClosing))

            // duvar kagidi modunda: menunun disina tiklayinca kapat
            MouseArea {
                id: wallCatch
                anchors.fill: parent
                enabled: root.wallMode && !root.toastMode
                onClicked: root.closeMode()
            }

            Item {
                id: zone
                readonly property real thick: win.shown ? (root.horiz ? dock.height : (root.wallShape ? root.morphW : root.dockW)) + 12 : 4
                x: root.horiz ? Math.round((win.width - width) / 2) : 0
                y: root.horiz ? win.height - height : Math.round((win.height - height) / 2)
                width: root.horiz ? dock.width + root.fil * 2 : thick
                height: root.horiz ? thick : dock.height + root.fil * 2
                HoverHandler { id: zoneHH }
            }

            Connections {
                target: root
                function onOrientFlip() {
                    if (snakeAnim.running) return;
                    if (root.toH) root.snakeHV = dock.height; else root.snakeWB = dock.width;
                    root.horiz = root.toH;
                    snakeAnim.from = root.toH ? 0 : 1;
                    snakeAnim.to = root.toH ? 1 : 0;
                    root.snakeT = snakeAnim.from;
                    snakeAnim.restart();
                }
            }

            // ================= YILAN GECISI =================
            // dikey -> yatay: asagi kayar, koseden donup alt kenar boyunca saga akar, ortaya "cat" diye oturur.
            // (yatay -> dikey ayni yolun tersi)
            Item {
                id: snake
                anchors.fill: parent
                // bitince gercek dock'un ustunde kisa bir sure erir (ani kopma yok)
                visible: root.morphing || snakeFade.running
                opacity: 1
                NumberAnimation { id: snakeFade; target: snake; property: "opacity"; from: 1; to: 0; duration: 170; easing.type: Easing.OutQuad }
                Connections {
                    target: root
                    function onMorphingChanged() { if (root.morphing) { snakeFade.stop(); snake.opacity = 1; } else snakeFade.restart(); }
                }
                readonly property real sw: win.width
                readonly property real sh: win.height
                readonly property real hv: Math.round(root.horiz ? root.snakeHV : Math.round(col.implicitHeight) + 24)
                readonly property real wb: Math.round(root.horiz ? Math.round(col.implicitWidth) + 28 : root.snakeWB)
                readonly property real dw: root.dockW
                readonly property real bh: root.barH
                readonly property real fl: root.fil
                // yol: sol kenardan asagi, koseden donup alt kenar boyunca saga. s = yol uzerindeki konum
                // (dikeyde y, kose C'den sonra C + x). Yilan [kuyruk, bas] araligini kaplar; boyu da yolda
                // dikey boydan yatay ene dogru akar.
                readonly property real c: sh - bh
                readonly property real tail0: Math.round((sh - hv) / 2)
                readonly property real head0: tail0 + hv - bh
                readonly property real tail1: c + Math.round((sw - wb) / 2)
                readonly property real head1: tail1 + wb - dw
                readonly property real t: root.snakeT
                readonly property real tail: Math.round(tail0 + (tail1 - tail0) * t)
                readonly property real head: Math.round(head0 + (head1 - head0) * t)
                function cl(v) { return Math.max(0, Math.min(1, v)); }
                // yatay parcanin sol/sag ucu
                readonly property real xl: Math.max(0, tail - c)
                readonly property real xr: head - c + dw
                readonly property bool hasV: tail < c
                readonly property bool hasH: head > c

                // dikey govde
                Rectangle {
                    visible: snake.hasV
                    x: 0; width: snake.dw
                    y: snake.tail
                    height: Math.min(snake.head, snake.c) + snake.bh - snake.tail
                    color: "#000000"
                    topRightRadius: Math.min(22, height / 2)
                    // koseye yaklastikca alt kavis yavasca duzlesir (pat diye degil)
                    bottomRightRadius: Math.max(0, Math.min(22, snake.c - snake.head))
                }
                // yatay govde
                Rectangle {
                    visible: snake.hasH
                    y: snake.c; height: snake.bh
                    x: snake.xl
                    width: Math.max(0, snake.xr - snake.xl)
                    color: "#000000"
                    topRightRadius: Math.max(0, Math.min(22, snake.xr - snake.dw))
                    topLeftRadius: Math.min(22, snake.xl)
                }
                // kenara baglanan ic kavisler: gercek dock'takilerle ayni, yilanla birlikte akar
                Fil {   // dikey ust
                    x: 0; y: snake.tail - snake.fl; width: snake.fl; height: snake.fl
                    cx: 1; cy: 0
                    visible: snake.hasV
                    opacity: snake.cl((snake.c - snake.tail) / 40)
                }
                Fil {   // dikey alt
                    x: 0; y: snake.head + snake.bh; width: snake.fl; height: snake.fl
                    cx: 1; cy: 1
                    visible: !snake.hasH
                    opacity: snake.cl((snake.c - snake.head) / 40)
                }
                Fil {   // donus kosesi (dikey ile yatayin birlestigi ic kose)
                    x: snake.dw; y: snake.c - snake.fl; width: snake.fl; height: snake.fl
                    cx: 1; cy: 0
                    visible: snake.hasV && snake.hasH
                    opacity: Math.min(snake.cl((snake.xr - snake.dw) / 30), snake.cl((snake.c - snake.tail - snake.fl) / 30))
                }
                Fil {   // yatay sol
                    x: snake.xl - snake.fl; y: snake.sh - snake.fl; width: snake.fl; height: snake.fl
                    cx: 0; cy: 0
                    visible: snake.hasH && !snake.hasV
                    opacity: snake.cl(snake.xl / 40)
                }
                Fil {   // yatay sag
                    x: snake.xr; y: snake.sh - snake.fl; width: snake.fl; height: snake.fl
                    cx: 1; cy: 0
                    visible: snake.hasH
                    opacity: snake.cl((snake.xr - snake.dw) / 40)
                }
            }

            // parcalar (DockBtn / AppBtn) bunlari "w" uzerinden cagirir
            // ikonun dock eksenindeki yeri (dikeyde y, yatayda x)
            function yOf(it) { return root.horiz ? it.mapToItem(win.contentItem, it.width / 2, 0).x : it.mapToItem(win.contentItem, 0, it.height / 2).y; }
            // ipucu kutulari istenmedi: kapali (geri acmak icin showTips: true)
            readonly property bool showTips: false
            function showTip(t, cy) { if (!win.showTips) return; tipBox.text = t; tipBox.cy = cy; tipBox.on = t !== ""; }
            function hideTip(t) { if (tipBox.text === t) tipBox.on = false; }
            function openCtx(a, cy) { tipBox.on = false; trayCard.close(); ctx.openFor(a, cy); }
            function closeMenus() { ctx.open = false; trayCard.close(); }
            function showVol(btn) { tipBox.on = false; trayChev.open = false; trayCard.close(); volPop.cy = btn.mapToItem(dock, 0, btn.height / 2).y; volPop.cx = btn.mapToItem(dock, btn.width / 2, 0).x; volPop.on = true; volTimer.restart(); }
            function toggleTray(btn) {
                tipBox.on = false; ctx.open = false; volPop.on = false;
                if (trayChev.open) { trayChev.open = false; trayCard.close(); return; }
                trayPop.cy = btn.mapToItem(dock, 0, btn.height / 2).y;
                trayPop.cx = btn.mapToItem(dock, btn.width / 2, 0).x;
                trayChev.open = true;
            }
            // tepsi menusu: cekmecenin altinda, tiklanan ikonun hizasinda
            function trayMenuFor(m, btn) {
                const p = btn.mapToItem(win.contentItem, 0, 0);
                if (root.horiz) trayCard.openAt(m, p.x - 8, dock.y + trayPop.y - 3, true);
                else trayCard.openAt(m, Math.max(dock.x + root.dockW + 10, p.x - 8), dock.y + trayPop.y + trayPop.height + 3);
            }
            // medya paneli: plagin hizasinda acilir / kapanir
            Connections {
                target: root
                function onWallModeChanged() { if (root.wallMode) { ctx.open = false; trayCard.close(); trayChev.open = false; volPop.on = false; mediaPop.on = false; tipBox.on = false; } }
            }
            function toggleMedia(it) {
                tipBox.on = false; ctx.open = false; volPop.on = false; trayChev.open = false; trayCard.close();
                if (mediaPop.on) { mediaPop.on = false; return; }
                mediaPop.cy = it.mapToItem(dock, 0, it.height / 2).y;
                mediaPop.cx = it.mapToItem(dock, it.width / 2, 0).x;
                mediaPop.on = true;
            }
            // ses cubugu: son dokunustan 1.5 sn sonra (ustunde degilse) geri cekilir
            Timer { id: volTimer; interval: 1500; onTriggered: { if (volHH.hovered) volTimer.restart(); else volPop.on = false; } }

            // gizliyken kenarda ince pywal cizgi
            Rectangle {
                x: 0; width: 3; height: 90; radius: 1.5
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent
                opacity: 0                          // gizliyken kenarda cizgi gorunmesin
                visible: false
            }

            Item {
                id: dock
                // duvar kagidi modunda genisleyip uzar (yaylanarak), kapaninca yine ince dock
                readonly property real rawW: root.wallShape ? root.morphW : (root.horiz ? Math.round(col.implicitWidth) + 28 : root.dockW)
                width: dock.softOpen ? dock.softW : dock.rawW
                readonly property real rawH: root.wallShape ? (root.lastMode === "ezan" ? root.ezH : (root.lastMode === "dash" ? root.dashH : (root.lastMode === "net" ? (root.horiz ? root.netHH : Math.min(win.height - 110, 660)) : (root.lastMode === "notif" ? (root.horiz ? root.notifHH : Math.min(win.height - 110, 700)) : (root.lastMode === "toast" ? root.toastH : (root.lastMode === "bat" ? root.batH : (root.lastMode === "audio" ? root.audioH : (root.horiz ? (root.lastMode === "walls" ? root.wallHH : (root.lastMode === "apps" ? root.appHH : Math.min(win.height - 110, 780))) : Math.min(win.height - 110, 780))))))))) : (root.horiz ? root.barH : Math.round(col.implicitHeight) + 24)
                height: dock.softOpen ? dock.softH : dock.rawH
                // yumusak acilis icin ayri, tasmasiz animasyonlu kopyalar (easing'i kosullu baglamak calismiyordu:
                // animasyon hep OutBack ile basliyor, sonda tasip geri cekiliyordu)
                property real softW: rawW
                property real softH: rawH
                Behavior on softW { NumberAnimation { duration: 420; easing.type: Easing.OutQuart } }
                Behavior on softH { NumberAnimation { duration: 420; easing.type: Easing.OutQuart } }
                // dikey: sol kenarda ortali; yatay: alt kenarda ortali. Gizliyken kenarin disina "hideOff" kadar kayar
                readonly property real extent: root.horiz ? height : width
                // gizlilik orani (0 = acik, 1 = tamamen disarida). Konum = oran x GUNCEL boy: gizliyken dock
                // birden buyuk bir panele donusse bile (menu / bildirim) yine tamamen disarida kalir ve
                // oradan bastan sona kayarak gelir (eskiden eski kucuk boy kadar disaridaydi, panel "pat" diye
                // yarisi ekranda beliriyor, takiliyormus gibi duruyordu)
                property real hideFrac: win.shown ? 0 : 1
                readonly property real hideOff: hideFrac * (extent + 2)
                readonly property bool onScreen: hideFrac < 0.97
                x: root.horiz ? Math.round((win.width - width) / 2) : -hideOff
                y: root.horiz ? win.height - height + hideOff : Math.round((win.height - height) / 2)
                // gecis sirasinda gercek dock gizli (yilan ciziliyor)
                // visible:false DEGIL: gizli Grid ikonlari yerlesimden dusuruyor, olcu kuculuyordu ->
                // yilan bitince dock'tan kisa kaliyordu. Sadece saydam (cizilmez ama olcusu dogru)
                opacity: root.morphing ? 0 : 1
                enabled: !root.morphing
                // acilis yaylanarak, kapanis yumusak (hizlanip yavaslayarak)
                // gizliyken boy degisirse (yeni sabit, tray ikonu) aninda uysun; yoksa acilirken boy hala animasyondaydi
                // dock ekran disindayken (gizli) boy aninda degissin: gizliyken gelen bildirim
                // once uzun dock olarak cikip kuculmesin, dogrudan kutu olarak kayip gelsin
                // yatay duvar kagidi / uygulama menusu: tasmasiz, yumusak (OutBack sonda geri cekilip "cat" diye oturuyordu)
                readonly property bool softOpen: root.horiz && (root.dmode === "walls" || root.dmode === "apps")
                Behavior on height { enabled: dock.onScreen && !root.morphing && !dock.softOpen; NumberAnimation { duration: root.wallShape ? 460 : 300; easing.type: root.wallShape ? Easing.OutBack : Easing.InOutCubic; easing.overshoot: 0.7 } }
                Behavior on width { enabled: dock.onScreen && !root.morphing && !dock.softOpen; NumberAnimation { duration: root.wallShape ? 420 : 280; easing.type: root.wallShape ? Easing.OutBack : Easing.InOutCubic; easing.overshoot: 0.8 } }
                HoverHandler { id: dockHH }
                // kenardan kayarak cikar; zemini (siyah govde) slime gibi esner ve titreyerek oturur
                // kayma tasmasiz (OutCubic): eskiden OutBack sola bosluk aciyordu; yaylanmayi zemin veriyor
                // (bildirim hazirligi: gizliyken kutu genisligi kadar sola aninda atlar)
                // bildirim kutusu genis oldugu icin daha yumusak ve uzun kayar (OutCubic'te ilk karelerde
                // kutunun cogu birden ekrana giriyor, "cat" diye geliyormus gibi duruyordu)
                Behavior on hideFrac {
                    enabled: !root.morphing
                    NumberAnimation {
                        duration: win.shown ? (root.wallMode ? 460 : 300) : 200
                        easing.type: win.shown ? (root.wallMode ? Easing.OutQuad : Easing.OutCubic) : Easing.InCubic
                    }
                }
                // jelly: sadece zemin esner (ikonlar/yazilar hic bozulmaz)
                property real jx: 1
                property real jy: 1
                SequentialAnimation {
                    id: dockJelly
                    // kayarken zemin yavasca esner, yerine oturunca tek yumusak yaylanmayla geri toplanir
                    ParallelAnimation {
                        NumberAnimation { target: dock; property: "jx"; from: 1; to: 1.14; duration: 220; easing.type: Easing.OutQuad }
                        NumberAnimation { target: dock; property: "jy"; from: 1; to: 1.03; duration: 220; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: dock; property: "jx"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                        NumberAnimation { target: dock; property: "jy"; to: 1; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }
                }
                Connections {
                    target: win
                    function onShownChanged() {
                        if (win.shown && !root.wallMode) { if (!dockJelly.running) dockJelly.start(); }
                        else { dockJelly.stop(); dock.jx = 1; dock.jy = 1; }
                    }
                }

                // ---- ses cubugu: dock'un arkasindan kayarak cikar, birlesme yerinde ice kavisler ----
                Item {
                    id: volPop
                    property real cy: 0
                    property real cx: 0
                    property bool on: false
                    readonly property bool shown: on && win.shown
                    readonly property int curve: 14
                    width: vRow.implicitWidth + 12 + 16
                    height: 40
                    // dikey: dock'un sagina kayar; yatay: dock'un ustune kayar (ikonun hizasinda)
                    property real hid: shown ? 0 : 1
                    Behavior on hid { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    x: root.horiz ? Math.max(22 + curve, Math.min(dock.width - 22 - curve - width, cx - width / 2)) : root.dockW - 1 - hid * width
                    y: root.horiz ? -height + 1 + hid * (height + 2) : cy - height / 2
                    visible: hid < 0.995
                    HoverHandler { id: volHH }
                    // birlesme kavisleri (dikey: ust/alt sol, yatay: alt sol/sag)
                    Fil {
                        x: root.horiz ? -volPop.curve : 0; y: root.horiz ? volPop.height - volPop.curve : -volPop.curve
                        width: volPop.curve; height: volPop.curve
                        cx: root.horiz ? 0 : 1; cy: 0
                    }
                    Fil {
                        x: root.horiz ? volPop.width : 0; y: root.horiz ? volPop.height - volPop.curve : volPop.height
                        width: volPop.curve; height: volPop.curve
                        cx: 1; cy: root.horiz ? 0 : 1
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        topLeftRadius: root.horiz ? 20 : 0; topRightRadius: 20; bottomRightRadius: root.horiz ? 0 : 20
                    }
                    Row {
                        id: vRow
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                            // cubuk: tikla / surukle / tekerlek
                        Item {
                            id: vTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: 120; height: 20
                            // surukleyince top/cubuk farenin altinda kalsin (pipewire'in gec gelen
                            // degerine bakinca top ileri geri ziplayip takiliyordu)
                            property real dragV: 0
                            readonly property real v: vMa.pressed ? dragV : (root.muted ? 0 : Math.max(0, Math.min(1, root.vol)))
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 6; radius: 3
                                color: "#2a2a2a"
                                Rectangle {
                                    width: Math.max(6, parent.width * vTrack.v)
                                    height: parent.height; radius: 3
                                    color: root.accent
                                    Behavior on width { enabled: !vMa.pressed; NumberAnimation { duration: 120 } }
                                }
                            }
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                x: Math.max(0, Math.min(vTrack.width - width, vTrack.width * vTrack.v - width / 2))
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                                // basinca boyu degil olcegi buyur: konumu kaymaz
                                scale: vMa.pressed ? 1.35 : (vMa.containsMouse ? 1.12 : 1)
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                Behavior on x { enabled: !vMa.pressed; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                id: vMa
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                function upd(m) {
                                    const v = Math.max(0, Math.min(1, (m.x - 6) / vTrack.width));
                                    vTrack.dragV = Math.round(v * 100) / 100;
                                    root.setVol(vTrack.dragV);
                                    volTimer.restart();
                                }
                                onPressed: m => upd(m)
                                onPositionChanged: m => { if (pressed) upd(m); }
                                onWheel: wh => { root.setVol(root.vol + (wh.angleDelta.y > 0 ? 0.05 : -0.05)); volTimer.restart(); }
                            }
                        }
                        Label2 {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            horizontalAlignment: Text.AlignRight
                            text: root.muted && !vMa.pressed ? "—" : Math.round(vTrack.v * 100) + "%"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // ---- MEDYA PANELI ("plak kilifi"): plaga tiklayinca plagin hizasinda dock'un arkasindan saga kayar ----
                // Kapak bir plak kilifi gibi durur; calarken plak kiliftan disari kayip doner (etiketinde kapak resmi),
                // durunca kilifa geri girer. Sagda dikey Spotify sesi, altta dalgali ilerleme cizgisi ve tuslar.
                Item {
                    id: mediaPop
                    property real cy: 0
                    property real cx: 0
                    property bool on: false
                    readonly property bool shown: on && win.shown && root.musicOn
                    readonly property int curve: 14
                    readonly property int pad: 16
                    width: 320
                    height: 342
                    // plagin hizasinda ortali; ama dock'un yuvarlak koselerine tasmasin
                    // (tasinca birlesme yerindeki kavis bosta kaliyordu)
                    readonly property int edge: 22 + curve + 2
                    property real hid: shown ? 0 : 1
                    x: root.horiz ? Math.round(Math.max(edge, Math.min(dock.width - width - edge, cx - width / 2))) : root.dockW - 1 - hid * (width + 4)
                    y: root.horiz ? -height + 1 + hid * (height + 4) : Math.round(Math.max(edge, Math.min(dock.height - height - edge, cy - height / 2)))
                    // live: panel acik ya da kayiyor -> animasyonlar (plak, robot, dalga) sadece o zaman calisir
                    readonly property bool live: hid < 0.995
                    // muzik varken panel hep hazir (dock'un arkasinda, gorunmez) tutulur: acilista ilk kez
                    // cizilip kare kaydirmasin. Eskiden ilk karede her sey birden cizildigi icin acilis
                    // bir bekleyip "cat" diye geliyordu.
                    // (bir menu acikken hazir bekleyen panel saklanir: kavisleri menu kenarindan tasmasin)
                    visible: (root.musicOn && !root.wallShape) || live
                    // genis panel: yumusak ve dengeli kayar
                    Behavior on hid { NumberAnimation { duration: mediaPop.shown ? 440 : 220; easing.type: mediaPop.shown ? Easing.OutQuad : Easing.InCubic } }
                    // jelly: kayip gelirken zemin slime gibi esner (kapak/yazilar bozulmaz)
                    property real jx: 1
                    property real jy: 1
                    SequentialAnimation {
                        id: mediaJelly
                        ParallelAnimation {
                            NumberAnimation { target: mediaPop; property: "jx"; from: 1; to: 1.08; duration: 230; easing.type: Easing.OutQuad }
                            NumberAnimation { target: mediaPop; property: "jy"; from: 1; to: 1.03; duration: 230; easing.type: Easing.OutQuad }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: mediaPop; property: "jx"; to: 1; duration: 540; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                            NumberAnimation { target: mediaPop; property: "jy"; to: 1; duration: 580; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        }
                    }
                    onShownChanged: { if (shown) { if (!mediaJelly.running) mediaJelly.start(); } else { mediaJelly.stop(); jx = 1; jy = 1; } }
                    HoverHandler { id: mediaHH }

                    property bool dragging: false
                    property real dragPos: 0
                    readonly property real len: root.trackLen
                    readonly property real pos: dragging ? dragPos : root.trackPos
                    readonly property real ratio: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0
                    Timer {
                        interval: 500; repeat: true
                        running: mediaPop.shown && root.playing && !mediaPop.dragging
                        onTriggered: { if (root.player) { root.player.positionChanged(); if (Date.now() >= root.posHoldUntil || root.player.position <= 3) root.trackPos = root.player.position; } }
                    }

                    // ---- sarki degisince: plak kilifa girer, kapak yaylanarak degisir, plak yeniden cikar ----
                    property real recOut: root.playing ? 1 : 0.22          // plagin kiliftan cikma orani
                    Behavior on recOut { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
                    // ---- sarki degisimi ----
                    // Ekranda gosterilenler (kapak / ad / sanatci) animasyonun ORTASINDA degisir:
                    // once plak kilifa girer ve eski kapak kuculup soner, sonra yeni kapak yaylanarak gelir.
                    // Yeni kapak once gizlice yuklenir (en fazla 0.7 sn beklenir), boylece yarim yuklu kapak gorunmez.
                    property string shownArt: ""
                    property string shownTitle: ""
                    property string shownArtist: ""
                    property bool swapPending: false
                    function syncShown() { shownArt = root.dispArt; shownTitle = root.dispTitle; shownArtist = root.dispArtist; }
                    Component.onCompleted: syncShown()
                    onVisibleChanged: if (visible && !m2Swap.running && !swapPending) syncShown()
                    function startSwap() {
                        if (!swapPending) return;
                        swapPending = false;
                        m2SwapWait.stop();
                        m2Swap.restart();
                    }
                    Connections {
                        target: root
                        function onDispTitleChanged() {
                            if (!mediaPop.live) { mediaPop.syncShown(); return; }
                            mediaPop.swapPending = true;
                            m2SwapWait.restart();
                            m2SwapShort.restart();       // kapak bilgisi hemen arkasindan gelir: kisa bir an bekle
                        }
                        function onDispArtistChanged() { if (!mediaPop.swapPending && !m2Swap.running && root.dispTitle === mediaPop.shownTitle) mediaPop.shownArtist = root.dispArtist; }
                        // kapak sarki adindan sonra gelirse ve degisim coktan bittiyse direkt guncelle
                        function onDispArtChanged() { if (!mediaPop.swapPending && !m2Swap.running) mediaPop.shownArt = root.dispArt; }
                    }
                    Timer { id: m2SwapWait; interval: 700; onTriggered: mediaPop.startSwap() }
                    Timer { id: m2SwapShort; interval: 180; onTriggered: if (m2Preload.status === Image.Ready) mediaPop.startSwap() }
                    Image {
                        id: m2Preload
                        visible: false
                        asynchronous: true
                        source: root.hiResArt(root.dispArt)
                        sourceSize.width: 252; sourceSize.height: 252
                        onStatusChanged: if (status === Image.Ready && mediaPop.swapPending && !m2SwapShort.running) mediaPop.startSwap()
                    }
                    SequentialAnimation {
                        id: m2Swap
                        onStopped: { m2Info.opacity = 1; m2InfoShift.y = 0; m2Sleeve.scale = 1; m2Dim.opacity = 0; m2Rec.slide = 1; }
                        // 1) cikis: plak kilifa girer, eski kapak ve yazilar soner
                        ParallelAnimation {
                            NumberAnimation { target: m2Rec; property: "slide"; to: 0; duration: 240; easing.type: Easing.InCubic }
                            NumberAnimation { target: m2Sleeve; property: "scale"; to: 0.9; duration: 240; easing.type: Easing.InCubic }
                            NumberAnimation { target: m2Dim; property: "opacity"; to: 0.55; duration: 240; easing.type: Easing.InCubic }
                            NumberAnimation { target: m2Info; property: "opacity"; to: 0; duration: 180 }
                            NumberAnimation { target: m2InfoShift; property: "y"; to: -6; duration: 180; easing.type: Easing.InCubic }
                        }
                        // 2) tam ortada yeni sarkiya gec
                        ScriptAction { script: { mediaPop.syncShown(); m2RecSpin.rotation = Math.random() * 360; } }
                        // 3) giris: yeni kapak yaylanir, yazilar asagidan gelir, plak yeniden cikar
                        ParallelAnimation {
                            NumberAnimation { target: m2Sleeve; property: "scale"; from: 0.86; to: 1; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                            NumberAnimation { target: m2Dim; property: "opacity"; to: 0; duration: 260 }
                            NumberAnimation { target: m2InfoShift; property: "y"; from: 8; to: 0; duration: 380; easing.type: Easing.OutCubic }
                            NumberAnimation { target: m2Info; property: "opacity"; to: 1; duration: 320 }
                            SequentialAnimation {
                                PauseAnimation { duration: 160 }
                                ParallelAnimation {
                                    NumberAnimation { target: m2Rec; property: "slide"; to: 1; duration: 560; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: m2Rec; property: "boost"; from: 520; to: 0; duration: 900; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }

                    // ---- zemin: dock'a yapisik siyah panel; ustten hafif pywal isigi ----
                    // ust kavis panelin ust kenariyla ayni pywal tonunda (birlesme yerinde siyah leke kalmasin).
                    // Canvas yerine Shape: renk degisince kendiliginden guncellenir, kesme islemi gerekmez.
                    Shape {
                        visible: !root.horiz
                        x: 0; y: -mediaPop.curve; width: mediaPop.curve; height: mediaPop.curve
                        transform: Scale { origin.x: 0; origin.y: mediaPop.height / 2 + mediaPop.curve; xScale: mediaPop.jx; yScale: mediaPop.jy }
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: 0; strokeColor: "transparent"
                            // siyah zemin + %20 pywal = tek duz renk
                            fillColor: Qt.rgba(root.accent.r * 0.2, root.accent.g * 0.2, root.accent.b * 0.2, 1)
                            startX: 0; startY: 0
                            PathLine { x: 0; y: mediaPop.curve }
                            PathLine { x: mediaPop.curve; y: mediaPop.curve }
                            PathArc { x: 0; y: 0; radiusX: mediaPop.curve; radiusY: mediaPop.curve; direction: PathArc.Clockwise }
                        }
                    }
                    // yatay: sol alt kavis
                    Fil {
                        visible: root.horiz
                        x: -mediaPop.curve; y: mediaPop.height - mediaPop.curve
                        width: mediaPop.curve; height: mediaPop.curve
                        cx: 0; cy: 0
                        transform: Scale { origin.x: mediaPop.width / 2 + mediaPop.curve; origin.y: mediaPop.curve; xScale: mediaPop.jy; yScale: mediaPop.jx }
                    }
                    // dikey: sol alt kavis / yatay: sag alt kavis
                    Fil {
                        x: root.horiz ? mediaPop.width : 0
                        y: root.horiz ? mediaPop.height - mediaPop.curve : mediaPop.height
                        width: mediaPop.curve; height: mediaPop.curve
                        cx: 1; cy: root.horiz ? 0 : 1
                        transform: Scale {
                            origin.x: root.horiz ? -mediaPop.width / 2 : 0
                            origin.y: root.horiz ? mediaPop.curve : -mediaPop.height / 2
                            xScale: root.horiz ? mediaPop.jy : mediaPop.jx; yScale: root.horiz ? mediaPop.jx : mediaPop.jy
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        topLeftRadius: root.horiz ? 24 : 0; topRightRadius: 24; bottomRightRadius: root.horiz ? 0 : 24
                        transform: Scale { origin.x: root.horiz ? mediaPop.width / 2 : 0; origin.y: root.horiz ? mediaPop.height : mediaPop.height / 2; xScale: root.horiz ? mediaPop.jy : mediaPop.jx; yScale: root.horiz ? mediaPop.jx : mediaPop.jy }
                    }
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: root.horiz ? 24 : 0; topRightRadius: 24; bottomRightRadius: root.horiz ? 0 : 24
                        transform: Scale { origin.x: root.horiz ? mediaPop.width / 2 : 0; origin.y: root.horiz ? mediaPop.height : mediaPop.height / 2; xScale: root.horiz ? mediaPop.jy : mediaPop.jx; yScale: root.horiz ? mediaPop.jx : mediaPop.jy }
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20) }
                            GradientStop { position: 0.55; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.0) }
                        }
                    }

                    // ---- ust: calan playlist hapi (yoksa "Spotify") ----
                    Rectangle {
                        id: m2Pill
                        x: mediaPop.pad; y: 14
                        height: 26; radius: 7
                        width: Math.min(mediaPop.width - mediaPop.pad * 2 - 30, m2PillRow.implicitWidth + 16)
                        color: "#000000"
                        border.width: 1
                        border.color: m2PillMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : "transparent"
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        clip: true
                        Row {
                            id: m2PillRow
                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Item {
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    anchors.fill: parent; radius: 5; color: "#1f1f1f"
                                    visible: m2PlImg.status !== Image.Ready
                                    CGlyph {
                                        anchors.centerIn: parent; size: 11; color: root.accent
                                        text: root.g(!root.plShown ? 0xF04C7 : root.plType === "liked" ? 0xF02D1 : root.plType === "album" ? 0xF0025
                                                    : root.plType === "artist" ? 0xF0803 : root.plType === "radio" ? 0xF0439 : 0xF0CB8)
                                    }
                                }
                                ClippingRectangle {
                                    anchors.fill: parent; radius: 5; color: "transparent"
                                    visible: m2PlImg.status === Image.Ready
                                    Image { id: m2PlImg; anchors.fill: parent; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 40; sourceSize.height: 40; source: root.plShown ? root.plImage : "" }
                                }
                            }
                            Item {
                                id: m2PlBox
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(m2PlName.implicitWidth, 210)
                                height: m2PlName.implicitHeight
                                clip: true
                                readonly property real overflow: Math.max(0, m2PlName.implicitWidth - width)
                                Text {
                                    id: m2PlName
                                    text: root.plShown ? root.plName : "Spotify"
                                    font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: root.accent
                                }
                                SequentialAnimation {
                                    running: mediaPop.live && m2PlBox.overflow > 0
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) m2PlName.x = 0
                                    PauseAnimation { duration: 1800 }
                                    NumberAnimation { target: m2PlName; property: "x"; to: -m2PlBox.overflow; duration: Math.max(600, m2PlBox.overflow * 35); easing.type: Easing.InOutSine }
                                    PauseAnimation { duration: 1400 }
                                    NumberAnimation { target: m2PlName; property: "x"; to: 0; duration: Math.max(600, m2PlBox.overflow * 35); easing.type: Easing.InOutSine }
                                }
                            }
                        }
                        MouseArea {
                            id: m2PillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "class:spotify" })'])
                        }
                    }

                    // ---- plak: kilifin arkasinda, calarken saga kayip doner ----
                    Item {
                        id: m2Rec
                        property real slide: 1                     // sarki degisirken 0'a iner (kilifa girer)
                        readonly property int size: 114
                        width: size; height: size
                        x: m2Sleeve.x + (m2Sleeve.width - size) / 2 + 60 * mediaPop.recOut * slide
                        y: m2Sleeve.y + (m2Sleeve.height - size) / 2
                        property real speed: root.playing ? 100 : 0
                        property real boost: 0
                        Behavior on speed { NumberAnimation { duration: root.playing ? 700 : 1400; easing.type: root.playing ? Easing.InQuad : Easing.OutCubic } }
                        property bool scratching: false
                        FrameAnimation {
                            running: mediaPop.live && !m2Rec.scratching && (m2Rec.speed + m2Rec.boost) > 0.05
                            onTriggered: m2RecSpin.rotation = (m2RecSpin.rotation + (m2Rec.speed + m2Rec.boost) * frameTime) % 360
                        }
                        Item {
                            id: m2RecSpin
                            anchors.fill: parent
                            Canvas {
                                id: m2Vinyl
                                width: m2Rec.size * 2; height: m2Rec.size * 2
                                anchors.centerIn: parent
                                scale: 0.5
                                smooth: true; antialiasing: true
                                Component.onCompleted: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d");
                                    const w = width, h = height;
                                    const cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2;
                                    ctx.reset();
                                    ctx.beginPath(); ctx.arc(cx, cy, R - 2, 0, Math.PI * 2); ctx.fillStyle = "#0e0e0e"; ctx.fill();
                                    ctx.beginPath(); ctx.arc(cx, cy, R - 3, 0, Math.PI * 2); ctx.lineWidth = 2; ctx.strokeStyle = "#333333"; ctx.stroke();
                                    ctx.lineWidth = 1; ctx.strokeStyle = "#222222";
                                    for (let r = R - 8; r > R * 0.44; r -= 5) { ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke(); }
                                    ctx.lineWidth = 6; ctx.strokeStyle = "rgba(255,255,255,0.10)";
                                    ctx.beginPath(); ctx.arc(cx, cy, R * 0.74, -2.4, -1.75); ctx.stroke();
                                    ctx.beginPath(); ctx.arc(cx, cy, R * 0.74, 0.74, 1.39); ctx.stroke();
                                }
                            }
                            // etiket: kapak resmi, ince pywal halka
                            Rectangle {
                                anchors.centerIn: parent
                                width: 46; height: 46; radius: 23
                                color: root.accent
                                ClippingRectangle {
                                    anchors.centerIn: parent
                                    width: 42; height: 42; radius: 21
                                    color: "#141414"
                                    Image { anchors.fill: parent; source: root.hiResArt(mediaPop.shownArt); fillMode: Image.PreserveAspectCrop; asynchronous: true; retainWhileLoading: true; sourceSize.width: 96; sourceSize.height: 96 }
                                }
                                Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; color: "#000000"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3) }
                            }
                        }
                        // plagi elle cevirip sarma (DJ scratch): saat yonu ileri, tersi geri
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: m2Rec.scratching ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real lastAng: 0
                            property real accum: 0
                            property real startPos: 0
                            function ang(mx, my) { return Math.atan2(my - height / 2, mx - width / 2) * 180 / Math.PI; }
                            function finish() {
                                if (!m2Rec.scratching) return;
                                const p = root.player;
                                if (p && Math.abs(accum) > 3) { p.position = mediaPop.dragPos; root.trackPos = mediaPop.dragPos; }
                                mediaPop.dragging = false;
                                m2Rec.scratching = false;
                            }
                            onPressed: m => {
                                const p = root.player;
                                if (!p || !p.canSeek || mediaPop.len <= 0) { m.accepted = false; return; }
                                lastAng = ang(m.x, m.y); accum = 0;
                                p.positionChanged();
                                startPos = p.position;
                                mediaPop.dragPos = startPos;
                                mediaPop.dragging = true;
                                m2Rec.scratching = true;
                            }
                            onPositionChanged: m => {
                                if (!m2Rec.scratching) return;
                                const a = ang(m.x, m.y);
                                let d = a - lastAng;
                                if (d > 180) d -= 360;
                                if (d < -180) d += 360;
                                lastAng = a; accum += d;
                                m2RecSpin.rotation = (m2RecSpin.rotation + d + 360) % 360;
                                mediaPop.dragPos = Math.max(0, Math.min(mediaPop.len - 1, startPos + accum / 360 * 10));
                            }
                            onReleased: finish()
                            onCanceled: finish()
                        }
                    }

                    // ---- kilif: buyuk albüm kapagi (tikla: oynat/durdur) ----
                    Item {
                        id: m2Sleeve
                        x: mediaPop.pad; y: 52
                        width: 126; height: 126
                        // gölge
                        Rectangle { x: 3; y: 5; width: parent.width; height: parent.height; radius: 12; color: Qt.rgba(0, 0, 0, 0.6) }
                        Rectangle {
                            anchors.fill: parent; radius: 12; color: "#161616"
                            visible: m2Cover.status !== Image.Ready && m2CoverOld.status !== Image.Ready
                            CGlyph { anchors.centerIn: parent; size: 34; text: root.g(0xF075A); color: root.accent }
                        }
                        ClippingRectangle {
                            anchors.fill: parent; radius: 12; color: "transparent"
                            // alttaki: bir onceki kapak (yenisi yuklenirken bu gorunur)
                            Image {
                                id: m2CoverOld
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 252; sourceSize.height: 252
                                smooth: true; mipmap: true
                            }
                            Image {
                                id: m2Cover
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                source: root.hiResArt(mediaPop.shownArt)
                                sourceSize.width: 252; sourceSize.height: 252
                                smooth: true; mipmap: true
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { enabled: !m2Swap.running; NumberAnimation { duration: 220 } }
                                onStatusChanged: if (status === Image.Ready) m2OldSwap.restart()
                                Timer { id: m2OldSwap; interval: 260; onTriggered: m2CoverOld.source = m2Cover.source }
                            }
                        }
                        // sarki degisirken eski kapak kararir (kilif saydamlasmaz, arkadaki plak gorunmez)
                        Rectangle { id: m2Dim; anchors.fill: parent; radius: 12; color: "#000000"; opacity: 0 }
                        // ustune gelince oynat/durdur isareti belirir
                        Rectangle {
                            anchors.fill: parent; radius: 12
                            color: Qt.rgba(0, 0, 0, 0.45)
                            opacity: m2SleeveMa.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            CGlyph { anchors.centerIn: parent; size: 30; text: root.g(root.playing ? 0xF03E4 : 0xF040A); color: "#ffffff" }
                        }
                        MouseArea {
                            id: m2SleeveMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.player) root.player.togglePlaying()
                        }
                    }

                    // ---- sag: dikey Spotify sesi (sistem sesine dokunmaz) ----
                    Item {
                        id: m2Vol
                        x: mediaPop.width - mediaPop.pad - width
                        y: m2Sleeve.y
                        width: 22; height: m2Sleeve.height
                        property bool dragging: false
                        property real dragVal: 0
                        readonly property real val: dragging ? dragVal : (root.spMuted ? 0 : Math.min(1, root.spVolume))
                        opacity: root.spVolReady ? 1 : 0.4
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const step = event.angleDelta.y > 0 ? 0.05 : (event.angleDelta.y < 0 ? -0.05 : 0);
                                if (step !== 0) root.setSpotifyVolume(Math.round((root.spVolume + step) * 20) / 20);
                            }
                        }
                        Item {
                            id: m2VolTrack
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 0
                            width: 22; height: parent.height - 28
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 5; height: parent.height; radius: 2.5
                                color: "#262626"
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; radius: 2.5
                                    height: parent.height * m2Vol.val
                                    color: root.accent
                                    Behavior on height { enabled: !m2Vol.dragging; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                            }
                            // yuzde: surukleyince topun yaninda
                            Text {
                                anchors.right: parent.left; anchors.rightMargin: 4
                                y: m2VolKnob.y + m2VolKnob.height / 2 - height / 2
                                text: Math.round(m2Vol.val * 100)
                                font.pixelSize: 11; font.weight: Font.DemiBold
                                color: root.accent
                                opacity: m2Vol.dragging || m2VolMa.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                            }
                            Rectangle {
                                id: m2VolKnob
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: m2Vol.dragging || m2VolMa.containsMouse ? 14 : 12
                                height: width; radius: width / 2
                                y: (parent.height - 12) * (1 - m2Vol.val) - (width - 12) / 2
                                color: root.accent
                                Behavior on width { NumberAnimation { duration: 120 } }
                                Behavior on y { enabled: !m2Vol.dragging; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                Rectangle { anchors.centerIn: parent; width: parent.width - 4; height: width; radius: width / 2; color: "#000000" }
                            }
                            MouseArea {
                                id: m2VolMa
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                function valAt(my) { return Math.max(0, Math.min(1, 1 - (my - 4 - 6) / (m2VolTrack.height - 12))); }
                                onPressed: m => { m2Vol.dragVal = valAt(m.y); m2Vol.dragging = true; root.setSpotifyVolume(m2Vol.dragVal); }
                                onPositionChanged: m => { if (!m2Vol.dragging) return; m2Vol.dragVal = valAt(m.y); root.setSpotifyVolume(m2Vol.dragVal); }
                                onReleased: m2Vol.dragging = false
                                onCanceled: m2Vol.dragging = false
                            }
                        }
                        CGlyph {
                            id: m2VolIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            size: 15
                            text: root.g((root.spMuted || m2Vol.val <= 0.001) ? 0xF0581 : m2Vol.val < 0.34 ? 0xF057F : m2Vol.val < 0.67 ? 0xF0580 : 0xF057E)
                            color: m2MuteMa.containsMouse ? root.accent : (root.spMuted ? "#7a7a7a" : "#cfcfcf")
                            Behavior on color { ColorAnimation { duration: 130 } }
                            MouseArea {
                                id: m2MuteMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.spVolReady) root.spotifyNode.audio.muted = !root.spotifyNode.audio.muted; }
                            }
                        }
                    }

                    // ---- sarki adi + sanatci ----
                    Column {
                        id: m2Info
                        transform: Translate { id: m2InfoShift }
                        x: mediaPop.pad; y: m2Sleeve.y + m2Sleeve.height + 16
                        width: mediaPop.width - mediaPop.pad * 2
                        spacing: 2
                        Text {
                            width: parent.width
                            text: mediaPop.shownTitle
                            font.pixelSize: 17; font.weight: Font.Bold
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: mediaPop.shownArtist
                            font.pixelSize: 12
                            color: root.accent
                            elide: Text.ElideRight
                        }
                    }

                    // ---- dalgali ilerleme cizgisi: calarken calinan kisim dalgalanir, durunca duzlesir ----
                    Item {
                        id: m2Prog
                        x: mediaPop.pad; y: m2Info.y + 60
                        width: mediaPop.width - mediaPop.pad * 2
                        height: 22
                        property real phase: 0
                        property real amp: root.playing && !mediaPop.dragging ? 3 : 0
                        Behavior on amp { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                        FrameAnimation {
                            running: mediaPop.live && (m2Prog.amp > 0.05)
                            onTriggered: { m2Prog.phase = (m2Prog.phase + frameTime * 5) % (Math.PI * 2); m2Wave.requestPaint(); }
                        }
                        onAmpChanged: m2Wave.requestPaint()
                        Connections { target: mediaPop; function onRatioChanged() { m2Wave.requestPaint(); } }
                        Connections { target: root; function onAccentChanged() { m2Wave.requestPaint(); } }
                        Canvas {
                            id: m2Wave
                            anchors.fill: parent
                            onPaint: {
                                const c = getContext("2d");
                                c.reset();
                                const mid = height / 2, px = Math.max(0, Math.min(width, width * mediaPop.ratio));
                                c.lineCap = "round"; c.lineWidth = 3;
                                // kalan kisim: duz gri
                                c.strokeStyle = "#2a2a2a";
                                c.beginPath(); c.moveTo(Math.min(width - 2, px + 6), mid); c.lineTo(width - 2, mid); c.stroke();
                                // calinan kisim: pywal dalga
                                c.strokeStyle = root.accent.toString();
                                c.beginPath();
                                for (let x = 2; x <= Math.max(2, px - 6); x += 1.5) {
                                    const y = mid + Math.sin(x / 7 - m2Prog.phase) * m2Prog.amp;
                                    if (x === 2) c.moveTo(x, y); else c.lineTo(x, y);
                                }
                                c.stroke();
                            }
                        }
                        // konum isareti: dik cubuk, ustune gelince uzar
                        Rectangle {
                            width: 5; radius: 2.5
                            height: m2SeekMa.containsMouse || mediaPop.dragging ? 20 : 14
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            x: Math.max(0, Math.min(m2Prog.width - width, m2Prog.width * mediaPop.ratio - width / 2))
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#ffffff"
                        }
                        MouseArea {
                            id: m2SeekMa
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.player !== null && mediaPop.len > 0
                            property real pressY: 0
                            property bool summoned: false
                            function ratioAt(mx) { return Math.max(0, Math.min(1, (mx - 4) / m2Prog.width)); }
                            onPressed: m => { pressY = m.y; summoned = false; mediaPop.dragPos = ratioAt(m.x) * mediaPop.len; mediaPop.dragging = true; }
                            onPositionChanged: m => {
                                if (!mediaPop.dragging) return;
                                // robot kayipken basili tutup yukari cekince geri gelir (sarma iptal)
                                if (m2Bot.gone && pressY - m.y > 22) {
                                    summoned = true;
                                    mediaPop.dragging = false;
                                    m2Bot.comeBack();
                                    return;
                                }
                                mediaPop.dragPos = ratioAt(m.x) * mediaPop.len;
                            }
                            onReleased: m => {
                                if (summoned || !mediaPop.dragging) { mediaPop.dragging = false; return; }
                                const t = ratioAt(m.x) * mediaPop.len;
                                if (root.player) { root.player.position = t; root.trackPos = t; }
                                mediaPop.dragPos = t;
                                mediaPop.dragging = false;
                            }
                            onCanceled: mediaPop.dragging = false
                        }
                        // ---- dans eden robot: cizginin sag tarafinda, cizginin ustunde sabit durur, calarken dans eder ----
                        // tikla: dusup kaybolur. Geri getirmek icin cizgiye basili tutup yukari cek.
                        Item {
                            id: m2Bot
                            readonly property int px: 2
                            width: 9 * px; height: 8 * px
                            z: 10
                            property bool gone: false
                            property int beat: 0
                            property real sway: 0
                            property real drop: 0                    // dusme / geri gelme kaymasi
                            readonly property bool dancing: root.playing && !gone && mediaPop.live && !mediaPop.dragging
                            x: Math.round(m2Prog.width - 62 + sway)
                            // ayaklari cizginin hemen ustunde
                            y: Math.round(m2Prog.height / 2 - 2 - height + (dancing && beat % 2 === 1 ? 2 : 0) + drop)
                            visible: !gone || dropAnim.running
                            // govde (bacaksiz, kolsuz) + kol ve bacak kareleri
                            readonly property var body: [
                                "....#....",
                                ".#######.",
                                ".#.###.#.",
                                ".#.###.#.",
                                ".#######.",
                                ".##...##.",
                                ".#######."
                            ]
                            // kollar: 0 asagi, 1 ikisi yukari, 2 sol yukari, 3 sag yukari
                            readonly property int arms: dancing ? [1, 0, 2, 0, 3, 0, 1, 1][beat % 8] : 0
                            readonly property string legs: dancing && beat % 2 === 1 ? ".#.....#." : "..#...#.."
                            property bool blink: false
                            function on(cx, cy) {
                                if (cy === 7) return legs.charAt(cx) === "#";
                                if (body[cy].charAt(cx) === "#") return true;
                                const l = cx === 0, r = cx === 8;
                                if (!l && !r) return false;
                                // kol asagi: 3. satirda; kol yukari: 1. satirda
                                const up = arms === 1 || (arms === 2 && l) || (arms === 3 && r);
                                return up ? (cy === 1 || cy === 2) : cy === 3;
                            }
                            Repeater {
                                model: 72
                                Rectangle {
                                    required property int index
                                    readonly property int cx: index % 9
                                    readonly property int cy: Math.floor(index / 9)
                                    readonly property bool eye: (cy === 2 || cy === 3) && (cx === 2 || cx === 6)
                                    visible: m2Bot.on(cx, cy) || (eye && m2Bot.blink)
                                    x: cx * m2Bot.px; y: cy * m2Bot.px
                                    width: m2Bot.px; height: m2Bot.px
                                    color: "#e07a4f"
                                    // arms degisince yeniden hesaplansin
                                    property int _a: m2Bot.arms
                                    property string _l: m2Bot.legs
                                }
                            }
                            // ritim: 230 ms'de bir vurus; her vurusta saga sola sallanir
                            Timer {
                                interval: 230; repeat: true
                                running: m2Bot.dancing
                                onTriggered: { m2Bot.beat++; m2Bot.sway = m2Bot.beat % 4 === 0 ? -2 : (m2Bot.beat % 4 === 2 ? 2 : 0); }
                                onRunningChanged: if (!running) { m2Bot.beat = 0; m2Bot.sway = 0; }
                            }
                            // dururken arada goz kirpar
                            Timer {
                                interval: 2600; repeat: true
                                running: !m2Bot.dancing && !m2Bot.gone && mediaPop.live
                                onTriggered: { m2Bot.blink = true; blinkOff.restart(); }
                            }
                            Timer { id: blinkOff; interval: 140; onTriggered: m2Bot.blink = false }

                            // dusme: once zipla, sonra asagi dusup kaybol
                            SequentialAnimation {
                                id: dropAnim
                                NumberAnimation { target: m2Bot; property: "drop"; to: -8; duration: 140; easing.type: Easing.OutQuad }
                                ParallelAnimation {
                                    NumberAnimation { target: m2Bot; property: "drop"; to: 46; duration: 420; easing.type: Easing.InQuad }
                                    NumberAnimation { target: m2Bot; property: "opacity"; to: 0; duration: 420; easing.type: Easing.InQuad }
                                }
                            }
                            // geri gelme: cizginin altindan firlayip yerine oturur
                            SequentialAnimation {
                                id: backAnim
                                PropertyAction { target: m2Bot; property: "drop"; value: 24 }
                                PropertyAction { target: m2Bot; property: "opacity"; value: 0 }
                                PropertyAction { target: m2Bot; property: "gone"; value: false }
                                ParallelAnimation {
                                    NumberAnimation { target: m2Bot; property: "drop"; to: -10; duration: 260; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: m2Bot; property: "opacity"; to: 1; duration: 160 }
                                }
                                NumberAnimation { target: m2Bot; property: "drop"; to: 0; duration: 300; easing.type: Easing.OutBounce }
                            }
                            function fall() { if (gone) return; gone = true; dropAnim.restart(); }
                            function comeBack() { if (!gone) return; dropAnim.stop(); backAnim.restart(); }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -3
                                enabled: !m2Bot.gone
                                cursorShape: Qt.PointingHandCursor
                                onClicked: m2Bot.fall()
                            }
                        }
                    }
                    Text { x: mediaPop.pad; y: m2Prog.y + m2Prog.height + 1; text: root.fmtTime(mediaPop.pos); font.pixelSize: 10; color: "#7a7a7a" }
                    Text { x: mediaPop.width - mediaPop.pad - width; y: m2Prog.y + m2Prog.height + 1; text: "-" + root.fmtTime(Math.max(0, mediaPop.len - mediaPop.pos)); font.pixelSize: 10; color: "#7a7a7a" }

                    // ---- tuslar: karistir | onceki | (oynat) | sonraki | tekrarla ----
                    Row {
                        id: m2Ctl
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: m2Prog.y + m2Prog.height + 18
                        spacing: 20
                        Repeater {
                            model: ["shuffle", "prev", "toggle", "next", "loop"]
                            Item {
                                id: m2B
                                required property string modelData
                                readonly property bool big: modelData === "toggle"
                                readonly property bool small: modelData === "shuffle" || modelData === "loop"
                                readonly property bool active: {
                                    const p = root.player;
                                    if (!p) return false;
                                    if (modelData === "shuffle") return p.shuffle === true;
                                    if (modelData === "loop") return p.loopState !== undefined && p.loopState !== 0 && p.loopState !== MprisLoopState.None;
                                    return false;
                                }
                                width: big ? 36 : 24; height: 40
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    visible: m2B.big
                                    anchors.centerIn: parent
                                    width: 36; height: 36; radius: 18
                                    color: root.accent
                                    // oynat/durdur isareti yazi tipinden degil, elle cizili: dairenin tam ortasinda
                                    // durdur: iki yuvarlak cubuk
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        visible: root.playing
                                        Rectangle { width: 4; height: 14; radius: 1.5; color: "#000000" }
                                        Rectangle { width: 4; height: 14; radius: 1.5; color: "#000000" }
                                    }
                                    // oynat: ucgen; agirlik merkezi ortada olsun diye 1.5 px saga
                                    Shape {
                                        visible: !root.playing
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: 1.5
                                        width: 13; height: 15
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            fillColor: "#000000"; strokeColor: "#000000"; strokeWidth: 1.5
                                            joinStyle: ShapePath.RoundJoin
                                            startX: 1; startY: 1
                                            PathLine { x: 12; y: 7.5 }
                                            PathLine { x: 1; y: 14 }
                                            PathLine { x: 1; y: 1 }
                                        }
                                    }
                                    scale: m2BMa.pressed ? 0.9 : (m2BMa.containsMouse ? 1.07 : 1)
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                // karistir / tekrarla: cizgiyle cizilir, her boyda keskin
                                Item {
                                    id: m2Vec
                                    visible: m2B.small
                                    anchors.centerIn: parent
                                    width: 18; height: 18
                                    readonly property color col: m2B.active ? root.accent : (m2BMa.containsMouse ? "#ffffff" : "#6a6a6a")
                                    readonly property bool one: root.player !== null && root.player.loopState === MprisLoopState.Track
                                    Shape {
                                        width: 24; height: 24
                                        transform: Scale { xScale: 0.75; yScale: 0.75 }
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            strokeColor: m2Vec.col; strokeWidth: 2.2; fillColor: "transparent"
                                            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                            PathSvg {
                                                path: m2B.modelData === "shuffle"
                                                    ? "M3 7 H6.5 C11 7 13 17 17.5 17 H21 M18 14 L21 17 L18 20 M3 17 H6.5 C9 17 10.2 14.6 11.2 12.6 M12.8 11.4 C13.8 9.4 15 7 17.5 7 H21 M18 4 L21 7 L18 10"
                                                    : "M4 12 V10 A4 4 0 0 1 8 6 H20 M17 3 L20 6 L17 9 M20 12 V14 A4 4 0 0 1 16 18 H4 M7 21 L4 18 L7 15"
                                            }
                                        }
                                    }
                                    // tek sarki tekrari: ortada kucuk 1
                                    Text {
                                        visible: m2B.modelData === "loop" && m2Vec.one
                                        anchors.centerIn: parent
                                        text: "1"
                                        font.pixelSize: 8; font.weight: Font.Black
                                        color: m2Vec.col
                                    }
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                }
                                CGlyph {
                                    id: m2BIcon
                                    visible: !m2B.small && !m2B.big
                                    anchors.centerIn: parent
                                    // daire icindeki oynat/durdur isareti (kaydirma ayari: horizontalCenterOffset)
                                    anchors.horizontalCenterOffset: m2B.big ? -1 : 0
                                    size: m2B.big ? 18 : 19
                                    text: root.g(m2B.modelData === "shuffle" ? 0xF049D : m2B.modelData === "loop"
                                                 ? (root.player && root.player.loopState === MprisLoopState.Track ? 0xF0458 : 0xF0456)
                                                 : m2B.modelData === "prev" ? 0xF04AE : m2B.modelData === "next" ? 0xF04AD
                                                 : (root.playing ? 0xF03E4 : 0xF040A))
                                    color: m2B.big ? "#000000"
                                         : m2B.small ? (m2B.active ? root.accent : (m2BMa.containsMouse ? "#ffffff" : "#6a6a6a"))
                                         : (m2BMa.containsMouse ? root.accent : "#ffffff")
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                                // etkinse altinda kucuk nokta
                                Rectangle {
                                    visible: m2B.small && m2B.active
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height / 2 + 11
                                    width: 4; height: 4; radius: 2
                                    color: root.accent
                                }
                                SequentialAnimation {
                                    id: m2BBounce
                                    NumberAnimation { target: m2B.small ? m2Vec : m2BIcon; property: "scale"; to: 1.3; duration: 120; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: m2B.small ? m2Vec : m2BIcon; property: "scale"; to: 1.0; duration: 180; easing.type: Easing.OutBack }
                                }
                                MouseArea {
                                    id: m2BMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const p = root.player;
                                        if (!p) return;
                                        m2BBounce.restart();
                                        if (m2B.modelData === "prev") p.previous();
                                        else if (m2B.modelData === "next") p.next();
                                        else if (m2B.modelData === "toggle") p.togglePlaying();
                                        else if (m2B.modelData === "shuffle") { if (p.shuffleSupported !== false) p.shuffle = !p.shuffle; }
                                        else if (m2B.modelData === "loop") {
                                            if (p.loopSupported === false) return;
                                            p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                                        : p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }


                // ---- tepsi cekmecesi: ok'un hizasinda dock'un arkasindan saga kayar ----
                Item {
                    id: trayPop
                    property real cy: 0
                    property real cx: 0
                    readonly property bool shown: trayChev.open && win.shown
                    readonly property int curve: 14
                    width: trayRow.implicitWidth + 22
                    height: 44
                    property real hid: shown ? 0 : 1
                    Behavior on hid { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    x: root.horiz ? Math.max(22 + curve, Math.min(dock.width - 22 - curve - width, cx - width / 2)) : root.dockW - 1 - hid * width
                    y: root.horiz ? -height + 1 + hid * (height + 2) : cy - height / 2
                    visible: hid < 0.995
                    HoverHandler { id: trayHH }
                    // birlesme kavisleri (dikey: ust/alt sol, yatay: alt sol/sag)
                    Fil {
                        x: root.horiz ? -trayPop.curve : 0; y: root.horiz ? trayPop.height - trayPop.curve : -trayPop.curve
                        width: trayPop.curve; height: trayPop.curve
                        cx: root.horiz ? 0 : 1; cy: 0
                    }
                    Fil {
                        x: root.horiz ? trayPop.width : 0; y: root.horiz ? trayPop.height - trayPop.curve : trayPop.height
                        width: trayPop.curve; height: trayPop.curve
                        cx: 1; cy: root.horiz ? 0 : 1
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                    }
                    Row {
                        id: trayRow
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: SystemTray.items
                            DockBtn {
                                id: trayBtn
                                required property var modelData
                                readonly property var td: modelData     // (id uzerinden modelData okunamiyor)
                                w: win
                                height: 36; width: 34
                                        centerH: false
                                tip: modelData ? (modelData.tooltipTitle || modelData.title || modelData.id || "") : ""
                                IconImage {
                                    id: trayIcon
                                    anchors.centerIn: parent
                                    implicitSize: 20
                                    source: {
                                        // Discord gibi Electron uygulamalari "isim?path=klasor" veriyor
                                        if (!trayBtn.td) return "";
                                        let ic = trayBtn.td.icon || "";
                                        if (ic.indexOf("?path=") >= 0) {
                                            const p = ic.split("?path=");
                                            ic = "file://" + p[1] + "/" + p[0].slice(p[0].lastIndexOf("/") + 1);
                                        }
                                        return ic;
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 20; height: 20; radius: 10
                                    visible: trayIcon.status !== Image.Ready
                                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)
                                    Label2 { anchors.centerIn: parent; text: trayBtn.td ? ((trayBtn.td.title || trayBtn.td.id || "?") + "").charAt(0).toUpperCase() : ""; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                onLeftClicked: {
                                    const it = trayBtn.td;
                                    if (it.onlyMenu && it.hasMenu) win.trayMenuFor(it.menu, trayBtn);
                                    else it.activate();
                                }
                                onRightClicked: cy => { const it = trayBtn.td; tipBox.on = false; ctx.open = false; if (it.hasMenu) win.trayMenuFor(it.menu, trayBtn); else it.secondaryActivate(); }
                                onMiddleClicked: trayBtn.td.secondaryActivate()
                            }
                        }
                    }
                }

                // kenara baglanan ic kavisler (dikey: ust + alt, yatay: sol + sag)
                Fil {
                    // govdeye 1px tasar: acilistaki ziplama (olcek) sirasinda kavisle govde arasinda
                    // yari saydam ince cizgi (dikis) kalmasin
                    x: root.horiz ? -root.fil : 0
                    y: root.horiz ? dock.height - root.fil : -root.fil
                    width: root.fil + (root.horiz ? 1 : 0); height: root.fil + (root.horiz ? 0 : 1)
                    cx: root.horiz ? 0 : 1; cy: 0
                    transform: Scale {
                        origin.x: root.horiz ? dock.width / 2 + root.fil : 0
                        origin.y: root.horiz ? root.fil : dock.height / 2 + root.fil
                        xScale: root.horiz ? dock.jy : dock.jx; yScale: root.horiz ? dock.jx : dock.jy
                    }
                }
                // dashboard acikken ust kavis panelin ustundeki pywal isigiyla ayni tonda
                Shape {
                    id: dashFillet
                    x: 0; y: -root.fil; width: root.fil; height: root.fil
                    // (sadece dikeyde: yatayda kavisler altta, isik ustte)
                    transform: Scale { origin.x: 0; origin.y: dock.height / 2 + root.fil; xScale: dock.jx; yScale: dock.jy }
                    preferredRendererType: Shape.CurveRenderer
                    opacity: root.horiz ? 0 : Math.max(dashUi.opacity, netUi.opacity, notifUi.opacity, toastUi.opacity, batUi.opacity, audioUi.opacity)
                    visible: opacity > 0.01
                    ShapePath {
                        strokeWidth: 0; strokeColor: "transparent"
                        fillColor: Qt.rgba(root.accent.r * 0.16, root.accent.g * 0.16, root.accent.b * 0.16, 1)
                        startX: 0; startY: 0
                        PathLine { x: 0; y: root.fil }
                        PathLine { x: root.fil; y: root.fil }
                        PathArc { x: 0; y: 0; radiusX: root.fil; radiusY: root.fil; direction: PathArc.Clockwise }
                    }
                }
                Fil {
                    x: root.horiz ? dock.width - 1 : 0
                    y: root.horiz ? dock.height - root.fil : dock.height - 1
                    width: root.fil + (root.horiz ? 1 : 0); height: root.fil + (root.horiz ? 0 : 1)
                    cx: 1; cy: root.horiz ? 0 : 1
                    transform: Scale {
                        origin.x: root.horiz ? -dock.width / 2 + 1 : 0
                        origin.y: root.horiz ? root.fil : -dock.height / 2 + 1
                        xScale: root.horiz ? dock.jy : dock.jx; yScale: root.horiz ? dock.jx : dock.jy
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                    // jelly: dikeyde saga, yatayda yukari esner
                    transform: Scale {
                        origin.x: root.horiz ? dock.width / 2 : 0
                        origin.y: root.horiz ? dock.height : dock.height / 2
                        xScale: root.horiz ? dock.jy : dock.jx; yScale: root.horiz ? dock.jx : dock.jy
                    }
                }

                // dikeyde sutun, yatayda satir (Grid: iki yonde de ortalar)
                Grid {
                    id: col
                    objectName: "dockGrid"
                    flow: root.horiz ? Grid.LeftToRight : Grid.TopToBottom
                    columns: root.horiz ? 99 : 1
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    y: root.horiz ? Math.round((root.barH - height) / 2) - 2 : 12
                    x: root.horiz ? 14 : Math.round((root.dockW - width) / 2)
                    spacing: root.horiz ? 4 : root.gap
                    opacity: root.wallShape || root.morphing ? 0 : 1
                    enabled: !root.wallShape
                    // acilirken hemen soner; kapanirken dock buzulmeye yaklasinca belirir
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: col.opacity < 0.5 && !root.flipHold ? 170 : 0 }
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }

                    // ---- en ust: Arch -> dashboard (uygulamalar: Super / uygulama menusu) ----
                    DockBtn {
                        w: win
                        tip: "Panel"
                        CGlyph { anchors.centerIn: parent; text: root.g(0xF08C7); size: 26; color: root.accent }
                        // tek tik: dashboard (kisa beklemeyle), cift tik: dikey <-> yatay
                        Timer { id: archTap; interval: 240; onTriggered: root.openDash() }
                        onLeftClicked: { if (archTap.running) { archTap.stop(); root.toggleOrient(); } else archTap.start(); }
                    }
                    Sep {}

                    // ---- sabitler ----
                    Repeater {
                        model: root.apps.pinned
                        AppBtn { required property var modelData; app: modelData; w: win }
                    }
                    // ---- acik ama sabit olmayanlar ----
                    Sep { visible: root.apps.running.length > 0 }
                    Repeater {
                        model: root.apps.running
                        AppBtn { required property var modelData; app: modelData; w: win }
                    }
                    Sep {
                        id: mediaSep
                        color: "#2a2a2a"
                    }
                    // Win11 gibi: uygulamalar ile sistem simgeleri arasinda siyah bosluk (sadece yatay)
                    Item { visible: root.horiz; width: root.horiz ? 60 : 0; height: 1 }


                    // ses + bildirim + ag: birbirine yakin, tek grup
                    Grid {
                        objectName: "dockGrid"
                        flow: root.horiz ? Grid.LeftToRight : Grid.TopToBottom
                        columns: root.horiz ? 99 : 1
                            horizontalItemAlignment: Grid.AlignHCenter
                        verticalItemAlignment: Grid.AlignVCenter
                        spacing: 0
                        // ---- muzik calar (plak): kapak doner, etrafindaki halka sarkinin ilerlemesi ----
                        // tik: medya panelini acar, ustune gelince ust ok onceki / alt ok sonraki, tekerlek: onceki/sonraki,
                        // sag tik: Spotify penceresine gec. Calan bir sey yoksa tamamen gizlenir.
                        Item {
                            id: music
                            transform: Translate { x: root.horiz ? 2 : 0; y: root.horiz ? 3 : 0 }
                            // yatayda plak yok (medya: ses simgesine cift tik)
                            visible: root.musicOn && !root.horiz
                            width: root.horiz ? (visible ? 14 + 50 + 14 : 0) : root.cell
                            height: root.horiz ? root.cell + 8 : (visible ? 16 + 50 + 16 : 0)
                            HoverHandler { id: musicHH }
                            readonly property bool hot: musicHH.hovered

                            // ust ok: onceki sarki
                            CGlyph {
                                id: mPrev
                                x: root.horiz ? -4 : Math.round((parent.width - width) / 2)
                                y: root.horiz ? Math.round((parent.height - height) / 2) : -3
                                size: 15
                                text: root.g(root.horiz ? 0xF0141 : 0xF0143)
                                color: mPrevMa.containsMouse ? root.accent : "#9a9a9a"
                                opacity: music.hot ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                transform: Translate {
                                    x: root.horiz ? (music.hot ? 0 : 5) : 0; y: root.horiz ? 0 : (music.hot ? 0 : 5)
                                    Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                }
                                MouseArea { id: mPrevMa; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root.player) root.player.previous() }
                            }

                            // plak + ilerleme halkasi
                            Item {
                                id: disc
                                width: 50; height: 50
                                x: root.horiz ? 14 : Math.round((parent.width - width) / 2)
                                y: root.horiz ? Math.round((parent.height - height) / 2) : 16
                                scale: discMa.pressed ? 0.92 : (discMa.containsMouse ? 1.06 : 1)
                                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                // sarki degisince kucuk bir ziplama
                                // gosterilen kapak animasyonun ortasinda degisir; yeni kapak once gizlice yuklenir
                                property string shownArt: root.trackArt
                                property bool pending: false
                                function go() { if (!pending) return; pending = false; discWait.stop(); discPop.restart(); }
                                Connections {
                                    target: root
                                    function onTrackArtChanged() {
                                        if (!win.shown) { disc.shownArt = root.trackArt; return; }
                                        disc.pending = true;
                                        discWait.restart();
                                        if (discPre.status === Image.Ready) Qt.callLater(disc.go);
                                    }
                                }
                                Timer { id: discWait; interval: 700; onTriggered: disc.go() }
                                Image {
                                    id: discPre
                                    visible: false
                                    asynchronous: true
                                    source: root.trackArt
                                    sourceSize.width: 96; sourceSize.height: 96
                                    onStatusChanged: if (status === Image.Ready) disc.go()
                                }
                                SequentialAnimation {
                                    id: discPop
                                    onStopped: { vinyl.scale = 1; vinyl.opacity = 1; }
                                    ParallelAnimation {
                                        NumberAnimation { target: vinyl; property: "scale"; to: 0.55; duration: 180; easing.type: Easing.InQuad }
                                        NumberAnimation { target: vinyl; property: "opacity"; to: 0.2; duration: 180; easing.type: Easing.InQuad }
                                    }
                                    ScriptAction { script: { disc.shownArt = root.trackArt; vinyl.rotation = Math.random() * 360; } }
                                    ParallelAnimation {
                                        NumberAnimation { target: vinyl; property: "scale"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                        NumberAnimation { target: vinyl; property: "opacity"; to: 1; duration: 200 }
                                    }
                                }

                                Shape {
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        strokeColor: "#262626"; strokeWidth: 2.6; fillColor: "transparent"
                                        PathAngleArc { centerX: 25; centerY: 25; radiusX: 23.4; radiusY: 23.4; startAngle: 0; sweepAngle: 360 }
                                    }
                                    ShapePath {
                                        strokeColor: root.accent; strokeWidth: 2.6; fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        PathAngleArc {
                                            centerX: 25; centerY: 25; radiusX: 23.4; radiusY: 23.4
                                            startAngle: -90
                                            sweepAngle: 360 * root.trackFrac
                                            Behavior on sweepAngle { NumberAnimation { duration: 950; easing.type: Easing.Linear } }
                                        }
                                    }
                                }

                                // donen plak: kapak resmi yuvarlak; resim yoksa koyu plak + nota
                                Item {
                                    id: vinyl
                                    anchors.centerIn: parent
                                    width: 40; height: 40
                                    ClippingRectangle {
                                        anchors.fill: parent
                                        radius: 20
                                        color: "#161616"
                                        Image {
                                            id: discArt
                                            anchors.fill: parent
                                            source: disc.shownArt
                                            retainWhileLoading: true
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 96; sourceSize.height: 96
                                        }
                                        // plak cizgileri (resim yokken)
                                        Repeater {
                                            model: (disc.shownArt === "" || discArt.status === Image.Error) ? 3 : 0
                                            Rectangle {
                                                required property int index
                                                anchors.centerIn: parent
                                                width: 36 - index * 8; height: width; radius: width / 2
                                                color: "transparent"; border.width: 1; border.color: "#2c2c2c"
                                            }
                                        }
                                        CGlyph {
                                            visible: disc.shownArt === "" || discArt.status === Image.Error
                                            anchors.centerIn: parent
                                            size: 13
                                            text: root.g(0xF075A)
                                            color: root.accent
                                        }
                                    }
                                    // ortadaki delik
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8; height: 8; radius: 4
                                        color: "#000000"
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                                    }
                                }
                                // calarken doner (dakikada ~7.5 tur); durunca oldugu yerde kalir
                                FrameAnimation {
                                    running: root.playing && win.shown
                                    onTriggered: vinyl.rotation = (vinyl.rotation + frameTime * 45) % 360
                                }
                                // durakladiginda ortada oynat isareti
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 22; height: 22; radius: 11
                                    color: Qt.rgba(0, 0, 0, 0.62)
                                    opacity: root.playing ? 0 : 1
                                    scale: root.playing ? 0.6 : 1
                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                    CGlyph { anchors.centerIn: parent; size: 13; text: root.g(0xF040A); color: "#ffffff" }
                                }
                                MouseArea {
                                    id: discMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: m => {
                                        if (!root.player) return;
                                        if (m.button === Qt.RightButton)
                                            Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "class:spotify" })']);
                                        else win.toggleMedia(disc);
                                    }
                                    onWheel: wh => {
                                        if (!root.player) return;
                                        if (wh.angleDelta.y < 0) root.player.next(); else if (wh.angleDelta.y > 0) root.player.previous();
                                    }
                                }
                            }

                            // alt ok: sonraki sarki
                            CGlyph {
                                id: mNext
                                x: root.horiz ? 14 + 50 - 2 : Math.round((parent.width - width) / 2)
                                y: root.horiz ? Math.round((parent.height - height) / 2) : 16 + 50 - 1
                                size: 15
                                text: root.g(root.horiz ? 0xF0142 : 0xF0140)
                                color: mNextMa.containsMouse ? root.accent : "#9a9a9a"
                                opacity: music.hot ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                transform: Translate {
                                    x: root.horiz ? (music.hot ? 0 : -5) : 0; y: root.horiz ? 0 : (music.hot ? 0 : -5)
                                    Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                }
                                MouseArea { id: mNextMa; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root.player) root.player.next() }
                            }
                        }
                        // ---- ses: tekerlekle ac/kis (dock'a yapisik ses cubugu cikar), tik: sessiz, sag tik: ses menusu ----
                        // simge qsbar'daki gibi canli: ses arttikca dalgalar tek tek belirir, sessizde X olur
                        DockBtn {
                            id: volBtn
                            w: win
                            height: 36
                            tip: root.muted ? root.t("Sessiz", "Muted") : Math.round(root.vol * 100) + "%"
                            readonly property bool silent: root.muted || root.vol <= 0.001
                            readonly property color ink: volBtn.hovered ? root.accent : (root.muted ? "#6a6a6a" : "#e6e6e6")
                            property real w1: silent ? 0 : Math.max(0, Math.min(1, root.vol / 0.15))
                            property real w2: silent ? 0 : Math.max(0, Math.min(1, (root.vol - 0.4) / 0.3))
                            property real xs: silent ? 1 : 0
                            Behavior on w1 { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on w2 { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on xs { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            // gorunen kisim (govde + acik dalgalar) her zaman tam ortada dursun: dalga sayisina gore kayar
                            readonly property real k: 22 / 24
                            readonly property real rightEdge: Math.max(12.8 + 5.0 * volBtn.w1 + 3.7 * volBtn.w2, 12.8 + 8.2 * Math.min(1, volBtn.xs))
                            readonly property real shiftU: 12 - (2.2 + rightEdge) / 2
                            Shape {
                                width: 24; height: 24
                                x: (parent.width - 24 * volBtn.k) / 2 + volBtn.shiftU * volBtn.k
                                y: Math.round((parent.height - 24 * volBtn.k) / 2)
                                preferredRendererType: Shape.CurveRenderer
                                transform: Scale { xScale: volBtn.k; yScale: volBtn.k }
                                // hoparlor govdesi
                                ShapePath {
                                    fillColor: volBtn.ink; strokeColor: volBtn.ink
                                    strokeWidth: 2; joinStyle: ShapePath.RoundJoin
                                    startX: 3; startY: 9.2
                                    PathLine { x: 7; y: 9.2 }
                                    PathLine { x: 12; y: 5 }
                                    PathLine { x: 12; y: 19 }
                                    PathLine { x: 7; y: 14.8 }
                                    PathLine { x: 3; y: 14.8 }
                                    PathLine { x: 3; y: 9.2 }
                                }
                                // kucuk dalga
                                ShapePath {
                                    strokeColor: Qt.rgba(volBtn.ink.r, volBtn.ink.g, volBtn.ink.b, volBtn.w1)
                                    strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    startX: 15.5; startY: 9
                                    PathArc { x: 15.5; y: 15; radiusX: 4.2; radiusY: 4.2 }
                                }
                                // buyuk dalga
                                ShapePath {
                                    strokeColor: Qt.rgba(volBtn.ink.r, volBtn.ink.g, volBtn.ink.b, volBtn.w2)
                                    strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    startX: 18; startY: 6
                                    PathArc { x: 18; y: 18; radiusX: 8.5; radiusY: 8.5 }
                                }
                                // sessiz: X
                                ShapePath {
                                    strokeColor: Qt.rgba(volBtn.ink.r, volBtn.ink.g, volBtn.ink.b, Math.max(0, Math.min(1, volBtn.xs)))
                                    strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    startX: 15.5; startY: 9.5
                                    PathLine { x: 20.5; y: 14.5 }
                                    PathMove { x: 20.5; y: 9.5 }
                                    PathLine { x: 15.5; y: 14.5 }
                                }
                            }
                            onWheeled: d => { root.setVol(root.vol + d * 0.05); win.showVol(volBtn); }
                            // tik: dock ses paneline donusur; sag tik: sessiz; tekerlek: dock'a yapisik ses cubugu
                            // yatayda: tek tik ses paneli (cift tiki beklemek icin 240ms sonra), cift tik medya paneli
                            Timer { id: volTap; interval: 240; onTriggered: root.openAudio() }
                            onLeftClicked: {
                                if (!root.horiz) { root.openAudio(); return; }
                                if (volTap.running) {
                                    volTap.stop();
                                    if (root.musicOn && root.player) win.toggleMedia(volBtn);
                                } else volTap.start();
                            }
                            onRightClicked: cy => { root.toggleMute(); win.showVol(volBtn); }
                        }
                        // ---- bildirimler: tik -> bildirim merkezin; sag tik -> rahatsiz etme ----
                        DockBtn {
                            w: win
                            height: 36
                            tip: root.dnd ? root.t("Rahatsız etme açık", "Do not disturb on") : (root.notifCount > 0 ? root.notifCount + root.t(" bildirim", " notifications") : root.t("Bildirim yok", "No notifications"))
                            CGlyph {
                                anchors.centerIn: parent
                                text: root.g(root.dnd ? 0xF009B : 0xF009A)
                                size: 20
                                color: "#e6e6e6"
                            }
                            // okunmamis sayisi
                            Rectangle {
                                visible: root.notifCount > 0 && !root.dnd
                                x: parent.width - width - 2; y: 3
                                width: Math.max(15, ncText.implicitWidth + 7); height: 15; radius: 7.5
                                color: root.accent
                                Label2 { id: ncText; anchors.centerIn: parent; text: root.notifCount > 9 ? "9+" : root.notifCount; font.pixelSize: 9; font.weight: Font.Bold; color: "#000000" }
                            }
                            // tik: dock bildirim paneline donusur; sag tik: rahatsiz etme
                            onLeftClicked: root.openNotif()
                            onRightClicked: cy => root.nToggleDnd()
                        }

                        // ---- ag: wi-fi sinyali ya da (kabloluysa) qsbar'daki ethernet logosu ----
                        DockBtn {
                            w: win
                            height: 36
                            tip: root.ssid
                            CGlyph { anchors.centerIn: parent; visible: root.netKind !== "eth"; text: root.wifiIcon; size: 20 }
                            EthLogo { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; visible: root.netKind === "eth"; size: 20 }
                            // tik: dock ag menusune donusur; sag tik: eski wi-fi menusu
                            onLeftClicked: root.openNet()
                            onRightClicked: cy => Quickshell.execDetached(["sh", "-c", root.cmdWifi])
                        }
                        // ---- pil: bizim Win11 simgesi (sarjda solunda priz) + yuzde; tik -> batarya menun ----
                        DockBtn {
                            // yatayda yuzde yazisi yok; simge eski yerinden 3px asagida
                            transform: Translate { y: root.horiz ? -1 : 0 }
                            visible: root.batPct >= 0
                            w: win
                            height: 46
                            width: root.horiz ? 48 : root.cell
                            tip: Math.round(root.batPct) + "%" + (root.charging ? root.t(" · Şarjda", " · Charging") : "")
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                // pil yuzdenin tam ustunde ortali (ucundaki cikinti hesaba katilmadan govdesi ortalanir)
                                    Item {
                                        width: 27; height: 14
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.horizontalCenterOffset: 1.5
                                        Rectangle {
                                            width: 24; height: 14
                                            radius: 4
                                            color: "transparent"
                                            border.width: 1.4
                                            border.color: "#e6e6e6"
                                            Rectangle {
                                                x: 2.6; y: 2.6
                                                height: parent.height - 5.2
                                                radius: 1.4
                                                width: Math.max(1.5, (parent.width - 5.2) * Math.max(0, root.batPct) / 100)
                                                color: (!root.charging && root.batPct < 20) ? "#ff4d4f" : root.accent
                                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                        Rectangle { x: 24.8; y: 4.4; width: 2.4; height: 5.2; radius: 1.2; color: "#e6e6e6" }
                                        // sarjdayken simsek pilin govdesinin tam ortasinda, beyaz
                                        CGlyph {
                                            visible: root.charging
                                            size: 11; width: 14; height: 14
                                            x: (24 - width) / 2 - 1; y: (14 - height) / 2
                                            text: root.g(0xF0E7)
                                            color: "#ffffff"
                                        }
                                    }
                                Label2 {
                                    visible: !root.horiz
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Math.round(root.batPct) + "%"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }
                            // tik: dock batarya paneline donusur
                            onLeftClicked: root.openBat()
                        }
                        // ---- tepsi: ok -> dock'a yapisik, saga kayarak acilan arka plan uygulamalari ----
                        DockBtn {
                            id: trayChev
                            visible: SystemTray.items.values.length > 0
                            property bool open: false
                            w: win
                            height: 36
                            tip: open ? root.t("Gizle", "Hide") : root.t("Arka plan uygulamaları", "Background apps")
                            CGlyph {
                                anchors.centerIn: parent
                                text: root.g(0xF0142); size: 20
                                color: trayChev.open ? root.accent : "#e6e6e6"
                                // yatayda: kapaliyken asagi, acikken yukari bakar
                                rotation: root.horiz ? (trayChev.open ? -90 : 90) : (trayChev.open ? 180 : 0)
                                Behavior on rotation { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                            onLeftClicked: win.toggleTray(trayChev)
                        }
                    }
                    // ---- saat: ust satir saat, alt satir dakika, altta tarih; tikla -> ezan menusu ----
                    DockBtn {
                        id: clockBtn
                        w: win
                        onLeftClicked: root.openEzan()
                        height: clk.implicitHeight + 6
                        width: root.horiz ? clk.implicitWidth + 16 : root.cell
                        tip: root.gunler[clock.date.getDay()] + ", " + clock.date.getDate() + " " + root.aylar[clock.date.getMonth()]
                        hoverMove: false
                        Column {
                            id: clk
                            anchors.centerIn: parent
                            spacing: 0
                            // ustune gelince saat yumusakca pywal rengine doner (tikla: ezan menusu)
                            Label2 { anchors.horizontalCenter: parent.horizontalCenter; text: root.horiz ? root.pad2(clock.hours) + ":" + root.pad2(clock.minutes) : root.pad2(clock.hours); font.pixelSize: 17; font.weight: Font.DemiBold
                                     color: clockBtn.hovered ? root.accent : "#e6e6e6"; Behavior on color { ColorAnimation { duration: 180 } } }
                            Label2 { visible: !root.horiz; anchors.horizontalCenter: parent.horizontalCenter; text: root.pad2(clock.minutes); font.pixelSize: 17; font.weight: Font.DemiBold
                                     color: clockBtn.hovered ? root.accent : "#e6e6e6"; Behavior on color { ColorAnimation { duration: 180 } } }
                            Label2 { anchors.horizontalCenter: parent.horizontalCenter; text: clock.date.getDate() + " " + root.aylar[clock.date.getMonth()]; font.pixelSize: 10; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85) }
                        }
                    }
                }

                // ================= DUVAR KAGIDI MODU: dock genisleyip dikey duvar kagidi menusune donusur =================
                // kirpma kutusu: dock daralirken menunun tasan kismi gorunmesin
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: (root.dmode === "walls" && !root.horiz) || wallUi.opacity > 0.01
                    // menunun bos yerine tiklamak kapatmasin
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "walls" }
                Item {
                    id: wallUi
                    x: 0; y: 0
                    width: root.wallW
                    height: dock.height
                    // dock genisledikten sonra belirir, kapanirken once kaybolur
                    opacity: root.dmode === "walls" && !root.horiz && dock.width > root.wallW - 40 ? 1 : 0
                    visible: opacity > 0.01
                    enabled: root.dmode === "walls"
                    Behavior on opacity { NumberAnimation { duration: root.dmode === "walls" ? 220 : 90; easing.type: Easing.OutCubic } }
                    transform: Translate { x: root.dmode === "walls" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }

                    // ---- baslik ----
                    Row {
                        id: wHead
                        x: 18; y: 16
                        spacing: 9
                        CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0E09); size: 19; color: root.accent }
                        Label2 { anchors.verticalCenter: parent.verticalCenter; text: root.t("Duvar Kağıdı", "Wallpapers"); font.pixelSize: 15; font.weight: Font.Bold; color: "#ffffff" }
                    }
                    Label2 {
                        anchors.right: parent.right; anchors.rightMargin: 20
                        anchors.verticalCenter: wHead.verticalCenter
                        text: root.wallList.length + (root.wallQuery.length > 0 ? " / " + root.wallAll.length : "")
                        font.pixelSize: 11
                        color: "#7a7a7a"
                    }

                    // ---- arama ----
                    Rectangle {
                        id: wSearch
                        x: 16; y: 50
                        width: parent.width - 32; height: 36
                        radius: 10
                        color: "#141414"
                        border.width: 1
                        border.color: wIn.activeFocus && root.wallQuery.length > 0 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : "#1f1f1f"
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                        CGlyph { id: wSIc; x: 9; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0349); size: 16; color: root.accent }
                        TextInput {
                            id: wIn
                            anchors.left: wSIc.right; anchors.leftMargin: 6
                            anchors.right: wClr.left; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#ffffff"
                            font.family: root.fontName; font.pixelSize: 13
                            selectionColor: root.accent
                            clip: true
                            onTextChanged: if (!root.horiz) root.wallQuery = text
                            Keys.onUpPressed: e => { root.wallMove(-1); e.accepted = true; }
                            Keys.onDownPressed: e => { root.wallMove(1); e.accepted = true; }
                            Keys.onTabPressed: e => { root.wallMove(1); e.accepted = true; }
                            Keys.onReturnPressed: e => { if (root.wallOk(root.wallSel)) root.wallApply(root.wallList[root.wallSel]); e.accepted = true; }
                            Keys.onEnterPressed: e => { if (root.wallOk(root.wallSel)) root.wallApply(root.wallList[root.wallSel]); e.accepted = true; }
                            Keys.onEscapePressed: e => { if (text.length > 0) text = ""; else root.closeWalls(); e.accepted = true; }
                            Label2 {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.t("Ara…", "Search…")
                                color: "#5a5a5a"
                                font.pixelSize: 13
                                visible: wIn.text.length === 0
                            }
                        }
                        CGlyph {
                            id: wClr
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.wallQuery.length > 0 ? 22 : 0
                            opacity: root.wallQuery.length > 0 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            text: root.g(0xF0156); size: 14
                            color: wClrMa.containsMouse ? root.accent : "#8a8a8a"
                            MouseArea { id: wClrMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { wIn.text = ""; wIn.forceActiveFocus(); } }
                        }
                    }
                    Connections {
                        target: root
                        function onWallsOpened() { wIn.text = ""; wFocus.restart(); wList.positionViewAtIndex(root.wallSel, ListView.Center); }
                    }
                    Timer { id: wFocus; interval: 80; onTriggered: if (!root.horiz) wIn.forceActiveFocus() }

                    // ---- dikey liste: secili kart ortada buyuk, digerleri kucuk ve soluk ----
                    ListView {
                        id: wList
                        x: 0; y: wSearch.y + wSearch.height + 12
                        width: parent.width
                        height: parent.height - y - 12
                        clip: true
                        spacing: 6
                        topMargin: 6; bottomMargin: 6
                        model: root.wallList
                        currentIndex: root.wallSel
                        boundsBehavior: Flickable.StopAtBounds
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: height / 2 - wList.cardH / 2
                        preferredHighlightEnd: height / 2 + wList.cardH / 2
                        highlightMoveDuration: 320
                        readonly property real cardW: width - 36
                        readonly property real cardH: Math.round(cardW * 9 / 16)
                        // arama/acilis: liste yenilenince kartlar sirayla asagidan suzulerek gelir
                        cacheBuffer: 600
                        delegate: Item {
                            id: wc
                            required property int index
                            // veri index'ten okunur (dizi modelinde modelData bazen bos geliyordu)
                            readonly property var md: root.wallList[index] || ({ name: "", path: "", thumb: "" })
                            readonly property bool sel: root.wallSel === index
                            readonly property bool cur: root.wallSame(md.path, root.wallCur)
                            width: wList.width
                            height: wList.cardH
                            // giris animasyonu: her kart olusunca (arama / acilis) sirayla suzulur
                            opacity: 0
                            property real rise: 14
                            transform: Translate { y: wc.rise }
                            Component.onCompleted: wcIn.start()
                            SequentialAnimation {
                                id: wcIn
                                PauseAnimation { duration: Math.min(wc.index, 6) * 45 }
                                ParallelAnimation {
                                    NumberAnimation { target: wc; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wc; property: "rise"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                                }
                            }
                            ClippingRectangle {
                                id: wCard
                                anchors.centerIn: parent
                                width: wList.cardW; height: wList.cardH
                                radius: 14
                                color: "#151515"
                                scale: wc.sel ? (wcMa.pressed ? 0.97 : 1) : 0.9
                                opacity: wc.sel ? 1 : 0.55
                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                Behavior on opacity { NumberAnimation { duration: 260 } }
                                // resim yuklenirken bos siyah yerine hafifce nefes alan gri zemin
                                Rectangle {
                                    anchors.fill: parent
                                    color: "#1d1d1d"
                                    visible: wcImg.status !== Image.Ready
                                    SequentialAnimation on opacity {
                                        running: wcImg.status !== Image.Ready && root.dmode === "walls"
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutSine }
                                    }
                                }
                                Image {
                                    id: wcImg
                                    anchors.fill: parent
                                    property int tryN: 0
                                    readonly property var srcs: [wc.md.thumb, wc.md.path]
                                    onSrcsChanged: tryN = 0
                                    source: "file://" + srcs[Math.min(tryN, 1)]
                                    onStatusChanged: if (status === Image.Error && tryN < 1) tryN++
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    retainWhileLoading: true
                                    sourceSize: Qt.size(320, 180)
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                }
                                // alt kisimda isim (koyu gecis uzerinde)
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: 34
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.82) }
                                    }
                                    Label2 {
                                        anchors.left: parent.left; anchors.leftMargin: 10
                                        anchors.right: parent.right; anchors.rightMargin: 10
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                        text: wc.md.name
                                        elide: Text.ElideMiddle
                                        font.pixelSize: 11
                                        font.weight: wc.sel ? Font.DemiBold : Font.Normal
                                        color: "#ffffff"
                                    }
                                }
                                // aktif olan: sag ustte pywal etiket
                                Rectangle {
                                    visible: wc.cur
                                    anchors.right: parent.right; anchors.rightMargin: 8
                                    anchors.top: parent.top; anchors.topMargin: 8
                                    height: 20; radius: 6
                                    width: wcCurRow.implicitWidth + 12
                                    color: root.accent
                                    Row {
                                        id: wcCurRow
                                        anchors.centerIn: parent
                                        spacing: 3
                                        CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF012C); size: 11; color: "#000000" }
                                        Label2 { anchors.verticalCenter: parent.verticalCenter; text: root.t("Aktif", "Active"); font.pixelSize: 10; font.weight: Font.Bold; color: "#000000" }
                                    }
                                }
                            }
                            // secim cercevesi
                            Rectangle {
                                anchors.centerIn: wCard
                                width: wCard.width * wCard.scale + 6; height: wCard.height * wCard.scale + 6
                                radius: 17
                                color: "transparent"
                                border.width: 2
                                border.color: root.accent
                                opacity: wc.sel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }
                            MouseArea {
                                id: wcMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // tik: sec (secili olana tiklayinca uygula), cift tik: uygula
                                onClicked: { if (wc.cur) return; if (wc.sel) root.wallApply(wc.md); else root.wallSel = wc.index; wIn.forceActiveFocus(); }
                                onDoubleClicked: if (!wc.cur) root.wallApply(wc.md)
                            }
                        }
                        // tekerlek: birer birer gez
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            property real acc: 0
                            onWheel: w => {
                                acc += w.angleDelta.y;
                                while (acc >= 120) { root.wallMove(-1); acc -= 120; }
                                while (acc <= -120) { root.wallMove(1); acc += 120; }
                            }
                        }
                    }
                    Label2 {
                        anchors.centerIn: wList
                        text: root.wallLoading ? root.t("Yükleniyor…", "Loading…") : (root.wallQuery.length > 0 ? root.t("Sonuç bulunamadı", "No results") : root.t("Klasör boş", "Folder is empty"))
                        font.pixelSize: 12
                        color: root.accent
                        opacity: root.wallList.length === 0 ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                    }
                }
                }

                // ================= UYGULAMA MODU: dock genisleyip dikey uygulama menusune donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: (root.dmode === "apps" && !root.horiz) || appUi.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "apps" }
                Item {
                    id: appUi
                    width: root.wallW
                    height: dock.height
                    opacity: root.dmode === "apps" && !root.horiz && dock.width > root.wallW - 40 ? 1 : 0
                    enabled: root.dmode === "apps"
                    Behavior on opacity { NumberAnimation { duration: root.dmode === "apps" ? 220 : 90; easing.type: Easing.OutCubic } }
                    transform: Translate { x: root.dmode === "apps" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }

                    // ---- baslik ----
                    Row {
                        id: aHead
                        x: 18; y: 16
                        spacing: 9
                        CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF08C7); size: 19; color: root.accent }
                        Label2 { anchors.verticalCenter: parent.verticalCenter; text: root.t("Uygulamalar", "Apps"); font.pixelSize: 15; font.weight: Font.Bold; color: "#ffffff" }
                    }
                    Label2 {
                        anchors.right: parent.right; anchors.rightMargin: 20
                        anchors.verticalCenter: aHead.verticalCenter
                        text: root.appList.length
                        font.pixelSize: 11
                        color: "#7a7a7a"
                    }

                    // ---- arama ----
                    Rectangle {
                        id: aSearch
                        x: 16; y: 50
                        width: parent.width - 32; height: 36
                        radius: 10
                        color: "#141414"
                        border.width: 1
                        border.color: root.appQuery.length > 0 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : "#1f1f1f"
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                        CGlyph { id: aSIc; x: 9; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0349); size: 16; color: root.accent }
                        TextInput {
                            id: aIn
                            anchors.left: aSIc.right; anchors.leftMargin: 6
                            anchors.right: aClr.left; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#ffffff"
                            font.family: root.fontName; font.pixelSize: 13
                            selectionColor: root.accent
                            clip: true
                            onTextChanged: if (!root.horiz) root.appQuery = text
                            Keys.onUpPressed: e => { root.appMove(-1); e.accepted = true; }
                            Keys.onDownPressed: e => { root.appMove(1); e.accepted = true; }
                            Keys.onTabPressed: e => { root.appMove(1); e.accepted = true; }
                            Keys.onReturnPressed: e => { root.appActivate(); e.accepted = true; }
                            Keys.onEnterPressed: e => { root.appActivate(); e.accepted = true; }
                            Keys.onEscapePressed: e => { if (text.length > 0) text = ""; else root.closeMode(); e.accepted = true; }
                            Label2 {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.t("Uygulama ara…", "Search apps…")
                                color: "#5a5a5a"
                                font.pixelSize: 13
                                visible: aIn.text.length === 0
                            }
                        }
                        CGlyph {
                            id: aClr
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.appQuery.length > 0 ? 22 : 0
                            opacity: root.appQuery.length > 0 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            text: root.g(0xF0156); size: 14
                            color: aClrMa.containsMouse ? root.accent : "#8a8a8a"
                            MouseArea { id: aClrMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { aIn.text = ""; aIn.forceActiveFocus(); } }
                        }
                    }
                    Connections {
                        target: root
                        function onAppsOpened() { aIn.text = ""; aFocus.restart(); aList.positionViewAtBeginning(); }
                    }
                    Timer { id: aFocus; interval: 80; onTriggered: if (!root.horiz) aIn.forceActiveFocus() }

                    // ---- liste ----
                    ListView {
                        id: aList
                        x: 10; y: aSearch.y + aSearch.height + 10
                        width: parent.width - 20
                        height: parent.height - y - 12
                        clip: true
                        spacing: 2
                        cacheBuffer: 400
                        model: root.appList
                        currentIndex: root.appSel
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 200
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: 40
                        preferredHighlightEnd: height - 40
                        delegate: Item {
                            id: ar
                            required property int index
                            readonly property var e: root.appList[index] || null
                            readonly property bool sel: root.appSel === index
                            readonly property bool pinned: root.isPinnedEntry(e)
                            width: aList.width
                            height: 44
                            // giris: sirayla suzulur (arama / acilis)
                            opacity: 0
                            property real rise: 10
                            transform: Translate { y: ar.rise }
                            Component.onCompleted: arIn.start()
                            SequentialAnimation {
                                id: arIn
                                PauseAnimation { duration: Math.min(ar.index, 8) * 30 }
                                ParallelAnimation {
                                    NumberAnimation { target: ar; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: ar; property: "rise"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 11
                                color: ar.sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : "transparent"
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                            // secili satirda solda pywal cubuk
                            Rectangle {
                                x: 0; anchors.verticalCenter: parent.verticalCenter
                                width: 3; radius: 1.5
                                height: ar.sel ? 22 : 0
                                color: root.accent
                                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            IconImage {
                                id: arIcon
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 28
                                scale: ar.sel ? 1.08 : 1
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                source: ar.e ? Quickshell.iconPath(ar.e.icon || "", "application-x-executable") : ""
                            }
                            Column {
                                anchors.left: arIcon.right; anchors.leftMargin: 12
                                anchors.right: arPin.left; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Label2 {
                                    width: parent.width
                                    text: ar.e ? ar.e.name : ""
                                    elide: Text.ElideRight
                                    font.pixelSize: 13
                                    font.weight: ar.sel ? Font.DemiBold : Font.Normal
                                    color: ar.sel ? root.accent : "#e6e6e6"
                                }
                                Label2 {
                                    width: parent.width
                                    visible: text !== ""
                                    text: ar.e ? (ar.e.comment || ar.e.genericName || "") : ""
                                    elide: Text.ElideRight
                                    font.pixelSize: 10
                                    color: "#6a6a6a"
                                }
                            }
                            // raptiye: dock'a sabitle / kaldir (sabitliyse hep, degilse ustune gelince gorunur)
                            CGlyph {
                                id: arPin
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                size: 14
                                text: root.g(ar.pinned ? 0xF0403 : 0xF0931)
                                color: arPinMa.containsMouse ? root.accent : (ar.pinned ? root.accent : "#6a6a6a")
                                opacity: ar.pinned || ar.sel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: root.appSel = ar.index
                                onClicked: root.appLaunch(ar.e)
                            }
                            MouseArea {
                                id: arPinMa
                                anchors.fill: arPin
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePinEntry(ar.e)
                            }
                        }
                    }
                    Label2 {
                        anchors.centerIn: aList
                        text: root.t("Sonuç bulunamadı", "No results")
                        font.pixelSize: 12
                        color: root.accent
                        opacity: root.appList.length === 0 ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                    }
                }
                }

                // ================= EZAN MODU: saate tiklayinca dock ezan menusune donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: root.dmode === "ezan" || ezUi.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "ezan" }
                    FocusScope {
                        id: ezUi
                        width: root.ezW
                        height: root.ezH
                        focus: root.dmode === "ezan"
                        opacity: root.dmode === "ezan" && dock.width > root.ezW - 30 ? 1 : 0
                        enabled: root.dmode === "ezan"
                        Behavior on opacity { NumberAnimation { duration: root.dmode === "ezan" ? 220 : 90; easing.type: Easing.OutCubic } }
                        transform: Translate { x: root.dmode === "ezan" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        // klavye: Esc kapat, sol/sag sehir degistir
                        Keys.onEscapePressed: root.closeMode()
                        Keys.onLeftPressed: if (root.ezSehirIndex > 0) root.ezSehirDegistir(-1)
                        Keys.onRightPressed: if (root.ezSehirIndex < root.ezSehirler.length - 1) root.ezSehirDegistir(1)
                        Timer { id: ezFocus; interval: 80; onTriggered: ezUi.forceActiveFocus() }
                        Connections { target: root; function onDmodeChanged() { if (root.dmode === "ezan") ezFocus.restart(); } }
                    Item {
                        id: ezPage
                        anchors.fill: parent
                            // sehir degisimi: icerik kayip soner, yeni sehir ters yandan gelir
                            SequentialAnimation {
                                id: ezGecis
                                ParallelAnimation {
                                    NumberAnimation { target: root; property: "ezIcerikOpacity"; to: 0; duration: 160; easing.type: Easing.InQuad }
                                    NumberAnimation { target: root; property: "ezIcerikKayma"; to: root.ezGecisYonu > 0 ? -root.ezCityShift : root.ezCityShift; duration: 160; easing.type: Easing.InQuad }
                                }
                                ScriptAction {
                                    script: {
                                        root.ezSehirIndex = (root.ezSehirIndex + root.ezGecisYonu + root.ezSehirler.length) % root.ezSehirler.length;
                                        root.ezIcerikKayma = root.ezGecisYonu > 0 ? root.ezCityShift : -root.ezCityShift;
                                    }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: root; property: "ezIcerikOpacity"; to: 1; duration: 160; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: root; property: "ezIcerikKayma"; to: 0; duration: 160; easing.type: Easing.OutQuad }
                                }
                                PropertyAction { target: ezSehirYazi; property: "color"; value: root.ezAccent }
                                ColorAnimation { target: ezSehirYazi; property: "color"; to: root.ezDim; duration: 950; easing.type: Easing.OutQuad }
                            }
                            Connections {
                                target: root
                                function onEzSehirDegisti(yon) {
                                    if (ezGecis.running) return;
                                    root.ezGecisYonu = yon;
                                    ezGecis.restart();
                                }
                            }

                            // caminin yeri (sag ust). Simgenin kendisi ucan cami (ezFly): ana menudeki
                            // saatin yanindan buraya kayar, geri donunce yine oraya gider
                            // cikis: sol ustte ok -> dock'a geri doner
                            Item {
                                x: 8; y: 10
                                width: 26; height: 26
                                z: 5
                                CGlyph {
                                    anchors.centerIn: parent
                                    size: 20
                                    text: root.g(root.horiz ? 0xF0140 : 0xF0141)
                                    color: ezBackMa.containsMouse ? root.accent : "#e6e6e6"
                                    scale: ezBackMa.pressed ? 0.85 : (ezBackMa.containsMouse ? 1.12 : 1)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { id: ezBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeMode() }
                            }

                            // cami simgesi (sag ust): tikla -> para gibi doner, yesil <-> pywal
                            Item {
                                id: ezCami
                                x: root.horiz ? root.ezPad + 204 - width : parent.width - 15 - width; y: 16
                            width: 18; height: 18
                            property real donus: 0
                            property real pop: 1.0
                            property real hov: ezCamiMa.containsMouse ? 1.18 : 1.0
                            Behavior on hov { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.0 } }
                            transform: [
                                Rotation { origin.x: ezCami.width / 2; origin.y: ezCami.height / 2; axis { x: 0; y: 1; z: 0 } angle: ezCami.donus },
                                Scale { origin.x: ezCami.width / 2; origin.y: ezCami.height / 2; xScale: ezCami.pop * ezCami.hov; yScale: ezCami.pop * ezCami.hov }
                            ]
                            SequentialAnimation {
                                id: ezZipla
                                ParallelAnimation {
                                    NumberAnimation { target: ezCami; property: "donus"; from: 0; to: 90; duration: 165; easing.type: Easing.InQuad }
                                    NumberAnimation { target: ezCami; property: "pop"; from: 1.0; to: 1.15; duration: 165; easing.type: Easing.OutQuad }
                                }
                                ScriptAction { script: root.ezPywal = !root.ezPywal }
                                PropertyAction { target: ezCami; property: "donus"; value: 270 }
                                ParallelAnimation {
                                    NumberAnimation { target: ezCami; property: "donus"; to: 360; duration: 225; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: ezCami; property: "pop"; to: 1.0; duration: 225; easing.type: Easing.OutBack }
                                }
                                PropertyAction { target: ezCami; property: "donus"; value: 0 }
                            }
                            Item {
                                anchors.fill: parent
                                opacity: ezCamiMa.containsMouse ? 1.0 : 0.85
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                                Shape {
                                    width: 24; height: 24
                                    x: -0.752; y: -0.691
                                    transform: Scale { xScale: 0.81264; yScale: 0.81264 }
                                    preferredRendererType: Shape.CurveRenderer
                                    layer.enabled: true
                                    layer.samples: 8
                                    ShapePath { fillColor: root.ezAccent; strokeWidth: 0; strokeColor: "transparent"
                                        PathSvg { path: "M13.209 1.041 A2.45 2.45 0 1 0 14.189 4.812 A2.0 2.0 0 0 1 13.209 1.041 Z" } }
                                    ShapePath { fillColor: root.ezAccent; strokeWidth: 0; strokeColor: "transparent"
                                        PathSvg { path: "M11.5 4.4 H12.5 V7.6 H11.5 Z" } }
                                    ShapePath { fillColor: root.ezAccent; strokeWidth: 0; strokeColor: "transparent"
                                        PathSvg { path: "M6.4 13.8 C6.4 9.8, 8.6 7.3, 12 6.5 C15.4 7.3, 17.6 9.8, 17.6 13.8 Z" } }
                                    ShapePath { fillColor: root.ezAccent; strokeWidth: 0; strokeColor: "transparent"
                                        PathSvg { path: "M6.4 13.6 H17.6 V23 H13.9 v-4.1 c0 -1 -0.85 -1.8 -1.9 -1.8 s-1.9 0.8 -1.9 1.8 V23 H6.4 z" } }
                                    ShapePath { fillColor: root.ezAccent; strokeWidth: 0; strokeColor: "transparent"
                                        PathSvg { path: "M1.4 23 V10.2 C1.4 8.6, 2.12 7.9, 3.0 6.3 C3.88 7.9, 4.6 8.6, 4.6 10.2 V23 Z" } }
                                    ShapePath { fillColor: root.ezAccent; strokeWidth: 0; strokeColor: "transparent"
                                        PathSvg { path: "M19.4 23 V10.2 C19.4 8.6, 20.12 7.9, 21.0 6.3 C21.88 7.9, 22.6 8.6, 22.6 10.2 V23 Z" } }
                                }
                            }
                            MouseArea {
                                id: ezCamiMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ezZipla.restart()
                            }
                            }

                            // veri bugune ait degilse caminin solunda nabiz gibi atan turuncu nokta (tikla: tazele)
                            Rectangle {
                                anchors { right: ezCami.left; verticalCenter: ezCami.verticalCenter; rightMargin: 9 }
                                width: 6; height: 6; radius: 3
                                color: "transparent"
                                border.width: 1.4
                                border.color: root.ezStale
                                opacity: root.ezVeriEski ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 400 } }
                                property real nabiz: 0
                                SequentialAnimation on nabiz {
                                    loops: Animation.Infinite
                                    running: root.ezVeriEski && ezUi.visible
                                    NumberAnimation { from: 0; to: 1; duration: 1600; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1; to: 0; duration: 1600; easing.type: Easing.InOutSine }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 2.6 + parent.nabiz * 1.4
                                    height: width
                                    radius: width / 2
                                    color: root.ezStale
                                    opacity: 0.55 + parent.nabiz * 0.45
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ezCekici.running = true
                                }
                            }

                            Column {
                                id: ezGovde
                                // genislik sabit (dikeyde zaten 236-32); yatayda bu sol sutun, tepsi saga tasinir
                                anchors { left: parent.left; top: parent.top; margins: root.ezPad }
                                width: 204
                                spacing: 0
                                onImplicitHeightChanged: root.ezContentH = implicitHeight
                                Component.onCompleted: root.ezContentH = implicitHeight

                                Column {
                                    width: parent.width
                                    spacing: 0
                                    opacity: root.ezIcerikOpacity
                                    transform: Translate { x: root.ezIcerikKayma }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.t("SONRAKİ VAKİT", "NEXT PRAYER")
                                        font.family: root.ezFont
                                        renderType: Text.NativeRendering
                                        antialiasing: true
                                        font.pixelSize: 10
                                        font.letterSpacing: 1.8
                                        color: root.ezDim
                                    }
                                    Item { width: 1; height: 8 }
                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.ezVeriVar ? root.ezVakitler[root.ezSiradaki][0] : "—"
                                        font.family: root.ezFont
                                        renderType: Text.NativeRendering
                                        antialiasing: true
                                        font.pixelSize: 15
                                        font.bold: true
                                        font.letterSpacing: 0.6
                                        color: root.ezAccent
                                    }
                                    Item { width: 1; height: 9 }
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 7
                                        Repeater {
                                            model: 3
                                            Row {
                                                required property int index
                                                spacing: 1
                                                Text {
                                                    text: {
                                                        const k = root.ezSimdiSn >= 0 ? root.ezKalan() : 0;
                                                        if (index === 0) return root.ezIki(Math.floor(k / 3600));
                                                        if (index === 1) return root.ezIki(Math.floor((k % 3600) / 60));
                                                        return root.ezIki(k % 60);
                                                    }
                                                    font.family: root.ezFont
                                                    renderType: Text.NativeRendering
                                                    antialiasing: true
                                                    font.pixelSize: 30
                                                    font.weight: Font.ExtraLight
                                                    color: root.ezInk
                                                }
                                                Text {
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: 3
                                                    text: index === 1 ? root.t("d", "m") : root.t("s", "h")
                                                    font.family: root.ezFont
                                                    renderType: Text.NativeRendering
                                                    antialiasing: true
                                                    font.pixelSize: 15
                                                    font.weight: Font.Light
                                                    color: root.ezDim
                                                }
                                            }
                                        }
                                    }
                                    Item { width: 1; height: 5 }
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 0
                                        Text {
                                            text: (root.ezVeriVar ? root.ezVakitler[root.ezSiradaki][1] : "--:--") + " · "
                                            font.family: root.ezFont
                                            renderType: Text.NativeRendering
                                            antialiasing: true
                                            font.pixelSize: 10
                                            font.letterSpacing: 0.6
                                            color: root.ezDim
                                        }
                                        Text {
                                            id: ezSehirYazi
                                            text: root.ezSehirler[root.ezSehirIndex].ad
                                            font.family: root.ezFont
                                            renderType: Text.NativeRendering
                                            antialiasing: true
                                            font.pixelSize: 10
                                            font.letterSpacing: 0.6
                                            color: root.ezDim
                                        }
                                    }
                                }

                                Item { width: 1; height: 18 }

                                Rectangle {
                                    id: ezTepsi
                                    width: root.horiz ? root.ezTrayW : parent.width
                                    // yatayda: sag sutunun en ustune
                                    transform: Translate { x: root.horiz ? 204 + 24 : 0; y: root.horiz ? -ezTepsi.y : 0 }
                                    height: root.ezRowH * 5 + root.ezTrayPadV * 2
                                    color: root.ezTray
                                    radius: 14

                                    Rectangle {
                                        id: ezCubuk
                                        x: 7; y: 14
                                        width: 2
                                        height: ezTepsi.height - 28
                                        radius: 1
                                        color: root.ezTrack
                                        Rectangle {
                                            width: parent.width
                                            radius: 1
                                            height: Math.max(0, Math.min(ezCubuk.height, root.ezNoktaY - ezCubuk.y))
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: root.ezTrack }
                                                GradientStop { position: 1.0; color: root.ezAccent }
                                            }
                                            Behavior on height { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    Rectangle {
                                        id: ezNokta
                                        x: 4
                                        y: root.ezNoktaY - 4
                                        width: 8; height: 8; radius: 4
                                        color: root.ezAccent
                                        Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                                        property real nabiz: 0
                                        SequentialAnimation on nabiz {
                                            loops: Animation.Infinite
                                            running: ezUi.visible
                                            NumberAnimation { from: 0; to: 1; duration: 2600; easing.type: Easing.OutQuad }
                                        }
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8 + ezNokta.nabiz * 10
                                            height: width
                                            radius: width / 2
                                            color: "transparent"
                                            border.width: 2
                                            border.color: root.ezAccent
                                            opacity: 0.20 * (1 - ezNokta.nabiz)
                                        }
                                    }

                                    Column {
                                        id: ezSatirlar
                                        width: ezTepsi.width - root.ezTrayPadH * 2
                                        x: root.ezTrayPadH
                                        y: root.ezTrayPadV
                                        spacing: 0
                                        opacity: root.ezIcerikOpacity
                                        transform: Translate { x: root.ezIcerikKayma }
                                        Repeater {
                                            model: 5
                                            Rectangle {
                                                id: ezSatir
                                                required property int index
                                                // satir verisi index'ten okunur (dizi modelinde modelData bazen bos geliyordu)
                                                readonly property var modelData: (root.ezVeriVar ? root.ezVakitler : [
                                                    [root.t("Sabah", "Fajr"),"--:--"], [root.t("Öğlen", "Dhuhr"),"--:--"], [root.t("İkindi", "Asr"),"--:--"],
                                                    [root.t("Akşam", "Maghrib"),"--:--"], [root.t("Yatsı", "Isha"),"--:--"]
                                                ])[index]
                                                width: ezSatirlar.width
                                                height: root.ezRowH
                                                radius: 9
                                                readonly property bool siradaki: root.ezVeriVar && index === root.ezSiradaki
                                                readonly property bool gecmis: root.ezVeriVar && root.ezDakika(modelData[1]) * 60 <= root.ezSimdiSn
                                                readonly property color yaziRengi: siradaki ? root.ezAccent : gecmis ? root.ezPast : root.ezDim
                                                color: siradaki ? root.ezRow : "transparent"
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 10
                                                    Text {
                                                        text: ezSatir.modelData[0]
                                                        font.family: root.ezFont
                                                        renderType: Text.NativeRendering
                                                        antialiasing: true
                                                        font.pixelSize: 13
                                                        font.bold: ezSatir.siradaki
                                                        color: ezSatir.yaziRengi
                                                    }
                                                    Text {
                                                        text: ezSatir.modelData[1]
                                                        font.family: root.ezFont
                                                        renderType: Text.NativeRendering
                                                        antialiasing: true
                                                        font.pixelSize: 13
                                                        color: ezSatir.yaziRengi
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Item { width: 1; height: 14 }

                                // alt cubuk: < tarih/gun >
                                Item {
                                    id: ezAlt
                                    width: parent.width
                                    height: 26
                                    // yatayda: sol sutunun altina, tepsinin alt kenariyla hizali
                                    transform: Translate { y: root.horiz ? (root.ezRowH * 5 + root.ezTrayPadV * 2 - 26) - ezAlt.y : 0 }
                                    Item {
                                        id: ezSolOk
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        width: 24; height: 24
                                        readonly property bool aktif: root.ezSehirIndex > 0
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: ezSolOk.aktif && ezSolMa.containsMouse ? Qt.rgba(root.ezAccent.r, root.ezAccent.g, root.ezAccent.b, 0.18) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "❮"
                                            font.family: root.ezFont
                                            renderType: Text.NativeRendering
                                            antialiasing: true
                                            font.pixelSize: 15
                                            color: root.ezAccent
                                            opacity: ezSolOk.aktif ? (ezSolMa.containsMouse ? 1.0 : 0.85) : 0.32
                                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                                        }
                                        MouseArea {
                                            id: ezSolMa
                                            anchors.fill: parent
                                            hoverEnabled: ezSolOk.aktif
                                            cursorShape: ezSolOk.aktif ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (ezSolOk.aktif) root.ezSehirDegistir(-1)
                                        }
                                    }
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.formatDate(new Date(root.ezBugun > 0 ? Date.now() : 0), "dd/MM/yyyy")
                                            font.family: root.ezFont
                                            renderType: Text.NativeRendering
                                            antialiasing: true
                                            font.pixelSize: 10
                                            font.letterSpacing: 1.3
                                            color: root.ezAccent
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.ezGunAdlari[new Date(root.ezBugun > 0 ? Date.now() : 0).getDay()]
                                            font.family: root.ezFont
                                            renderType: Text.NativeRendering
                                            antialiasing: true
                                            font.pixelSize: 10
                                            font.letterSpacing: 1.3
                                            color: root.ezAccent
                                        }
                                    }
                                    Item {
                                        id: ezSagOk
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        width: 24; height: 24
                                        readonly property bool aktif: root.ezSehirIndex < root.ezSehirler.length - 1
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: ezSagOk.aktif && ezSagMa.containsMouse ? Qt.rgba(root.ezAccent.r, root.ezAccent.g, root.ezAccent.b, 0.18) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "❯"
                                            font.family: root.ezFont
                                            renderType: Text.NativeRendering
                                            antialiasing: true
                                            font.pixelSize: 15
                                            color: root.ezAccent
                                            opacity: ezSagOk.aktif ? (ezSagMa.containsMouse ? 1.0 : 0.85) : 0.32
                                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                                        }
                                        MouseArea {
                                            id: ezSagMa
                                            anchors.fill: parent
                                            hoverEnabled: ezSagOk.aktif
                                            cursorShape: ezSagOk.aktif ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (ezSagOk.aktif) root.ezSehirDegistir(1)
                                        }
                                    }
                                }
                            }
                    }
                    }

                }

                // ================= DASHBOARD MODU: Arch'a tiklayinca dock sistem paneline donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: root.dmode === "dash" || dashUi.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "dash" }
                    FocusScope {
                        id: dashUi
                        width: root.dashW
                        height: root.dashH
                        focus: root.dmode === "dash"
                        opacity: root.dmode === "dash" && dock.width > root.dashW - 30 ? 1 : 0
                        enabled: root.dmode === "dash"
                        Behavior on opacity { NumberAnimation { duration: root.dmode === "dash" ? 220 : 90; easing.type: Easing.OutCubic } }
                        transform: Translate { x: root.dmode === "dash" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        Keys.onEscapePressed: root.closeMode()
                        Timer { id: dashFocus; interval: 80; onTriggered: dashUi.forceActiveFocus() }
                        Connections { target: root; function onDmodeChanged() { if (root.dmode === "dash") { dashFocus.restart(); dashIn.restart(); } } }

                        // bolumler sirayla asagidan suzulur
                        property real rise: 0
                        SequentialAnimation {
                            id: dashIn
                            PropertyAction { target: dashUi; property: "rise"; value: 1 }
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: dashUi; property: "rise"; to: 0; duration: 520; easing.type: Easing.OutCubic }
                        }

                        // ust kisimda hafif pywal isigi (sol ustteki kavis de ayni tonda: dashFillet)
                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
                                GradientStop { position: 0.30; color: "transparent" }
                            }
                        }

                        // net yazi: kucuk boyutlarda sistemin font cizimi (bulanik/pikselli durmasin)
                        component DText: Text {
                            color: "#ededed"
                            font.family: root.fontName
                            font.pixelSize: 12
                            renderType: Text.NativeRendering
                        }

                        component DRing: Item {
                            id: rg
                            property real v: 0
                            property string label: ""
                            property string val: ""
                            property string sub: ""
                            property int icon: 0
                            property bool hot: false
                            width: 72; height: 106
                            property real av: v
                            Behavior on av { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                            Shape {
                                width: 72; height: 72
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath { strokeColor: "#262626"; strokeWidth: 6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    PathAngleArc { centerX: 36; centerY: 36; radiusX: 30; radiusY: 30; startAngle: 135; sweepAngle: 270 } }
                                ShapePath { strokeColor: rg.hot || rg.av > 0.85 ? "#ff6b6b" : root.accent; strokeWidth: 6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    PathAngleArc { centerX: 36; centerY: 36; radiusX: 30; radiusY: 30; startAngle: 135; sweepAngle: Math.max(0.5, 270 * Math.min(1, rg.av)) } }
                            }
                            Column {
                                x: 0; y: 18; width: 72
                                CGlyph { anchors.horizontalCenter: parent.horizontalCenter; text: root.g(rg.icon); size: 13; color: "#a8a8a8" }
                                DText { anchors.horizontalCenter: parent.horizontalCenter; text: rg.val; font.pixelSize: 15; font.bold: true; color: "#ffffff" }
                            }
                            DText { y: 70; anchors.horizontalCenter: parent.horizontalCenter; text: rg.label; font.pixelSize: 12; font.bold: true; color: "#e0e0e0" }
                            DText { y: 87; anchors.horizontalCenter: parent.horizontalCenter; text: rg.sub; font.pixelSize: 10; color: rg.hot ? "#ff8a8a" : "#9a9a9a" }
                        }

                        // ---- sol ust: cikis oku -> dock'a geri doner ----
                        Item {
                            x: root.horiz ? 12 : 8; y: 26
                            width: 26; height: 26
                            z: 5
                            opacity: 1 - dashUi.rise
                            CGlyph {
                                anchors.centerIn: parent
                                size: 20
                                text: root.g(root.horiz ? 0xF0140 : 0xF0141)
                                color: dashBackMa.containsMouse ? root.accent : "#e6e6e6"
                                scale: dashBackMa.pressed ? 0.85 : (dashBackMa.containsMouse ? 1.12 : 1)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            MouseArea { id: dashBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeMode() }
                        }

                        // ---- ust: profil + acik kalma suresi ----
                        Row {
                            x: root.horiz ? 46 : 40; y: 15; spacing: 12
                            opacity: 1 - dashUi.rise
                            Rectangle {
                                width: 48; height: 48; radius: 24
                                color: "#0d0d0d"; border.width: 2; border.color: root.accent
                                CGlyph { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; text: root.g(0xF08C7); size: 25; color: root.accent }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                DText { text: root.userName; font.pixelSize: 17; font.bold: true; color: "#ffffff" }
                                DText { text: root.t("Arch Linux · açık ", "Arch Linux · up ") + (root.dUptime || "…"); font.pixelSize: 11; color: "#a0a0a0" }
                            }
                        }

                        // ---- sag ust: Bip-chan (sag kolunu sallar, goz kirpar; tiklayinca ziplar) ----
                        Item {
                            id: bip
                            x: root.dashW - (root.horiz ? 24 : 18) - 27; y: 25
                            width: 27; height: 24
                            opacity: 1 - dashUi.rise
                            property bool wave: false
                            property bool blink: false
                            property real hop: 0
                            readonly property var idle: [
                                "....#....",
                                ".#######.",
                                ".#.###.#.",
                                "##.###.##",
                                ".#######.",
                                ".##...##.",
                                ".#######.",
                                "..#...#.."
                            ]
                            // sadece sag kol bir sira yukari kalkar; govde ve agiz hic degismez
                            readonly property var waving: [
                                "....#....",
                                ".#######.",
                                ".#.###.##",
                                "##.###.#.",
                                ".#######.",
                                ".##...##.",
                                ".#######.",
                                "..#...#.."
                            ]
                            readonly property var rows: bip.wave ? bip.waving : bip.idle
                            transform: Translate { y: -bip.hop }
                            Timer { interval: 480; repeat: true; running: root.dmode === "dash"; onTriggered: bip.wave = !bip.wave }
                            Timer { interval: 3100; repeat: true; running: root.dmode === "dash"; onTriggered: { bip.blink = true; bipBlink.restart(); } }
                            Timer { id: bipBlink; interval: 140; onTriggered: bip.blink = false }
                            Repeater {
                                model: 72
                                Rectangle {
                                    required property int index
                                    readonly property int cx: index % 9
                                    readonly property int cy: Math.floor(index / 9)
                                    readonly property bool eye: (cy === 2 || cy === 3) && (cx === 2 || cx === 6)
                                    visible: bip.rows[cy].charAt(cx) === "#" || (eye && bip.blink)
                                    x: cx * 3; y: cy * 3; width: 3; height: 3
                                    color: "#e07a4f"
                                }
                            }
                            SequentialAnimation {
                                id: bipHop
                                NumberAnimation { target: bip; property: "hop"; to: 7; duration: 140; easing.type: Easing.OutQuad }
                                NumberAnimation { target: bip; property: "hop"; to: 0; duration: 260; easing.type: Easing.OutBounce }
                            }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bipHop.restart()
                            }
                        }

                        // ---- sistem halkalari ----
                        Item {
                            x: 0; y: 86; width: parent.width; height: 132
                            opacity: 1 - dashUi.rise
                            transform: Translate { y: dashUi.rise * 18 }
                            DText { x: root.horiz ? 24 : 18; y: 0; text: root.t("SİSTEM", "SYSTEM"); font.pixelSize: 11; font.bold: true; color: "#8a8a8a"; font.letterSpacing: 1.6 }
                            Row {
                                x: root.horiz ? 24 : 16; y: 22; spacing: root.horiz ? Math.floor((root.dashW - 48 - 4 * 72) / 3) : 13
                                DRing { icon: 0xF061A; v: root.dCpu; val: Math.round(root.dCpu * 100) + "%"; label: "CPU"
                                        sub: root.dCpuTemp >= 0 ? root.dCpuTemp + "°C" : "—"; hot: root.dCpuTemp >= 90 }
                                DRing { icon: 0xF035B; v: root.dRam; val: Math.round(root.dRam * 100) + "%"; label: "RAM"
                                        sub: root.dRamTot > 0 ? root.dRamUsed.toFixed(1) + "/" + Math.round(root.dRamTot) + " GB" : "—" }
                                DRing { icon: 0xF08AE; v: root.dGpu; val: root.dGpuOk ? Math.round(root.dGpu * 100) + "%" : "—"; label: "GPU"
                                        sub: root.dGpuTemp >= 0 ? root.dGpuTemp + "°C" : "—"; hot: root.dGpuTemp >= 85 }
                                DRing { icon: 0xF02CA; v: root.dDisk; val: Math.round(root.dDisk * 100) + "%"; label: "Disk"
                                        sub: root.dDiskTot > 0 ? Math.round(root.dDiskUsed) + "/" + Math.round(root.dDiskTot) + " GB" : "—" }
                            }
                        }

                        // ---- ekran karti ----
                        Rectangle {
                            id: dGpuCard
                            x: 16; y: 230; width: root.horiz ? Math.floor((root.dashW - 44) / 2) : root.dashW - 32; height: root.horiz ? 134 : 122; radius: 16
                            color: "#101010"; border.width: 1; border.color: "#1e1e1e"
                            opacity: 1 - dashUi.rise
                            transform: Translate { y: dashUi.rise * 26 }
                            Row {
                                x: 14; y: 13; spacing: 10
                                Rectangle {
                                    width: 34; height: 34; radius: 10; color: "#76b900"
                                    CGlyph { anchors.centerIn: parent; text: root.g(0xF08AE); size: 18; color: "#0b1a00" }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    DText { text: root.dGpuOk ? root.dGpuName : root.t("Ekran kartı", "Graphics card"); font.pixelSize: 14; font.bold: true; color: "#f0f0f0"; width: root.horiz ? 150 : 190; elide: Text.ElideRight }
                                    DText { text: root.dGpuOk ? root.t("NVIDIA · sürücü ", "NVIDIA · driver ") + root.dGpuDrv : root.t("nvidia-smi bulunamadı", "nvidia-smi not found"); font.pixelSize: 10; color: "#9a9a9a" }
                                }
                            }
                            DText {
                                anchors.right: parent.right; anchors.rightMargin: 14; y: 13
                                text: root.dGpuTemp >= 0 ? root.dGpuTemp + "°C" : "—"
                                font.pixelSize: 23; font.bold: true
                                color: root.dGpuTemp >= 85 ? "#ff6b6b" : root.accent
                            }
                            // sicaklik grafigi
                            Canvas {
                                id: gpuGraph
                                x: 14; y: 58; width: parent.width - 28; height: root.horiz ? 40 : 32
                                onHeightChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                Connections { target: root; function onDGpuHistChanged() { gpuGraph.requestPaint(); } }
                                Connections { target: root; function onAccentChanged() { gpuGraph.requestPaint(); } }
                                onPaint: {
                                    const c = getContext("2d"); c.reset();
                                    const pts = root.dGpuHist;
                                    if (pts.length < 2) return;
                                    let lo = Math.min.apply(null, pts) - 4, hi = Math.max.apply(null, pts) + 4;
                                    if (hi - lo < 15) { const m = (hi + lo) / 2; lo = m - 7.5; hi = m + 7.5; }
                                    const n = 40;
                                    const x0 = (n - pts.length) * width / (n - 1);
                                    c.beginPath();
                                    for (let i = 0; i < pts.length; i++) {
                                        const x = x0 + i * width / (n - 1), y = 2 + (height - 4) * (1 - (pts[i] - lo) / (hi - lo));
                                        i ? c.lineTo(x, y) : c.moveTo(x, y);
                                    }
                                    c.strokeStyle = root.accent; c.lineWidth = 2; c.lineJoin = "round"; c.stroke();
                                    c.lineTo(width, height); c.lineTo(x0, height); c.closePath();
                                    c.fillStyle = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15); c.fill();
                                }
                            }
                            DText {
                                anchors.centerIn: gpuGraph
                                visible: root.dGpuHist.length < 2
                                text: root.t("ölçülüyor…", "measuring…"); font.pixelSize: 10; color: "#5a5a5a"
                            }
                            Row {
                                x: 14; y: root.horiz ? 108 : 98; spacing: root.horiz ? 12 : 16
                                DText { text: "⚡ " + (root.dGpuW >= 0 ? Math.round(root.dGpuW) + " W" : "—"); font.pixelSize: 11; color: "#b0b0b0" }
                                DText { text: "VRAM " + (root.dVramTot > 0 ? root.dVramUsed.toFixed(1) + "/" + Math.round(root.dVramTot) + " GB" : "—"); font.pixelSize: 11; color: "#b0b0b0" }
                                DText { visible: root.dGpuFan >= 0; text: root.t("Fan %" + root.dGpuFan, "Fan " + root.dGpuFan + "%"); font.pixelSize: 11; color: "#b0b0b0" }
                            }
                        }

                        // ---- en cok kullananlar ----
                        Rectangle {
                            id: dProcCard
                            x: root.horiz ? 16 + dGpuCard.width + 12 : 16; y: root.horiz ? 230 : 364
                            width: root.horiz ? dGpuCard.width : root.dashW - 32; height: 134; radius: 16
                            color: "#101010"; border.width: 1; border.color: "#1e1e1e"
                            opacity: 1 - dashUi.rise
                            transform: Translate { y: dashUi.rise * 34 }
                            DText { x: 14; y: 12; text: root.t("En çok kullananlar", "Top processes"); font.pixelSize: 13; font.bold: true; color: "#f0f0f0" }
                            DText { anchors.right: parent.right; anchors.rightMargin: 14; y: 14; text: "CPU · RAM"; font.pixelSize: 10; color: "#8a8a8a" }
                            Column {
                                x: 14; y: 40; spacing: 9
                                Repeater {
                                    model: 4
                                    Item {
                                        id: prow
                                        required property int index
                                        readonly property var p: root.dProcs[index] || null
                                        width: dProcCard.width - 28; height: 14
                                        opacity: p ? 1 : 0.25
                                        DText { width: root.horiz ? 88 : 100; elide: Text.ElideRight; text: prow.p ? prow.p.n : "—"; font.pixelSize: 11; color: "#dcdcdc"; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle {
                                            x: root.horiz ? 94 : 106; anchors.verticalCenter: parent.verticalCenter
                                            width: root.horiz ? 68 : 104; height: 5; radius: 2.5; color: "#242424"
                                            Rectangle {
                                                width: prow.p ? Math.max(4, parent.width * Math.min(1, prow.p.c * 4)) : 0
                                                height: 5; radius: 2.5; color: root.accent
                                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                        DText {
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            text: prow.p ? Math.round(prow.p.c * 100) + "%  " + (prow.p.r >= 1024 ? (prow.p.r / 1024).toFixed(1) + " GB" : Math.round(prow.p.r) + " MB") : ""
                                            font.pixelSize: 10; color: "#a8a8a8"
                                        }
                                    }
                                }
                            }
                        }

                        // ---- guc ----
                        Item {
                            x: 0; y: root.horiz ? 380 : 512; width: parent.width; height: 110
                            opacity: 1 - dashUi.rise
                            transform: Translate { y: dashUi.rise * 42 }
                            DText {
                                x: root.horiz ? 24 : 18; y: 0
                                text: root.dashArm >= 0 ? root.t("EMİN MİSİN? TEKRAR BAS", "SURE? PRESS AGAIN") : root.t("GÜÇ", "POWER")
                                font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.6
                                color: root.dashArm >= 0 ? "#ff8a8a" : "#8a8a8a"
                            }
                            Row {
                                x: 16; y: 22; spacing: 9.5
                                Repeater {
                                    model: 5
                                    Column {
                                        id: pb
                                        required property int index
                                        readonly property var icons: [0xF033E, 0xF04B2, 0xF0343, 0xF0453, 0xF0425]
                                        readonly property var names: [root.t("Kilit", "Lock"), root.t("Uyku", "Sleep"), root.t("Çıkış", "Logout"), root.t("Yeniden", "Reboot"), root.t("Kapat", "Shutdown")]
                                        readonly property bool armed: root.dashArm === index
                                        readonly property bool danger: index === 4 || armed
                                        spacing: 6
                                        Rectangle {
                                            width: root.horiz ? Math.floor((root.dashW - 32 - 4 * 9.5) / 5) : 58; height: root.horiz ? 54 : 58; radius: 17
                                            color: pb.armed ? "#4a1818" : (pb.index === 4 ? "#2a1414" : (pbMa.containsMouse ? "#1c1c1c" : "#141414"))
                                            border.width: 1
                                            border.color: pb.armed ? "#ff6b6b" : (pbMa.containsMouse ? (pb.index === 4 ? "#7a2a2a" : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)) : (pb.index === 4 ? "#4a1f1f" : "#222222"))
                                            scale: pbMa.pressed ? 0.92 : (pbMa.containsMouse ? 1.06 : 1)
                                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            CGlyph { anchors.centerIn: parent; anchors.horizontalCenterOffset: pb.index === 3 ? 2 : 0; text: root.g(pb.icons[pb.index]); size: 22; color: pb.danger ? "#ff6b6b" : (pbMa.containsMouse ? root.accent : "#ededed") }
                                            MouseArea {
                                                id: pbMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.dashPower(pb.index)
                                            }
                                        }
                                        DText { anchors.horizontalCenter: parent.horizontalCenter; text: pb.armed ? root.t("Emin?", "Sure?") : pb.names[pb.index]; font.pixelSize: 10; color: pb.armed ? "#ff8a8a" : "#a8a8a8" }
                                    }
                                }
                            }
                        }
                    }
                }
                // ================= AG MODU: ag simgesine tiklayinca dock ag menusune donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: root.dmode === "net" || netUi.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "net" }
                    FocusScope {
                        id: netUi
                        width: root.netW
                        height: dock.height
                        focus: root.dmode === "net"
                        opacity: root.dmode === "net" && dock.width > root.netW - 30 ? 1 : 0
                        enabled: root.dmode === "net"
                        Behavior on opacity { NumberAnimation { duration: root.dmode === "net" ? 220 : 90; easing.type: Easing.OutCubic } }
                        transform: Translate { x: root.dmode === "net" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        Keys.onEscapePressed: { if (root.nPass !== "") root.nPass = ""; else root.closeMode(); }
                        Timer { id: netFocus; interval: 80; onTriggered: netUi.forceActiveFocus() }
                        Connections { target: root; function onDmodeChanged() { if (root.dmode === "net") { netFocus.restart(); netIn.restart(); } } }
                        property real rise: 0
                        SequentialAnimation {
                            id: netIn
                            PropertyAction { target: netUi; property: "rise"; value: 1 }
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: netUi; property: "rise"; to: 0; duration: 520; easing.type: Easing.OutCubic }
                        }

                        // ust kisimda hafif pywal isigi (kavis dashFillet ile ayni tonda)
                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
                                GradientStop { position: 0.30; color: "transparent" }
                            }
                        }

                        // sinyal cubuklari (4 cubuk, guce gore dolar)
                        component Bars: Item {
                            id: bars
                            property int sig: 0
                            property color on: "#ededed"
                            property color off: "#333333"
                            width: 18; height: 14
                            readonly property int n: sig >= 75 ? 4 : sig >= 50 ? 3 : sig >= 25 ? 2 : sig > 0 ? 1 : 0
                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    x: index * 4.6; width: 3; radius: 1.5
                                    height: 4 + index * 3.3
                                    y: bars.height - height
                                    color: index < bars.n ? bars.on : bars.off
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                }
                            }
                        }

                        // ---- sol ust: cikis oku ----
                        Item {
                            x: 8; y: 16
                            width: 26; height: 26
                            z: 5
                            opacity: 1 - netUi.rise
                            CGlyph {
                                anchors.centerIn: parent
                                size: 20
                                text: root.g(root.horiz ? 0xF0140 : 0xF0141)
                                color: netBackMa.containsMouse ? root.accent : "#e6e6e6"
                                scale: netBackMa.pressed ? 0.85 : (netBackMa.containsMouse ? 1.12 : 1)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            MouseArea { id: netBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeMode() }
                        }
                        NText {
                            x: 40; y: 18
                            text: root.t("Ağ", "Network")
                            font.pixelSize: 16; font.bold: true; color: "#ffffff"
                            opacity: 1 - netUi.rise
                        }
                        // sag ust: yeniden tara
                        Item {
                            x: root.netW - 16 - 26; y: 16
                            width: 26; height: 26
                            readonly property bool can: root.nView === "bt" ? root.nBtOn : root.nWifiOn
                            readonly property bool busy: root.nView === "bt" ? root.bScanning : root.nScanning
                            opacity: (1 - netUi.rise) * (can ? 1 : 0.3)
                            CGlyph {
                                id: scanIc
                                anchors.centerIn: parent
                                size: 18
                                text: root.g(0xF0450)
                                color: scanMa.containsMouse || scanIc.parent.busy ? root.accent : "#bdbdbd"
                                RotationAnimation on rotation { running: scanIc.parent.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            MouseArea {
                                id: scanMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (!parent.can || parent.busy) return;
                                    scanIc.rotation = 0;
                                    if (root.nView === "bt") btScan.running = true; else netScan.running = true;
                                }
                            }
                        }

                        // ---- durum karti: su anki baglanti ----
                        Rectangle {
                            id: nHero
                            x: 16; y: 56; width: root.horiz ? root.netCol : root.netW - 32; height: 78; radius: 18
                            readonly property bool eth: root.nEthOn
                            readonly property bool wifi: !eth && root.nCurSsid !== ""
                            readonly property bool online: eth || wifi
                            color: online ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.13) : "#101010"
                            border.width: 1
                            border.color: online ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35) : "#1e1e1e"
                            Behavior on color { ColorAnimation { duration: 250 } }
                            opacity: 1 - netUi.rise
                            transform: Translate { y: netUi.rise * 16 }
                            // ikon + baglanti varken yayilan halka
                            Item {
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 46; height: 46
                                Rectangle {
                                    id: ripple
                                    anchors.centerIn: parent
                                    width: 46; height: 46; radius: 23
                                    color: "transparent"
                                    border.width: 2; border.color: root.accent
                                    opacity: 0
                                    visible: nHero.online
                                    SequentialAnimation on scale {
                                        running: nHero.online && root.dmode === "net"; loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 1.5; duration: 1600; easing.type: Easing.OutCubic }
                                    }
                                    SequentialAnimation on opacity {
                                        running: nHero.online && root.dmode === "net"; loops: Animation.Infinite
                                        NumberAnimation { from: 0.55; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: 23
                                    color: nHero.online ? root.accent : "#1c1c1c"
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                    EthLogo { anchors.centerIn: parent; visible: nHero.eth; size: 22 }
                                    CGlyph {
                                        anchors.centerIn: parent; visible: !nHero.eth
                                        text: root.g(nHero.wifi ? (root.nCurSig >= 75 ? 0xF0928 : root.nCurSig >= 50 ? 0xF0925 : root.nCurSig >= 25 ? 0xF0922 : 0xF091F) : 0xF092D)
                                        size: 22
                                        color: nHero.online ? "#0b1530" : "#8a8a8a"
                                    }
                                }
                            }
                            Column {
                                x: 72; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 72 - 14
                                spacing: 3
                                NText {
                                    width: parent.width; elide: Text.ElideRight
                                    text: nHero.eth ? "Ethernet" : (nHero.wifi ? root.nCurSsid : root.t("Bağlı değil", "Not connected"))
                                    font.pixelSize: 15; font.bold: true; color: "#ffffff"
                                }
                                NText {
                                    width: parent.width; elide: Text.ElideRight
                                    text: nHero.eth ? (root.t("Kablolu · ", "Wired · ") + (root.nEthIp || root.nEthDev))
                                         : nHero.wifi ? ("Wi-Fi · " + root.t("%" + root.nCurSig, root.nCurSig + "%") + (root.nWifiIp ? " · " + root.nWifiIp : ""))
                                         : (root.nWifiOn ? root.t("Aşağıdan bir ağ seç", "Pick a network below") : root.t("Wi-Fi kapalı", "Wi-Fi off"))
                                    font.pixelSize: 11; color: nHero.online ? "#cfd8ff" : "#9a9a9a"
                                }
                            }
                        }

                        // ---- anahtarlar: Wi-Fi / Ethernet / Bluetooth ----
                        Row {
                            id: nTog
                            x: 16; y: 146; spacing: 8
                            opacity: 1 - netUi.rise
                            transform: Translate { y: netUi.rise * 22 }
                            Repeater {
                                model: 3
                                Rectangle {
                                    id: tg
                                    required property int index
                                    readonly property bool present: index === 0 ? root.nWifiDev !== "" : index === 1 ? root.nEthDev !== "" : root.nBtPresent
                                    readonly property bool on: index === 0 ? root.nWifiOn : index === 1 ? root.nEthOn : root.nBtOn
                                    readonly property var names: ["Wi-Fi", "Ethernet", "Bluetooth"]
                                    width: ((root.horiz ? root.netCol : root.netW - 32) - 16) / 3; height: 62; radius: 16
                                    color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, tgMa.containsMouse ? 0.28 : 0.2) : (tgMa.containsMouse ? "#181818" : "#101010")
                                    border.width: 1
                                    border.color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5) : "#1e1e1e"
                                    opacity: present ? 1 : 0.35
                                    scale: tgMa.pressed ? 0.95 : 1
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Item {
                                        x: 10; y: 10; width: 22; height: 22
                                        CGlyph {
                                            anchors.centerIn: parent; visible: tg.index !== 1
                                            text: root.g(tg.index === 0 ? (tg.on ? 0xF05A9 : 0xF05AA) : (tg.on ? 0xF00AF : 0xF00B2))
                                            size: 18; color: tg.on ? root.accent : "#8a8a8a"
                                        }
                                        EthLogo { anchors.centerIn: parent; visible: tg.index === 1; size: 17 }
                                    }
                                    // kucuk anahtar
                                    Rectangle {
                                        x: parent.width - width - 10; y: 13
                                        width: 24; height: 14; radius: 7
                                        color: tg.on ? root.accent : "#2a2a2a"
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Rectangle {
                                            width: 10; height: 10; radius: 5
                                            y: 2; x: tg.on ? parent.width - width - 2 : 2
                                            color: tg.on ? "#0b1530" : "#8a8a8a"
                                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                        }
                                    }
                                    NText {
                                        x: 10; y: 38
                                        text: tg.names[tg.index]
                                        font.pixelSize: 10; font.bold: true
                                        color: tg.on ? "#ffffff" : "#bdbdbd"
                                    }
                                    MouseArea {
                                        id: tgMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: tg.present
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: tg.index === 0 ? root.netToggleWifi() : tg.index === 1 ? root.netToggleEth() : root.netToggleBt()
                                    }
                                    // ok: alttaki listeyi bu kutunun listesine cevirir (Wi-Fi aglari / Bluetooth cihazlari)
                                    Rectangle {
                                        id: tgArrow
                                        readonly property string view: tg.index === 0 ? "wifi" : "bt"
                                        readonly property bool active: root.nView === view
                                        visible: tg.index !== 1
                                        enabled: tg.present
                                        x: parent.width - width - 7; y: parent.height - height - 8
                                        width: 18; height: 18; radius: 6
                                        color: "transparent"
                                        scale: arMa.pressed ? 0.88 : (arMa.containsMouse ? 1.1 : 1)
                                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                        CGlyph {
                                            anchors.centerIn: parent
                                            text: root.g(0xF0142); size: 16
                                            color: tgArrow.active ? root.accent : (arMa.containsMouse ? "#ffffff" : "#8a8a8a")
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                            // yatayda liste sagda: ok hep saga bakar, secili olan pywal renkte
                                            rotation: tgArrow.active && !root.horiz ? 90 : 0
                                            Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { id: arMa; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.netShow(tgArrow.view) }
                                    }
                                }
                            }
                        }

                        // ---- aglar ----
                        NText {
                            x: root.horiz ? root.netRx + 2 : 18; y: root.horiz ? 22 : 222
                            text: root.nView === "bt" ? root.t("CİHAZLAR", "DEVICES") : root.t("AĞLAR", "NETWORKS")
                            font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.6; color: "#8a8a8a"
                            opacity: 1 - netUi.rise
                        }
                        NText {
                            anchors.right: parent.right; anchors.rightMargin: root.horiz ? 18 + 26 + 10 : 18; y: root.horiz ? 22 : 222
                            readonly property bool scan: root.nView === "bt" ? root.bScanning : root.nScanning
                            text: scan ? root.t("taranıyor…", "scanning…") : (root.nView === "bt" ? (root.nBtOn && root.bList.length > 0 ? root.bList.length + root.t(" cihaz", " devices") : "")
                                                                                 : (root.nList.length > 0 ? root.nList.length + root.t(" ağ", " networks") : ""))
                            font.pixelSize: 10; color: scan ? root.accent : "#6a6a6a"
                            opacity: 1 - netUi.rise
                        }
                        ListView {
                            id: nListView
                            x: root.horiz ? root.netRx - 6 : 10; y: root.horiz ? 46 : 244
                            width: root.horiz ? root.netW - root.netRx - 4 : root.netW - 20
                            // yatayda mesaj kutusu sol sutunda: liste boydan boya
                            height: parent.height - y - (nMsgBox.visible && !root.horiz ? 50 : 14)
                            Behavior on height { NumberAnimation { duration: 200 } }
                            clip: true
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            property real show: root.nView === "wifi" ? 1 : 0
                            Behavior on show { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            opacity: (1 - netUi.rise) * show
                            visible: show > 0.01
                            transform: Translate { y: netUi.rise * 30; x: (1 - nListView.show) * -24 }
                            model: root.nList.length
                            delegate: Item {
                                id: nr
                                required property int index
                                readonly property var it: root.nList[index] || null
                                readonly property bool asking: it !== null && root.nPass === it.ssid
                                readonly property bool busy: it !== null && root.nBusy === it.ssid
                                width: nListView.width
                                height: asking ? 98 : 50
                                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                // giris: sirayla suzulur
                                opacity: 0
                                property real rs: 10
                                Component.onCompleted: nrIn.start()
                                SequentialAnimation {
                                    id: nrIn
                                    PauseAnimation { duration: Math.min(nr.index, 8) * 35 }
                                    ParallelAnimation {
                                        NumberAnimation { target: nr; property: "opacity"; to: 1; duration: 220 }
                                        NumberAnimation { target: nr; property: "rs"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                    }
                                }
                                transform: Translate { y: nr.rs }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
                                    color: nr.it && nr.it.inUse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
                                         : (nrMa.containsMouse || nr.asking ? "#151515" : "transparent")
                                    border.width: nr.asking ? 1 : 0
                                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                Rectangle {
                                    x: 0; y: 15; width: 3; height: 20; radius: 1.5
                                    color: root.accent
                                    visible: nr.it !== null && nr.it.inUse
                                }
                                Bars {
                                    x: 14; y: 18
                                    sig: nr.it ? nr.it.signal : 0
                                    on: nr.it && nr.it.inUse ? root.accent : "#ededed"
                                }
                                Column {
                                    x: 44; y: 9
                                    width: parent.width - 44 - 64
                                    spacing: 2
                                    NText {
                                        width: parent.width; elide: Text.ElideRight
                                        text: nr.it ? nr.it.ssid : ""
                                        font.pixelSize: 13; font.bold: nr.it !== null && nr.it.inUse
                                        color: nr.it && nr.it.inUse ? root.accent : "#ededed"
                                    }
                                    NText {
                                        text: !nr.it ? "" : nr.busy ? root.t("Bağlanıyor…", "Connecting…") : nr.it.inUse ? root.t("Bağlı", "Connected") : nr.it.known ? root.t("Kayıtlı", "Saved") : (nr.it.secured ? root.t("Şifreli", "Secured") : root.t("Açık ağ", "Open network"))
                                        font.pixelSize: 10
                                        color: nr.busy ? root.accent : "#8a8a8a"
                                    }
                                }
                                // sag: kilit / baglanti kes / unut
                                Row {
                                    anchors.right: parent.right; anchors.rightMargin: 12
                                    y: 15
                                    spacing: 6
                                    CGlyph {
                                        visible: nr.it !== null && nr.it.secured && !nr.it.inUse && !(nrMa.containsMouse && nr.it.known)
                                        text: root.g(0xF033E); size: 13; color: "#6a6a6a"
                                    }
                                    CGlyph {
                                        id: busySpin
                                        visible: nr.busy
                                        text: root.g(0xF0772); size: 14; color: root.accent
                                        RotationAnimation on rotation { running: nr.busy; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                                    }
                                    // kayitliysa: unut (ustune gelince)
                                    Rectangle {
                                        visible: nr.it !== null && nr.it.known && !nr.it.inUse && nrMa.containsMouse && !nr.busy
                                        width: 22; height: 22; radius: 7
                                        color: fgMa.containsMouse ? "#3a1818" : "#1c1c1c"
                                        CGlyph { anchors.centerIn: parent; text: root.g(0xF0A7A); size: 13; color: fgMa.containsMouse ? "#ff6b6b" : "#9a9a9a" }
                                        MouseArea { id: fgMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.netForget(nr.it.ssid) }
                                    }
                                    // bagliysa: baglantiyi kes
                                    Rectangle {
                                        visible: nr.it !== null && nr.it.inUse
                                        width: dcText.implicitWidth + 16; height: 22; radius: 7
                                        color: dcMa.containsMouse ? "#3a1818" : "#1c1c1c"
                                        NText { id: dcText; anchors.centerIn: parent; text: root.t("Kes", "Disconnect"); font.pixelSize: 10; font.bold: true; color: dcMa.containsMouse ? "#ff6b6b" : "#cfcfcf" }
                                        MouseArea { id: dcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.netDisconnect() }
                                    }
                                }
                                MouseArea {
                                    id: nrMa
                                    anchors.fill: parent
                                    z: -1
                                    hoverEnabled: true
                                    cursorShape: nr.it && !nr.it.inUse ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (nr.it && !nr.asking) root.netConnect(nr.it)
                                }
                                // sifre kutusu (sifreli ve kayitli olmayan aga tiklayinca acilir)
                                Rectangle {
                                    x: 12; y: 54
                                    width: parent.width - 24; height: 34; radius: 10
                                    visible: nr.asking
                                    opacity: nr.asking ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                    color: "#0d0d0d"
                                    border.width: 1
                                    border.color: pwIn.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6) : "#262626"
                                    CGlyph { id: pwIc; x: 8; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0306); size: 15; color: root.accent }
                                    TextInput {
                                        id: pwIn
                                        anchors.left: pwIc.right; anchors.leftMargin: 6
                                        anchors.right: pwEye.left; anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "#ffffff"
                                        font.family: root.fontName; font.pixelSize: 12
                                        echoMode: pwEye.show ? TextInput.Normal : TextInput.Password
                                        passwordCharacter: "•"
                                        selectionColor: root.accent
                                        clip: true
                                        onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                        Keys.onReturnPressed: e => { if (text.length > 0) root.netConnect(nr.it, text); e.accepted = true; }
                                        Keys.onEnterPressed: e => { if (text.length > 0) root.netConnect(nr.it, text); e.accepted = true; }
                                        Keys.onEscapePressed: e => { root.nPass = ""; netUi.forceActiveFocus(); e.accepted = true; }
                                        NText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.t("Şifre  ·  Enter ile bağlan", "Password  ·  Enter to connect")
                                            color: "#5a5a5a"; font.pixelSize: 11
                                            visible: pwIn.text.length === 0
                                        }
                                    }
                                    CGlyph {
                                        id: pwEye
                                        property bool show: false
                                        anchors.right: parent.right; anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.g(show ? 0xF0209 : 0xF0208); size: 14
                                        color: eyeMa.containsMouse ? root.accent : "#8a8a8a"
                                        MouseArea { id: eyeMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pwEye.show = !pwEye.show }
                                    }
                                }
                            }
                        }
                        // bos durumlar
                        Column {
                            anchors.horizontalCenter: nListView.horizontalCenter
                            y: nListView.y + 40
                            spacing: 8
                            visible: root.nView === "wifi" && root.nList.length === 0
                            opacity: 1 - netUi.rise
                            CGlyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.g(root.nWifiOn ? 0xF0928 : 0xF092E); size: 30
                                color: "#333333"
                            }
                            NText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: !root.nWifiOn ? root.t("Wi-Fi kapalı", "Wi-Fi off") : (root.nScanning ? root.t("Ağlar aranıyor…", "Searching networks…") : root.t("Ağ bulunamadı", "No networks found"))
                                font.pixelSize: 12; color: "#6a6a6a"
                            }
                        }
                        // ---- bluetooth cihazlari ----
                        ListView {
                            id: bListView
                            x: root.horiz ? root.netRx - 6 : 10; y: root.horiz ? 46 : 244
                            width: root.horiz ? root.netW - root.netRx - 4 : root.netW - 20
                            // yatayda mesaj kutusu sol sutunda: liste boydan boya
                            height: parent.height - y - (nMsgBox.visible && !root.horiz ? 50 : 14)
                            Behavior on height { NumberAnimation { duration: 200 } }
                            clip: true
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            property real show: root.nView === "bt" ? 1 : 0
                            Behavior on show { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            opacity: (1 - netUi.rise) * show
                            visible: show > 0.01
                            transform: Translate { y: netUi.rise * 30; x: (1 - bListView.show) * 24 }
                            model: root.nBtOn ? root.bList.length : 0
                            delegate: Item {
                                id: br
                                required property int index
                                readonly property var d: root.bList[index] || null
                                readonly property bool busy: d !== null && root.bBusy === d.mac
                                width: bListView.width
                                height: 50
                                opacity: 0
                                property real rs: 10
                                Component.onCompleted: brIn.start()
                                SequentialAnimation {
                                    id: brIn
                                    PauseAnimation { duration: Math.min(br.index, 8) * 35 }
                                    ParallelAnimation {
                                        NumberAnimation { target: br; property: "opacity"; to: 1; duration: 220 }
                                        NumberAnimation { target: br; property: "rs"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                    }
                                }
                                transform: Translate { y: br.rs }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
                                    color: br.d && br.d.conn ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : (brMa.containsMouse ? "#151515" : "transparent")
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                Rectangle {
                                    x: 0; y: 15; width: 3; height: 20; radius: 1.5
                                    color: root.accent
                                    visible: br.d !== null && br.d.conn
                                }
                                Rectangle {
                                    x: 10; anchors.verticalCenter: parent.verticalCenter
                                    width: 30; height: 30; radius: 10
                                    color: br.d && br.d.conn ? root.accent : "#1a1a1a"
                                    CGlyph { anchors.centerIn: parent; text: root.g(root.btIcon(br.d ? br.d.icon : "")); size: 16; color: br.d && br.d.conn ? "#0b1530" : "#cfcfcf" }
                                }
                                Column {
                                    x: 50; y: 9
                                    width: parent.width - 50 - 64
                                    spacing: 2
                                    NText {
                                        width: parent.width; elide: Text.ElideRight
                                        text: br.d ? br.d.name : ""
                                        font.pixelSize: 13; font.bold: br.d !== null && br.d.conn
                                        color: br.d && br.d.conn ? root.accent : "#ededed"
                                    }
                                    NText {
                                        text: !br.d ? "" : br.busy ? (br.d.paired ? root.t("Bağlanıyor…", "Connecting…") : root.t("Eşleştiriliyor…", "Pairing…"))
                                             : br.d.conn ? (root.t("Bağlı", "Connected") + (br.d.bat >= 0 ? " · " + root.t("%" + br.d.bat, br.d.bat + "%") : "")) : br.d.paired ? root.t("Eşleşmiş", "Paired") : root.t("Yeni cihaz", "New device")
                                        font.pixelSize: 10
                                        color: br.busy ? root.accent : "#8a8a8a"
                                    }
                                }
                                Row {
                                    anchors.right: parent.right; anchors.rightMargin: 12
                                    y: 14
                                    spacing: 6
                                    CGlyph {
                                        visible: br.busy
                                        text: root.g(0xF0772); size: 14; color: root.accent
                                        RotationAnimation on rotation { running: br.busy; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                                    }
                                    Rectangle {
                                        visible: br.d !== null && br.d.paired && !br.d.conn && brMa.containsMouse && !br.busy
                                        width: 22; height: 22; radius: 7
                                        color: bfMa.containsMouse ? "#3a1818" : "#1c1c1c"
                                        CGlyph { anchors.centerIn: parent; text: root.g(0xF0A7A); size: 13; color: bfMa.containsMouse ? "#ff6b6b" : "#9a9a9a" }
                                        MouseArea { id: bfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.btForget(br.d) }
                                    }
                                    Rectangle {
                                        visible: br.d !== null && br.d.conn
                                        width: bdText.implicitWidth + 16; height: 22; radius: 7
                                        color: bdMa.containsMouse ? "#3a1818" : "#1c1c1c"
                                        NText { id: bdText; anchors.centerIn: parent; text: root.t("Kes", "Disconnect"); font.pixelSize: 10; font.bold: true; color: bdMa.containsMouse ? "#ff6b6b" : "#cfcfcf" }
                                        MouseArea { id: bdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.btDisconnect(br.d) }
                                    }
                                }
                                MouseArea {
                                    id: brMa
                                    anchors.fill: parent
                                    z: -1
                                    hoverEnabled: true
                                    cursorShape: br.d && !br.d.conn ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.btConnect(br.d)
                                }
                            }
                        }
                        Column {
                            anchors.horizontalCenter: bListView.horizontalCenter
                            y: bListView.y + 40
                            spacing: 8
                            visible: root.nView === "bt" && (!root.nBtOn || root.bList.length === 0)
                            opacity: 1 - netUi.rise
                            CGlyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.g(root.nBtOn ? 0xF00AF : 0xF00B2); size: 30
                                color: "#333333"
                            }
                            NText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: !root.nBtOn ? root.t("Bluetooth kapalı", "Bluetooth off") : (root.bScanning ? root.t("Cihazlar aranıyor…", "Searching devices…") : root.t("Cihaz bulunamadı", "No devices found"))
                                font.pixelSize: 12; color: "#6a6a6a"
                            }
                        }

                        // alt: kisa bildirim (baglandi / sifre yanlis)
                        Rectangle {
                            id: nMsgBox
                            x: 16; width: root.horiz ? root.netCol : root.netW - 32; height: 34; radius: 12
                            y: parent.height - height - (root.horiz ? 16 : 12)
                            visible: root.nMsg !== ""
                            color: root.nMsgBad ? "#2a1414" : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                            border.width: 1; border.color: root.nMsgBad ? "#4a1f1f" : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
                            NText {
                                anchors.centerIn: parent
                                width: parent.width - 20; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                                text: root.nMsg
                                font.pixelSize: 11; color: root.nMsgBad ? "#ff8a8a" : "#e6e6e6"
                            }
                        }
                    }
                }
                // ================= BILDIRIM MODU: zile tiklayinca dock bildirim paneline donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: root.dmode === "notif" || notifUi.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "notif" }
                    FocusScope {
                        id: notifUi
                        width: root.notifW
                        height: dock.height
                        focus: root.dmode === "notif"
                        opacity: root.dmode === "notif" && dock.width > root.notifW - 30 ? 1 : 0
                        enabled: root.dmode === "notif"
                        Behavior on opacity { NumberAnimation { duration: root.dmode === "notif" ? 220 : 90; easing.type: Easing.OutCubic } }
                        transform: Translate { x: root.dmode === "notif" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        Keys.onEscapePressed: root.closeMode()
                        Timer { id: notifFocus; interval: 80; onTriggered: notifUi.forceActiveFocus() }
                        Connections { target: root; function onDmodeChanged() { if (root.dmode === "notif") { notifFocus.restart(); notifIn.restart(); nFlick.contentY = 0; } } }
                        property real rise: 0
                        SequentialAnimation {
                            id: notifIn
                            PropertyAction { target: notifUi; property: "rise"; value: 1 }
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: notifUi; property: "rise"; to: 0; duration: 520; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
                                GradientStop { position: 0.30; color: "transparent" }
                            }
                        }

                        // kucuk ikon dugmesi (baslikta)
                        component NIconBtn: Item {
                            id: nib
                            property int icon: 0
                            property bool on: false
                            property bool danger: false
                            signal clicked()
                            width: 30; height: 30
                            Rectangle {
                                anchors.fill: parent; radius: 10
                                color: nib.on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : (nibMa.containsMouse ? (nib.danger ? "#2a1414" : "#1a1a1a") : "transparent")
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            CGlyph {
                                anchors.centerIn: parent
                                text: root.g(nib.icon); size: 18
                                color: nib.on ? root.accent : (nibMa.containsMouse ? (nib.danger ? "#ff6b6b" : "#ffffff") : "#bdbdbd")
                                scale: nibMa.pressed ? 0.85 : 1
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            MouseArea { id: nibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nib.clicked() }
                        }

                        // ---- baslik ----
                        Item {
                            x: 8; y: 16
                            width: 26; height: 26
                            z: 5
                            opacity: 1 - notifUi.rise
                            CGlyph {
                                anchors.centerIn: parent
                                size: 20
                                text: root.g(root.horiz ? 0xF0140 : 0xF0141)
                                color: notifBackMa.containsMouse ? root.accent : "#e6e6e6"
                                scale: notifBackMa.pressed ? 0.85 : (notifBackMa.containsMouse ? 1.12 : 1)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            MouseArea { id: notifBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeMode() }
                        }
                        Row {
                            x: 40; y: 18; spacing: 8
                            opacity: 1 - notifUi.rise
                            NText { text: root.t("Bildirimler", "Notifications"); font.pixelSize: 16; font.bold: true; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.nItems.length > 0
                                width: Math.max(20, ncnt.implicitWidth + 10); height: 18; radius: 9
                                color: root.accent
                                NText { id: ncnt; anchors.centerIn: parent; text: root.nItems.length; font.pixelSize: 10; font.bold: true; color: "#0b1530" }
                            }
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            y: 14; spacing: 4
                            opacity: 1 - notifUi.rise
                            NIconBtn { icon: root.dnd ? 0xF00A0 : 0xF009C; on: root.dnd; onClicked: root.nToggleDnd() }
                            NIconBtn { icon: 0xF039F; danger: true; visible: root.nItems.length > 0; onClicked: root.nClear() }
                        }

                        // ---- rahatsiz etme seridi ----
                        Rectangle {
                            id: dndBar
                            x: 16; y: 56
                            width: root.notifW - 32
                            height: root.dnd ? 38 : 0
                            radius: 12
                            clip: true
                            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.13)
                            border.width: root.dnd ? 1 : 0
                            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                            opacity: root.dnd ? (1 - notifUi.rise) : 0
                            Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Row {
                                x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0F65); size: 15; color: root.accent }
                                NText { anchors.verticalCenter: parent.verticalCenter; text: root.t("Rahatsız etme açık", "Do not disturb on"); font.pixelSize: 11; font.bold: true; color: "#e6e6e6" }
                            }
                            NText {
                                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                text: root.t("Kapat", "Turn off"); font.pixelSize: 10; font.bold: true
                                color: dndOffMa.containsMouse ? root.accent : "#9a9a9a"
                                MouseArea { id: dndOffMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.nToggleDnd() }
                            }
                        }

                        // ---- liste: uygulamaya gore gruplu ----
                        Flickable {
                            id: nFlick
                            x: 10; y: dndBar.y + dndBar.height + (root.dnd ? 10 : 0)
                            width: root.notifW - 20
                            height: parent.height - y - 12
                            contentHeight: nCol.implicitHeight + 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            opacity: 1 - notifUi.rise
                            transform: Translate { y: notifUi.rise * 26 }
                            // yatayda uygulama gruplari iki sutun halinde
                            Grid {
                                id: nCol
                                width: parent.width
                                columns: root.horiz ? 2 : 1
                                spacing: 12
                                Repeater {
                                    model: root.nGroups.length
                                    Column {
                                        id: grp
                                        required property int index
                                        readonly property var gd: root.nGroups[index] || ({ app: "", icon: "", items: [] })
                                        readonly property bool open: root.nGroupOpen[gd.app] === true
                                        readonly property int shownN: open ? gd.items.length : Math.min(2, gd.items.length)
                                        width: root.horiz ? Math.floor((nCol.width - 12) / 2) : nCol.width
                                        spacing: 6
                                        // giris
                                        opacity: 0
                                        property real rs: 12
                                        transform: Translate { y: grp.rs }
                                        Component.onCompleted: grpIn.start()
                                        SequentialAnimation {
                                            id: grpIn
                                            PauseAnimation { duration: Math.min(grp.index, 6) * 50 }
                                            ParallelAnimation {
                                                NumberAnimation { target: grp; property: "opacity"; to: 1; duration: 220 }
                                                NumberAnimation { target: grp; property: "rs"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                            }
                                        }
                                        // grup basligi
                                        Item {
                                            width: parent.width; height: 24
                                            HoverHandler { id: ghHH }
                                            Rectangle {
                                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                                width: 20; height: 20; radius: 6
                                                color: "#161616"
                                                IconImage {
                                                    id: gIcon
                                                    anchors.centerIn: parent
                                                    implicitSize: 16
                                                    source: grp.gd.icon
                                                    visible: grp.gd.icon !== "" && status !== Image.Error
                                                }
                                                CGlyph { anchors.centerIn: parent; visible: !gIcon.visible; text: root.g(0xF009A); size: 12; color: root.accent }
                                            }
                                            NText {
                                                x: 34; anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 34 - 90; elide: Text.ElideRight
                                                text: grp.gd.app + (grp.gd.items.length > 1 ? "  ·  " + grp.gd.items.length : "")
                                                font.pixelSize: 11; font.bold: true; color: "#cfcfcf"
                                            }
                                            NText {
                                                anchors.right: parent.right; anchors.rightMargin: 34
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: grp.gd.items.length ? root.nAgo(grp.gd.items[0].time) : ""
                                                font.pixelSize: 10; color: "#6a6a6a"
                                            }
                                            // uygulamanin hepsini sil
                                            Rectangle {
                                                anchors.right: parent.right; anchors.rightMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 22; height: 22; radius: 7
                                                opacity: ghHH.hovered ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                                color: gxMa.containsMouse ? "#2a1414" : "#161616"
                                                CGlyph { anchors.centerIn: parent; text: root.g(0xF0156); size: 13; color: gxMa.containsMouse ? "#ff6b6b" : "#9a9a9a" }
                                                MouseArea { id: gxMa; anchors.fill: parent; enabled: parent.opacity > 0.5; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.nDismissApp(grp.gd.app) }
                                            }
                                        }
                                        // kartlar
                                        Repeater {
                                            model: grp.shownN
                                            Item {
                                                id: nc
                                                required property int index
                                                readonly property var n: grp.gd.items[index] || null
                                                readonly property string body: n ? root.nPlain(n.body) : ""
                                                readonly property bool hasImg: n !== null && (n.image || "") !== ""
                                                width: grp.width
                                                height: Math.max(hasImg ? 64 : 0, ncText.implicitHeight + 24)
                                                HoverHandler { id: ncHH }
                                                // saga surukleyince silinir
                                                property real dx: 0
                                                Behavior on dx { enabled: !ncDrag.active; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                                DragHandler {
                                                    id: ncDrag
                                                    target: null
                                                    xAxis.enabled: true; yAxis.enabled: false
                                                    onTranslationChanged: nc.dx = Math.max(0, translation.x)
                                                    onActiveChanged: {
                                                        if (active) return;
                                                        if (nc.dx > 90 && nc.n) { nc.dx = nc.width; ncGone.restart(); }
                                                        else nc.dx = 0;
                                                    }
                                                }
                                                Timer { id: ncGone; interval: 200; onTriggered: if (nc.n) root.nDismiss(nc.n.id) }
                                                TapHandler { onTapped: root.nInvoke(nc.n) }
                                                Rectangle {
                                                    id: ncCard
                                                    x: nc.dx
                                                    width: parent.width; height: parent.height
                                                    radius: 14
                                                    opacity: 1 - Math.min(1, nc.dx / (nc.width * 0.8))
                                                    color: ncHH.hovered ? "#141414" : "#0f0f0f"
                                                    border.width: 1
                                                    border.color: ncHH.hovered ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35) : "#1c1c1c"
                                                    Behavior on color { ColorAnimation { duration: 140 } }
                                                    Behavior on border.color { ColorAnimation { duration: 140 } }
                                                    ClippingRectangle {
                                                        id: ncImg
                                                        visible: nc.hasImg
                                                        x: 12; y: 12
                                                        width: 40; height: 40; radius: 10
                                                        color: "#1a1a1a"
                                                        Image {
                                                            anchors.fill: parent
                                                            source: nc.hasImg ? (nc.n.image.startsWith("/") ? "file://" + nc.n.image : nc.n.image) : ""
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            sourceSize: Qt.size(80, 80)
                                                        }
                                                    }
                                                    Column {
                                                        id: ncText
                                                        x: nc.hasImg ? 62 : 14
                                                        y: 11
                                                        width: parent.width - x - 14
                                                        spacing: 3
                                                        Item {
                                                            width: parent.width; height: ncSum.implicitHeight
                                                            NText {
                                                                id: ncSum
                                                                width: parent.width - 44
                                                                elide: Text.ElideRight
                                                                text: nc.n ? (nc.n.summary || nc.n.app) : ""
                                                                font.pixelSize: 12; font.bold: true; color: "#f0f0f0"
                                                            }
                                                            // sag ust: zaman, ustune gelince kapat dugmesi
                                                            NText {
                                                                anchors.right: parent.right
                                                                visible: !ncHH.hovered
                                                                text: nc.n && grp.gd.items.length > 1 ? root.nAgo(nc.n.time) : ""
                                                                font.pixelSize: 9; color: "#5a5a5a"
                                                            }
                                                            Rectangle {
                                                                anchors.right: parent.right; anchors.rightMargin: -4
                                                                y: -3
                                                                width: 20; height: 20; radius: 7
                                                                visible: ncHH.hovered
                                                                color: ncxMa.containsMouse ? "#2a1414" : "#1c1c1c"
                                                                CGlyph { anchors.centerIn: parent; text: root.g(0xF0156); size: 12; color: ncxMa.containsMouse ? "#ff6b6b" : "#bdbdbd" }
                                                                MouseArea { id: ncxMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (nc.n) root.nDismiss(nc.n.id) }
                                                            }
                                                        }
                                                        NText {
                                                            width: parent.width
                                                            visible: nc.body !== ""
                                                            text: nc.body
                                                            wrapMode: Text.Wrap
                                                            maximumLineCount: 3
                                                            elide: Text.ElideRight
                                                            font.pixelSize: 11; color: "#a8a8a8"
                                                            lineHeight: 1.1
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        // daha fazla / daralt
                                        Item {
                                            visible: grp.gd.items.length > 2
                                            width: parent.width; height: 22
                                            Row {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 4
                                                NText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: grp.open ? root.t("Daralt", "Collapse") : ((grp.gd.items.length - 2) + root.t(" tane daha", " more"))
                                                    font.pixelSize: 10; font.bold: true
                                                    color: moreMa.containsMouse ? root.accent : "#8a8a8a"
                                                }
                                                CGlyph {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root.g(0xF0140); size: 13
                                                    color: moreMa.containsMouse ? root.accent : "#8a8a8a"
                                                    rotation: grp.open ? 180 : 0
                                                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                                }
                                            }
                                            MouseArea { id: moreMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.nToggleGroup(grp.gd.app) }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- bos: Bip-chan uyuyor ----
                        Item {
                            id: nEmpty
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: nFlick.y + Math.max(40, (nFlick.height - height) / 2 - 30)
                            width: 160; height: 110
                            visible: root.nItems.length === 0
                            opacity: 1 - notifUi.rise
                            readonly property var rows: [
                                "....#....",
                                ".#######.",
                                ".#######.",
                                "##.###.##",
                                ".#######.",
                                ".##...##.",
                                ".#######.",
                                "..#...#.."
                            ]
                            Item {
                                id: sleepBot
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 14
                                width: 36; height: 32
                                property real breathe: 0
                                SequentialAnimation on breathe {
                                    running: nEmpty.visible && root.dmode === "notif"; loops: Animation.Infinite
                                    NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0; duration: 1400; easing.type: Easing.InOutSine }
                                }
                                transform: Translate { y: sleepBot.breathe * 2 }
                                Repeater {
                                    model: 72
                                    Rectangle {
                                        required property int index
                                        readonly property int cx: index % 9
                                        readonly property int cy: Math.floor(index / 9)
                                        visible: nEmpty.rows[cy].charAt(cx) === "#"
                                        x: cx * 4; y: cy * 4; width: 4; height: 4
                                        color: "#e07a4f"
                                    }
                                }
                            }
                            // yukari suzulen z'ler
                            Repeater {
                                model: 3
                                NText {
                                    id: zz
                                    required property int index
                                    text: "z"
                                    font.pixelSize: 10 + index * 3; font.bold: true
                                    color: "#e07a4f"
                                    x: 104 + index * 7
                                    property real t: 0
                                    y: 18 - t * 22 - index * 6
                                    opacity: Math.sin(t * Math.PI)
                                    SequentialAnimation on t {
                                        running: nEmpty.visible && root.dmode === "notif"; loops: Animation.Infinite
                                        PauseAnimation { duration: zz.index * 600 }
                                        NumberAnimation { from: 0; to: 1; duration: 1800; easing.type: Easing.OutSine }
                                        PauseAnimation { duration: (2 - zz.index) * 600 }
                                    }
                                }
                            }
                            NText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 62
                                text: root.t("Bildirim yok", "No notifications")
                                font.pixelSize: 13; font.bold: true; color: "#cfcfcf"
                            }
                            NText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 82
                                text: root.dnd ? root.t("Rahatsız etme açık, Bip-chan uyuyor", "Do not disturb is on, Bip-chan is sleeping") : root.t("Her şey sakin", "All quiet")
                                font.pixelSize: 10; color: "#6a6a6a"
                            }
                        }
                    }
                }
                // ================= BILDIRIM KUTUSU: yeni bildirim gelince dock kisa sureligine buna donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: root.toastMode || toastUi.opacity > 0.01
                    Item {
                        id: toastUi
                        width: root.toastW
                        height: root.toastH
                        // kapanirken kutu icerigiyle birlikte kayip gitsin (bos kutu kalmasin)
                        opacity: (root.toastMode || (root.toastClosing && root.wallShape)) && dock.width > root.toastW - 40 ? 1 : 0
                        enabled: root.toastMode
                        Behavior on opacity { NumberAnimation { duration: root.toastMode ? 200 : 90; easing.type: Easing.OutCubic } }
                        transform: Translate { x: root.toastMode || root.toastClosing ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        readonly property var n: root.tN
                        readonly property string body: n ? root.nPlain(n.body) : ""
                        readonly property bool hasImg: n !== null && (n.image || "") !== ""
                        HoverHandler { id: toastHH }
                        // kalan sure (5 sn); ustune gelince durur
                        property real prog: 1
                        NumberAnimation {
                            id: toastRun
                            target: toastUi; property: "prog"
                            from: 1; to: 0; duration: 5200
                            paused: running && toastHH.hovered
                            onFinished: root.toastClose()
                        }
                        // yeni bildirimde ayni kutu kucuk bir ziplama yapar
                        property real bump: 0
                        SequentialAnimation {
                            id: toastBump
                            NumberAnimation { target: toastUi; property: "bump"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
                            NumberAnimation { target: toastUi; property: "bump"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2 }
                        }
                        Connections {
                            target: root
                            function onToastKick() { toastRun.restart(); toastBump.restart(); }
                        }

                        TapHandler { onTapped: { const n = root.tN; root.toastClose(); root.nInvoke(n); } }

                        // ust kisimda hafif pywal isigi
                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
                                GradientStop { position: 0.6; color: "transparent" }
                            }
                        }
                        Item {
                            x: 16; y: 14
                            width: parent.width - 32; height: parent.height - 24
                            scale: 1 + toastUi.bump * 0.03
                            // uygulama ikonu ya da resim
                            Rectangle {
                                id: tIco
                                width: 44; height: 44; radius: 13
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -4
                                color: "#141414"
                                border.width: 1; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                                ClippingRectangle {
                                    anchors.fill: parent; anchors.margins: 1
                                    radius: 12
                                    color: "transparent"
                                    visible: toastUi.hasImg
                                    Image {
                                        anchors.fill: parent
                                        source: toastUi.hasImg ? (toastUi.n.image.startsWith("/") ? "file://" + toastUi.n.image : toastUi.n.image) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize: Qt.size(88, 88)
                                    }
                                }
                                IconImage {
                                    id: tAppIc
                                    anchors.centerIn: parent
                                    implicitSize: 26
                                    source: toastUi.n ? (toastUi.n.icon || "") : ""
                                    visible: !toastUi.hasImg && toastUi.n !== null && (toastUi.n.icon || "") !== "" && status !== Image.Error
                                }
                                CGlyph { anchors.centerIn: parent; visible: !toastUi.hasImg && !tAppIc.visible; text: root.g(0xF009A); size: 22; color: root.accent }
                                // resim varsa sag altta kucuk uygulama ikonu
                                Rectangle {
                                    visible: toastUi.hasImg && toastUi.n && (toastUi.n.icon || "") !== ""
                                    x: parent.width - 14; y: parent.height - 14
                                    width: 20; height: 20; radius: 7
                                    color: "#000000"
                                    IconImage { anchors.centerIn: parent; implicitSize: 14; source: toastUi.n ? (toastUi.n.icon || "") : "" }
                                }
                            }
                            Column {
                                x: 58
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -4
                                width: parent.width - 58
                                spacing: 3
                                Item {
                                    width: parent.width; height: tApp.implicitHeight
                                    NText {
                                        id: tApp
                                        width: parent.width - 30; elide: Text.ElideRight
                                        text: toastUi.n ? toastUi.n.app + root.t("  ·  şimdi", "  ·  now") : ""
                                        font.pixelSize: 10; color: root.accent; font.bold: true
                                    }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.rightMargin: -6
                                        y: -5
                                        width: 22; height: 22; radius: 7
                                        opacity: toastHH.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                        color: txMa.containsMouse ? "#2a1414" : "#1a1a1a"
                                        CGlyph { anchors.centerIn: parent; text: root.g(0xF0156); size: 13; color: txMa.containsMouse ? "#ff6b6b" : "#bdbdbd" }
                                        MouseArea {
                                            id: txMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { const n = root.tN; root.toastClose(); if (n) root.nDismiss(n.id); }
                                        }
                                    }
                                }
                                NText {
                                    width: parent.width; elide: Text.ElideRight
                                    text: toastUi.n ? (toastUi.n.summary || toastUi.n.app) : ""
                                    font.pixelSize: 13; font.bold: true; color: "#ffffff"
                                }
                                NText {
                                    width: parent.width
                                    visible: toastUi.body !== ""
                                    text: toastUi.body
                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                    font.pixelSize: 11; color: "#b0b0b0"
                                }
                            }
                        }
                        // alt: kalan sure cizgisi
                        Rectangle {
                            x: 16; y: parent.height - 9
                            width: parent.width - 32; height: 3; radius: 1.5
                            color: "#1e1e1e"
                            Rectangle {
                                width: parent.width * toastUi.prog; height: 3; radius: 1.5
                                color: root.accent
                                opacity: toastHH.hovered ? 0.5 : 1
                            }
                        }
                    }
                }
                // ================= BATARYA MODU: pile tiklayinca dock batarya paneline donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: root.dmode === "bat" || batUi.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "bat" }
                    FocusScope {
                        id: batUi
                        width: root.batW
                        height: root.batH
                        focus: root.dmode === "bat"
                        opacity: root.dmode === "bat" && dock.width > root.batW - 30 ? 1 : 0
                        enabled: root.dmode === "bat"
                        Behavior on opacity { NumberAnimation { duration: root.dmode === "bat" ? 220 : 90; easing.type: Easing.OutCubic } }
                        transform: Translate { x: root.dmode === "bat" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        Keys.onEscapePressed: root.closeMode()
                        Keys.onLeftPressed: if (root.bProfIdx > 0) root.setBatProfile(root.bProfIdx - 1)
                        Keys.onRightPressed: if (root.bProfIdx < 2) root.setBatProfile(root.bProfIdx + 1)
                        Timer { id: batFocus; interval: 80; onTriggered: batUi.forceActiveFocus() }
                        Connections { target: root; function onDmodeChanged() { if (root.dmode === "bat") { batFocus.restart(); batIn.restart(); } } }
                        property real rise: 0
                        SequentialAnimation {
                            id: batIn
                            PropertyAction { target: batUi; property: "rise"; value: 1 }
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: batUi; property: "rise"; to: 0; duration: 520; easing.type: Easing.OutCubic }
                        }
                        readonly property real cap: Math.max(0, root.bCap) / 100
                        readonly property bool low: root.bCap >= 0 && root.bCap < 20 && !root.bCharging
                        readonly property color fillCol: low ? "#ff5a5a" : root.accent

                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
                                GradientStop { position: 0.30; color: "transparent" }
                            }
                        }

                        // ---- baslik ----
                        Item {
                            x: 8; y: 16
                            width: 26; height: 26
                            z: 5
                            opacity: 1 - batUi.rise
                            CGlyph {
                                anchors.centerIn: parent
                                size: 20
                                text: root.g(root.horiz ? 0xF0140 : 0xF0141)
                                color: batBackMa.containsMouse ? root.accent : "#e6e6e6"
                                scale: batBackMa.pressed ? 0.85 : (batBackMa.containsMouse ? 1.12 : 1)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            MouseArea { id: batBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeMode() }
                        }
                        NText { x: 40; y: 18; text: root.t("Batarya", "Battery"); font.pixelSize: 16; font.bold: true; color: "#ffffff"; opacity: 1 - batUi.rise }
                        // sag ust: fis durumu
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 16
                            y: 18
                            height: 22; radius: 11
                            width: plugRow.implicitWidth + 16
                            opacity: 1 - batUi.rise
                            color: root.bAc === 1 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : "#141414"
                            border.width: 1
                            border.color: root.bAc === 1 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : "#222222"
                            Row {
                                id: plugRow
                                anchors.centerIn: parent
                                spacing: 4
                                CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(root.bAc === 1 ? 0xF06A5 : 0xF0079); size: 12; color: root.bAc === 1 ? root.accent : "#9a9a9a" }
                                NText { anchors.verticalCenter: parent.verticalCenter; text: root.bAc === 1 ? root.t("Fişte", "Plugged in") : root.t("Pilde", "On battery"); font.pixelSize: 10; font.bold: true; color: root.bAc === 1 ? root.accent : "#9a9a9a" }
                            }
                        }

                        // ---- kahraman: sivi dolu pil + yuzde ----
                        Item {
                            x: 16; y: 58
                            width: root.horiz ? root.batCol : root.batW - 32; height: 112
                            opacity: 1 - batUi.rise
                            transform: Translate { y: batUi.rise * 16 }
                            // pil govdesi
                            Item {
                                id: bigBat
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                width: 124; height: 62
                                Rectangle {
                                    id: batShell
                                    width: 116; height: 62; radius: 16
                                    color: "#0d0d0d"
                                    border.width: 2.5
                                    border.color: "#3a3a3a"
                                    // sivi: kapasite kadar dolu, ust kenari dalgali (sarjdayken dalga hareketli)
                                    ClippingRectangle {
                                        x: 5; y: 5
                                        width: parent.width - 10; height: parent.height - 10
                                        radius: 11
                                        color: "transparent"
                                        Canvas {
                                            id: liquid
                                            anchors.fill: parent
                                            property real phase: 0
                                            property real level: batUi.cap
                                            Behavior on level { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                                            onLevelChanged: requestPaint()
                                            onPhaseChanged: requestPaint()
                                            Connections { target: batUi; function onFillColChanged() { liquid.requestPaint(); } }
                                            NumberAnimation on phase {
                                                running: root.dmode === "bat"; loops: Animation.Infinite
                                                from: 0; to: Math.PI * 2; duration: root.bCharging ? 1400 : 3600
                                            }
                                            onPaint: {
                                                const c = getContext("2d"); c.reset();
                                                const w = width, h = height;
                                                const fx = w * Math.max(0.03, level);
                                                const amp = root.bCharging ? 3.2 : 1.4;
                                                // sivinin sag kenari dikey dalga
                                                c.beginPath();
                                                c.moveTo(0, 0);
                                                for (let y = 0; y <= h; y += 2) {
                                                    const x = fx + Math.sin(y / h * Math.PI * 2 + phase) * amp;
                                                    c.lineTo(Math.min(w, x), y);
                                                }
                                                c.lineTo(0, h); c.closePath();
                                                const fc = batUi.fillCol;
                                                const g = c.createLinearGradient(0, 0, w, 0);
                                                g.addColorStop(0, Qt.rgba(fc.r, fc.g, fc.b, 0.55));
                                                g.addColorStop(1, Qt.rgba(fc.r, fc.g, fc.b, 1));
                                                c.fillStyle = g; c.fill();
                                            }
                                        }
                                        // kabarciklar (sarjdayken)
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                id: bub
                                                required property int index
                                                width: 4 + (index % 2) * 2; height: width; radius: width / 2
                                                color: "#ffffff"
                                                visible: root.bCharging
                                                property real t: 0
                                                x: Math.max(4, liquid.width * batUi.cap * (0.2 + index * 0.18))
                                                y: liquid.height - t * (liquid.height + 6)
                                                opacity: 0.35 * (1 - t)
                                                NumberAnimation on t {
                                                    running: root.bCharging && root.dmode === "bat"; loops: Animation.Infinite
                                                    from: 0; to: 1; duration: 1500 + bub.index * 380
                                                }
                                            }
                                        }
                                    }
                                    // simsek
                                    CGlyph {
                                        anchors.centerIn: parent
                                        visible: root.bCharging
                                        text: root.g(0xF140B); size: 26
                                        color: "#ffffff"
                                        SequentialAnimation on scale {
                                            running: root.bCharging && root.dmode === "bat"; loops: Animation.Infinite
                                            NumberAnimation { from: 1; to: 1.12; duration: 700; easing.type: Easing.InOutSine }
                                            NumberAnimation { from: 1.12; to: 1; duration: 700; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }
                                Rectangle {
                                    x: batShell.width + 2; anchors.verticalCenter: batShell.verticalCenter
                                    width: 6; height: 22; radius: 3
                                    color: "#3a3a3a"
                                }
                            }
                            Column {
                                x: bigBat.x + bigBat.width + 22
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Row {
                                    spacing: 2
                                    NText {
                                        text: root.bCap >= 0 ? root.bCap : "—"
                                        font.pixelSize: 40; font.bold: true; color: "#ffffff"
                                    }
                                    NText {
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                                        text: "%"; font.pixelSize: 16; font.bold: true; color: "#8a8a8a"
                                    }
                                }
                                NText {
                                    text: root.bTimeText
                                    font.pixelSize: 12; font.bold: true
                                    color: batUi.low ? "#ff8a8a" : root.accent
                                }
                            }
                        }

                        // ---- uc kucuk deger ----
                        Row {
                            x: 16; y: 182; spacing: 8
                            opacity: 1 - batUi.rise
                            transform: Translate { y: batUi.rise * 22 }
                            Repeater {
                                model: 3
                                Rectangle {
                                    id: st
                                    required property int index
                                    readonly property var icons: [0xF0241, 0xF05F6, 0xF050F]
                                    readonly property var names: [root.t("Güç", "Power"), root.t("Sağlık", "Health"), root.t("Sıcaklık", "Temp")]
                                    readonly property string val: index === 0 ? root.bWatt.toFixed(1) + " W"
                                                                 : index === 1 ? root.bHealth + "%"
                                                                 : (root.bTemp > 0 ? root.bTemp + "°C" : "—")
                                    readonly property bool warn: (index === 1 && root.bHealth > 0 && root.bHealth < 70) || (index === 2 && root.bTemp >= 45)
                                    width: ((root.horiz ? root.batCol : root.batW - 32) - 16) / 3; height: 64; radius: 16
                                    color: "#101010"
                                    border.width: 1; border.color: "#1e1e1e"
                                    CGlyph { x: 10; y: 10; text: root.g(st.icons[st.index]); size: 15; color: st.warn ? "#ff8a8a" : root.accent }
                                    NText { x: 12; y: 30; text: st.val; font.pixelSize: 15; font.bold: true; color: st.warn ? "#ff8a8a" : "#ffffff" }
                                    NText { anchors.right: parent.right; anchors.rightMargin: 10; y: 12; text: st.names[st.index]; font.pixelSize: 9; color: "#8a8a8a" }
                                }
                            }
                        }

                        // ---- guc profili: kayan secici ----
                        NText {
                            x: root.horiz ? root.batRx + 2 : 18; y: root.horiz ? 58 : 262
                            text: root.t("GÜÇ PROFİLİ", "POWER PROFILE")
                            font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.6; color: "#8a8a8a"
                            opacity: 1 - batUi.rise
                        }
                        Rectangle {
                            id: profBox
                            x: root.horiz ? root.batRx : 16; y: root.horiz ? 80 : 284
                            width: root.horiz ? root.batCol : root.batW - 32; height: 52; radius: 16
                            color: "#0f0f0f"
                            border.width: 1; border.color: "#1e1e1e"
                            opacity: 1 - batUi.rise
                            transform: Translate { y: batUi.rise * 28 }
                            readonly property real seg: (width - 8) / 3
                            Rectangle {
                                x: 4 + root.bProfIdx * profBox.seg
                                y: 4
                                width: profBox.seg; height: parent.height - 8; radius: 12
                                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                                border.width: 1.5; border.color: root.accent
                                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                            }
                            Repeater {
                                model: 3
                                Item {
                                    id: pf
                                    required property int index
                                    readonly property var icons: [0xF032A, 0xF05D1, 0xF14DE]
                                    readonly property var names: [root.t("Tasarruf", "Saver"), root.t("Denge", "Balanced"), root.t("Performans", "Performance")]
                                    readonly property bool on: root.bProfIdx === index
                                    x: 4 + index * profBox.seg; y: 4
                                    width: profBox.seg; height: profBox.height - 8
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        CGlyph {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.g(pf.icons[pf.index]); size: 15
                                            color: pf.on ? root.accent : (pfMa.containsMouse ? "#ffffff" : "#8a8a8a")
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                        NText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: pf.names[pf.index]; font.pixelSize: 11; font.bold: pf.on
                                            color: pf.on ? "#ffffff" : (pfMa.containsMouse ? "#e6e6e6" : "#9a9a9a")
                                        }
                                    }
                                    MouseArea { id: pfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setBatProfile(pf.index) }
                                }
                            }
                        }

                        // ---- grafik modu (sadece gosterir) ----
                        Rectangle {
                            x: 16; y: root.horiz ? 258 : 346
                            width: root.horiz ? root.batCol : root.batW - 32; height: 44; radius: 14
                            color: "#101010"
                            border.width: 1; border.color: "#1e1e1e"
                            opacity: 1 - batUi.rise
                            transform: Translate { y: batUi.rise * 32 }
                            Row {
                                x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 26; height: 26; radius: 8; color: "#76b900"
                                    CGlyph { anchors.centerIn: parent; text: root.g(0xF08AE); size: 14; color: "#0b1a00" }
                                }
                                NText { anchors.verticalCenter: parent.verticalCenter; text: root.t("Grafik modu", "Graphics mode"); font.pixelSize: 12; color: "#cfcfcf" }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                height: 24; radius: 8
                                width: gfxT.implicitWidth + 18
                                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                                NText { id: gfxT; anchors.centerIn: parent; text: root.bGfx === "Hibrit" ? root.t("Hibrit", "Hybrid") : root.bGfx; font.pixelSize: 11; font.bold: true; color: root.accent }
                            }
                        }

                        // ---- en cok tuketen ----
                        Rectangle {
                            id: batApps
                            x: root.horiz ? root.batRx : 16; y: root.horiz ? 144 : 402
                            width: root.horiz ? root.batCol : root.batW - 32; height: root.horiz ? 158 : 140; radius: 16
                            color: "#101010"
                            border.width: 1; border.color: "#1e1e1e"
                            opacity: 1 - batUi.rise
                            transform: Translate { y: batUi.rise * 38 }
                            NText { x: 14; y: 12; text: root.t("En çok tüketen", "Top consumers"); font.pixelSize: 13; font.bold: true; color: "#f0f0f0" }
                            NText {
                                anchors.right: parent.right; anchors.rightMargin: 14; y: 14
                                text: root.t("toplam ", "total ") + root.bWatt.toFixed(1) + " W"
                                font.pixelSize: 10; color: "#8a8a8a"
                            }
                            Column {
                                x: 14; y: root.horiz ? 48 : 42; spacing: root.horiz ? 18 : 12
                                Repeater {
                                    model: 3
                                    Item {
                                        id: ba
                                        required property int index
                                        readonly property var a: (root.bApps && root.bApps.length > index) ? root.bApps[index] : null
                                        width: batApps.width - 28; height: 16
                                        opacity: a ? 1 : 0.25
                                        NText { width: 100; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: ba.a ? ba.a.name : "—"; font.pixelSize: 11; color: "#dcdcdc" }
                                        Rectangle {
                                            x: 108; anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 108 - 56; height: 5; radius: 2.5; color: "#242424"
                                            Rectangle {
                                                width: ba.a ? Math.max(4, parent.width * Math.min(1, ba.a.r || 0)) : 0
                                                height: 5; radius: 2.5; color: root.accent
                                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                        NText {
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            text: ba.a ? Number(ba.a.w || 0).toFixed(1) + " W" : ""
                                            font.pixelSize: 11; font.bold: true; color: root.accent
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // ================= SES MODU: hoparlore tiklayinca dock ses paneline donusur =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: root.dmode === "audio" || audioUi.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "audio" }
                    FocusScope {
                        id: audioUi
                        width: root.audioW
                        height: root.audioH
                        focus: root.dmode === "audio"
                        opacity: root.dmode === "audio" && dock.width > root.audioW - 30 ? 1 : 0
                        enabled: root.dmode === "audio"
                        Behavior on opacity { NumberAnimation { duration: root.dmode === "audio" ? 220 : 90; easing.type: Easing.OutCubic } }
                        transform: Translate { x: root.dmode === "audio" ? 0 : -10; Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        Keys.onEscapePressed: root.closeMode()
                        Keys.onUpPressed: root.setVol(root.vol + 0.05)
                        Keys.onDownPressed: root.setVol(root.vol - 0.05)
                        Timer { id: audioFocus; interval: 80; onTriggered: audioUi.forceActiveFocus() }
                        Connections { target: root; function onDmodeChanged() { if (root.dmode === "audio") { audioFocus.restart(); audioIn.restart(); } } }
                        property real rise: 0
                        SequentialAnimation {
                            id: audioIn
                            PropertyAction { target: audioUi; property: "rise"; value: 1 }
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: audioUi; property: "rise"; to: 0; duration: 520; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: root.horiz ? 22 : 0; topRightRadius: 22; bottomRightRadius: root.horiz ? 0 : 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
                                GradientStop { position: 0.30; color: "transparent" }
                            }
                        }

                        // kalin, yuvarlak ses cubugu (surukle / tikla / tekerlek)
                        component ASlider: Item {
                            id: as
                            property real value: 0          // 0..1
                            property bool dim: false
                            property int barH: 8
                            signal moved(real v)
                            height: 20
                            property real dragV: 0
                            readonly property real v: asMa.pressed ? dragV : Math.max(0, Math.min(1, value))
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: as.barH; radius: as.barH / 2
                                color: "#232323"
                                Rectangle {
                                    width: Math.max(as.barH, parent.width * as.v)
                                    height: parent.height; radius: parent.radius
                                    color: as.dim ? "#4a4a4a" : root.accent
                                    Behavior on width { enabled: !asMa.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }
                            }
                            Rectangle {
                                width: as.barH + 8; height: width; radius: width / 2
                                x: Math.max(0, Math.min(as.width - width, as.width * as.v - width / 2))
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                                scale: asMa.pressed ? 1.25 : (asMa.containsMouse ? 1.1 : 1)
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                Behavior on x { enabled: !asMa.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                id: asMa
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                function upd(m) { as.dragV = Math.max(0, Math.min(1, (m.x - 6) / as.width)); as.moved(Math.round(as.dragV * 100) / 100); }
                                onPressed: m => upd(m)
                                onPositionChanged: m => { if (pressed) upd(m); }
                                onWheel: w => as.moved(Math.max(0, Math.min(1, as.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
                            }
                        }

                        // ---- baslik ----
                        Item {
                            x: 8; y: 16
                            width: 26; height: 26
                            z: 5
                            opacity: 1 - audioUi.rise
                            CGlyph {
                                anchors.centerIn: parent
                                size: 20
                                text: root.g(root.horiz ? 0xF0140 : 0xF0141)
                                color: audBackMa.containsMouse ? root.accent : "#e6e6e6"
                                scale: audBackMa.pressed ? 0.85 : (audBackMa.containsMouse ? 1.12 : 1)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            MouseArea { id: audBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeMode() }
                        }
                        NText { x: 40; y: 18; text: root.t("Ses", "Sound"); font.pixelSize: 16; font.bold: true; color: "#ffffff"; opacity: 1 - audioUi.rise }

                        // ---- ana ses karti ----
                        Rectangle {
                            id: aHero
                            x: 16; y: 56
                            width: root.horiz ? root.audCol : root.audioW - 32; height: 112; radius: 18
                            color: root.muted ? "#101010" : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                            border.width: 1
                            border.color: root.muted ? "#1e1e1e" : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                            Behavior on color { ColorAnimation { duration: 220 } }
                            opacity: 1 - audioUi.rise
                            transform: Translate { y: audioUi.rise * 16 }
                            // sessiz dugmesi: canli hoparlor
                            Rectangle {
                                id: aMuteBtn
                                x: 14; y: 14
                                width: 44; height: 44; radius: 22
                                color: root.muted ? "#1c1c1c" : root.accent
                                Behavior on color { ColorAnimation { duration: 200 } }
                                scale: amMa.pressed ? 0.9 : (amMa.containsMouse ? 1.06 : 1)
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                CGlyph {
                                    anchors.centerIn: parent
                                    text: root.g(root.muted ? 0xF0581 : 0xF057E); size: 22
                                    color: root.muted ? "#9a9a9a" : "#0b1530"
                                }
                                MouseArea { id: amMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMute() }
                            }
                            Column {
                                x: 70; y: 16
                                width: parent.width - 70 - 14
                                spacing: 2
                                NText {
                                    width: parent.width; elide: Text.ElideRight
                                    text: root.sink ? root.aName(root.sink) : root.t("Çıkış yok", "No output")
                                    font.pixelSize: 14; font.bold: true; color: "#ffffff"
                                }
                                NText {
                                    text: root.muted ? root.t("Sessiz", "Muted") : (root.sink ? root.aSub(root.sink, false).split(" · ")[0] : "")
                                    font.pixelSize: 11; color: root.muted ? "#ff8a8a" : "#cfd8ff"
                                }
                            }
                            ASlider {
                                id: masterSl
                                x: 16; y: 74
                                width: parent.width - 32 - 52
                                barH: 10
                                value: root.vol
                                dim: root.muted
                                onMoved: v => root.setVol(v)
                            }
                            NText {
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: masterSl.verticalCenter
                                text: Math.round(masterSl.v * 100) + "%"
                                font.pixelSize: 15; font.bold: true
                                color: root.muted ? "#6a6a6a" : "#ffffff"
                            }
                        }

                        // ---- sekmeler: Cikis / Giris / Uygulamalar ----
                        Rectangle {
                            id: aTabs
                            x: 16; y: 182
                            width: root.horiz ? root.audCol : root.audioW - 32; height: 40; radius: 13
                            color: "#0f0f0f"
                            border.width: 1; border.color: "#1e1e1e"
                            opacity: 1 - audioUi.rise
                            transform: Translate { y: audioUi.rise * 22 }
                            readonly property var keys: ["out", "in", "app"]
                            readonly property int idx: Math.max(0, keys.indexOf(root.aTab))
                            readonly property real seg: (width - 8) / 3
                            Rectangle {
                                x: 4 + aTabs.idx * aTabs.seg; y: 4
                                width: aTabs.seg; height: parent.height - 8; radius: 10
                                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                                border.width: 1.5; border.color: root.accent
                                Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                            }
                            Repeater {
                                model: 3
                                Item {
                                    id: at
                                    required property int index
                                    readonly property var icons: [0xF04C3, 0xF036C, 0xF0387]
                                    readonly property var names: [root.t("Çıkış", "Output"), root.t("Giriş", "Input"), root.t("Uygulama", "Apps")]
                                    readonly property bool on: aTabs.idx === index
                                    x: 4 + index * aTabs.seg; y: 4
                                    width: aTabs.seg; height: aTabs.height - 8
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(at.icons[at.index]); size: 14; color: at.on ? root.accent : (atMa.containsMouse ? "#ffffff" : "#8a8a8a") }
                                        NText { anchors.verticalCenter: parent.verticalCenter; text: at.names[at.index]; font.pixelSize: 11; font.bold: at.on; color: at.on ? "#ffffff" : (atMa.containsMouse ? "#e6e6e6" : "#9a9a9a") }
                                    }
                                    MouseArea { id: atMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.aTab = aTabs.keys[at.index] }
                                }
                            }
                        }

                        // ---- liste ----
                        ListView {
                            id: audList
                            x: root.horiz ? 16 + root.audCol + 10 : 10; y: root.horiz ? 14 : 234
                            width: root.horiz ? root.audioW - root.audCol - 16 - 10 - 10 : root.audioW - 20
                            height: parent.height - y - 14
                            clip: true
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            opacity: 1 - audioUi.rise
                            readonly property var src: root.aTab === "in" ? root.aIns : (root.aTab === "app" ? root.aApps : root.aOuts)
                            model: src.length
                            // sekme degisince liste yana kayarak yenilenir
                            property real slide: 0
                            transform: Translate { y: audioUi.rise * 30; x: audList.slide }
                            Connections {
                                target: root
                                function onATabChanged() { aSwap.restart(); }
                            }
                            SequentialAnimation {
                                id: aSwap
                                PropertyAction { target: audList; property: "slide"; value: 24 }
                                NumberAnimation { target: audList; property: "slide"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                            }
                            delegate: Item {
                                id: ar2
                                required property int index
                                readonly property var n: audList.src[index] || null
                                readonly property bool app: root.aTab === "app"
                                readonly property bool input: root.aTab === "in"
                                readonly property bool sel: !app && n !== null && (input ? (root.aSource && root.aSource.id === n.id) : (root.sink && root.sink.id === n.id))
                                width: audList.width
                                height: app || sel ? 66 : 52
                                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                opacity: 0
                                property real rs: 10
                                Component.onCompleted: ar2In.start()
                                SequentialAnimation {
                                    id: ar2In
                                    PauseAnimation { duration: Math.min(ar2.index, 8) * 35 }
                                    ParallelAnimation {
                                        NumberAnimation { target: ar2; property: "opacity"; to: 1; duration: 220 }
                                        NumberAnimation { target: ar2; property: "rs"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                    }
                                }
                                transform: Translate { y: ar2.rs }
                                HoverHandler { id: ar2HH }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
                                    color: ar2.sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : (ar2HH.hovered ? "#151515" : "transparent")
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                Rectangle {
                                    x: 0; y: 16; width: 3; height: 20; radius: 1.5
                                    color: root.accent
                                    visible: ar2.sel
                                }
                                // satira tikla: varsayilan cikis/giris yap
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !ar2.app && !ar2.sel
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!ar2.n) return;
                                        if (ar2.input) Pipewire.preferredDefaultAudioSource = ar2.n;
                                        else Pipewire.preferredDefaultAudioSink = ar2.n;
                                    }
                                }
                                // ikon (uygulamalarda tikla: o uygulamayi sustur)
                                Rectangle {
                                    id: aIco
                                    x: 10; y: 11
                                    width: 32; height: 32; radius: 10
                                    color: ar2.sel ? root.accent : "#1a1a1a"
                                    readonly property bool appMuted: ar2.app && ar2.n && ar2.n.audio && ar2.n.audio.muted
                                    IconImage {
                                        id: aAppIc
                                        anchors.centerIn: parent
                                        implicitSize: 20
                                        asynchronous: true
                                        source: ar2.app && ar2.n && root.aAppIcon(ar2.n) !== "" ? Quickshell.iconPath(root.aAppIcon(ar2.n), true) : ""
                                        visible: ar2.app && ar2.n !== null && root.aAppIcon(ar2.n) !== "" && status === Image.Ready
                                        opacity: aIco.appMuted ? 0.35 : 1
                                    }
                                    CGlyph {
                                        anchors.centerIn: parent
                                        visible: !aAppIc.visible
                                        text: root.g(ar2.app ? 0xF0387 : (ar2.n ? root.aIcon(ar2.n, ar2.input) : 0xF04C3)); size: 16
                                        color: ar2.sel ? "#0b1530" : (ar2.app ? root.accent : "#cfcfcf")
                                        opacity: aIco.appMuted ? 0.35 : 1
                                    }
                                    // sessiz rozeti
                                    Rectangle {
                                        visible: aIco.appMuted
                                        x: parent.width - 12; y: -3
                                        width: 15; height: 15; radius: 7.5
                                        color: "#ff6b6b"
                                        CGlyph { anchors.centerIn: parent; text: root.g(0xF0581); size: 9; color: "#000000" }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: ar2.app
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (ar2.n && ar2.n.audio) ar2.n.audio.muted = !ar2.n.audio.muted
                                    }
                                }
                                NText {
                                    x: 54; y: ar2.app || ar2.sel ? 9 : 10
                                    width: parent.width - 54 - 56; elide: Text.ElideRight
                                    text: ar2.n ? root.aName(ar2.n) : ""
                                    font.pixelSize: 13; font.bold: ar2.sel
                                    color: ar2.sel ? root.accent : "#ededed"
                                }
                                NText {
                                    x: 54; y: 27
                                    visible: !ar2.app && !ar2.sel
                                    width: parent.width - 54 - 14; elide: Text.ElideRight
                                    text: ar2.n ? root.aSub(ar2.n, ar2.input) : ""
                                    font.pixelSize: 10; color: "#8a8a8a"
                                }
                                // secili cihaz ya da uygulama: kendi ses cubugu
                                ASlider {
                                    id: rowSl
                                    visible: ar2.app || ar2.sel
                                    x: 54; y: 34
                                    width: parent.width - 54 - 56
                                    barH: 6
                                    readonly property real maxV: ar2.app ? root.aMaxApp : 1
                                    value: ar2.n && ar2.n.audio ? ar2.n.audio.volume / maxV : 0
                                    dim: ar2.n && ar2.n.audio ? ar2.n.audio.muted : false
                                    onMoved: v => {
                                        if (!ar2.n || !ar2.n.audio) return;
                                        if (ar2.n.audio.muted && v > 0) ar2.n.audio.muted = false;
                                        ar2.n.audio.volume = v * maxV;
                                    }
                                }
                                NText {
                                    visible: rowSl.visible
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    anchors.verticalCenter: rowSl.verticalCenter
                                    text: Math.round(rowSl.v * rowSl.maxV * 100) + "%"
                                    font.pixelSize: 11; font.bold: true
                                    color: rowSl.dim ? "#6a6a6a" : "#cfcfcf"
                                }
                            }
                        }
                        // bos durum
                        Column {
                            anchors.horizontalCenter: audList.horizontalCenter
                            y: audList.y + 50
                            spacing: 8
                            visible: audList.src.length === 0
                            opacity: 1 - audioUi.rise
                            CGlyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.g(root.aTab === "in" ? 0xF036D : (root.aTab === "app" ? 0xF0387 : 0xF0581)); size: 30
                                color: "#333333"
                            }
                            NText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.aTab === "in" ? root.t("Mikrofon bulunamadı", "No microphone found") : (root.aTab === "app" ? root.t("Şu an ses çalan uygulama yok", "No apps playing audio") : root.t("Ses çıkışı bulunamadı", "No audio output found"))
                                font.pixelSize: 12; color: "#6a6a6a"
                            }
                        }
                    }
                }
                // ================= YATAY DOCK: DUVAR KAGIDI SERIDI (alt ortadan yukari esner) =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: (root.dmode === "walls" && root.horiz) || wallUiH.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "walls" && root.horiz }
                    Item {
                        id: wallUiH
                        width: root.wallHW
                        height: root.wallHH
                        // icerik panel buyudukce yavasca belirir (sonda birden "pat" diye gelmez)
                        opacity: root.dmode === "walls" && root.horiz ? Math.max(0, Math.min(1, (dock.height - root.wallHH * 0.4) / (root.wallHH * 0.55))) : 0
                        enabled: root.dmode === "walls" && root.horiz
                        Behavior on opacity { enabled: root.dmode !== "walls"; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        transform: Translate { y: root.dmode === "walls" ? 0 : 10; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: 22; topRightRadius: 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) }
                                GradientStop { position: 0.4; color: "transparent" }
                            }
                        }
                        // ---- baslik + sayi ----
                        Row {
                            id: whHead
                            x: 22; y: 18
                            spacing: 9
                            CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0E09); size: 19; color: root.accent }
                            Label2 { anchors.verticalCenter: parent.verticalCenter; text: root.t("Duvar Kağıdı", "Wallpapers"); font.pixelSize: 15; font.weight: Font.Bold; color: "#ffffff" }
                            Label2 {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.wallList.length + (root.wallQuery.length > 0 ? " / " + root.wallAll.length : "")
                                font.pixelSize: 11; color: "#7a7a7a"
                            }
                        }
                        // ---- arama (sag ust) ----
                        Rectangle {
                            id: whSearch
                            anchors.right: parent.right; anchors.rightMargin: 20
                            y: 12
                            width: 200; height: 34; radius: 10
                            color: "#141414"
                            // arama varken: 2px pywal kenar, yavasca yanip soner
                            readonly property bool searching: root.wallQuery.length > 0
                            property real pulse: 1
                            SequentialAnimation on pulse {
                                running: whSearch.searching && root.dmode === "walls"; loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 750; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 750; easing.type: Easing.InOutSine }
                            }
                            onSearchingChanged: pulse = 1
                            border.width: searching ? 2 : 1
                            border.color: searching ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25 + 0.6 * pulse) : "#1f1f1f"
                            CGlyph { id: whSIc; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0349); size: 15; color: root.accent }
                            TextInput {
                                id: whIn
                                anchors.left: whSIc.right; anchors.leftMargin: 7
                                anchors.right: parent.right; anchors.rightMargin: whSearch.searching ? 34 : 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                                font.family: root.fontName; font.pixelSize: 13
                                selectionColor: root.accent
                                clip: true
                                // klavye hep burada (oklar/Enter/yazma) ama imlec sadece yazmaya baslayinca
                                // ya da kutuya tiklayinca gorunur; bos dururken yanip sonmez
                                property bool typing: false
                                onTextChanged: { if (root.horiz) root.wallQuery = text; if (text.length > 0) typing = true; }
                                onActiveFocusChanged: if (!activeFocus) typing = false
                                cursorDelegate: Rectangle {
                                    width: 1.5; color: "#ffffff"
                                    visible: whIn.typing && whIn.activeFocus
                                    SequentialAnimation on opacity {
                                        running: whIn.typing && whIn.activeFocus; loops: Animation.Infinite
                                        PropertyAction { value: 1 }
                                        PauseAnimation { duration: 530 }
                                        PropertyAction { value: 0 }
                                        PauseAnimation { duration: 530 }
                                    }
                                }
                                Keys.onLeftPressed: e => { root.wallMove(-1); e.accepted = true; }
                                Keys.onRightPressed: e => { root.wallMove(1); e.accepted = true; }
                                Keys.onTabPressed: e => { root.wallMove(1); e.accepted = true; }
                                Keys.onReturnPressed: e => { if (root.wallOk(root.wallSel)) root.wallApply(root.wallList[root.wallSel]); e.accepted = true; }
                                Keys.onEnterPressed: e => { if (root.wallOk(root.wallSel)) root.wallApply(root.wallList[root.wallSel]); e.accepted = true; }
                                Keys.onEscapePressed: e => { if (text.length > 0) { text = ""; typing = false; } else root.closeMode(); e.accepted = true; }
                            }
                            // kutuya tiklayinca yazma moduna gec (imlec belirir)
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: { whIn.typing = true; whIn.forceActiveFocus(); }
                            }
                            // en sagda X: aramayi iptal eder
                            Rectangle {
                                anchors.right: parent.right; anchors.rightMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 10
                                visible: opacity > 0.01
                                opacity: whSearch.searching ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                color: whClrMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : "#222222"
                                scale: whClrMa.pressed ? 0.85 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                CGlyph { anchors.centerIn: parent; text: root.g(0xF0156); size: 12; color: whClrMa.containsMouse ? root.accent : "#bdbdbd" }
                                MouseArea {
                                    id: whClrMa
                                    anchors.fill: parent; anchors.margins: -4
                                    enabled: whSearch.searching
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { whIn.text = ""; root.wallQuery = ""; whIn.typing = false; whIn.forceActiveFocus(); }
                                }
                            }
                        }
                        Connections {
                            target: root
                            function onWallsOpened() { if (!root.horiz) return; whIn.text = ""; whIn.typing = false; whFocus.restart(); whList.positionViewAtIndex(root.wallSel, ListView.Center); }
                            function onWallsReordered() { if (root.horiz) whList.positionViewAtIndex(root.wallSel, ListView.Center); }
                        }
                        Timer { id: whFocus; interval: 80; onTriggered: whIn.forceActiveFocus() }

                        // ---- yatay serit: secili kart ortada buyuk ----
                        ListView {
                            id: whList
                            x: 16; y: 58
                            width: parent.width - 32
                            height: parent.height - y - 16
                            orientation: ListView.Horizontal
                            clip: true
                            spacing: 10
                            leftMargin: 10; rightMargin: 10
                            model: root.wallList.length   // sayi: liste yenilenince kartlar bastan olusmasin (takilma)
                            currentIndex: root.wallSel
                            boundsBehavior: Flickable.StopAtBounds
                            highlightRangeMode: ListView.ApplyRange
                            // secili kart hep ortada (aktif olan basta, solunda gorunur)
                            preferredHighlightBegin: width / 2 - whList.cardW / 2
                            preferredHighlightEnd: width / 2 + whList.cardW / 2
                            highlightMoveDuration: 320
                            readonly property real cardH: height - 20
                            readonly property real cardW: Math.round(cardH * 16 / 9)
                            cacheBuffer: 900
                            delegate: Item {
                                id: whc
                                required property int index
                                readonly property var md: root.wallList[index] || ({ name: "", path: "", thumb: "" })
                                readonly property bool sel: root.wallSel === index
                                readonly property bool cur: root.wallSame(md.path, root.wallCur)
                                width: whList.cardW
                                height: whList.height
                                opacity: 0
                                property real rise: 18
                                transform: Translate { y: whc.rise }
                                Component.onCompleted: whcIn.start()
                                SequentialAnimation {
                                    id: whcIn
                                    PauseAnimation { duration: Math.min(whc.index, 6) * 45 }
                                    ParallelAnimation {
                                        NumberAnimation { target: whc; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: whc; property: "rise"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                                    }
                                }
                                ClippingRectangle {
                                    id: whCard
                                    anchors.centerIn: parent
                                    width: whList.cardW; height: whList.cardH
                                    radius: 14
                                    color: "#151515"
                                    scale: whc.sel ? (whMa.pressed ? 0.97 : 1) : 0.86
                                    opacity: whc.sel ? 1 : 0.5
                                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                    Behavior on opacity { NumberAnimation { duration: 260 } }
                                    Rectangle {
                                        anchors.fill: parent; color: "#1d1d1d"
                                        visible: whImg.status !== Image.Ready
                                    }
                                    Image {
                                        id: whImg
                                        anchors.fill: parent
                                        property int tryN: 0
                                        readonly property var srcs: [whc.md.hq || whc.md.thumb, whc.md.thumb, whc.md.path]
                                        onSrcsChanged: tryN = 0
                                        source: "file://" + srcs[Math.min(tryN, 2)]
                                        onStatusChanged: if (status === Image.Error && tryN < 2) tryN++
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: true; retainWhileLoading: true
                                        smooth: true; mipmap: true
                                        sourceSize: Qt.size(720, 405)
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 220 } }
                                    }
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 36
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.82) }
                                        }
                                        Label2 {
                                            anchors.left: parent.left; anchors.leftMargin: 10
                                            anchors.right: parent.right; anchors.rightMargin: 10
                                            anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                                            text: whc.md.name; elide: Text.ElideMiddle
                                            font.pixelSize: 11; font.weight: whc.sel ? Font.DemiBold : Font.Normal
                                            color: "#ffffff"
                                        }
                                    }
                                    Rectangle {
                                        visible: whc.cur
                                        anchors.right: parent.right; anchors.rightMargin: 8
                                        anchors.top: parent.top; anchors.topMargin: 8
                                        height: 20; radius: 6
                                        width: whCurRow.implicitWidth + 12
                                        color: root.accent
                                        Row {
                                            id: whCurRow
                                            anchors.centerIn: parent; spacing: 3
                                            CGlyph { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF012C); size: 11; color: "#000000" }
                                            Label2 { anchors.verticalCenter: parent.verticalCenter; text: root.t("Aktif", "Active"); font.pixelSize: 10; font.weight: Font.Bold; color: "#000000" }
                                        }
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn: whCard
                                    width: whCard.width * whCard.scale + 6; height: whCard.height * whCard.scale + 6
                                    radius: 17
                                    color: "transparent"
                                    border.width: 2; border.color: root.accent
                                    opacity: whc.sel ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                MouseArea {
                                    id: whMa
                                    anchors.fill: parent
                                    cursorShape: whc.cur ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: { if (whc.cur) return; if (whc.sel) root.wallApply(whc.md); else root.wallSel = whc.index; whIn.forceActiveFocus(); }
                                    onDoubleClicked: if (!whc.cur) root.wallApply(whc.md)
                                }
                            }
                            // tekerlek: yana gez
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                property real acc: 0
                                onWheel: w => {
                                    acc += w.angleDelta.y + w.angleDelta.x;
                                    while (acc >= 120) { root.wallMove(-1); acc -= 120; }
                                    while (acc <= -120) { root.wallMove(1); acc += 120; }
                                }
                            }
                        }
                        Label2 {
                            anchors.centerIn: whList
                            text: root.wallLoading ? root.t("Yükleniyor…", "Loading…") : (root.wallQuery.length > 0 ? root.t("Sonuç bulunamadı", "No results") : root.t("Klasör boş", "Folder is empty"))
                            font.pixelSize: 12; color: root.accent
                            visible: root.wallList.length === 0
                        }
                    }
                }
                // ================= YATAY DOCK: UYGULAMALAR (Win11 baslat menusu gibi izgara) =================
                Item {
                    width: dock.width; height: dock.height
                    clip: true
                    visible: (root.dmode === "apps" && root.horiz) || appUiH.opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.dmode === "apps" && root.horiz }
                    Item {
                        id: appUiH
                        width: root.appHW
                        height: root.appHH
                        // icerik panel buyudukce yavasca belirir (sonda birden "pat" diye gelmez)
                        opacity: root.dmode === "apps" && root.horiz ? Math.max(0, Math.min(1, (dock.height - root.appHH * 0.4) / (root.appHH * 0.55))) : 0
                        enabled: root.dmode === "apps" && root.horiz
                        Behavior on opacity { enabled: root.dmode !== "apps"; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        transform: Translate { y: root.dmode === "apps" ? 0 : 10; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
                        readonly property int cols: 6
                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: 22; topRightRadius: 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) }
                                GradientStop { position: 0.3; color: "transparent" }
                            }
                        }
                        // ---- arama (Win11 gibi en ustte, genis) ----
                        Rectangle {
                            id: ahSearch
                            x: 24; y: 20
                            width: parent.width - 48; height: 40; radius: 20
                            color: "#141414"
                            border.width: 1
                            border.color: root.appQuery.length > 0 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : "#1f1f1f"
                            CGlyph { id: ahSIc; x: 14; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0349); size: 16; color: root.accent }
                            TextInput {
                                id: ahIn
                                anchors.left: ahSIc.right; anchors.leftMargin: 8
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                                font.family: root.fontName; font.pixelSize: 13
                                selectionColor: root.accent
                                clip: true
                                onTextChanged: if (root.horiz) root.appQuery = text
                                Keys.onLeftPressed: e => { root.appMove(-1); e.accepted = true; }
                                Keys.onRightPressed: e => { root.appMove(1); e.accepted = true; }
                                Keys.onUpPressed: e => { root.appMove(-appUiH.cols); e.accepted = true; }
                                Keys.onDownPressed: e => { root.appMove(appUiH.cols); e.accepted = true; }
                                Keys.onTabPressed: e => { root.appMove(1); e.accepted = true; }
                                Keys.onReturnPressed: e => { root.appActivate(); e.accepted = true; }
                                Keys.onEnterPressed: e => { root.appActivate(); e.accepted = true; }
                                Keys.onEscapePressed: e => { if (text.length > 0) text = ""; else root.closeMode(); e.accepted = true; }
                                Label2 {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.t("Uygulama, ayar ya da dosya ara", "Search apps, settings or files")
                                    color: "#5a5a5a"; font.pixelSize: 13
                                    visible: ahIn.text.length === 0
                                }
                            }
                        }
                        Connections {
                            target: root
                            function onAppsOpened() { if (!root.horiz) return; ahIn.text = ""; ahFocus.restart(); ahGrid.positionViewAtBeginning(); }
                        }
                        Timer { id: ahFocus; interval: 80; onTriggered: ahIn.forceActiveFocus() }
                        // ---- baslik ----
                        Row {
                            x: 30; y: 78
                            spacing: 8
                            Label2 { anchors.verticalCenter: parent.verticalCenter; text: root.appQuery.length > 0 ? root.t("Sonuçlar", "Results") : root.t("Tüm uygulamalar", "All apps"); font.pixelSize: 14; font.weight: Font.Bold; color: "#ffffff" }
                            Label2 { anchors.verticalCenter: parent.verticalCenter; text: root.appList.length; font.pixelSize: 11; color: "#7a7a7a" }
                        }
                        // ---- izgara ----
                        GridView {
                            id: ahGrid
                            x: 18; y: 108
                            width: parent.width - 36
                            height: parent.height - y - 16
                            cellWidth: Math.floor(width / appUiH.cols)
                            cellHeight: 92
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.appList.length
                            currentIndex: root.appSel
                            highlightRangeMode: GridView.ApplyRange
                            preferredHighlightBegin: 0
                            preferredHighlightEnd: height
                            highlightMoveDuration: 200
                            delegate: Item {
                                id: ag
                                required property int index
                                readonly property var e: root.appList[index] || null
                                readonly property bool sel: root.appSel === index
                                readonly property bool pinned: root.isPinnedEntry(e)
                                width: ahGrid.cellWidth; height: ahGrid.cellHeight
                                opacity: 0
                                property real rs: 10
                                transform: Translate { y: ag.rs }
                                Component.onCompleted: agIn.start()
                                SequentialAnimation {
                                    id: agIn
                                    PauseAnimation { duration: Math.min(ag.index, 18) * 18 }
                                    ParallelAnimation {
                                        NumberAnimation { target: ag; property: "opacity"; to: 1; duration: 220 }
                                        NumberAnimation { target: ag; property: "rs"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: 3
                                    radius: 14
                                    color: ag.sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : (agMa.containsMouse ? "#141414" : "transparent")
                                    border.width: ag.sel ? 1 : 0
                                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                                IconImage {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 14
                                    implicitSize: 38
                                    scale: ag.sel || agMa.containsMouse ? 1.08 : 1
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    source: ag.e ? Quickshell.iconPath(ag.e.icon || "", "application-x-executable") : ""
                                }
                                Label2 {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 60
                                    width: parent.width - 12
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: ag.e ? ag.e.name : ""
                                    font.pixelSize: 11
                                    color: ag.sel ? root.accent : "#dcdcdc"
                                }
                                // sabitliyse kucuk raptiye
                                CGlyph {
                                    visible: ag.pinned
                                    x: parent.width - 22; y: 8
                                    text: root.g(0xF0403); size: 11; color: root.accent
                                }
                                MouseArea {
                                    id: agMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: root.appSel = ag.index
                                    // sag tik: dock'a sabitle / kaldir
                                    onClicked: m => { if (m.button === Qt.RightButton) root.togglePinEntry(ag.e); else root.appLaunch(ag.e); }
                                }
                            }
                        }
                        Label2 {
                            anchors.centerIn: ahGrid
                            text: root.t("Sonuç bulunamadı", "No results")
                            font.pixelSize: 12; color: root.accent
                            visible: root.appList.length === 0
                        }
                    }
                }
            }

            // ---- ipucu: ikonun sagina kayarak gelir ----
            Rectangle {
                id: tipBox
                property string text: ""
                property real cy: 0
                property bool on: false
                x: dock.x + root.dockW + (on ? 10 : 4)
                y: cy - height / 2
                width: tipText.implicitWidth + 20
                height: 28
                radius: 9
                color: "#000000"
                opacity: on && win.shown && !ctx.open && !trayCard.open && !volPop.on && !trayChev.open ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Label2 { id: tipText; anchors.centerIn: parent; text: tipBox.text }
            }

            // ---- uygulama sag tik menusu ----
            Rectangle {
                id: ctx
                property bool open: false
                property var app: null
                readonly property bool running: app !== null && app.wins.length > 0
                // dikeyde ikonun sagi, yatayda ikonun ustu
                property real ax: 0
                function openFor(a, cy) {
                    ctx.app = a;
                    if (root.horiz) ctx.ax = cy; else ctx.y = Math.max(8, Math.min(win.height - height - 8, cy - 18));
                    ctx.open = true;
                }
                x: root.horiz ? Math.max(8, Math.min(win.width - width - 8, ctx.ax - width / 2)) : dock.x + root.dockW + 10
                y: root.horiz ? dock.y - height - 10 : 0
                width: 180
                height: ctxCol.implicitHeight + 10
                radius: 12
                color: "#0d0d0d"
                border.width: 1
                border.color: "#222222"
                opacity: open && win.shown ? 1 : 0
                visible: opacity > 0.01
                scale: open ? 1 : 0.9
                transformOrigin: root.horiz ? Item.Bottom : Item.Left
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                HoverHandler { id: ctxHH }
                Column {
                    id: ctxCol
                    x: 5; y: 5
                    width: parent.width - 10
                    CtxItem {
                        visible: ctx.app !== null && ctx.app.pinId !== ""
                        icon: root.g(ctx.app && ctx.app.pinned ? 0xF0404 : 0xF0403)
                        label: ctx.app && ctx.app.pinned ? root.t("Dock'tan kaldır", "Unpin from dock") : root.t("Dock'a sabitle", "Pin to dock")
                        onPicked: { root.togglePin(ctx.app.pinId); ctx.open = false; }
                    }
                    CtxItem {
                        visible: ctx.running && ctx.app.entry !== null
                        icon: root.g(0xF0415)
                        label: root.t("Yeni pencere", "New window")
                        onPicked: { ctx.app.entry.execute(); ctx.open = false; }
                    }
                    CtxItem {
                        visible: ctx.running
                        icon: root.g(0xF0156)
                        label: ctx.app && ctx.app.wins.length > 1 ? root.t("Hepsini kapat", "Close all") : root.t("Kapat", "Close")
                        danger: true
                        onPicked: { const l = ctx.app.wins.slice(); ctx.open = false; for (const t of l) t.close(); }
                    }
                }
            }

            // ---- tepsi menusu (sag tik): uygulamanin kendi menusu, alt menuler ayni kartta ----
            Rectangle {
                id: trayCard
                property bool open: false
                property var rootMenu: null
                property var stack: []
                readonly property var current: stack.length > 0 ? stack[stack.length - 1] : rootMenu
                property real px: 0
                property real py: 0
                property bool above: false
                function openAt(m, x, y, up) {
                    if (open && rootMenu === m) { close(); return; }
                    stack = []; rootMenu = m; px = x; py = y; above = !!up; open = true;
                }
                function close() { open = false; rootMenu = null; stack = []; }
                function clean(t) { return (t || "").replace(/_(?!_)/g, "").replace(/__/g, "_"); }
                x: Math.max(8, Math.min(win.width - width - 8, px))
                y: Math.max(8, Math.min(win.height - height - 8, above ? py - height : py))
                width: 210
                height: tcCol.implicitHeight + 10
                radius: 12
                color: "#0d0d0d"
                border.width: 1
                border.color: "#222222"
                opacity: open && win.shown ? 1 : 0
                visible: opacity > 0.01
                scale: open ? 1 : 0.9
                transformOrigin: above ? Item.BottomLeft : Item.TopLeft
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                HoverHandler { id: cardHH }
                QsMenuOpener { id: trayOpener; menu: trayCard.current }
                Column {
                    id: tcCol
                    x: 5; y: 5
                    width: parent.width - 10
                    // alt menudeyken geri satiri
                    CtxItem {
                        visible: trayCard.stack.length > 0
                        icon: root.g(0xF0141)
                        label: root.t("Geri", "Back")
                        onPicked: trayCard.stack = trayCard.stack.slice(0, -1)
                    }
                    Repeater {
                        model: trayOpener.children
                        Item {
                            id: te
                            required property var modelData
                            readonly property var md: modelData
                            width: tcCol.width
                            height: md && md.isSeparator ? 9 : 30
                            Rectangle {
                                visible: te.md.isSeparator
                                anchors.verticalCenter: parent.verticalCenter
                                x: 8; width: parent.width - 16; height: 1
                                color: "#262626"
                            }
                            Rectangle {
                                visible: !te.md.isSeparator
                                anchors.fill: parent
                                radius: 8
                                color: teMa.containsMouse && te.md.enabled ? "#181818" : "transparent"
                            }
                            Row {
                                visible: !te.md.isSeparator
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                CGlyph {
                                    visible: te.md.buttonType !== QsMenuButtonType.None
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 14
                                    color: root.accent
                                    text: te.md.checkState === Qt.Checked
                                        ? (te.md.buttonType === QsMenuButtonType.RadioButton ? root.g(0xF043E) : root.g(0xF0132))
                                        : (te.md.buttonType === QsMenuButtonType.RadioButton ? root.g(0xF043D) : root.g(0xF0131))
                                }
                                IconImage {
                                    visible: (te.md.icon || "") !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitSize: 16
                                    source: te.md.icon || ""
                                }
                                Label2 {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, tcCol.width - 50)
                                    elide: Text.ElideRight
                                    text: trayCard.clean(te.md.text)
                                    color: !te.md.enabled ? "#5a5a5a" : (teMa.containsMouse ? root.accent : "#e6e6e6")
                                }
                            }
                            CGlyph {
                                visible: !te.md.isSeparator && te.md.hasChildren
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.g(0xF0142); size: 14; color: "#9a9a9a"
                            }
                            MouseArea {
                                id: teMa
                                visible: !te.md.isSeparator
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: te.md.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (!te.md.enabled) return;
                                    if (te.md.hasChildren) { trayCard.stack = trayCard.stack.concat([te.md]); return; }
                                    te.md.triggered();
                                    trayCard.close();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
