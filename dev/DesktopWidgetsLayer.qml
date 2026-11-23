import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Couche des widgets de bureau (`core/widgets.json`), mode placement et bandeau d'édition.
Item {
    id: root
    required property var targetScreen

    property var placingWindow: null
    property real placingX: 0
    property real placingY: 0
    property real placingGrabX: 0
    property real placingGrabY: 0
    property bool placingArmed: false
    readonly property bool placing: placingWindow !== null

    property var resizeTargetWindow: null
    property var resizingWindow: null
    property real resizingX: 0
    property real resizingY: 0
    property real resizingW: 0
    property real resizingH: 0
    property real resizingStartX: 0
    property real resizingStartY: 0
    property real resizingOrigX: 0
    property real resizingOrigY: 0
    property real resizingOrigW: 0
    property real resizingOrigH: 0
    property string resizingCorner: "br"
    property bool resizingArmed: false
    readonly property bool resizing: resizingWindow !== null
    property string findWidgetMode: "move"

    property var widgetWindows: []

    property string menuWidgetId: ""
    property real menuWidgetX: 0
    property real menuWidgetY: 0
    property real menuWidgetW: 0
    property real menuWidgetH: 0
    readonly property var menuWidget: {
        if (menuWidgetId === "") return ({})
        const l = ShellState.widgets || []
        for (let i = 0; i < l.length; ++i)
            if (String(l[i].id) === menuWidgetId) return l[i]
        return ({})
    }

    Connections {
        target: ShellState
        function onPlaceWidgetRequested() { root.startPlacementFromCursor() }
        function onResizeWidgetRequested() { root.startResizeFromCursor() }
        function onWidgetMenuRequested(id) {
            if (String(id) === "") { root.menuWidgetId = ""; return }
            for (let i = 0; i < root.widgetWindows.length; ++i) {
                const win = root.widgetWindows[i]
                if (!win || String(win.w.id) !== String(id)) continue
                root.menuWidgetX = Number(win.w.x) || 0
                root.menuWidgetY = Number(win.w.y) || 0
                root.menuWidgetW = win.implicitWidth
                root.menuWidgetH = win.implicitHeight
                root.menuWidgetId = String(id)
                return
            }
            const l = ShellState.widgets || []
            for (let i = 0; i < l.length; ++i) {
                if (String(l[i].id) !== String(id)) continue
                root.menuWidgetX = Number(l[i].x) || 0
                root.menuWidgetY = Number(l[i].y) || 0
                root.menuWidgetW = 0
                root.menuWidgetH = 0
                root.menuWidgetId = String(id)
                return
            }
        }
    }

    function widgetVisible(w) {
        if (!w || w.enabled === false) return false
        const brut = (w.workspaces && w.workspaces.length > 0)
            ? w.workspaces : [w.workspace]
        const liste = []
        for (let i = 0; i < brut.length; ++i) {
            const n = Number(brut[i])
            if (!isNaN(n)) liste.push(n)
        }
        if (liste.length === 0) return true
        if (liste.indexOf(0) >= 0) return true
        const ici = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : -1
        return liste.indexOf(ici) >= 0
    }

    function startPlacementFromCursor() {
        if (Theme.widgetsLocked) {
            if (placingWindow) endPlacement(false)
            return
        }
        if (resizingWindow) endResize(false)
        if (placingWindow) { endPlacement(false); return }
        findWidgetMode = "move"
        findWidgetProc.running = true
    }

    function startResizeFromCursor() {
        if (Theme.widgetsLocked) {
            if (resizingWindow) endResize(false)
            resizeTargetWindow = null
            return
        }
        if (placingWindow) endPlacement(false)
        if (resizingWindow) { endResize(false); return }
        if (resizeTargetWindow) { resizeTargetWindow = null; return }
        findWidgetMode = "resize"
        findWidgetProc.running = true
    }

    Process {
        id: findWidgetProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).trim().split(",")
                const cx = parseInt(parts[0], 10)
                const cy = parseInt(parts[1], 10)
                if (isNaN(cx) || isNaN(cy)) return
                for (let i = 0; i < root.widgetWindows.length; i++) {
                    const win = root.widgetWindows[i]
                    if (!win || !win.visible) continue
                    const wx = Number(win.w.x) || 0
                    const wy = Number(win.w.y) || 0
                    if (cx >= wx && cx <= wx + win.implicitWidth
                            && cy >= wy && cy <= wy + win.implicitHeight) {
                        if (root.findWidgetMode === "resize") {
                            root.resizeTargetWindow = (root.resizeTargetWindow === win) ? null : win
                        } else {
                            root.beginPlacement(win, cx - wx, cy - wy)
                        }
                        return
                    }
                }
            }
        }
    }

    function beginPlacement(win, grabX, grabY) {
        placingWindow = win
        placingGrabX = grabX
        placingGrabY = grabY
        placingX = Number(win.w.x) || 0
        placingY = Number(win.w.y) || 0
        placingArmed = false
        placementArmTimer.restart()
    }

    property string pendingMoveId: ""
    property real pendingX: 0
    property real pendingY: 0

    function endPlacement(commit) {
        if (commit && placingWindow) {
            const fx = Theme.widgetsSnapGrid ? Math.round(placingX / 32) * 32 : Math.round(placingX)
            const fy = Theme.widgetsSnapGrid ? Math.round(placingY / 32) * 32 : Math.round(placingY)
            pendingMoveId = String(placingWindow.w.id || "")
            pendingX = fx
            pendingY = fy
            moveWidget(placingWindow.w.id, fx, fy)
        }
        placingWindow = null
    }

    Timer {
        id: placementArmTimer
        interval: 220
        onTriggered: root.placingArmed = true
    }

    Process {
        id: moveWidgetProc
        onExited: pendingClearTimer.restart()
    }

    Timer {
        id: pendingClearTimer
        interval: 120
        onTriggered: root.pendingMoveId = ""
    }

    function moveWidget(id, x, y) {
        if (!id) return
        moveWidgetProc.command = [
            Quickshell.shellPath("core/as-core"), "config",
            "widget_move", String(id), String(Math.round(x)), String(Math.round(y))
        ]
        moveWidgetProc.running = true
    }

    property string pendingResizeId: ""
    property real pendingW: 0
    property real pendingH: 0

    function beginResize(win, startX, startY, corner) {
        const ox = Number(win.w.x) || 0
        const oy = Number(win.w.y) || 0
        const ow = win.implicitWidth
        const oh = win.implicitHeight
        resizingOrigX = ox
        resizingOrigY = oy
        resizingOrigW = ow
        resizingOrigH = oh
        resizingX = ox
        resizingY = oy
        resizingW = ow
        resizingH = oh
        resizingStartX = startX
        resizingStartY = startY
        resizingCorner = corner || "br"
        resizingArmed = false
        resizingWindow = win
        resizeArmTimer.restart()
    }

    function endResize(commit) {
        if (commit && resizingWindow) {
            const wid = String(resizingWindow.w.id || "")
            const fw = Math.max(110, Theme.widgetsSnapGrid ? Math.round(resizingW / 32) * 32 : Math.round(resizingW))
            const fh = Math.max(48, Theme.widgetsSnapGrid ? Math.round(resizingH / 32) * 32 : Math.round(resizingH))
            const hasLeft = resizingCorner.indexOf("l") >= 0
            const hasTop = resizingCorner.indexOf("t") >= 0
            const fx = hasLeft ? Math.max(0, Math.round(resizingOrigX + resizingOrigW - fw)) : Math.round(resizingOrigX)
            const fy = hasTop ? Math.max(0, Math.round(resizingOrigY + resizingOrigH - fh)) : Math.round(resizingOrigY)
            pendingResizeId = wid
            pendingW = fw
            pendingH = fh
            resizeWidget(wid, fw, fh)
            if (fx !== Math.round(resizingOrigX) || fy !== Math.round(resizingOrigY)) {
                pendingMoveId = wid
                pendingX = fx
                pendingY = fy
                moveWidget(wid, fx, fy)
            }
        }
        resizingWindow = null
    }

    Timer {
        id: resizeArmTimer
        interval: 220
        onTriggered: root.resizingArmed = true
    }

    Process {
        id: resizeWidgetProc
        onExited: pendingResizeClearTimer.restart()
    }

    Timer {
        id: pendingResizeClearTimer
        interval: 120
        onTriggered: root.pendingResizeId = ""
    }

    function resizeWidget(id, w, h) {
        if (!id) return
        resizeWidgetProc.command = [
            Quickshell.shellPath("core/as-core"), "config",
            "widget_resize", String(id), String(Math.round(w)), String(Math.round(h))
        ]
        resizeWidgetProc.running = true
    }

    Variants {
        model: ShellState.widgets

        PanelWindow {
            id: widgetWindow
            required property var modelData
            readonly property var w: modelData || ({})

            screen: root.targetScreen
            visible: Theme.widgetsBureauVisibles && root.widgetVisible(w)
            anchors { top: true; left: true }

            property bool dragging: false
            property real dragStartX: 0
            property real dragStartY: 0
            property real liveX: Number(w.x) || 0
            property real liveY: Number(w.y) || 0
            readonly property bool isPlacing: root.placingWindow === widgetWindow
            readonly property bool isPendingMove: root.pendingMoveId !== "" && root.pendingMoveId === String(w.id || "")
            margins.top: widgetWindow.isPlacing ? Math.round(root.placingY)
                       : (widgetWindow.isResizing ? Math.round(root.resizingY)
                       : (widgetWindow.isPendingMove ? Math.round(root.pendingY) : (Number(w.y) || 0)))
            margins.left: widgetWindow.isPlacing ? Math.round(root.placingX)
                        : (widgetWindow.isResizing ? Math.round(root.resizingX)
                        : (widgetWindow.isPendingMove ? Math.round(root.pendingX) : (Number(w.x) || 0)))
            readonly property int pad: 18
            readonly property bool hasOpacity: w.opacity !== undefined && w.opacity !== null
                                               && !isNaN(Number(w.opacity))
            readonly property real cardOpacity: hasOpacity
                ? Math.max(0, Math.min(1, Number(w.opacity))) : 0.35
            readonly property bool isTransparentStyle: String(w.style || "") === "transparent"
                || (!w.style && cardOpacity <= 0.01)
            readonly property bool isGlassStyle: !isTransparentStyle && cardOpacity > 0.01
            readonly property bool broken: widgetLoader.status === Loader.Error
            readonly property bool isResizeSelected: root.resizeTargetWindow === widgetWindow
            readonly property bool isResizing: root.resizingWindow === widgetWindow
            readonly property bool resizeActive: Theme.widgetsEditMode || isResizeSelected || isResizing
            readonly property bool isPendingResize: root.pendingResizeId !== "" && root.pendingResizeId === String(w.id || "")
            readonly property bool hasCustomSize: Number(w.w) > 0 && Number(w.h) > 0
            readonly property real targetW: isResizing ? root.resizingW
                : (isPendingResize ? root.pendingW : (hasCustomSize ? Number(w.w) : 0))
            readonly property real targetH: isResizing ? root.resizingH
                : (isPendingResize ? root.pendingH : (hasCustomSize ? Number(w.h) : 0))
            readonly property real contentW: broken ? brokenText.implicitWidth : widgetLoader.implicitWidth
            readonly property real contentH: broken ? brokenText.implicitHeight : widgetLoader.implicitHeight
            implicitWidth: targetW > 0 ? Math.max(110, targetW) : (contentW + pad * 2)
            implicitHeight: targetH > 0 ? Math.max(48, targetH) : (contentH + pad * 2)

            Component.onCompleted: {
                const list = root.widgetWindows.slice()
                list.push(widgetWindow)
                root.widgetWindows = list
            }
            Component.onDestruction: {
                const i = root.widgetWindows.indexOf(widgetWindow)
                if (i >= 0) {
                    const list = root.widgetWindows.slice()
                    list.splice(i, 1)
                    root.widgetWindows = list
                }
            }

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "shell-widget-" + (w.id || "x")

            Rectangle {
                id: carteWidget
                anchors.fill: parent
                clip: true
                radius: Theme.globalRadius
                color: (widgetWindow.isResizeSelected || widgetWindow.isResizing) ? Qt.alpha(Theme.accent, 0.08) : "transparent"
                border.width: widgetWindow.resizeActive ? 2 : ((widgetWindow.isTransparentStyle || widgetWindow.w.border === false) ? 0 : 1)
                border.color: widgetWindow.resizeActive ? Theme.accent : Qt.alpha(Theme.accent, 0.16)

                SurfaceFloutee {
                    anchors.fill: parent
                    visible: widgetWindow.isGlassStyle
                    rayon: Theme.globalRadius
                    teinte: Qt.alpha(Theme.surface, widgetWindow.cardOpacity)
                    bordureLargeur: 0
                    actif: widgetWindow.isGlassStyle
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.menuWidgetX = Number(widgetWindow.w.x) || 0
                        root.menuWidgetY = Number(widgetWindow.w.y) || 0
                        root.menuWidgetW = widgetWindow.implicitWidth
                        root.menuWidgetH = widgetWindow.implicitHeight
                        root.menuWidgetId = String(widgetWindow.w.id || "")
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    visible: Theme.widgetsEditMode
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.SizeAllCursor
                    onPressed: mouse => {
                        root.beginPlacement(widgetWindow,
                            (Number(widgetWindow.w.x) || 0) + mouse.x,
                            (Number(widgetWindow.w.y) || 0) + mouse.y)
                    }
                }

                Text {
                    id: brokenText
                    anchors.centerIn: parent
                    visible: widgetWindow.broken
                    text: "Widget « " + (widgetWindow.w.type || "?") + " » introuvable"
                    color: Qt.alpha(Theme.error, 0.9)
                    font.pixelSize: Theme.textXs
                }

                Loader {
                    id: widgetLoader
                    anchors.centerIn: parent
                    source: {
                        const t = widgetWindow.w.type
                        if (!t) return ""
                        const partages = ["deepseek", "ollama", "antigravity"]
                        return "widgets/" + (partages.indexOf(t) >= 0 ? "llm" : t) + ".qml"
                    }
                    onLoaded: {
                        if (item) {
                            item.options = widgetWindow.w.options || ({})
                            item.widgetId = widgetWindow.w.id || ""
                        }
                    }
                }

                Binding {
                    target: widgetLoader.item
                    property: "widgetW"
                    value: widgetWindow.targetW > 0 ? Math.max(40, widgetWindow.targetW - widgetWindow.pad * 2) : 0
                    when: widgetLoader.item !== null && ("widgetW" in widgetLoader.item)
                }

                Binding {
                    target: widgetLoader.item
                    property: "widgetH"
                    value: widgetWindow.targetH > 0 ? Math.max(24, widgetWindow.targetH - widgetWindow.pad * 2) : 0
                    when: widgetLoader.item !== null && ("widgetH" in widgetLoader.item)
                }

                Binding {
                    target: widgetLoader.item
                    property: "widgetResizing"
                    value: widgetWindow.resizeActive
                    when: widgetLoader.item !== null && ("widgetResizing" in widgetLoader.item)
                }

                Binding {
                    target: widgetLoader.item
                    property: "widgetOpacity"
                    value: widgetWindow.isTransparentStyle ? 0.18 : widgetWindow.cardOpacity
                    when: widgetLoader.item !== null && ("widgetOpacity" in widgetLoader.item)
                }

                Connections {
                    target: widgetWindow
                    function onWChanged() {
                        if (widgetLoader.item) {
                            widgetLoader.item.options = widgetWindow.w.options || ({})
                        }
                    }
                }

                Repeater {
                    model: widgetWindow.resizeActive ? 4 : 0
                    delegate: Rectangle {
                        id: cornerHandle
                        required property int index
                        readonly property bool isTop: index < 2
                        readonly property bool isLeft: index % 2 === 0
                        readonly property string cornerCode: (isTop ? "t" : "b") + (isLeft ? "l" : "r")
                        z: 12
                        width: 12
                        height: 12
                        radius: 4
                        color: cornerMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.85)
                        anchors.top: isTop ? parent.top : undefined
                        anchors.bottom: !isTop ? parent.bottom : undefined
                        anchors.left: isLeft ? parent.left : undefined
                        anchors.right: !isLeft ? parent.right : undefined
                        anchors.margins: 1

                        MouseArea {
                            id: cornerMa
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: (cornerHandle.index === 0 || cornerHandle.index === 3)
                                ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                            onPressed: mouse => {
                                const wx = Number(widgetWindow.w.x) || 0
                                const wy = Number(widgetWindow.w.y) || 0
                                const gx = wx + (cornerHandle.isLeft ? 0 : widgetWindow.implicitWidth)
                                const gy = wy + (cornerHandle.isTop ? 0 : widgetWindow.implicitHeight)
                                root.beginResize(widgetWindow, gx, gy, cornerHandle.cornerCode)
                            }
                        }
                    }
                }

                Rectangle {
                    visible: Boolean(widgetWindow.isResizeSelected || widgetWindow.isResizing)
                    z: 11
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 14
                    width: sizeBadgeTxt.implicitWidth + 10
                    height: 18
                    radius: 4
                    color: Qt.alpha(Theme.bg, 0.88)
                    border.width: 1
                    border.color: Theme.accent
                    Text {
                        id: sizeBadgeTxt
                        anchors.centerIn: parent
                        text: Math.round(widgetWindow.implicitWidth) + " × " + Math.round(widgetWindow.implicitHeight)
                        color: Theme.accent
                        font.pixelSize: Theme.text2xs
                        font.bold: true
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    visible: Boolean(widgetWindow.isResizeSelected && !widgetWindow.isResizing && !Theme.widgetsEditMode)
                    z: 11
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 14
                    width: 20
                    height: 18
                    radius: 4
                    color: doneResizeMa.containsMouse ? Theme.accent : Qt.alpha(Theme.bg, 0.88)
                    border.width: 1
                    border.color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: doneResizeMa.containsMouse ? Theme.bg : Theme.accent
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        id: doneResizeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resizeTargetWindow = null
                    }
                }

                Rectangle {
                    visible: Theme.widgetsEditMode
                    z: 10
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                    width: editToolsRow.implicitWidth + 8
                    height: 22
                    radius: 6
                    color: Qt.alpha(Theme.bg, 0.88)
                    border.width: 1
                    border.color: Qt.alpha(Theme.accent, 0.55)

                    Row {
                        id: editToolsRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: decScaleMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                            Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.pixelSize: 11; font.bold: true }
                            MouseArea {
                                id: decScaleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const cur = Number((widgetWindow.w.options && widgetWindow.w.options.text_scale) || 100)
                                    const nxt = Math.max(60, Math.round(cur - 10))
                                    Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "widget_set", String(widgetWindow.w.id), "text_scale", String(nxt)])
                                }
                            }
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: incScaleMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.pixelSize: 11; font.bold: true }
                            MouseArea {
                                id: incScaleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const cur = Number((widgetWindow.w.options && widgetWindow.w.options.text_scale) || 100)
                                    const nxt = Math.min(160, Math.round(cur + 10))
                                    Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "widget_set", String(widgetWindow.w.id), "text_scale", String(nxt)])
                                }
                            }
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: styleTogMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                            Text { anchors.centerIn: parent; text: widgetWindow.isGlassStyle ? "◆" : "◇"; color: Theme.accent; font.pixelSize: 11 }
                            MouseArea {
                                id: styleTogMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const nxt = widgetWindow.isGlassStyle ? "transparent" : "glass"
                                    Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "widget_set", String(widgetWindow.w.id), "style", nxt])
                                }
                            }
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: delWidMa.containsMouse ? Qt.alpha(Theme.error, 0.28) : "transparent"
                            Text { anchors.centerIn: parent; text: "✕"; color: Theme.error; font.pixelSize: 10; font.bold: true }
                            MouseArea {
                                id: delWidMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "widget_remove", String(widgetWindow.w.id)])
                            }
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: widgetsEditBanner
        screen: root.targetScreen
        visible: Theme.widgetsEditMode
        anchors { top: true }
        margins.top: Theme.barHeight + 14
        implicitWidth: editBannerRow.implicitWidth + 28
        implicitHeight: 36
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-whichkey"

        SurfaceFloutee {
            anchors.fill: parent
            rayon: Theme.pillRadius
            teinte: Theme.surfaceBg
            bordureCouleur: Theme.accent
            bordureLargeur: 1
            actif: true
        }

        Row {
            id: editBannerRow
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ÉDITION WIDGETS"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.bold: true
                color: Theme.accent
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: bannerSnapTxt.implicitWidth + 14
                height: 22
                radius: 6
                color: Theme.widgetsSnapGrid ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)
                Text {
                    id: bannerSnapTxt
                    anchors.centerIn: parent
                    text: Theme.widgetsSnapGrid ? "Grille 32 px" : "Libre"
                    font.pixelSize: Theme.text2xs
                    color: Theme.widgetsSnapGrid ? Theme.accent : Theme.fg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.widgetsSnapGrid = !Theme.widgetsSnapGrid
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: bannerDoneTxt.implicitWidth + 16
                height: 22
                radius: 6
                color: Theme.accent
                Text {
                    id: bannerDoneTxt
                    anchors.centerIn: parent
                    text: "Terminer"
                    font.pixelSize: Theme.text2xs
                    font.bold: true
                    color: Theme.bg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.widgetsEditMode = false
                }
            }
        }
    }

    PanelWindow {
        id: placementCatcher
        visible: root.placing
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell-widget-placement"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor

            onPositionChanged: mouse => {
                if (!root.placingWindow) return
                const maxX = parent.width - root.placingWindow.implicitWidth
                const maxY = parent.height - root.placingWindow.implicitHeight
                const rawX = Math.max(0, Math.min(maxX, mouse.x - root.placingGrabX))
                const rawY = Math.max(0, Math.min(maxY, mouse.y - root.placingGrabY))
                root.placingX = Theme.widgetsSnapGrid ? Math.max(0, Math.min(maxX, Math.round(rawX / 32) * 32)) : rawX
                root.placingY = Theme.widgetsSnapGrid ? Math.max(0, Math.min(maxY, Math.round(rawY / 32) * 32)) : rawY
            }

            onClicked: if (root.placingArmed) root.endPlacement(true)
            onWheel: if (root.placing) root.endPlacement(false)

            Keys.onEscapePressed: root.endPlacement(false)
            focus: true
        }
    }

    PanelWindow {
        id: resizeCatcher
        visible: root.resizing
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell-widget-resize"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: (root.resizingCorner === "tl" || root.resizingCorner === "br")
                ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

            onPositionChanged: mouse => {
                if (!root.resizingWindow) return
                const dx = mouse.x - root.resizingStartX
                const dy = mouse.y - root.resizingStartY
                const hasLeft = root.resizingCorner.indexOf("l") >= 0
                const hasTop = root.resizingCorner.indexOf("t") >= 0

                if (hasLeft) {
                    const maxW = root.resizingOrigX + root.resizingOrigW
                    const nw = Math.max(110, Math.min(maxW, root.resizingOrigW - dx))
                    root.resizingW = nw
                    root.resizingX = root.resizingOrigX + (root.resizingOrigW - nw)
                } else {
                    const maxW = parent.width - root.resizingOrigX
                    root.resizingW = Math.max(110, Math.min(maxW, root.resizingOrigW + dx))
                    root.resizingX = root.resizingOrigX
                }

                if (hasTop) {
                    const maxH = root.resizingOrigY + root.resizingOrigH
                    const nh = Math.max(48, Math.min(maxH, root.resizingOrigH - dy))
                    root.resizingH = nh
                    root.resizingY = root.resizingOrigY + (root.resizingOrigH - nh)
                } else {
                    const maxH = parent.height - root.resizingOrigY
                    root.resizingH = Math.max(48, Math.min(maxH, root.resizingOrigH + dy))
                    root.resizingY = root.resizingOrigY
                }
            }

            onClicked: if (root.resizingArmed) root.endResize(true)
            onWheel: if (root.resizing) root.endResize(false)

            Keys.onEscapePressed: root.endResize(false)
            focus: true
        }
    }

    WidgetMenu {
        ouvert: root.menuWidgetId !== ""
        widget: root.menuWidget
        xEcran: root.menuWidgetX
        yEcran: root.menuWidgetY
        wEcran: root.menuWidgetW
        hEcran: root.menuWidgetH
        onFermer: root.menuWidgetId = ""
        onRedimensionner: {
            const targetId = root.menuWidgetId
            root.menuWidgetId = ""
            for (let i = 0; i < root.widgetWindows.length; ++i) {
                const win = root.widgetWindows[i]
                if (win && String(win.w.id) === targetId) {
                    root.resizeTargetWindow = win
                    return
                }
            }
        }
    }
}
