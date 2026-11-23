import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

// Zones tactiles de bord actives uniquement en mode tablette :
// - Haut (swipe ↓) : ouvre l'Îlot dynamique
// - Bas  (swipe ↑) : ouvre la grille d'applications TabletLauncher
// - Gauche (glisser ↕) : luminosité
// - Droite (glisser ↕) : volume
Scope {
    id: root
    required property var targetScreen

    // Bord haut → swipe bas pour déployer l'Îlot dynamique
    PanelWindow {
        screen: root.targetScreen
        visible: TabletMode.active
        anchors { top: true; left: true; right: true }
        implicitHeight: 22
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-tablet-edge-top"

        Rectangle {
            anchors.fill: parent
            color: "#01000000"

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                property real startY: 0
                property bool fired: false
                onPressed: mouse => { startY = mouse.y; fired = false }
                onPositionChanged: mouse => {
                    if (!fired && pressed && mouse.y - startY > 24) {
                        fired = true
                        if (TabletMode.launcherOpen) {
                            TabletMode.launcherOpen = false
                        } else if (Theme.barStyle === "island") {
                            Theme.islandPanelOpen = true
                        } else {
                            Theme.togglePopup("controls")
                        }
                    }
                }
            }
        }
    }

    // Bord bas → swipe haut pour ouvrir le lanceur d'applications tactile (hors coin bas-droite réservé au clavier)
    PanelWindow {
        screen: root.targetScreen
        visible: TabletMode.active && !TabletMode.launcherOpen && !TabletMode.keyboardOpen
        anchors { bottom: true; left: true; right: true }
        margins { right: 140 }
        implicitHeight: 24
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-tablet-edge-bottom"

        Rectangle {
            anchors.fill: parent
            color: "#01000000"

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                property real startY: 0
                property bool fired: false
                onPressed: mouse => { startY = mouse.y; fired = false }
                onPositionChanged: mouse => {
                    if (!fired && pressed && startY - mouse.y > 24) {
                        fired = true
                        TabletMode.launcherOpen = true
                    }
                }
            }
        }
    }

    // Bord gauche → balayage vers l'intérieur = capture d'écran ; glissement vertical = luminosité
    PanelWindow {
        screen: root.targetScreen
        visible: TabletMode.active
        anchors { left: true; top: true; bottom: true }
        margins { top: 80; bottom: 80 }
        implicitWidth: 36
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-tablet-edge-left"

        Rectangle {
            anchors.fill: parent
            color: "#01000000"

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                property real startX: 0
                property real startY: 0
                property real lastY: 0
                property bool swipeFired: false
                property bool verticalMode: false
                onPressed: mouse => {
                    startX = mouse.x
                    startY = mouse.y
                    lastY = mouse.y
                    swipeFired = false
                    verticalMode = false
                }
                onPositionChanged: mouse => {
                    if (!pressed || swipeFired) return
                    const dx = mouse.x - startX
                    const totalDy = Math.abs(mouse.y - startY)
                    if (!verticalMode && dx > 30 && dx > totalDy * 1.2) {
                        swipeFired = true
                        Theme.screenshotPickerVisible = true
                        return
                    }
                    if (!verticalMode && totalDy > 14 && totalDy > Math.abs(dx)) {
                        verticalMode = true
                    }
                    const dy = lastY - mouse.y
                    if (Math.abs(dy) >= 16) {
                        lastY = mouse.y
                        verticalMode = true
                        const cmd = dy > 0 ? "brightnessctl set 5%+" : "brightnessctl -n 5% set 5%-"
                        Quickshell.execDetached(["sh", "-c", cmd + " && \"" + Quickshell.shellPath("core/osd.sh") + "\" brightness"])
                    }
                }
            }
        }
    }

    // Bord droit → balayage vers l'intérieur = notes rapides ; glissement vertical = volume
    PanelWindow {
        screen: root.targetScreen
        visible: TabletMode.active
        anchors { right: true; top: true; bottom: true }
        margins { top: 80; bottom: 80 }
        implicitWidth: 36
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-tablet-edge-right"

        Rectangle {
            anchors.fill: parent
            color: "#01000000"

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                property real startX: 0
                property real startY: 0
                property real lastY: 0
                property bool swipeFired: false
                property bool verticalMode: false
                onPressed: mouse => {
                    startX = mouse.x
                    startY = mouse.y
                    lastY = mouse.y
                    swipeFired = false
                    verticalMode = false
                }
                onPositionChanged: mouse => {
                    if (!pressed || swipeFired) return
                    const dx = startX - mouse.x
                    const totalDy = Math.abs(mouse.y - startY)
                    if (!verticalMode && dx > 30 && dx > totalDy * 1.2) {
                        swipeFired = true
                        if (Theme.barStyle === "island") {
                            Theme.activePopup = ""
                            Theme.islandPanelOpen = false
                            Theme.islandLauncherOpen = false
                            Theme.islandNotesOpen = true
                        }
                        return
                    }
                    if (!verticalMode && totalDy > 14 && totalDy > Math.abs(dx)) {
                        verticalMode = true
                    }
                    const dy = lastY - mouse.y
                    if (Math.abs(dy) >= 16) {
                        lastY = mouse.y
                        verticalMode = true
                        const step = dy > 0 ? "5%+" : "5%-"
                        Quickshell.execDetached(["sh", "-c", "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ " + step + " && \"" + Quickshell.shellPath("core/osd.sh") + "\" volume"])
                    }
                }
            }
        }
    }

    // Coin inférieur droit → appui ou léger glissement = clavier virtuel
    PanelWindow {
        screen: root.targetScreen
        visible: TabletMode.active && !TabletMode.keyboardOpen && !TabletMode.launcherOpen
        anchors { right: true; bottom: true }
        implicitWidth: 140
        implicitHeight: 56
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-tablet-corner-kbd"

        Rectangle {
            anchors.fill: parent
            color: "#01000000"

            Rectangle {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    rightMargin: 12
                    bottomMargin: 10
                }
                width: 44
                height: 34
                radius: 12
                color: Qt.alpha(Theme.surfaceBg, 0.78)
                border.color: Qt.alpha(Theme.accent, 0.45)
                border.width: 1

                Icon {
                    anchors.centerIn: parent
                    glyph: "keyboard"
                    size: 18
                    color: Theme.fg
                }
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                property real startX: 0
                property real startY: 0
                property bool fired: false
                onPressed: mouse => {
                    startX = mouse.x
                    startY = mouse.y
                    fired = false
                }
                onPositionChanged: mouse => {
                    if (!fired && pressed && Math.hypot(mouse.x - startX, mouse.y - startY) > 10) {
                        fired = true
                        TabletMode.toggleVirtualKeyboard()
                    }
                }
                onClicked: {
                    if (!fired) {
                        fired = true
                        TabletMode.toggleVirtualKeyboard()
                    }
                }
            }
        }
    }
}
