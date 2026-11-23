pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Module profond de gestion du mode tablette (état matériel, verrou de rotation,
// taille des icônes du lanceur tactile et clavier virtuel intégré).
Scope {
    id: root

    property bool active: false
    property bool rotationLocked: false
    property bool launcherOpen: false
    property bool keyboardOpen: false
    property int launcherIconSize: 80

    signal launcherKeyInjected(string keyText, string keySpec)

    function sendLauncherKey(keyText, keySpec) {
        root.launcherKeyInjected(String(keyText || ""), String(keySpec || ""))
    }

    onActiveChanged: {
        if (!active) root.keyboardOpen = false
    }

    onLauncherOpenChanged: {
        if (!launcherOpen) root.keyboardOpen = false
    }

    readonly property string _runtimeDir: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR")
        if (xdg && String(xdg) !== "") return String(xdg) + "/quickshell-session"
        return String(Quickshell.env("HOME") || "/tmp") + "/.cache/quickshell"
    }

    FileView {
        id: modeFile
        path: root._runtimeDir + "/tablet_mode"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.active = (text().trim() === "tablet")
        }
        onLoadFailed: root.active = false
    }

    FileView {
        id: lockFile
        path: root._runtimeDir + "/tablet_rotation_lock"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.rotationLocked = (text().trim() === "1")
        }
        onLoadFailed: root.rotationLocked = false
    }

    FileView {
        id: kbdFile
        path: root._runtimeDir + "/tablet_kbd_open"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const val = text().trim()
            if (val.indexOf("1") === 0) {
                root.keyboardOpen = true
            } else if (val.indexOf("0") === 0) {
                if (!root.launcherOpen) root.keyboardOpen = false
            }
        }
    }

    function toggleMode() {
        root.active = !root.active
        Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "tablet-mode", "toggle"])
    }

    function toggleRotationLock() {
        root.rotationLocked = !root.rotationLocked
        Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "tablet-mode", "lock-toggle"])
    }

    function toggleVirtualKeyboard() {
        root.keyboardOpen = !root.keyboardOpen
    }
}
