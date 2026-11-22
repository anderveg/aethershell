pragma Singleton
import QtQuick
import Quickshell
import "."

// Registre unifié et placement par zones de l'Îlot dynamique (pilule, coins, panneau de config).
Scope {
    id: root

    readonly property var catalogue: [
        { id: "horloge",        label: "Horloge",              icone: "clock" },
        { id: "workspaces",     label: "Workspaces",           icone: "monitor" },
        { id: "systray",        label: "Systray",              icone: "widgets" },
        { id: "nuit",           label: "Mode nuit",            icone: "weather-night" },
        { id: "luminosite",     label: "Luminosité",           icone: "sun" },
        { id: "batterie",       label: "Batterie",             icone: "battery" },
        { id: "minimise",       label: "Minimisées",           icone: "window-minimize" },
        { id: "volume",         label: "Volume",               icone: "volume-high" },
        { id: "reseau",         label: "Wi-Fi / Réseau",       icone: "wifi" },
        { id: "notifications",  label: "Notifications",        icone: "bell" },
        { id: "maj",            label: "Mises à jour",         icone: "download" },
        { id: "todo",           label: "Tâches Todo",          icone: "check-circle" },
        { id: "meteo",          label: "Météo",                icone: "cloud" },
        { id: "presse-papiers", label: "Presse-papiers",       icone: "clipboard" },
        { id: "usb",            label: "USB",                  icone: "usb" },
        { id: "systeme",        label: "Système",              icone: "cpu" },
        { id: "comptes",        label: "Comptes LLM",          icone: "wallet" },
        { id: "ilot_media",     label: "Titre média en cours", icone: "music",   styleKey: "ilot_show_media" },
        { id: "ilot_planka",    label: "Échéance Kanban",      icone: "columns", styleKey: "ilot_show_planka" }
    ]

    readonly property var defaultIcons: ({
        "reseau": "wifi",
        "systray": "widgets",
        "nuit": "weather-night",
        "luminosite": "brightness",
        "batterie": "battery",
        "minimise": "monitor",
        "volume": "volume",
        "notifications": "bell",
        "maj": "download",
        "todo": "check",
        "meteo": "weather-cloud",
        "presse-papiers": "clipboard",
        "usb": "usb",
        "systeme": "cpu",
        "disques": "disque",
        "homelab": "speedometer",
        "comptes": "wallet",
        "hermes": "robot",
        "flotte": "rocket"
    })

    function iconFor(applet) {
        if (!applet) return "widgets"
        const ic = String(applet.icone || "")
        if (ic !== "") return ic
        return root.defaultIcons[String(applet.id || "")] || "widgets"
    }

    function styleKeyForId(id) {
        for (let i = 0; i < root.catalogue.length; ++i) {
            if (root.catalogue[i].id === id) return root.catalogue[i].styleKey || ""
        }
        return ""
    }

    function modeForItem(it) {
        if (it && it.styleKey === "ilot_show_media") return Theme.ilotShowMedia
        if (it && it.styleKey === "ilot_show_planka") return Theme.ilotShowPlanka
        return Theme.ilotAppletModeFor(it ? it.id : "")
    }

    function nextMode(cur) {
        if (cur === "compact") return "expanded"
        if (cur === "expanded") return "both"
        return "compact"
    }

    function modeShortLabel(cur) {
        if (cur === "compact") return "Repos"
        if (cur === "expanded") return "Étendu"
        return "2"
    }

    function zoneLabel(zoneCode) {
        if (zoneCode === "") return "Îlot (Pilule)"
        if (zoneCode === "top-left") return "Haut Gauche"
        if (zoneCode === "top-right") return "Haut Droite"
        if (zoneCode === "bottom-left") return "Bas Gauche"
        return "Bas Droite"
    }

    function _sideRankFor(id) {
        if (id === "workspaces") return 0
        if (id === "horloge") return 2
        if (id === "ilot_media") return 2
        if (id === "ilot_planka") return 4
        const catList = ShellState.barAppletsCatalogue || []
        const actifs = ShellState.barAppletsActifs || ({})
        const anciens = ShellState.barAnciens || ({})
        let catIle = "haut:fin"
        for (let i = 0; i < catList.length; ++i) {
            if (String(catList[i].id || "") === id) {
                catIle = String(catList[i].ile || "haut:fin")
                break
            }
        }
        const choix = actifs[id] || ({})
        let itemIle = String(choix.ile || catIle)
        itemIle = anciens[itemIle] || itemIle
        return itemIle === "haut:debut" ? 1 : 3
    }

    // Applets affichés dans la pilule centrale (state: "compact"|"expanded", side: "all"|"left"|"right").
    function appletsForPill(state, side) {
        const _ = ShellState.barAppletsRev + Theme.ilotAppletsRev
        const catList = ShellState.barAppletsCatalogue
        if (!catList || !catList.length) return []
        const liste = []
        for (let i = 0; i < catList.length; i++) {
            const cat = catList[i]
            if (!cat || !cat.id || cat.fixe) continue
            if (cat.id === "visualiseur" || cat.id === "workspaces" || cat.id === "horloge" || cat.id === "musique") continue
            if (Theme.ilotAppletCornerFor(cat.id) !== "") continue
            const mode = Theme.ilotAppletModeFor(cat.id)
            if (!Theme.ilotVisibleIn(mode, state)) continue

            const choix = ShellState.barAppletsActifs[cat.id] || ({})
            let itemIle = String(choix.ile || cat.ile || "haut:fin")
            itemIle = ShellState.barAnciens[itemIle] || itemIle
            if (side === "left" && itemIle !== "haut:debut") continue
            if (side === "right" && itemIle === "haut:debut") continue

            liste.push(ShellState.buildAppletEntry(cat, choix, itemIle))
        }
        return ShellState.sortApplets(liste)
    }

    // Applets détachés dans un coin d'écran ("top-left", "top-right", "bottom-left", "bottom-right").
    function appletsForCorner(corner) {
        const _ = ShellState.barAppletsRev + Theme.ilotAppletsRev
        const catList = ShellState.barAppletsCatalogue
        if (!corner || !catList || !catList.length) return []
        const liste = []
        for (let i = 0; i < catList.length; i++) {
            const cat = catList[i]
            if (!cat || !cat.id || cat.fixe) continue
            if (cat.id === "visualiseur" || cat.id === "musique") continue
            if (Theme.ilotAppletCornerFor(cat.id) !== corner) continue
            const mode = Theme.ilotAppletModeFor(cat.id)
            if (mode === "off") continue

            const choix = ShellState.barAppletsActifs[cat.id] || ({})
            let itemIle = String(choix.ile || cat.ile || "haut:fin")
            itemIle = ShellState.barAnciens[itemIle] || itemIle
            liste.push(ShellState.buildAppletEntry(cat, choix, itemIle))
        }
        return ShellState.sortApplets(liste)
    }

    // Liste d'entrées pour l'éditeur de zones (OngletIlot / IlotZoneColumn).
    function appletsInZone(zoneCode) {
        const _ = Theme.ilotAppletsRev + ShellState.barAppletsRev
        const order = Theme.ilotAppletsOrder || []
        const byId = ({})
        for (let i = 0; i < root.catalogue.length; ++i) {
            byId[root.catalogue[i].id] = root.catalogue[i]
        }
        const seen = ({})
        const out = []
        function pushIf(id) {
            if (seen[id] || !byId[id]) return
            seen[id] = true
            const it = byId[id]
            const mode = root.modeForItem(it)
            if (mode === "off") return
            const corner = it.styleKey ? "" : Theme.ilotAppletCornerFor(id)
            if (corner !== zoneCode) return
            out.push({ id: id, label: it.label, icone: it.icone, mode: mode, styleKey: it.styleKey || "" })
        }
        for (let i = 0; i < order.length; ++i) pushIf(String(order[i]))
        for (let i = 0; i < root.catalogue.length; ++i) pushIf(root.catalogue[i].id)
        if (zoneCode === "") {
            const idxMap = ({})
            for (let i = 0; i < out.length; ++i) idxMap[out[i].id] = i
            out.sort(function(a, b) {
                const sa = root._sideRankFor(a.id)
                const sb = root._sideRankFor(b.id)
                if (sa !== sb) return sa - sb
                return idxMap[a.id] - idxMap[b.id]
            })
        }
        return out
    }

    function inactiveApplets() {
        const _ = Theme.ilotAppletsRev
        const out = []
        for (let i = 0; i < root.catalogue.length; ++i) {
            const it = root.catalogue[i]
            if (root.modeForItem(it) === "off") out.push(it)
        }
        return out
    }
}
