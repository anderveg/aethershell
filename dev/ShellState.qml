pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root

    // ──────────────────────────────────────────────────────────────────────────
    // SUBMAP HYPRLAND & HOOKS SHELL/IPC
    // ──────────────────────────────────────────────────────────────────────────
    property string activeSubmap: ""

    function setSubmap(name) {
        if (Hyprland.usingLua !== false) {
            Hyprland.dispatch('hl.dsp.submap("' + name + '")')
        } else {
            Hyprland.dispatch("submap " + name)
        }
    }

    signal wallpaperNavRequested(string action)
    signal themeNavRequested(string action)
    signal islandNavRequested(string action)
    signal placeWidgetRequested()
    signal resizeWidgetRequested()
    signal widgetMenuRequested(string widgetId)
    signal captureRequested(string mode)

    // ──────────────────────────────────────────────────────────────────────────
    // NOTIFICATIONS (état partagé + crochets IPC)
    // ──────────────────────────────────────────────────────────────────────────
    property int notifCount: 0
    property var quietNotifApps: []
    property bool doNotDisturb: false
    property var notifList: []
    property var notifArchive: []
    property var notifOps: ({})
    property var notifToast: null
    property bool notifToastVisible: false
    property bool notifToastHovered: false
    property bool notifHistoryVisible: false
    property var notifProvider: null

    // ──────────────────────────────────────────────────────────────────────────
    // FOND D'ÉCRAN COURANT PARTAGÉ (awww query)
    // ──────────────────────────────────────────────────────────────────────────
    property string wallpaperCourant: ""
    property double wallpaperLockUntil: 0

    function setWallpaperCourant(path) {
        if (!path) return
        root.wallpaperLockUntil = Date.now() + 4500
        root.wallpaperCourant = String(path)
    }

    property Process wallpaperSondeProc: Process {
        command: ["awww", "query"]
        running: Theme.depthWallpaper || Theme.depthMask || Theme.wallpaperSlide
        stdout: StdioCollector {
            onStreamFinished: {
                if (Date.now() < root.wallpaperLockUntil) return
                const m = String(text).match(/currently displaying:.*?(?:image|video):\s*(\S+)/)
                if (m) root.wallpaperCourant = m[1]
            }
        }
    }

    function rafraichirWallpaper() {
        if (Date.now() < root.wallpaperLockUntil) return
        if (!wallpaperSondeProc.running) wallpaperSondeProc.running = true
    }

    property Timer wallpaperSondeTimer: Timer {
        interval: 2500
        repeat: true
        running: Theme.depthWallpaper || Theme.depthMask || Theme.wallpaperSlide
        triggeredOnStart: true
        onTriggered: root.rafraichirWallpaper()
    }

    // ──────────────────────────────────────────────────────────────────────────
    // OSD (ON-SCREEN DISPLAY)
    // ──────────────────────────────────────────────────────────────────────────
    property bool osdVisible: false
    property string osdKind: ""     // "volume" | "brightness" | "mute"
    property real osdValue: 0       // 0..100
    readonly property string osdGlyph: osdKind === "brightness" ? "brightness"
        : osdKind === "mute" ? "volume-off"
        : (osdValue <= 0 ? "mute" : osdValue < 50 ? "volume-medium" : "volume-high")
    readonly property string osdLabel: osdKind === "brightness" ? "Luminosité"
        : osdKind === "mute" ? "Micro coupé"
        : (osdValue <= 0 ? "Volume coupé" : "Volume")
    readonly property string osdPercent: Math.round(osdValue) + "%"
    signal volumeUpdated()

    property Connections hyprEvents: Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (Theme.activePopup !== "") Theme.activePopup = ""
        }
        function onRawEvent(event) {
            if (event && event.name === "submap") {
                root.activeSubmap = String(event.data || "").trim()
            }
        }
    }

    property Timer osdTimer: Timer {
        interval: 1600
        repeat: false
        onTriggered: root.osdVisible = false
    }

    function showOsd(kind, value) {
        root.osdKind = kind
        root.osdValue = Math.max(0, Math.min(100, value))
        root.osdVisible = true
        root.osdTimer.restart()
        if (kind === "volume") root.volumeUpdated()
    }

    // ──────────────────────────────────────────────────────────────────────────
    // WIDGETS DE BUREAU (core/widgets.json)
    // ──────────────────────────────────────────────────────────────────────────
    property var widgets: []

    property FileView widgetsFile: FileView {
        path: Quickshell.shellPath("core/widgets.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.widgets = Array.isArray(parsed.widgets) ? parsed.widgets : []
            } catch (e) {
                console.warn("ShellState.qml: Failed to parse core/widgets.json:", e)
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // REGISTRE DES APPLETS DE BARRE (bar_applets.json + applets_catalogue.json)
    // ──────────────────────────────────────────────────────────────────────────
    property var barAppletsCatalogue: []
    property var barAppletsActifs: ({})
    property int barAppletsRev: 0
    property real ilotWidth: 160

    readonly property var barAnciens: ({
        "gauche": "haut:debut", "centre": "haut:milieu", "droite": "haut:fin",
        "haut-gauche": "haut:debut", "haut-centre": "haut:milieu", "haut-droite": "haut:fin",
        "bas": "bas:milieu",
        "cote-gauche": "cote-gauche:milieu",
        "cote-droite": "cote-droite:milieu"
    })

    property FileView appletsCatalogueFile: FileView {
        path: Quickshell.shellPath("core/applets_catalogue.json")
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.barAppletsCatalogue = (d && Array.isArray(d.applets)) ? d.applets : []
                root.barAppletsRev++
            } catch (e) {
                root.barAppletsCatalogue = []
            }
        }
    }

    property FileView barAppletsFile: FileView {
        path: Quickshell.shellPath("core/bar_applets.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                const rawActifs = (d && typeof d.actifs === "object" && d.actifs) ? d.actifs : ({})
                const normActifs = ({})
                for (const cle in rawActifs) {
                    const item = Object.assign({}, rawActifs[cle])
                    if (item.ile && root.barAnciens[item.ile]) {
                        item.ile = root.barAnciens[item.ile]
                    }
                    normActifs[cle] = item
                }
                root.barAppletsActifs = normActifs
                root.barAppletsRev++
            } catch (e) {
                root.barAppletsActifs = ({})
            }
        }
    }

    function buildAppletEntry(cat, choix, itemIle) {
        const entree = Object.assign({}, cat)
        entree.actif = true
        entree.ile = itemIle
        const ordre = parseInt(choix.ordre, 10)
        entree.ordre = isNaN(ordre) ? (cat.ordre || 100) : ordre
        const echelle = parseInt(choix.text_scale, 10)
        entree.text_scale = isNaN(echelle) ? 100 : Math.max(60, Math.min(160, echelle))
        entree.options = choix.options || ({})
        return entree
    }

    function sortApplets(liste) {
        const ord = Array.isArray(Theme.ilotAppletsOrder) ? Theme.ilotAppletsOrder : []
        liste.sort(function(a, b) {
            const ia = ord.indexOf(String(a.id || ""))
            const ib = ord.indexOf(String(b.id || ""))
            if (ia !== -1 && ib !== -1) return ia - ib
            if (ia !== -1) return -1
            if (ib !== -1) return 1
            const oa = (typeof a.ordre === "number") ? a.ordre : 100
            const ob = (typeof b.ordre === "number") ? b.ordre : 100
            if (oa !== ob) return oa - ob
            return String(a.id || "").localeCompare(String(b.id || ""))
        })
        return liste
    }

    function appletsPourIle(ile) {
        const _ = root.barAppletsRev
        if (!ile || !root.barAppletsCatalogue.length) return []
        const cible = root.barAnciens[ile] || ile
        const liste = []
        for (let i = 0; i < root.barAppletsCatalogue.length; i++) {
            const cat = root.barAppletsCatalogue[i]
            if (!cat || !cat.id || cat.fixe) continue
            const choix = root.barAppletsActifs[cat.id]
            if (!choix) continue

            let itemIle = String(choix.ile || cat.ile || "haut:fin")
            itemIle = root.barAnciens[itemIle] || itemIle
            if (itemIle !== cible) continue

            liste.push(root.buildAppletEntry(cat, choix, itemIle))
        }
        return root.sortApplets(liste)
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CONTEXTES DE TRAVAIL (unifiés sur presets.json via EnvPresets)
    // ──────────────────────────────────────────────────────────────────────────
    readonly property string activeContext: EnvPresets.dernierApplique || "Normal"

    // Visibilité des widgets du bureau : persistée dans style_vars.json pour
    // qu'un profil d'environnement puisse l'enregistrer et la restaurer (même
    // mécanisme que le DND et la caféine).
    function setWidgetsBureauVisibles(v) {
        const b = Boolean(v)
        Theme.widgetsBureauVisibles = b
        Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "style",
                                 "widgets_bureau_visibles", b ? "true" : "false"])
    }

    function applyContext(ctxId) {
        const name = EnvPresets.resolveName(ctxId)
        if (!name) return false
        EnvPresets.apply(name)
        return true
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IPC HANDLER ("shell")
    // ──────────────────────────────────────────────────────────────────────────
    property IpcHandler ipc: IpcHandler {
        target: "shell"
        function placeWidget() {
            root.placeWidgetRequested()
        }
        function resizeWidget() {
            root.resizeWidgetRequested()
        }
        function openWidgetMenu(id: string) {
            root.widgetMenuRequested(id)
        }
        // Profils d'environnement : joignables en IPC pour tester l'application
        // sans passer par l'interface, et pour un futur raccourci clavier.
        function profilEnv(nom: string) {
            EnvPresets.apply(nom)
        }
        function profilsEnvListe() {
            EnvPresets.refresh()
        }
        // Profils de thème (lot B3) : mêmes raisons — vérifier sans souris, et
        // brancher plus tard un raccourci clavier par profil.
        function themeProfilsListe() {
            ThemeProfiles.refresh()
        }
        function themeProfilApplique(nom: string) {
            ThemeProfiles.apply(nom)
        }
        function themeProfilAppliqueIndex(idx: int) {
            ThemeProfiles.applyIndex(idx)
        }
        function themeProfilEnregistre(nom: string, modes: string) {
            ThemeProfiles.save(nom, modes)
        }
        function themeProfilAnnule() {
            ThemeProfiles.annuler()
        }
        function toggleConfig() {
            Theme.configPanelVisible = !Theme.configPanelVisible
        }
        function toggleMasqueParallaxe() {
            Theme.masqueParallaxeVisible = !Theme.masqueParallaxeVisible
        }
        function openConfigSection(section: string) {
            Theme.openConfigSection(section)
        }
        function setConfigButtonVisible(visible: bool) {
            Theme.showConfigButton = visible
        }
        function toggleConfigButton() {
            Theme.showConfigButton = !Theme.showConfigButton
        }
        function reloadTheme() {
            Theme.relireStyle()
        }
        function osd(kind: string, value: real) {
            root.showOsd(kind, value)
        }
        function togglePopup(name: string) {
            Theme.togglePopup(name)
        }
        function toggleIslandPanel() {
            if (Theme.barStyle !== "island") return
            Theme.activePopup = ""
            Theme.islandPanelOpen = !Theme.islandPanelOpen
            if (!Theme.islandPanelOpen) {
                Theme.islandSidePanel = ""
                Theme.islandNeedsKeyboard = false
            }
        }
        function openIslandPanel(tabIndex: int) {
            if (Theme.barStyle !== "island") return
            Theme.activePopup = ""
            const maxTab = Theme.ilotProjetsActif ? 4 : 3
            Theme.islandPanelTab = Math.max(0, Math.min(maxTab, tabIndex))
            Theme.islandPanelOpen = true
        }
        function nav(action: string): string {
            if (Theme.barStyle !== "island") return "not_island"
            const a = String(action || "").toLowerCase()
            if (a === "ouvrir" || a === "open") {
                Theme.activePopup = ""
                Theme.islandNavActive = true
                Theme.islandPanelOpen = true
                return "ok"
            }
            if (a === "fermer" || a === "close") {
                Theme.islandPanelOpen = false
                Theme.islandSidePanel = ""
                Theme.islandNeedsKeyboard = false
                Theme.islandNavActive = false
                return "ok"
            }
            if (!Theme.islandPanelOpen) {
                Theme.activePopup = ""
                Theme.islandPanelOpen = true
            }
            Theme.islandNavActive = true
            const nTabs = Theme.ilotProjetsActif ? 5 : 4
            if (a === "onglet_suiv" || a === "tab_next") {
                Theme.islandPanelTab = (Theme.islandPanelTab + 1) % nTabs
                return "ok"
            }
            if (a === "onglet_prec" || a === "tab_prev") {
                Theme.islandPanelTab = (Theme.islandPanelTab + nTabs - 1) % nTabs
                return "ok"
            }
            root.islandNavRequested(a)
            return "ok"
        }
        function navState(): bool {
            return Theme.islandNavActive
        }
        function toggleSpotlight() {
            if (Theme.barStyle === "island") {
                Theme.activePopup = ""
                Theme.islandPanelOpen = false
                Theme.wallpaperPickerOpen = false
                Theme.themePickerOpen = false
                Theme.islandNotesOpen = false
                Theme.islandLiveActivityOpen = false
                Theme.islandLauncherOpen = !Theme.islandLauncherOpen
            } else {
                Theme.spotlightVisible = !Theme.spotlightVisible
            }
        }
        function toggleNotes() {
            if (Theme.barStyle !== "island") return
            Theme.activePopup = ""
            Theme.islandPanelOpen = false
            Theme.wallpaperPickerOpen = false
            Theme.themePickerOpen = false
            Theme.islandLauncherOpen = false
            Theme.islandLiveActivityOpen = false
            Theme.islandNotesOpen = !Theme.islandNotesOpen
        }
        function toggleLiveActivity() {
            Theme.toggleLiveActivity()
        }
        function liveActivity(action: string, actId: string, title: string, progress: int): string {
            return LiveActivityStore.handleLiveActivity(action, actId, title, progress)
        }
        function liveActivityStart(actId: string, title: string, progress: int): string {
            return LiveActivityStore.handleLiveActivity("start", actId, title, progress)
        }
        function liveActivityUpdate(actId: string, progress: int, title: string): string {
            return LiveActivityStore.handleLiveActivity("update", actId, title, progress)
        }
        function liveActivityStop(actId: string): string {
            return LiveActivityStore.handleLiveActivity("stop", actId, "", -1)
        }
        function liveActivityClear(): string {
            return LiveActivityStore.handleLiveActivity("clear", "", "", -1)
        }
        function timerStart(minutes: int): string {
            LiveActivityStore.startTimer(minutes, "")
            return "ok"
        }
        function setContext(ctxId: string): string {
            return root.applyContext(ctxId) ? "ok" : "unknown_context"
        }
        function toggleCheatsheet() {
            Theme.cheatsheetVisible = !Theme.cheatsheetVisible
        }
        function toggleOverview() {
            Theme.overviewVisible = !Theme.overviewVisible
        }
        function toggleKeyboard() {
            TabletMode.toggleVirtualKeyboard()
        }
        function toggleWidgetEditMode() {
            Theme.widgetsEditMode = !Theme.widgetsEditMode
        }
        function toggleWallpaperPicker() {
            if (Theme.barStyle === "island") {
                Theme.activePopup = ""
                Theme.islandPanelOpen = false
                Theme.islandLauncherOpen = false
                Theme.islandNotesOpen = false
                Theme.themePickerOpen = false
                Theme.islandLiveActivityOpen = false
                Theme.wallpaperPickerOpen = !Theme.wallpaperPickerOpen
            } else {
                Quickshell.execDetached(["quickshell", "-n", "-p", Quickshell.env("HOME") + "/.config/quickshell/hyprquickpaper"])
            }
        }
        function toggleThemePicker() {
            if (Theme.barStyle === "island") {
                Theme.activePopup = ""
                Theme.islandPanelOpen = false
                Theme.islandLauncherOpen = false
                Theme.islandNotesOpen = false
                Theme.wallpaperPickerOpen = false
                Theme.islandLiveActivityOpen = false
                Theme.themePickerOpen = !Theme.themePickerOpen
            } else {
                Theme.openConfigSection("apparence_couleurs")
            }
        }
        function themeNav(action: string) {
            const a = String(action || "").toLowerCase()
            if (a === "close" || a === "fermer") {
                Theme.themePickerOpen = false
                return
            }
            root.themeNavRequested(a)
        }
        function wpNav(action: string) {
            const a = String(action || "").toLowerCase()
            if (a === "close" || a === "fermer") {
                Theme.wallpaperPickerOpen = false
                return
            }
            root.wallpaperNavRequested(a)
        }
        function showCheatsheet() {
            Theme.cheatsheetVisible = true
        }
        function hideCheatsheet() {
            Theme.cheatsheetVisible = false
        }
        function cheatsheetState(): bool {
            return Theme.cheatsheetVisible
        }
        function showSpotlight() {
            Theme.spotlightVisible = true
        }
        function hideSpotlight() {
            Theme.spotlightVisible = false
        }
        function spotlightState(): bool {
            return Theme.spotlightVisible
        }
        function launchHistoryState(): bool {
            return Theme.launchHistory
        }
        function toggleScreenshotPicker() {
            Theme.screenshotPickerVisible = !Theme.screenshotPickerVisible
        }
        function showScreenshotPicker() {
            Theme.screenshotPickerVisible = true
        }
        function hideScreenshotPicker() {
            Theme.screenshotPickerVisible = false
        }
        function screenshotPickerState(): bool {
            return Theme.screenshotPickerVisible
        }
        function captureMode(mode: string) {
            root.captureRequested(mode)
        }
        function notifTargets(): string {
            return root.notifProvider ? String(root.notifProvider.targetsJson()) : "[]"
        }
        function notifOpenLatest(): bool {
            return root.notifProvider ? Boolean(root.notifProvider.openLatest()) : false
        }
        function notifClear(): bool {
            return root.notifProvider ? Boolean(root.notifProvider.clearAll()) : false
        }
        function notifInvoke(actionId: string): bool {
            return root.notifProvider ? Boolean(root.notifProvider.invokeAction(actionId)) : false
        }
        function toggleNotifHistory() {
            root.notifHistoryVisible = !root.notifHistoryVisible
        }
        function showNotifHistory() {
            root.notifHistoryVisible = true
        }
        function hideNotifHistory() {
            root.notifHistoryVisible = false
        }
        function notifHistoryState(): bool {
            return root.notifHistoryVisible
        }
        function minimiser(): bool {
            return MinimizedWindows.minimiserFenetre("")
        }
        function rappelerDerniere(): bool {
            return MinimizedWindows.rappelerDerniere()
        }
        function rappelerFenetreAdresse(adresse: string) {
            return MinimizedWindows.rappelerFenetre(adresse)
        }
        function minimisees(): string {
            const liste = MinimizedWindows.fenetresMinimisees()
            const out = []
            for (let i = 0; i < liste.length; i++)
                out.push({ adresse: String(liste[i].address),
                           titre: String(liste[i].title || "") })
            return JSON.stringify(out)
        }
    }
}
