pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Porte d'entrée unique vers le backend `as-core` : centralise le chemin du
// binaire, l'exécution, la lecture JSON et la journalisation des erreurs.
QtObject {
    id: root

    readonly property string binaire: Quickshell.shellPath("core/as-core")

    property Component procFactory: Component {
        Process {
            id: p
            property var onDone: null
            property string outText: ""
            property string errText: ""
            property string cmdLabel: ""

            stdout: StdioCollector {
                onStreamFinished: p.outText = text
            }
            stderr: StdioCollector {
                onStreamFinished: p.errText = text
            }
            onExited: code => {
                if (code !== 0) {
                    console.warn("as-core", p.cmdLabel, "exit=" + code, p.errText.trim())
                }
                if (p.onDone) {
                    try {
                        p.onDone(code, p.outText, p.errText)
                    } catch (e) {
                        console.warn("as-core callback", p.cmdLabel, e)
                    }
                }
                p.destroy()
            }
        }
    }

    function call(cmd, args, onOk, onErr) {
        const argv = [root.binaire, String(cmd || "")]
        const list = Array.isArray(args) ? args : []
        for (let i = 0; i < list.length; ++i) {
            argv.push(String(list[i]))
        }
        const obj = procFactory.createObject(root, {
            command: argv,
            cmdLabel: String(cmd || ""),
            onDone: function(code, outText, errText) {
                if (code === 0) {
                    if (onOk) onOk(outText, code)
                } else if (onErr) {
                    onErr(errText.trim(), code, outText)
                }
            },
            running: true
        })
        if (!obj) {
            console.warn("as-core", cmd, "échec création Process")
            if (onErr) onErr("process creation failed", -1, "")
        }
    }

    function json(cmd, args, onOk, onErr) {
        call(cmd, args, function(outText, code) {
            const s = String(outText || "").trim()
            if (s === "") {
                console.warn("as-core JSON vide:", cmd)
                if (onErr) onErr("empty json", code, outText)
                return
            }
            try {
                const data = JSON.parse(s)
                if (onOk) onOk(data)
            } catch (e) {
                console.warn("as-core JSON invalide:", cmd, e, s.slice(0, 120))
                if (onErr) onErr(String(e), code, outText)
            }
        }, onErr)
    }
}
