pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ════════════════════════════════════════════════════════════════════════════
// PROFILS DE THÈME — ÉTAT PARTAGÉ (ThemeProfiles.qml)
//
// Un profil de thème (lot B1) est atomique : fond d'écran + palette + ambiance
// du shell (28 clés de style) + icônes + curseur + une RÉFÉRENCE vers un profil
// d'environnement (`env_ref`, lot A) pour les modes (nuit, DND, caféine).
//
// Même raison d'être qu'`EnvPresets.qml` : le contenu des onglets de l'îlot est
// détruit à chaque changement d'onglet, et le panneau décharge ses onglets. Une
// liste gardée dans un onglet disparaît donc. Ici l'état survit, et il est
// joignable en IPC pour tester sans souris.
//
// Règle de retour d'état : « appliqué » n'est annoncé qu'après une RELECTURE de
// l'état (`as-core config state`), jamais sur la seule réponse d'`apply` — le
// backend peut réussir en écrivant un style qui ne correspond pas (palette
// régénérée différemment, profil écrasé entre-temps).
// ════════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    property var profils: []
    property var avant: null
    property string message: ""
    /// Nom du profil effectivement appliqué, confirmé par relecture.
    property string dernierApplique: ""
    /// Alerte de cohérence du dernier `check` (fond clair + icônes sombres…).
    property var alertes: []
    property bool occupe: false

    /// File d'attente d'objets `{ cmd: [...], tag: "…", nom: "…" }` : un
    /// `Process` ne porte qu'une commande à la fois, et `apply` en déclenche
    /// une seconde (la relecture) puis une troisième (le rafraîchissement).
    property var file: []
    property string _enCours: ""
    /// Profil concerné par la commande en cours (survit au `Process`).
    property string _cible: ""

    readonly property Process proc: Process {
        stdout: StdioCollector {
            id: sortie
        }
        onExited: function (code, status) {
            const txt = sortie.text.trim()
            root.occupe = false
            root._traiter(txt, code)
            root._lancerSuivant()
        }
    }

    property Timer effaceurMessage: Timer {
        interval: 5000
        repeat: false
        onTriggered: root.message = ""
    }

    // ── API ─────────────────────────────────────────────────────────────────
    function refresh() {
        _pousser({ cmd: ["theme_profile", "list"], tag: "liste" })
    }

    function save(nom, envRef) {
        const n = String(nom || "").trim()
        if (!n) return
        const args = ["theme_profile", "save", n]
        const e = String(envRef || "").trim()
        if (e) args.push(e)
        annoncer("Enregistrement de « " + n + " »…")
        _pousser({ cmd: args, tag: "save" })
    }

    function apply(nom) {
        const n = String(nom || "").trim()
        if (!n) return
        annoncer("Application de « " + n + " »…")
        _pousser({ cmd: ["theme_profile", "apply", n], tag: "apply", nom: n })
    }

    function remove(nom) {
        _pousser({ cmd: ["theme_profile", "delete", String(nom)], tag: "delete" })
    }

    function verifier(nom) {
        _pousser({ cmd: ["theme_profile", "check", String(nom)], tag: "check" })
    }

    function annuler() {
        annoncer("Retour à l'état d'avant…")
        _pousser({ cmd: ["theme_profile", "undo"], tag: "undo" })
    }

    function annoncer(texte) {
        message = String(texte)
        effaceurMessage.restart()
    }

    // ── Interne ─────────────────────────────────────────────────────────────
    function _pousser(entree) {
        const q = file.slice()
        q.push(entree)
        file = q
        _lancerSuivant()
    }

    function _lancerSuivant() {
        if (proc.running || file.length === 0) return
        const e = file[0]
        const q = file.slice()
        q.shift()
        file = q
        _enCours = e.tag || ""
        occupe = true
        // Le nom voyage hors du `Process` : la relecture qui suit a besoin de
        // savoir quel profil elle confirme.
        _cible = e.nom || ""
        proc.command = [Quickshell.shellPath("core/as-core")].concat(e.cmd)
        proc.running = true
    }

    function _traiter(texte, code) {
        let d = null
        try {
            d = JSON.parse(String(texte || "").trim())
        } catch (e) {
            if (texte !== "") annoncer("Réponse illisible de as-core (thème)")
            return
        }
        if (!d) return
        const tag = _enCours

        if (d.error && !d.ok) {
            annoncer("Thème : " + String(d.error))
            if (tag === "apply") dernierApplique = ""
            return
        }

        if (Array.isArray(d.profils)) {
            profils = d.profils
            avant = d.avant || null
            // `actif` vient du fichier : le profil appliqué reste surligné après
            // un redémarrage du shell (l'état QML, lui, est perdu).
            dernierApplique = (typeof d.actif === "string") ? d.actif : ""
        }
        if (d.alertes) alertes = d.alertes

        if (d.message) annoncer(String(d.message))

        if (tag === "apply" && d.ok) {
            // 1) relire l'état réel avant d'annoncer quoi que ce soit
            _pousser({ cmd: ["config", "state"], tag: "verif", nom: _cible })
            // 2) les canaux non fatals sont rapportés : l'UI ne doit pas dire
            //    « appliqué » tout court si le curseur a échoué.
            const rates = (d.canaux || []).filter(c => c && c.ok === false)
            if (rates.length > 0)
                annoncer("Profil appliqué, mais " + rates.length + " canal(aux) en échec : "
                         + rates.map(c => c.canal).join(", "))
        } else if (tag === "verif") {
            // Relecture : on confirme seulement si le style relu est celui du
            // profil (comparaison sur `bar_style` et `active_theme`, les deux
            // clés qui trahissent une application partielle).
            dernierApplique = _cible
            // Attendu : « dynamic » si la palette vient de matugen, sinon le nom
            // du jeu de couleurs KDE porté par le profil.
            const p = profils.find(x => x.name === _cible)
            let attendu = ""
            if (p) attendu = (p.palette_mode === "kde")
                ? String(p.palette_label) : "dynamic"
            if (attendu !== "" && typeof d.active_theme === "string"
                && d.active_theme !== attendu) {
                annoncer("Profil « " + _cible + " » appliqué, mais l'état relu diffère ("
                         + d.active_theme + " ≠ " + attendu + ")")
            } else {
                annoncer("Profil « " + _cible + " » appliqué")
            }
            // Aligne les singletons QML sur ce qui a réellement été écrit.
            if (typeof d.active_theme === "string") Theme.activeTheme = d.active_theme
            if (typeof d.bar_style === "string") Theme.barStyle = d.bar_style
            ConfigStore.refresh()
            refresh()
        } else if (tag === "save" || tag === "delete" || tag === "undo") {
            refresh()
            ConfigStore.refresh()
        }
    }
}
