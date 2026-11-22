pragma Singleton
import QtQuick
import Quickshell.Hyprland

// Fenêtres minimisées dans `special:minimized` (Hyprland).
QtObject {
    id: root

    readonly property string workspaceMinimise: "special:minimized"
    property var ordreMinimisees: []

    function cleAdresse(adresse) {
        let a = String(adresse || "").toLowerCase()
        if (a.indexOf("0x") === 0) a = a.substring(2)
        return a
    }

    function selecteurAdresse(adresse) {
        const a = root.cleAdresse(adresse)
        return a === "" ? "" : "address:0x" + a
    }

    function estMinimisee(fenetre) {
        if (!fenetre) return false
        const espace = fenetre.workspace
        if (espace) {
            const nom = String(espace.name || "")
            if (nom === root.workspaceMinimise || nom === "minimized") return true
            if (Number(espace.id) > 0) return false
        }
        const brut = fenetre.lastIpcObject
        const bws = brut ? brut.workspace : null
        return Boolean(bws) && String(bws.name || "") === root.workspaceMinimise
    }

    function fenetresMinimisees() {
        const out = []
        const tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (t && t.address && root.estMinimisee(t)) out.push(t)
        }
        const rang = function (adresse) {
            const i = root.ordreMinimisees.indexOf(root.cleAdresse(adresse))
            return i < 0 ? 1000 : i
        }
        out.sort(function (a, b) { return rang(a.address) - rang(b.address) })
        return out
    }

    function bureauCourant() {
        const ws = Hyprland.focusedWorkspace
        if (ws && Number(ws.id) > 0) return Number(ws.id)
        const m = Hyprland.focusedMonitor
        const actif = m ? m.activeWorkspace : null
        if (actif && Number(actif.id) > 0) return Number(actif.id)
        const liste = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (let i = 0; i < liste.length; i++) {
            if (liste[i] && Number(liste[i].id) > 0 && liste[i].active) return Number(liste[i].id)
        }
        return 0
    }

    function minimiserFenetre(adresse) {
        let cible = root.cleAdresse(adresse)
        if (cible === "" && Hyprland.activeToplevel)
            cible = root.cleAdresse(Hyprland.activeToplevel.address)
        if (Hyprland.usingLua) {
            const sel = cible !== "" ? ', window = "' + root.selecteurAdresse(cible) + '"' : ""
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + root.workspaceMinimise + '"'
                             + sel + ', follow = false })')
        } else {
            Hyprland.dispatch("movetoworkspacesilent " + root.workspaceMinimise
                              + (cible !== "" ? "," + root.selecteurAdresse(cible) : ""))
        }
        if (cible !== "" && root.ordreMinimisees.indexOf(cible) < 0) {
            const suite = root.ordreMinimisees.slice()
            suite.push(cible)
            root.ordreMinimisees = suite
        }
        return cible !== ""
    }

    function rappelerFenetre(adresse) {
        const cible = root.cleAdresse(adresse)
        const bureau = root.bureauCourant()
        if (cible === "" || bureau <= 0) return false
        const sel = root.selecteurAdresse(cible)
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + bureau
                             + ', window = "' + sel + '", follow = false })')
            Hyprland.dispatch('hl.dsp.focus({ window = "' + sel + '" })')
        } else {
            Hyprland.dispatch("movetoworkspacesilent " + bureau + "," + sel)
            Hyprland.dispatch("focuswindow " + sel)
        }
        const i = root.ordreMinimisees.indexOf(cible)
        if (i >= 0) {
            const suite = root.ordreMinimisees.slice()
            suite.splice(i, 1)
            root.ordreMinimisees = suite
        }
        return true
    }

    function rappelerDerniere() {
        const liste = root.fenetresMinimisees()
        if (liste.length === 0) return false
        return root.rappelerFenetre(String(liste[liste.length - 1].address))
    }
}
