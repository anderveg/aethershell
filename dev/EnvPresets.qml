pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ════════════════════════════════════════════════════════════════════════════
// PROFILS D'ENVIRONNEMENT — ÉTAT PARTAGÉ (EnvPresets.qml)
//
// Pourquoi un singleton et pas des propriétés dans l'onglet : le contenu des
// onglets de l'îlot est monté par un Loader dont la `source` suit l'onglet
// courant, donc l'Item est DÉTRUIT à chaque changement d'onglet. Toute liste
// gardée là disparaissait (bug « le profil sauvegardé s'évapore »). Ici l'état
// survit aux onglets, et il est joignable en IPC pour tester/diagnostiquer.
//
// Un profil = style (25 clés) + widget + bloc `env` (DND, caféine, nuit,
// énergie, widgets du bureau). Le backend écrit style_vars.json et pilote les
// démons ; ce singleton aligne ensuite l'état QML sur ce qui a réellement été
// appliqué.
// ════════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    property var presets: []
    property string message: ""
    /// Dernier profil appliqué : sert à surligner la puce correspondante.
    property string dernierApplique: ""
    property var dernierEnv: ({})

    /// File d'attente : `apply` déclenche un `refresh` derrière, deux commandes
    /// ne doivent pas se marcher sur les pieds (un Process ne porte qu'une
    /// commande à la fois).
    property var file: []

    readonly property Process proc: Process {
        id: presetProc
        stdout: StdioCollector {
            onStreamFinished: root._traiter(text)
        }
        onExited: function (code, status) {
            if (code !== 0) root.message = "Profil : échec (code " + code + ")"
            root._lancerSuivant()
        }
    }

    property Timer effaceurMessage: Timer {
        interval: 4000
        repeat: false
        onTriggered: root.message = ""
    }

    // ── API ─────────────────────────────────────────────────────────────────
    Component.onCompleted: refresh()

    function refresh() {
        _pousser(["preset_list"])
    }

    function resolveName(query) {
        const raw = String(query || "").trim()
        if (!raw) return ""
        const q = raw.toLowerCase()
        const list = presets || []
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (p.name === raw || String(p.name || "").toLowerCase() === q) return p.name
            const aliases = p.aliases || []
            for (let j = 0; j < aliases.length; j++) {
                if (String(aliases[j] || "").toLowerCase() === q) return p.name
            }
        }
        return ""
    }

    function save(nom) {
        const n = String(nom || "").trim()
        if (!n) return
        annoncer("Profil « " + n + " » enregistré")
        _pousser(["preset_save", n])
    }

    function apply(nom) {
        const n = String(nom || "").trim()
        if (n) _pousser(["preset_apply", n])
    }

    function remove(nom) {
        _pousser(["preset_delete", String(nom)])
    }

    function annoncer(texte) {
        message = String(texte)
        effaceurMessage.restart()
    }

    // ── Interne ─────────────────────────────────────────────────────────────
    function _pousser(args) {
        const q = file.slice()
        q.push(args)
        file = q
        _lancerSuivant()
    }

    function _lancerSuivant() {
        if (presetProc.running || file.length === 0) return
        const args = file[0]
        const q = file.slice()
        q.shift()
        file = q
        presetProc.command = [Quickshell.shellPath("core/as-core"), "config"].concat(args)
        presetProc.running = true
    }

    function _traiter(texte) {
        let d = null
        try {
            d = JSON.parse(String(texte || "").trim())
        } catch (e) {
            return
        }
        if (!d) return
        if (Array.isArray(d.presets)) presets = d.presets
        if (d.message) annoncer(String(d.message))
        if (d.applied) {
            dernierApplique = String(d.applied)
            dernierEnv = d.env || ({})
            annoncer("Profil « " + d.applied + " » appliqué"
                     + (d.env_v2 === false
                        ? " — modes remis au repos, ce profil ne les enregistre pas (⟳ pour les ajouter)"
                        : ""))
            syncEnv(d.env)
            ConfigStore.refresh()
            // Relecture de la liste : `preset_apply` ne la renvoie pas, et le
            // profil appliqué vient peut-être d'être modifié ailleurs.
            _pousser(["preset_list"])
        }
    }

    /// Aligne les états qui vivent côté QML sur le bloc `env` appliqué.
    function syncEnv(env) {
        if (!env) return
        if (typeof env.caffeine_actif === "boolean")
            SystemServices.caffeineActif = env.caffeine_actif
        if (typeof env.do_not_disturb === "boolean")
            ShellState.doNotDisturb = env.do_not_disturb
        if (typeof env.widgets_bureau_visibles === "boolean")
            Theme.widgetsBureauVisibles = env.widgets_bureau_visibles
    }
}
