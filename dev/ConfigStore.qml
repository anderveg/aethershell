pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Magasin unifié de configuration (`as-core config state` + file d'écriture séquentielle).
Scope {
    id: root

    signal todoAddedOk()

    property string hostName: "Machine"
    property bool isLaptop: false
    property string screenshotsDir: "$HOME/Images/Screenshots/"
    property string kbLayout: Theme.kbLayout || "fr"
    property var workspaceKeys: ["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft"]

    property int gapsIn: 2
    property int gapsOut: 8
    property int borderSize: 2
    property int hyprRounding: 2
    property real hyprRoundingPower: 2.0
    property var apiKeys: ({})
    property string homelabUrl: ""
    property string homelabTokenId: ""
    property string homelabTokenTail: ""
    property bool homelabTokenPresent: false

    property var todoFichiers: []
    property string todoFocus: ""
    property string todoErreur: ""
    property bool todoSurveillance: false

    property int nuitTemp: 4000
    property bool nuitAllumee: false
    property bool dndActif: false
    property string nuitDe: ""
    property string nuitA: ""
    property var llmProviders: []

    property var monitorsList: []
    property string selectedMonitorName: "HDMI-A-1"
    property string timezoneStr: "Europe/Paris"
    property bool ntpSynced: true
    property int idleSuspendTimeout: 3600
    property int screensaverTimeout: 900
    property string screensaverApp: "unimatrix"
    property bool screensaverRandomColors: false
    property string screensaverSpeed: "normal"
    property var screensaverApps: []

    property var bindsList: []
    property var widgetsList: []
    property string launcherPosition: "bas-centre"
    property var appVarsModel: []
    property var notifTargets: ({ "apps": ({}), "types": ({}), "url": "Browser" })
    property var autostartModel: []

    property string wallpaperDir: Theme.wallpaperDir || "$HOME/Images/wallpapers/"
    property string matugenScheme: "scheme-tonal-spot"
    property real matugenContrast: 0
    property bool blurEnabled: true
    property bool launchHistory: false
    property int blurSize: 3
    property int blurPasses: 3
    property real blurVibrancy: 0.17

    property bool shellBlurEnabled: true
    property bool barBorder: true
    property bool barGapsTransparent: false
    property int vizFps: 30
    property int vizCols: 96
    property real vizSensibilite: 1.0
    property real vizLissage: 0.2
    property real vizEpaisseur: 1.4
    property string vizCouleur: "accent"
    property string vizCouleurIsland: "complement"
    property string vizStyleClassic: "onde"
    property string vizStyleIsland: "barres"
    property real shellBlurAlpha: 0.4
    property bool shellBlurPopups: true
    property int resizeStep: 15
    property var panelSections: ({})

    property var cmdQueue: []

    function resumeChemin(chemin) {
        const s = String(chemin || "")
        return s.replace(/^\$HOME/, "~").replace(/\/$/, "")
    }

    function cheminAbsolu(chemin) {
        let s = String(chemin || "")
        if (s.indexOf("$HOME") === 0) s = Quickshell.env("HOME") + s.substring(5)
        else if (s.indexOf("~") === 0) s = Quickshell.env("HOME") + s.substring(1)
        return s.replace(/\/$/, "")
    }

    function abregerHome(chemin) {
        const home = Quickshell.env("HOME")
        const s = String(chemin || "")
        if (home && s.indexOf(home) === 0) {
            return "~" + s.substring(home.length)
        }
        return s
    }

    function sectionOpen(name, fallback) {
        if (root.panelSections && root.panelSections[name] !== undefined) {
            return Boolean(root.panelSections[name])
        }
        return fallback !== undefined ? Boolean(fallback) : true
    }

    function refresh() {
        if (!stateProc.running) stateProc.running = true
    }

    function _startCmd(args) {
        cmdProc.command = [Quickshell.shellPath("core/as-core"), "config"].concat(args)
        cmdProc.running = true
    }

    function runCmd(args) {
        if (!cmdProc.running) {
            _startCmd(args)
            return
        }
        const q = cmdQueue.slice()
        q.push(args)
        cmdQueue = q
    }

    function applyStateJson(data) {
        if (!data) return
        if (typeof data.hostname === "string" && data.hostname.length > 0) {
            root.hostName = data.hostname.charAt(0).toUpperCase() + data.hostname.slice(1)
        }
        if (typeof data.is_laptop === "boolean") root.isLaptop = data.is_laptop
        if (typeof data.kb_layout === "string") root.kbLayout = data.kb_layout
        if (typeof data.wallpaper_dir === "string" && data.wallpaper_dir.length > 0) root.wallpaperDir = data.wallpaper_dir
        if (typeof data.screenshots_dir === "string" && data.screenshots_dir.length > 0) root.screenshotsDir = data.screenshots_dir
        if (typeof data.matugen_scheme === "string" && data.matugen_scheme.length > 0) root.matugenScheme = data.matugen_scheme
        if (typeof data.matugen_contrast === "number") root.matugenContrast = data.matugen_contrast
        if (typeof data.blur_enabled === "boolean") root.blurEnabled = data.blur_enabled
        if (typeof data.blur_size === "number") root.blurSize = data.blur_size
        if (typeof data.blur_passes === "number") root.blurPasses = data.blur_passes
        if (typeof data.blur_vibrancy === "number") root.blurVibrancy = data.blur_vibrancy
        if (typeof data.shell_blur_enabled === "boolean") root.shellBlurEnabled = data.shell_blur_enabled
        if (typeof data.bar_border === "boolean") root.barBorder = data.bar_border
        if (typeof data.bar_gaps_transparent === "boolean") root.barGapsTransparent = data.bar_gaps_transparent
        if (typeof data.viz_fps === "number") root.vizFps = data.viz_fps
        if (typeof data.viz_cols === "number") root.vizCols = data.viz_cols
        if (typeof data.viz_sensibilite === "number") root.vizSensibilite = data.viz_sensibilite
        if (typeof data.viz_lissage === "number") root.vizLissage = data.viz_lissage
        if (typeof data.viz_epaisseur === "number") root.vizEpaisseur = data.viz_epaisseur
        if (typeof data.viz_couleur === "string") root.vizCouleur = data.viz_couleur
        if (typeof data.viz_couleur_island === "string") root.vizCouleurIsland = data.viz_couleur_island
        if (typeof data.viz_style_classic === "string") root.vizStyleClassic = data.viz_style_classic
        if (typeof data.viz_style_island === "string") root.vizStyleIsland = data.viz_style_island
        if (typeof data.shell_blur_alpha === "number") root.shellBlurAlpha = data.shell_blur_alpha
        if (typeof data.shell_blur_popups === "boolean") root.shellBlurPopups = data.shell_blur_popups
        if (typeof data.launch_history === "boolean") root.launchHistory = data.launch_history
        if (typeof data.resize_step === "number") root.resizeStep = data.resize_step
        if (data.panel_sections) root.panelSections = data.panel_sections
        if (Array.isArray(data.workspace_keys)) root.workspaceKeys = data.workspace_keys
        if (data.gaps) {
            if (typeof data.gaps.gaps_in === "number") root.gapsIn = data.gaps.gaps_in
            if (typeof data.gaps.gaps_out === "number") root.gapsOut = data.gaps.gaps_out
            if (typeof data.gaps.border_size === "number") root.borderSize = data.gaps.border_size
        }
        if (typeof data.hypr_rounding === "number") root.hyprRounding = data.hypr_rounding
        if (data.api_keys && typeof data.api_keys === "object") root.apiKeys = data.api_keys
        if (typeof data.do_not_disturb === "boolean") root.dndActif = data.do_not_disturb
        if (data.night && typeof data.night === "object") {
            if (typeof data.night.temperature === "number") root.nuitTemp = data.night.temperature
            root.nuitAllumee = data.night.mode === true
            root.nuitDe = String(data.night.from || "")
            root.nuitA = String(data.night.to || "")
        }
        if (data.homelab && typeof data.homelab === "object") {
            root.homelabUrl = String(data.homelab.proxmox_url || "")
            root.homelabTokenId = String(data.homelab.proxmox_token_id || "")
            root.homelabTokenTail = String(data.homelab.jeton_tail || "")
            root.homelabTokenPresent = data.homelab.jeton_present === true
        }
        if (data.todo && typeof data.todo === "object") {
            root.todoFichiers = Array.isArray(data.todo.fichiers) ? data.todo.fichiers : []
            root.todoFocus = String(data.todo.focus || "")
            root.todoSurveillance = Boolean(data.todo.surveillance)
            if (typeof data.todo.erreur === "string") {
                root.todoErreur = data.todo.erreur
                if (data.todo.erreur === "") root.todoAddedOk()
            }
        }
        if (Array.isArray(data.llm_providers)) root.llmProviders = data.llm_providers
        if (typeof data.hypr_rounding_power === "number") root.hyprRoundingPower = data.hypr_rounding_power
        if (data.display) {
            root.monitorsList = data.display.monitors || []
            if (root.monitorsList.length > 0) {
                let found = false
                for (let i = 0; i < root.monitorsList.length; i++) {
                    if (root.monitorsList[i].name === root.selectedMonitorName) {
                        found = true
                        break
                    }
                }
                if (!found) root.selectedMonitorName = root.monitorsList[0].name
            }
            if (data.display.timezone) root.timezoneStr = data.display.timezone
            if (typeof data.display.ntp === "boolean") root.ntpSynced = data.display.ntp
        }
        if (typeof data.idle_suspend_timeout === "number") root.idleSuspendTimeout = data.idle_suspend_timeout
        if (typeof data.screensaver_timeout === "number") root.screensaverTimeout = data.screensaver_timeout
        if (typeof data.screensaver_app === "string") root.screensaverApp = data.screensaver_app
        if (typeof data.screensaver_random_colors === "boolean") root.screensaverRandomColors = data.screensaver_random_colors
        if (typeof data.screensaver_speed === "string") root.screensaverSpeed = data.screensaver_speed
        if (Array.isArray(data.screensaver_apps)) root.screensaverApps = data.screensaver_apps
        if (Array.isArray(data.widgets)) root.widgetsList = data.widgets
        if (typeof data.launcher_position === "string") root.launcherPosition = data.launcher_position
        if (Array.isArray(data.binds)) root.bindsList = data.binds
        if (data.notif_targets && typeof data.notif_targets === "object") {
            const nt = data.notif_targets
            root.notifTargets = {
                "apps": (nt.apps && typeof nt.apps === "object") ? nt.apps : ({}),
                "types": (nt.types && typeof nt.types === "object") ? nt.types : ({}),
                "url": (typeof nt.url === "string") ? nt.url : "Browser"
            }
        }
        if (data.apps) {
            const arr = []
            for (const k in data.apps) arr.push({ alias: k, cmd: data.apps[k] })
            root.appVarsModel = arr
        }
        if (Array.isArray(data.autostart)) root.autostartModel = data.autostart
    }

    Process {
        id: stateProc
        command: [Quickshell.shellPath("core/as-core"), "config", "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyStateJson(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: cmdProc
        onExited: {
            if (root.cmdQueue.length > 0) {
                const q = root.cmdQueue.slice()
                const next = q.shift()
                root.cmdQueue = q
                root._startCmd(next)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.cmdQueue.length > 0) return
                try {
                    root.applyStateJson(JSON.parse(text.trim()))
                } catch (e) {
                    root.refresh()
                }
            }
        }
    }
}
