import QtQuick
import QtQuick.Layouts
import "."

// ══════════════════════════════════════════════════════════════════════
// PANNEAU ÉTENDU DE L'ÎLOT DYNAMIQUE (IslandPanel.qml)
// ══════════════════════════════════════════════════════════════════════
// Contenu complet du mode « panneau » (680 × 420 px) :
// - En-tête permanent (date, média rapide, bouton réglages, fermer)
// - Rail vertical gauche à libellés horizontaux (5 onglets stricts)
// - Zone de contenu à droite chargeant l'onglet actif
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var clockDate: new Date()
    property var activePlayer: null
    property var validPlayers: []
    property bool isPlaying: false
    property string mediaTitle: ""
    property bool isMediaActive: false

    readonly property var sysInfo: SystemServices.systemInfo || ({})
    readonly property var batInfo: sysInfo.battery || ({})
    readonly property bool isLaptop: Boolean(sysInfo.has_battery || (batInfo && batInfo.present))

    readonly property var tabsModel: {
        let base = [
            { idx: 0, glyph: "widgets", label: I18n.t("island.tab.controls"),    src: "IslandTabControles.qml" },
            { idx: 1, glyph: "bell",    label: I18n.t("island.tab.productivity"), src: "IslandTabAlertes.qml" },
            { idx: 2, glyph: "cog",     label: I18n.t("island.tab.system"),      src: "IslandTabSysteme.qml" },
            { idx: 3, glyph: "palette", label: I18n.t("island.tab.appearance"), src: "IslandTabApparence.qml" }
        ]
        if (Theme.ilotProjetsActif) {
            base.push({ idx: 4, glyph: "columns-3", label: I18n.t("island.tab.projects"), src: "IlotProjets.qml" })
        }
        return base
    }

    // Navigation clavier (submap Hyprland aether-nav)
    property string navZone: "rail" // "rail" | "contenu"
    property int navIndex: 0
    property var navFocusRect: ({ x: 0, y: 0, w: 0, h: 0, visible: false })

    function findFlickableAncestor(item) {
        let p = item ? item.parent : null
        while (p && p !== contentArea) {
            if (p.hasOwnProperty("contentY") && p.hasOwnProperty("contentHeight") && p.hasOwnProperty("contentItem")) {
                return p
            }
            p = p.parent
        }
        return null
    }

    function collectFocusables(item, out) {
        if (!item || !item.visible) return
        let ch = item.children
        if (!ch) return
        for (let i = 0; i < ch.length; i++) {
            let c = ch[i]
            if (!c || !c.visible) continue
            let isMouseArea = (typeof c.clicked === "function") && c.hasOwnProperty("containsMouse")
            if (isMouseArea && c.enabled && c.width > 6 && c.height > 6) {
                let p = c.mapToItem(contentArea, 0, 0)
                if (p.x >= -4 && p.x < contentArea.width) {
                    out.push({ item: c, flick: findFlickableAncestor(c), x: p.x, y: p.y, w: c.width, h: c.height })
                }
            }
            collectFocusables(c, out)
        }
    }

    function getFocusables() {
        let out = []
        if (tabLoader.item) collectFocusables(tabLoader.item, out)
        out.sort(function(a, b) {
            if (Math.abs(a.y - b.y) > 16) return a.y - b.y
            return a.x - b.x
        })
        return out
    }

    function findVerticalNeighbor(list, curIdx, dir) {
        if (list.length === 0) return -1
        let cur = list[Math.max(0, Math.min(list.length - 1, curIdx))]
        let curCx = cur.x + cur.w / 2
        let curCy = cur.y + cur.h / 2
        let bestRowDy = 1e9
        let candidates = []
        for (let i = 0; i < list.length; i++) {
            let it = list[i]
            let cy = it.y + it.h / 2
            let dy = (cy - curCy) * dir
            if (dy <= 16) continue
            if (dy < bestRowDy) bestRowDy = dy
            candidates.push({ idx: i, dy: dy, cx: it.x + it.w / 2 })
        }
        if (candidates.length === 0) return -1
        let bestIdx = -1
        let bestDx = 1e9
        for (let j = 0; j < candidates.length; j++) {
            let c = candidates[j]
            if (c.dy <= bestRowDy + 20) {
                let dx = Math.abs(c.cx - curCx)
                if (dx < bestDx) {
                    bestDx = dx
                    bestIdx = c.idx
                }
            }
        }
        return bestIdx
    }

    function ensureVisibleInFlick(f) {
        if (!f || !f.flick || !f.item) return
        let fl = f.flick
        let pos = f.item.mapToItem(fl.contentItem, 0, 0)
        let top = pos.y
        let bottom = pos.y + f.h
        let maxY = Math.max(0, fl.contentHeight - fl.height)
        if (top < fl.contentY + 8) {
            fl.contentY = Math.max(0, top - 8)
        } else if (bottom > fl.contentY + fl.height - 8) {
            fl.contentY = Math.min(maxY, bottom - fl.height + 8)
        }
    }

    property var activeFlick: null
    property var activeFocusItem: null
    property real activeFocusW: 0
    property real activeFocusH: 0

    function updateOverlayFromActiveItem() {
        if (!Theme.islandNavActive || root.navZone !== "contenu" || !root.activeFocusItem) {
            root.navFocusRect = { x: 0, y: 0, w: 0, h: 0, visible: false }
            return
        }
        let p = root.activeFocusItem.mapToItem(contentArea, 0, 0)
        let vis = (p.y + root.activeFocusH > 0) && (p.y < contentArea.height)
        root.navFocusRect = { x: p.x, y: p.y, w: root.activeFocusW, h: root.activeFocusH, visible: vis }
    }

    Connections {
        target: root.activeFlick
        function onContentYChanged() {
            root.updateOverlayFromActiveItem()
        }
    }

    function syncFocusRect() {
        if (!Theme.islandNavActive || root.navZone !== "contenu") {
            root.activeFlick = null
            root.activeFocusItem = null
            root.navFocusRect = { x: 0, y: 0, w: 0, h: 0, visible: false }
            return
        }
        let list = getFocusables()
        if (list.length === 0) {
            root.activeFlick = null
            root.activeFocusItem = null
            root.navFocusRect = { x: 0, y: 0, w: 0, h: 0, visible: false }
            return
        }
        let idx = Math.max(0, Math.min(list.length - 1, root.navIndex))
        root.navIndex = idx
        let f = list[idx]
        ensureVisibleInFlick(f)
        root.activeFlick = f.flick
        root.activeFocusItem = f.item
        root.activeFocusW = f.w
        root.activeFocusH = f.h
        updateOverlayFromActiveItem()
    }

    function handleNav(action) {
        if (Theme.islandPanelTab === 0 && tabLoader.item && tabLoader.item.sessionMenuOpen) {
            return
        }
        let list = getFocusables()
        if (action === "gauche" || action === "left") {
            if (root.navZone === "rail") {
                Theme.islandPanelTab = (Theme.islandPanelTab - 1 + root.tabsModel.length) % root.tabsModel.length
            } else if (list.length > 0) {
                root.navIndex = (root.navIndex - 1 + list.length) % list.length
            }
        } else if (action === "droite" || action === "right") {
            if (root.navZone === "rail") {
                Theme.islandPanelTab = (Theme.islandPanelTab + 1) % root.tabsModel.length
            } else if (list.length > 0) {
                root.navIndex = (root.navIndex + 1) % list.length
            }
        } else if (action === "haut" || action === "up") {
            if (root.navZone === "rail" && list.length > 0) {
                root.navZone = "contenu"
                root.navIndex = 0
            } else if (root.navZone === "contenu" && list.length > 0) {
                let nxtUp = findVerticalNeighbor(list, root.navIndex, -1)
                if (nxtUp >= 0) root.navIndex = nxtUp
                else root.navZone = "rail"
            }
        } else if (action === "bas" || action === "down") {
            if (root.navZone === "rail" && list.length > 0) {
                root.navZone = "contenu"
                root.navIndex = 0
            } else if (root.navZone === "contenu") {
                let nxtDown = findVerticalNeighbor(list, root.navIndex, 1)
                if (nxtDown >= 0) root.navIndex = nxtDown
                else root.navZone = "rail"
            }
        } else if (action === "valider" || action === "enter") {
            if (root.navZone === "rail" && list.length > 0) {
                root.navZone = "contenu"
                root.navIndex = 0
            } else if (root.navZone === "contenu" && list.length > 0) {
                let idx = Math.max(0, Math.min(list.length - 1, root.navIndex))
                let target = list[idx].item
                if (target && typeof target.clicked === "function") {
                    target.clicked(null)
                }
            }
        }
        Qt.callLater(root.syncFocusRect)
    }

    Connections {
        target: Theme
        function onIslandNavActiveChanged() {
            if (Theme.islandNavActive) {
                root.navZone = "rail"
                root.navIndex = 0
            }
            Qt.callLater(root.syncFocusRect)
        }
        function onIslandPanelTabChanged() {
            root.navIndex = 0
            Qt.callLater(root.syncFocusRect)
        }
    }

    Connections {
        target: ShellState
        function onIslandNavRequested(action) { root.handleNav(action) }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.preferredWidth: 680
            Layout.fillHeight: true
            spacing: 0

        // ── En-tête permanent du panneau (hauteur = Theme.barHeight) ─────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.barHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padH + 4
                anchors.rightMargin: Theme.padH
                spacing: 12

                // Date + Heure
                Text {
                    text: Qt.formatDate(root.clockDate, "ddd d MMM") + "  ·  " + Qt.formatTime(root.clockDate, "HH:mm")
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
                    color: Theme.fg
                }

                // Séparateur + Média rapide si actif
                Rectangle {
                    visible: root.isMediaActive
                    width: 1
                    height: 14
                    color: Qt.alpha(Theme.fg, 0.2)
                }

                Text {
                    visible: root.isMediaActive
                    Layout.fillWidth: true
                    text: (root.isPlaying ? "▶ " : "⏸ ") + root.mediaTitle
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Theme.accent
                    elide: Text.ElideRight

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.islandPanelTab = 2
                    }
                }

                Item {
                    visible: !root.isMediaActive
                    Layout.fillWidth: true
                }

                // Infos compactes (Batterie · Alertes)
                Text {
                    visible: root.isLaptop
                    text: Math.round(Number((root.batInfo && (root.batInfo.level !== undefined ? root.batInfo.level : root.batInfo.percent)) || 0)) + "%"
                          + ((root.batInfo && (root.batInfo.status === "Charging" || root.batInfo.charging)) ? " ⚡" : "")
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Qt.alpha(Theme.fg, 0.65)
                }

                Text {
                    text: ShellState.notifCount + " " + (ShellState.notifCount > 1 ? I18n.t("island.alert_many") : I18n.t("island.alert_one")) + (ShellState.doNotDisturb ? " · N.P.D." : "")
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Qt.alpha(Theme.fg, 0.65)
                }

                // Bouton Notes rapides (bascule vers l'îlot Notes)
                Rectangle {
                    Layout.preferredWidth: notesBtnLbl.implicitWidth + 14
                    Layout.preferredHeight: 22
                    radius: 6
                    color: notesBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)

                    Text {
                        id: notesBtnLbl
                        anchors.centerIn: parent
                        text: I18n.t("island.notes")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        font.weight: Font.DemiBold
                        color: notesBtnMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
                    }

                    MouseArea {
                        id: notesBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.islandPanelOpen = false
                            Theme.islandNotesOpen = true
                        }
                    }
                }

                // Bouton réglages complets
                Rectangle {
                    visible: Theme.showConfigButton
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 8
                    color: cfgMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : "transparent"

                    Icon {
                        anchors.centerIn: parent
                        glyph: "cog"
                        size: Theme.iconSm
                        color: cfgMa.containsMouse ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        id: cfgMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.islandPanelOpen = false
                            Theme.configPanelVisible = true
                        }
                    }
                }

                // Bouton Fermer (croix seule sans fond)
                Item {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: closeMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.82)
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.islandPanelOpen = false
                            Theme.islandNeedsKeyboard = false
                        }
                    }
                }

                // Bouton chevron pour rétracter / afficher l'agenda (onglet Alertes & Tâches)
                Rectangle {
                    visible: Theme.islandPanelTab === 1
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: calToggleMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)

                    Icon {
                        anchors.centerIn: parent
                        glyph: "chevron-left"
                        size: 14
                        color: calToggleMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.8)
                        rotation: Theme.islandSidePanel === "calendar" ? 0 : 180
                        Behavior on rotation {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        id: calToggleMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Theme.islandSidePanel === "calendar") {
                                Theme.islandCalendarRetracted = true
                                Theme.islandSidePanel = ""
                            } else {
                                Theme.islandCalendarRetracted = false
                                Theme.islandSidePanel = "calendar"
                            }
                        }
                    }
                }
            }
        }

        // Ligne séparatrice sous l'en-tête
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.12)
        }

        // ── Corps : Contenu onglet pleine largeur + Rail horizontal en bas ──
        Item {
            id: contentArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Loader {
                id: tabLoader
                anchors.fill: parent
                anchors.margins: 14
                source: {
                    let idx = Math.max(0, Math.min(root.tabsModel.length - 1, Theme.islandPanelTab))
                    return root.tabsModel[idx].src
                }
                onLoaded: {
                    if (!item) return
                    if (Theme.islandPanelTab === 0) {
                        item.activePlayer = Qt.binding(() => root.activePlayer)
                        item.validPlayers = Qt.binding(() => root.validPlayers)
                    }
                    Qt.callLater(root.syncFocusRect)
                }
            }

            Rectangle {
                id: navFocusOverlay
                z: 50
                visible: Theme.islandNavActive && root.navZone === "contenu" && root.navFocusRect.visible
                x: root.navFocusRect.x
                y: root.navFocusRect.y
                width: root.navFocusRect.w
                height: root.navFocusRect.h
                radius: Math.max(6, Theme.globalRadius - 4)
                color: Qt.alpha(Theme.accent, 0.08)
                border.width: 2
                border.color: Theme.accent
                Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }

        // Séparateur horizontal au-dessus du rail d'onglets
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.12)
        }

        // Rail horizontal d'onglets en bas du panneau
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 5
                anchors.bottomMargin: 5
                spacing: 6

                Repeater {
                    model: root.tabsModel
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: Theme.islandPanelTab === modelData.idx

                        Layout.fillWidth: true
                        Layout.preferredWidth: tabInnerRow.implicitWidth + 16
                        Layout.fillHeight: true
                        radius: 10
                        clip: true
                        border.width: (Theme.islandNavActive && root.navZone === "rail" && active) ? 2 : 0
                        border.color: Theme.accent
                        color: active ? Qt.alpha(Theme.accent, 0.20) : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }

                        RowLayout {
                            id: tabInnerRow
                            anchors.centerIn: parent
                            spacing: 5

                            Icon {
                                glyph: parent.parent.modelData.glyph
                                size: Theme.iconSm
                                color: parent.parent.active ? Theme.accent : Qt.alpha(Theme.fg, 0.78)
                            }

                            Text {
                                text: parent.parent.modelData.label
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.weight: parent.parent.active ? Font.Bold : Font.Medium
                                color: parent.parent.active ? Theme.fg : Qt.alpha(Theme.fg, 0.82)
                            }
                        }

                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Theme.islandNeedsKeyboard = false
                                Theme.islandPanelTab = parent.modelData.idx
                            }
                        }
                    }
                }
            }
        }
        }

        // Séparateur vertical + panneau latéral droit (ajout de tâche / agenda)
        Rectangle {
            visible: sidePanel.visible
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Qt.alpha(Theme.fg, 0.12)
        }

        IslandSidePanel {
            id: sidePanel
            Layout.preferredWidth: 340
            Layout.fillHeight: true
            visible: opacity > 0.02
            opacity: Theme.islandSidePanel !== "" ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Theme.panelAnimDuration; easing.type: Easing.OutCubic } }
        }
    }
}
