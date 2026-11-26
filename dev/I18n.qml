pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Dictionnaire i18n réactif (FR / EN / ES / DE) chargé depuis `core/i18n/*.json`.
// Le changement de `Theme.langue` recharge le dictionnaire actif et met à jour
// toutes les liaisons `I18n.t("...")` à chaud sans redémarrer Quickshell.
QtObject {
    id: root

    readonly property var languesDisponibles: [
        { code: "fr", label: "Français" },
        { code: "en", label: "English" },
        { code: "es", label: "Español" },
        { code: "de", label: "Deutsch" }
    ]

    readonly property string langueActive: {
        const l = String(Theme.langue || "fr").toLowerCase()
        if (l === "en" || l === "es" || l === "de") return l
        return "fr"
    }

    property var dictFr: ({})
    property var dictActif: ({})
    property int revision: 0

    property FileView frView: FileView {
        path: Quickshell.shellPath("core/i18n/fr.json")
        watchChanges: false
        onLoaded: {
            try {
                root.dictFr = JSON.parse(text())
                if (root.langueActive === "fr") root.dictActif = root.dictFr
                root.revision += 1
            } catch (e) {
                console.warn("I18n fr.json:", e)
            }
        }
    }

    property FileView actifView: FileView {
        path: root.langueActive === "fr"
            ? ""
            : Quickshell.shellPath("core/i18n/" + root.langueActive + ".json")
        watchChanges: false
        onLoaded: {
            try {
                root.dictActif = JSON.parse(text())
                root.revision += 1
            } catch (e) {
                console.warn("I18n " + root.langueActive + ".json:", e)
                root.dictActif = ({})
            }
        }
        onLoadFailed: err => {
            if (root.langueActive !== "fr") {
                console.warn("I18n chargement impossible:", root.langueActive, err)
            }
            root.dictActif = ({})
        }
    }

    onLangueActiveChanged: {
        if (langueActive === "fr") {
            dictActif = dictFr
            revision += 1
        }
    }

    function t(cle, vars) {
        const _ = root.revision
        const k = String(cle || "")
        if (k === "") return ""
        let val = root.dictActif[k]
        if (val === undefined || val === null || val === "") {
            val = root.dictFr[k]
        }
        let s = (val !== undefined && val !== null && val !== "") ? String(val) : k
        if (vars && typeof vars === "object") {
            const keys = Object.keys(vars)
            for (let i = 0; i < keys.length; ++i) {
                const vk = keys[i]
                s = s.split("{" + vk + "}").join(String(vars[vk]))
            }
        }
        return s
    }
}
