pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Services système partagés : Wi-Fi, scan QR Wi-Fi, Bluetooth et lancement isolé.
QtObject {
    id: root

    // ── État système partagé (as-core system-service info) ──────────────────
    property var systemInfo: ({})
    property bool systemInfoPret: false

    property Process systemInfoProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "system-service", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && typeof d === "object") {
                        root.systemInfo = d
                        root.systemInfoPret = true
                    }
                } catch (e) {}
            }
        }
    }

    function rafraichirSystemInfo() {
        if (systemInfoProc.running) return
        systemInfoProc.running = true
    }

    property Timer systemInfoTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.rafraichirSystemInfo()
    }

    // ── Caffeine (inhibition mise en veille) ─────────────────────────────────
    // État partagé (style_vars.json via ConfigStore) : un profil d'environnement
    // l'enregistre, et il survit à une relance du shell.
    property bool caffeineActif: false
    property Process caffeineProc: Process {
        command: ["systemd-inhibit", "--what=idle", "--who=AetherShell", "--why=Mode Caffeine", "sleep", "infinity"]
        running: root.caffeineActif
    }

    function definirCaffeine(actif) {
        const v = Boolean(actif)
        root.caffeineActif = v
        Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "style",
                                 "caffeine_actif", v ? "true" : "false"])
    }

    // ── Météo partagée (as-core weather) ─────────────────────────────
    property var meteoData: ({})
    property string meteoStatut: ""
    property bool meteoLoaded: false
    property bool meteoActif: false

    property Process meteoProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "weather"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.meteoLoaded = true
                try {
                    const d = JSON.parse(String(text).trim())
                    if (d && d.ok) {
                        root.meteoData = d
                        root.meteoStatut = ""
                    } else {
                        root.meteoData = ({})
                        root.meteoStatut = String((d && d.error) || "météo indisponible")
                    }
                } catch (e) {
                    root.meteoData = ({})
                    root.meteoStatut = "réponse météo illisible"
                }
            }
        }
    }

    function rafraichirMeteo(force) {
        meteoActif = true
        if (meteoProc.running) return
        const args = [Quickshell.shellPath("core/as-core"), "weather"]
        if (force) args.push("--force")
        meteoProc.command = args
        meteoProc.running = true
    }

    property Timer meteoTimer: Timer {
        interval: 600000
        repeat: true
        running: root.meteoActif
        onTriggered: root.rafraichirMeteo(false)
    }

    // ── Démon de métriques partagé (CPU / RAM / GPU / Réseau) ───────────────
    property var systemeData: ({})
    property bool systemeCharge: false
    property var reseauData: ({})
    property bool reseauCharge: false
    property var _metriquesDemandeurs: ({})
    readonly property bool metriquesActif: Object.keys(_metriquesDemandeurs).length > 0

    function acquerirMetriques(id) {
        const cle = String(id || "")
        if (!cle || root._metriquesDemandeurs[cle]) return
        const nxt = Object.assign({}, root._metriquesDemandeurs)
        nxt[cle] = true
        root._metriquesDemandeurs = nxt
    }

    function relacherMetriques(id) {
        const cle = String(id || "")
        if (!cle || !root._metriquesDemandeurs[cle]) return
        const nxt = Object.assign({}, root._metriquesDemandeurs)
        delete nxt[cle]
        root._metriquesDemandeurs = nxt
    }

    property Process metriquesDaemonProc: Process {
        running: root.metriquesActif
        command: [Quickshell.shellPath("core/as-core"), "daemon", "2"]
        stdout: SplitParser {
            onRead: line => {
                const s = String(line || "").trim()
                if (!s) return
                try {
                    const d = JSON.parse(s)
                    if (d && d.systeme) {
                        root.systemeData = d.systeme
                        root.systemeCharge = true
                    }
                    if (d && d.reseau) {
                        root.reseauData = d.reseau
                        root.reseauCharge = true
                    }
                } catch (e) {}
            }
        }
    }

    property Timer metriquesGardeTimer: Timer {
        interval: 10000
        repeat: true
        running: root.metriquesActif && !root.metriquesDaemonProc.running
        onTriggered: root.metriquesDaemonProc.running = true
    }

    // ── Wi-Fi ────────────────────────────────────────────────────────────────
    property var wifiNetworks: []
    property bool wifiScanning: false
    property bool wifiEnabled: Boolean(root.systemInfo && root.systemInfo.wifi && (root.systemInfo.wifi.enabled !== false))
    property bool qrWifiAvailable: false

    property Process wifiCheckProc: Process {
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim().toLowerCase()
                if (s === "enabled" || s === "disabled") root.wifiEnabled = (s === "enabled")
            }
        }
    }

    property Process wifiToggleProc: Process {
        onExited: {
            if (!wifiCheckProc.running) wifiCheckProc.running = true
            root.rafraichirSystemInfo()
            if (root.wifiEnabled) root.scanWifi()
        }
    }

    property Process qrStatusProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "wifi-qr", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim() || "{}")
                    root.qrWifiAvailable = Boolean(d.available)
                } catch (e) {
                    root.qrWifiAvailable = false
                }
            }
        }
    }

    property Process wifiScanProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "system-service", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false
                try {
                    const arr = JSON.parse(text.trim())
                    root.wifiNetworks = Array.isArray(arr) ? arr : []
                } catch (e) {
                    root.wifiNetworks = []
                }
            }
        }
        onExited: root.wifiScanning = false
    }

    function checkWifiRadio() {
        if (!wifiCheckProc.running) wifiCheckProc.running = true
    }

    function toggleWifiRadio() {
        if (wifiToggleProc.running) return
        const target = root.wifiEnabled ? "off" : "on"
        root.wifiEnabled = !root.wifiEnabled
        wifiToggleProc.command = ["nmcli", "radio", "wifi", target]
        wifiToggleProc.running = true
    }

    function checkQrWifi() {
        if (!qrStatusProc.running) qrStatusProc.running = true
    }

    function scanWifi(rescan) {
        if (wifiScanProc.running) return
        root.wifiScanning = true
        const cmd = [Quickshell.shellPath("core/as-core"), "system-service", "wifi"]
        if (rescan === false) cmd.push("--no-rescan")
        wifiScanProc.command = cmd
        wifiScanProc.running = true
    }

    property bool wifiConnecting: false
    signal wifiConnectFinished(bool ok, string ssid, string message)
    property string _pendingWifiSsid: ""

    property Process wifiConnectProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiConnecting = false
                let ok = false
                let msg = ""
                let ssid = root._pendingWifiSsid
                try {
                    const d = JSON.parse(text.trim())
                    ok = Boolean(d.success)
                    msg = String(d.message || "")
                    if (d.ssid) ssid = String(d.ssid)
                } catch (e) {}
                if (ok) {
                    root.rafraichirSystemInfo()
                    root.scanWifi(false)
                }
                root.wifiConnectFinished(ok, ssid, msg)
            }
        }
    }

    function connectWifi(ssid, pwd) {
        if (!ssid || wifiConnectProc.running) return
        root._pendingWifiSsid = String(ssid)
        root.wifiConnecting = true
        wifiConnectProc.command = [
            Quickshell.shellPath("core/as-core"), "system-service",
            "wifi_connect", String(ssid), String(pwd || "")
        ]
        wifiConnectProc.running = true
    }

    function signalIconFor(sig, connected) {
        if (connected === false && Number(sig || 0) <= 0) return "wifi-none"
        const s = Number(sig || 0)
        if (s >= 75) return "wifi-full"
        if (s >= 50) return "wifi-high"
        if (s >= 25) return "wifi-medium"
        if (s > 0) return "wifi-low"
        // Connecté mais force inconnue (noyau sans /proc/net/wireless) : icône
        // « wifi » simple — jamais l'icône « déconnecté » alors qu'on est lié.
        return connected === true ? "wifi" : "wifi-none"
    }

    // ── Bluetooth ────────────────────────────────────────────────────────────
    property bool btPresent: false
    property bool btPowered: false
    property var btDevices: []
    property var btNearby: []
    property int btConnectedCount: 0
    property string btDevice: ""
    property bool btBusy: false
    property bool btScanning: false

    function _applyBtState(txt) {
        try {
            const d = JSON.parse(txt.trim())
            root.btPresent = d.present === true
            root.btPowered = Boolean(d.allume || d.powered)
            root.btDevices = Array.isArray(d.appaires) ? d.appaires : []
            if (!root.btPowered) {
                root.btNearby = []
            } else if (Array.isArray(d.a_portee)) {
                root.btNearby = d.a_portee
            }
            const conns = Array.isArray(d.connectes) ? d.connectes : []
            root.btConnectedCount = conns.length
            root.btDevice = conns.length > 0 ? String(conns[0].nom || conns[0].name || "") : ""
        } catch (e) {}
    }

    property Process btStateProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "bluetooth", "etat"]
        stdout: StdioCollector { onStreamFinished: root._applyBtState(text) }
    }

    property Process btActionProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.btBusy = false
                root.btScanning = false
                root._applyBtState(text)
            }
        }
        onExited: {
            root.btBusy = false
            root.btScanning = false
        }
    }

    function refreshBluetooth() {
        if (!btStateProc.running) btStateProc.running = true
    }

    function scanBluetooth() {
        if (btActionProc.running) return
        root.btScanning = true
        btCommand(["scanner"])
    }

    function btCommand(args) {
        if (btActionProc.running) return
        root.btBusy = true
        btActionProc.command = [Quickshell.shellPath("core/as-core"), "bluetooth"].concat(args)
        btActionProc.running = true
    }

    // ── Audio Bluetooth : profils (A2DP ↔ HFP), micro & bascule auto ─────────
    property var btAudioCards: []
    property var audioSinks: []
    property string defaultSinkName: ""
    property int volumePct: {
        const v = (systemInfo && systemInfo.volume && (systemInfo.volume.level !== undefined ? systemInfo.volume.level : systemInfo.volume.percent) !== undefined)
            ? Number(systemInfo.volume.level !== undefined ? systemInfo.volume.level : systemInfo.volume.percent) : 50
        return Math.max(0, Math.min(Theme.maxVolumePct, Math.round(v)))
    }
    property bool volumeMuted: Boolean(systemInfo && systemInfo.volume && systemInfo.volume.muted)
    property bool micMuted: false

    function _shortSinkLabel(name) {
        const s = String(name || "")
        if (s.indexOf("bluez_output") !== -1) return "Bluetooth"
        if (s.indexOf("hdmi") !== -1 || s.indexOf("HDMI") !== -1) return "HDMI"
        if (s.indexOf("usb") !== -1 || s.indexOf("USB") !== -1) return "USB Audio"
        if (s.indexOf("analog") !== -1 || s.indexOf("pci") !== -1) return "Haut-parleurs"
        return s.split(".").pop().slice(0, 14)
    }

    property Process audioSinksProc: Process {
        command: ["sh", "-c", "pactl get-default-sink 2>/dev/null; echo '---'; pactl list short sinks 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---\n")
                root.defaultSinkName = (parts[0] || "").trim()
                const lines = (parts[1] || "").trim().split("\n")
                const list = []
                for (let i = 0; i < lines.length; i++) {
                    const cols = lines[i].trim().split(/\s+/)
                    if (cols.length >= 2 && cols[1]) {
                        list.push({ name: cols[1], label: root._shortSinkLabel(cols[1]) })
                    }
                }
                root.audioSinks = list
            }
        }
    }

    property Process audioSinkSetProc: Process {
        onExited: root.refreshBtAudio()
    }

    property Process audioVolSetProc: Process {
        onExited: root.rafraichirSystemInfo()
    }

    function setDefaultSink(sinkName) {
        if (audioSinkSetProc.running) return
        root.defaultSinkName = String(sinkName)
        audioSinkSetProc.command = ["pactl", "set-default-sink", String(sinkName)]
        audioSinkSetProc.running = true
    }

    function setVolumePct(pct) {
        const v = Math.max(0, Math.min(Theme.maxVolumePct, Math.round(pct)))
        audioVolSetProc.command = ["wpctl", "set-volume", "-l", (Theme.maxVolumePct / 100).toFixed(1),
                                   "@DEFAULT_AUDIO_SINK@", (v / 100).toFixed(2)]
        audioVolSetProc.running = true
    }

    function toggleDefaultSinkMute() {
        audioVolSetProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        audioVolSetProc.running = true
    }

    function _labelProfilBt(id) {
        const s = String(id || "").toLowerCase()
        if (s.indexOf("a2dp") === 0) return "A2DP (Haute qualité)"
        if (s.indexOf("headset") === 0 || s.indexOf("hfp") !== -1 || s.indexOf("hsp") !== -1) return "HFP (Micro / Appel)"
        return id
    }

    property Process btCardsProc: Process {
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cards = []
                try {
                    const raw = JSON.parse(text.trim())
                    if (Array.isArray(raw)) {
                        for (let i = 0; i < raw.length; i++) {
                            const c = raw[i]
                            if (!c || String(c.name || "").indexOf("bluez_card.") !== 0) continue
                            const props = c.properties || ({})
                            const nom = String(props["device.alias"] || props["device.description"] || c.name)
                            const actif = String(c.active_profile || "")
                            const profObj = c.profiles || ({})
                            const profs = []
                            const keys = Object.keys(profObj)
                            for (let j = 0; j < keys.length; j++) {
                                const k = keys[j]
                                if (k === "off") continue
                                const p = profObj[k]
                                if (p && p.available === "no") continue
                                profs.push({ id: k, label: root._labelProfilBt(k), desc: String((p && p.description) || k) })
                            }
                            cards.push({ name: String(c.name), label: nom, activeProfile: actif, profiles: profs })
                        }
                    }
                } catch (e) {}
                root.btAudioCards = cards
            }
        }
    }

    property Process micStateProc: Process {
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: root.micMuted = text.indexOf("MUTED") >= 0
        }
    }

    property Process btProfileSetProc: Process {
        onExited: root.refreshBtAudio()
    }

    property Process micToggleProc: Process {
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]
        onExited: if (!micStateProc.running) micStateProc.running = true
    }

    function refreshBtAudio() {
        if (!btCardsProc.running) btCardsProc.running = true
        if (!micStateProc.running) micStateProc.running = true
        if (!audioSinksProc.running) audioSinksProc.running = true
    }

    function setBtCardProfile(cardName, profileId) {
        if (btProfileSetProc.running) return
        btProfileSetProc.command = ["pactl", "set-card-profile", String(cardName), String(profileId)]
        btProfileSetProc.running = true
    }

    function toggleDefaultMic() {
        if (!micToggleProc.running) micToggleProc.running = true
    }

    // Bascule automatique vers la sortie Bluetooth lorsqu'un casque se connecte
    property Timer btAutoSwitchDebounce: Timer {
        id: btAutoSwitchDebounce
        interval: 350
        repeat: false
        onTriggered: {
            if (!Theme.btAutoSwitchAudio) return
            if (!btAutoSwitchProc.running) btAutoSwitchProc.running = true
        }
    }

    property Process btSinkSubscribeProc: Process {
        id: btSinkSubscribeProc
        command: ["sh", "-c", "LC_ALL=C pactl subscribe 2>/dev/null | grep --line-buffered -E \"Event 'new' on sink\""]
        running: Theme.btAutoSwitchAudio
        stdout: SplitParser {
            onRead: _ => btAutoSwitchDebounce.restart()
        }
    }

    property Process btAutoSwitchProc: Process {
        id: btAutoSwitchProc
        command: ["sh", "-c", "s=$(pactl list short sinks 2>/dev/null | awk '/bluez_output\\./{print $2; exit}'); [ -n \"$s\" ] && pactl set-default-sink \"$s\" 2>/dev/null || true"]
        onExited: root.refreshBtAudio()
    }

    // ── Formatage partagé (USB / Hermes) ─────────────────────────────────────
    function formatBytes(o) {
        const go = Number(o || 0) / 1073741824
        if (go >= 1000) return (go / 1000).toFixed(1).replace(".", ",") + " To"
        if (go >= 1) return Math.round(go) + " Go"
        return Math.round(go * 1000) + " Mo"
    }

    function formatTokens(n) {
        n = Number(n) || 0
        if (n >= 1e6) return (n / 1e6).toFixed(1).replace(".", ",") + " M"
        if (n >= 1e3) return Math.round(n / 1e3) + " k"
        return String(n)
    }

    function formatDuration(s) {
        s = Number(s) || 0
        if (s < 60) return Math.round(s) + " s"
        const m = Math.floor(s / 60)
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60)
        return h + " h " + String(m % 60).padStart(2, "0")
    }

    // ── Lancement d'applications isolé (hors cgroup quickshell.service) ─────
    function launchInScope(shellCmd) {
        Quickshell.execDetached([
            "sh", "-c",
            'if command -v systemd-run >/dev/null 2>&1; then exec systemd-run --user --scope --quiet -- sh -c "$1"; else exec setsid sh -c "$1"; fi',
            "_", String(shellCmd)
        ])
    }

    // ── Icônes de zone de notification (core/tray_icons.json) ───────────────
    property var trayIconMap: ({})

    property FileView trayIconsFile: FileView {
        path: Quickshell.shellPath("core/tray_icons.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.trayIconMap = (parsed && typeof parsed === "object") ? parsed : ({})
            } catch (e) {
                root.trayIconMap = ({})
            }
        }
    }

    function trayIconFor(itemId) {
        if (!itemId) return ""
        const entry = (root.trayIconMap || ({}))[itemId]
        if (!entry) return ""
        const value = (typeof entry === "string") ? entry : (entry.icon || "")
        if (!value) return ""
        if (value.charAt(0) === "/")
            return "file://" + value
        return "file://" + Quickshell.shellPath("assets/tray/" + value)
    }

    // ── Variables d'application (core/app_vars.json) ────────────────────────
    property var appVars: ({})

    property FileView appVarsFile: FileView {
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.appVars = (parsed && typeof parsed === "object") ? parsed : ({})
            } catch (e) {
                root.appVars = ({})
            }
        }
    }

    function program(name) {
        return (root.appVars && root.appVars[name]) ? String(root.appVars[name]) : ""
    }

    // ── Démons et veilles d'arrière-plan (tray, xdg, thèmes, nuit) ──────────
    property Process trayWatchdogProc: Process {
        running: true
        command: [Quickshell.shellPath("core/as-core"), "tray-watchdog", "--interval", "10"]
    }

    property Process lienSystemeProc: Process {
        running: true
        command: [Quickshell.shellPath("core/as-core"), "lien-systeme", "--appliquer"]
    }

    property Process themesScanProc: Process {
        running: true
        command: [Quickshell.shellPath("core/as-core"), "themes-scan", "--sync"]
        onExited: Theme.relireCatalogue()
    }

    property Process themesVeilleProc: Process {
        running: true
        command: ["sh", Quickshell.shellPath("core/veille_themes.sh")]
        stdout: SplitParser {
            onRead: line => { if (line.indexOf(".colors") >= 0) themesDebounce.restart() }
        }
    }

    property Timer themesDebounce: Timer {
        interval: 600
        repeat: false
        onTriggered: {
            if (themesScanProc.running) return
            themesScanProc.running = true
        }
    }

    property var nuitEtat: ({})
    property Process nuitApplyProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "nuit", "appliquer"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && typeof d === "object") root.nuitEtat = d
                } catch (e) {}
            }
        }
    }

    property Timer nuitApplyTimer: Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (nuitApplyProc.running) return
            nuitApplyProc.running = true
        }
    }

    // ── Cache partagé des paires Popup ↔ Widget (USB, Todo, Hermes) ──────────
    property var usbData: ({})
    property Process usbPollProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "usb", "etat"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.usbData = (d.detail && d.detail.usb) ? d.detail.usb : d
                } catch (e) {
                    root.usbData = ({})
                }
            }
        }
    }
    function rafraichirUsb() {
        usbPollProc.running = false
        usbPollProc.running = true
    }

    property var todoData: ({})
    property Process todoPollProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "todo", "etat", "--options={\"fichier\": \"*\"}"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.todoData = (d.detail && d.detail.todo) ? d.detail.todo : d
                } catch (e) {
                    root.todoData = ({})
                }
            }
        }
    }
    function rafraichirTodo() {
        todoPollProc.running = false
        todoPollProc.running = true
    }

    property var hermesData: ({})
    property bool hermesCharge: false
    property Process hermesPollProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "hermes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.hermesData = (d.detail || ({})).hermes || ({})
                } catch (e) {
                    root.hermesData = ({})
                }
                root.hermesCharge = true
            }
        }
    }
    function rafraichirHermes() {
        hermesPollProc.running = false
        hermesPollProc.running = true
    }

    // ── Mises à jour système partagées (pacman / dnf / apt, évite les verrous) ──
    property string majGestionnaire: ""
    property int majNombre: 0
    property bool majPret: false
    property bool majActif: false

    onMajActifChanged: {
        if (majActif && majGestionnaire === "" && !majDetectProc.running) {
            majDetectProc.running = true
        }
    }

    property Process majDetectProc: Process {
        command: ["sh", "-c", "command -v pacman >/dev/null && echo arch; command -v dnf >/dev/null && echo dnf; command -v apt-get >/dev/null && echo apt"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lignes = text.trim().split("\n").map(function (s) { return s.trim() })
                for (let i = 0; i < lignes.length; ++i) {
                    if (lignes[i] === "arch" || lignes[i] === "dnf" || lignes[i] === "apt") {
                        root.majGestionnaire = lignes[i]
                        break
                    }
                }
                if (root.majGestionnaire !== "") root.verifierMaj()
            }
        }
    }

    property Process majVerifProc: Process {
        command: ["sh", "-c", root.majGestionnaire === "dnf"
                  ? "timeout 60 dnf -q check-update 2>/dev/null | grep -cE '^[A-Za-z0-9][A-Za-z0-9_.+-]*\\.'"
                  : (root.majGestionnaire === "apt"
                     ? "timeout 20 apt-get -s upgrade 2>/dev/null | grep -c '^Inst '"
                     : "timeout 15 sh -c '(checkupdates 2>/dev/null; yay -Qua 2>/dev/null)' | grep -v '^[[:space:]]*$' | wc -l")]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10)
                root.majNombre = isNaN(n) ? 0 : n
                root.majPret = true
            }
        }
    }

    property Timer majTimer: Timer {
        interval: 300000
        repeat: true
        running: root.majActif && root.majGestionnaire !== ""
        onTriggered: root.verifierMaj()
    }

    function verifierMaj() {
        if (root.majGestionnaire === "" || majVerifProc.running) return
        majVerifProc.running = true
    }

    function lancerMaj() {
        if (root.majGestionnaire === "dnf")
            Quickshell.execDetached(["bash", Quickshell.shellPath("core/maj_terminal.sh"), "sudo dnf upgrade --refresh"])
        else if (root.majGestionnaire === "apt")
            Quickshell.execDetached(["bash", Quickshell.shellPath("core/maj_terminal.sh"), "sudo apt update && sudo apt upgrade"])
        else
            Quickshell.execDetached(["bash", Quickshell.shellPath("core/maj_terminal.sh"), "arch-update"])
    }
}
