import QtQuick
import "."

// Onglet « Îlot dynamique » du panneau de configuration.
Column {
    id: bloc
    property var root
    property var mainFlickable

    visible: root ? root.currentTab === 1 : false
    width: mainFlickable ? mainFlickable.width : 0
    spacing: 12

    readonly property var sections: ({
        "ilot_config": secIlotConfig,
        "ilot_indicateurs": secIlotIndicateurs,
        "ilot_applets": secIlotApplets
    })

    readonly property var cibles: ({
        "secIlotConfig": secIlotConfig,
        "secIlotIndicateurs": secIlotIndicateurs,
        "secIlotApplets": secIlotApplets
    })

    readonly property var modeChoices: [
        { code: "off",      label: "Masqué" },
        { code: "compact",  label: "Repos" },
        { code: "expanded", label: "Étendu" },
        { code: "both",     label: "Les deux" }
    ]

    property string ilotAddZone: ""
    property bool ilotAddingOpen: false
    property bool majOptsOpen: false
    property string hoverIlotZone: "__none__"
    property int hoverIlotIdx: -1
    property var zoneRefs: ({})

    function findIlotZoneDrop(px, py) {
        const zones = ["", "top-left", "top-right", "bottom-left", "bottom-right"]
        for (let i = 0; i < zones.length; ++i) {
            const z = zones[i]
            const col = zoneRefs[z]
            if (!col || !root) continue
            const pt = root.mapToItem(col, px, py)
            if (pt.x >= 0 && pt.x <= col.width && pt.y >= 0 && pt.y <= col.height) {
                const count = IslandAppletLayout.appletsInZone(z).length
                const idx = Math.max(0, Math.min(count, Math.round((pt.y - 34) / 36)))
                return ({ zone: z, idx: idx })
            }
        }
        return null
    }

    CollapsibleSection {
        id: secIlotConfig
        width: parent.width
        title: "Îlot dynamique — Apparence & comportement"
        summary: (Theme.barStyle === "island" ? "Mode actif" : "Mode barre classique")
            + " · hauteur " + Theme.barHeight + " px · anim " + Theme.panelAnimDuration + " ms"
        expanded: root ? root.sectionOpen("ilot_config", true) : true
        espacementContenu: 8
        onToggled: {
            if (!root) return
            root.setPanelSection("ilot_config", expanded)
            if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ilot_config")
        }

        // Mode Îlot dynamique vs Barre classique
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Mode de barre :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Row {
                spacing: 6
                Repeater {
                    model: [
                        { key: "island",  label: "Îlot dynamique" },
                        { key: "classic", label: "Barre classique" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: Theme.barStyle === modelData.key
                        width: 118
                        height: 28
                        radius: Theme.globalRadius
                        color: active ? Theme.accent : (bmMa.containsMouse ? Theme.surfaceVariant : Theme.bg)
                        border.color: active ? Theme.accent : Theme.surfaceVariant
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: active ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: active
                        }

                        MouseArea {
                            id: bmMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root) root.runConfigCmd(["style", "bar_style", modelData.key])
                        }
                    }
                }
            }
        }

        // Onglet Projets (Kanban Planka)
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Onglet Projets (Kanban) :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Rectangle {
                width: 96
                height: 28
                radius: Theme.globalRadius
                color: Theme.ilotProjetsActif ? Theme.accent : Theme.bg
                border.color: Theme.ilotProjetsActif ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.ilotProjetsActif ? "Activé" : "Masqué"
                    color: Theme.ilotProjetsActif ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: Theme.ilotProjetsActif
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root) root.runConfigCmd(["style", "ilot_projets_actif", Theme.ilotProjetsActif ? "false" : "true"])
                }
            }
        }

        // Bordure de pilule
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Bordure de la pilule :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Rectangle {
                width: 96
                height: 28
                radius: Theme.globalRadius
                color: Theme.barBorder ? Theme.accent : Theme.bg
                border.color: Theme.barBorder ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.barBorder ? "Activée" : "Désactivée"
                    color: Theme.barBorder ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: Theme.barBorder
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root) root.runConfigCmd(["style", "bar_border", Theme.barBorder ? "false" : "true"])
                }
            }
        }

        // Hauteur de la pilule
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Hauteur de pilule :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.barHeight
                minimumValue: 14
                maximumValue: 60
                stepSize: 2
                suffix: " px"
                onValueModified: newVal => {
                    if (root) root.runConfigCmd(["style", "bar_height", String(newVal)])
                }
            }
        }

        // Arrondis îlots (Quickshell)
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Arrondis îlots (QS) :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.globalRadius
                minimumValue: 0
                maximumValue: 30
                stepSize: 2
                suffix: " px"
                onValueModified: newVal => {
                    if (root) root.runConfigCmd(["style", "global_radius", String(newVal)])
                }
            }
        }

        // Vitesse d'animation du panneau
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Durée d'animation :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.panelAnimDuration
                minimumValue: 80
                maximumValue: 500
                stepSize: 20
                suffix: " ms"
                onValueModified: newVal => {
                    if (root) root.runConfigCmd(["style", "panel_anim_duration", String(newVal)])
                }
            }
        }

        // Gaps latéraux (partagé avec l'onglet Barre — écarte aussi les applets sortis dans les coins)
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Gaps latéraux :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.gutterH
                minimumValue: 0
                maximumValue: 280
                stepSize: 1
                suffix: " px"
                onValueModified: newVal => {
                    if (root) root.runConfigCmd(["style", "bar_gaps_out_h", String(newVal)])
                }
            }
        }
    }

    CollapsibleSection {
        id: secIlotIndicateurs
        width: parent.width
        title: "Indicateurs de la pilule"
        summary: "Masqué · Repos · Étendu · Les deux"
        expanded: root ? root.sectionOpen("ilot_indicateurs", true) : true
        onToggled: {
            if (!root) return
            root.setPanelSection("ilot_indicateurs", expanded)
            if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ilot_indicateurs")
        }

        Repeater {
            model: [
                { key: "ilot_show_vpn",           label: "Voyant VPN",             desc: "Point d'état VPN",                    mode: Theme.ilotShowVpn },
                { key: "ilot_show_capture",       label: "Voyant Capture",         desc: "Capture vidéo / audio active",        mode: Theme.ilotShowCapture },
                { key: "ilot_show_live_activity", label: "Live Activity",          desc: "Minuteur, enregistrement, téléchargements", mode: Theme.ilotShowLiveActivity }
            ]

            delegate: Rectangle {
                required property var modelData
                width: parent ? parent.width : 0
                height: 46
                radius: Math.max(8, Math.round(Theme.globalRadius * 0.6))
                color: Qt.alpha(Theme.surfaceVariant, 0.35)
                border.color: Qt.alpha(Theme.fg, 0.08)
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 10

                    Column {
                        width: Math.max(90, parent.width - segTrack.width - 10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: modelData.label
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: modelData.desc
                            color: Qt.alpha(Theme.fg, 0.65)
                            font.pixelSize: Theme.text2xs
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    ConfigSegmented {
                        id: segTrack
                        anchors.verticalCenter: parent.verticalCenter
                        choices: bloc.modeChoices
                        currentCode: modelData.mode
                        onSelected: code => {
                            if (root) root.runConfigCmd(["style", modelData.key, code])
                        }
                    }
                }
            }
        }
    }

    CollapsibleSection {
        id: secIlotApplets
        width: parent.width
        title: "Applets de l'îlot"
        summary: "Glisser-déposer · Îlot & Coins"
        expanded: root ? root.sectionOpen("ilot_applets", false) : false
        onToggled: expanded => {
            if (!root) return
            root.setPanelSection("ilot_applets", expanded)
            if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ilot_applets")
        }

        // En-tête : position des applets sortis + Défaut + Ajouter
        Item {
            width: parent ? parent.width : 0
            height: 36

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Sortis :"
                    color: Qt.alpha(Theme.fg, 0.72)
                    font.pixelSize: Theme.textXs
                }

                ConfigSegmented {
                    id: coinsGroupesSeg
                    anchors.verticalCenter: parent.verticalCenter
                    itemHeight: 22
                    choices: [
                        { code: "false", label: "Coins" },
                        { code: "true",  label: "Autour" }
                    ]
                    currentCode: Theme.ilotCoinsGroupes ? "true" : "false"
                    onSelected: code => {
                        if (root) root.runConfigCmd(["style", "ilot_coins_groupes", code])
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Rectangle {
                    width: ilotResetTxt.implicitWidth + 18
                    height: 26
                    radius: Theme.globalRadius
                    color: ilotResetMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55)
                    border.color: Qt.alpha(Theme.fg, 0.14)
                    border.width: 1

                    Text {
                        id: ilotResetTxt
                        anchors.centerIn: parent
                        text: "↺ Défaut"
                        color: Theme.fg
                        font.pixelSize: Theme.text2xs
                    }

                    MouseArea {
                        id: ilotResetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            bloc.ilotAddingOpen = false
                            if (root) root.runConfigCmd(["ilot_applets_reset"])
                        }
                    }
                }

                Rectangle {
                    width: ilotAddTxt.implicitWidth + 20
                    height: 26
                    radius: Theme.globalRadius
                    color: bloc.ilotAddingOpen ? Theme.accent : Qt.alpha(Theme.accent, 0.88)

                    Text {
                        id: ilotAddTxt
                        anchors.centerIn: parent
                        text: bloc.ilotAddingOpen ? "Fermer" : "+ Ajouter"
                        color: Theme.bg
                        font.pixelSize: Theme.text2xs
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (bloc.ilotAddingOpen) {
                                bloc.ilotAddingOpen = false
                            } else {
                                bloc.ilotAddZone = ""
                                bloc.ilotAddingOpen = true
                            }
                        }
                    }
                }
            }
        }

        // Catalogue rapide d'ajout dans la zone choisie
        Rectangle {
            visible: bloc.ilotAddingOpen
            width: parent ? parent.width : 0
            height: visible ? ilotAddCol.implicitHeight + 16 : 0
            radius: Theme.globalRadius
            color: Qt.alpha(Theme.surfaceVariant, 0.65)
            border.color: Theme.accent
            border.width: 1

            Column {
                id: ilotAddCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 6

                Text {
                    text: "Ajouter un applet dans « " + IslandAppletLayout.zoneLabel(bloc.ilotAddZone) + " » :"
                    color: Theme.accent
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: IslandAppletLayout.inactiveApplets()

                        Rectangle {
                            id: addChipRect
                            required property var modelData
                            width: chipLbl.implicitWidth + 22
                            height: 26
                            radius: Theme.globalRadius
                            color: chipMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                            border.color: Qt.alpha(Theme.fg, 0.14)
                            border.width: 1

                            Text {
                                id: chipLbl
                                anchors.centerIn: parent
                                text: "+ " + modelData.label
                                color: chipMa.containsMouse ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                            }

                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: dragging
                                cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                property real startX: 0
                                property real startY: 0
                                property bool dragging: false

                                onPressed: mouse => {
                                    startX = mouse.x
                                    startY = mouse.y
                                    dragging = false
                                }

                                onPositionChanged: mouse => {
                                    if (!pressed || !root) return
                                    if (!dragging && Math.hypot(mouse.x - startX, mouse.y - startY) > 6) {
                                        dragging = true
                                        root.dragCapsuleId = addChipRect.modelData.id
                                        root.dragCapsuleLabel = addChipRect.modelData.label
                                    }
                                    if (dragging) {
                                        const pt = addChipRect.mapToItem(root, mouse.x, mouse.y)
                                        root.dragPointerX = pt.x
                                        root.dragPointerY = pt.y
                                        const hit = bloc.findIlotZoneDrop(pt.x, pt.y)
                                        bloc.hoverIlotZone = hit ? hit.zone : "__none__"
                                        bloc.hoverIlotIdx = hit ? hit.idx : -1
                                    }
                                }

                                onReleased: {
                                    const sk = IslandAppletLayout.styleKeyForId(addChipRect.modelData.id)
                                    if (dragging && root) {
                                        const hit = bloc.findIlotZoneDrop(root.dragPointerX, root.dragPointerY)
                                        if (hit) {
                                            if (sk) {
                                                root.runConfigCmd(["style", sk, "both"])
                                            } else {
                                                const cArg = hit.zone === "" ? "ilot" : hit.zone
                                                root.runConfigCmd(["ilot_applet_move_to", addChipRect.modelData.id, cArg, String(hit.idx)])
                                            }
                                        }
                                        root.dragCapsuleId = ""
                                        root.dragCapsuleLabel = ""
                                        bloc.hoverIlotZone = "__none__"
                                        bloc.hoverIlotIdx = -1
                                        dragging = false
                                        return
                                    }
                                    dragging = false
                                    if (root) {
                                        if (sk) root.runConfigCmd(["style", sk, "both"])
                                        else root.runConfigCmd(["ilot_applet_move_to", addChipRect.modelData.id, bloc.ilotAddZone === "" ? "ilot" : bloc.ilotAddZone])
                                    }
                                    bloc.ilotAddingOpen = false
                                }

                                onCanceled: {
                                    dragging = false
                                    bloc.hoverIlotZone = "__none__"
                                    bloc.hoverIlotIdx = -1
                                    if (root) {
                                        root.dragCapsuleId = ""
                                        root.dragCapsuleLabel = ""
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: IslandAppletLayout.inactiveApplets().length === 0
                        text: "Tous les applets sont déjà affichés."
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Theme.text2xs
                    }
                }
            }
        }

        // Ligne 1 : 3 colonnes principales (Îlot | Haut Gauche | Haut Droite)
        Row {
            id: ilotBoardTop
            width: parent ? parent.width : 0
            spacing: 8
            readonly property real colW: Math.floor((width - spacing * 2) / 3)

            Repeater {
                model: [
                    { code: "top-left",  label: "Haut Gauche" },
                    { code: "",          label: "Îlot (Pilule)" },
                    { code: "top-right", label: "Haut Droite" }
                ]

                delegate: IlotZoneColumn {
                    ilotBloc: bloc
                    panelRoot: root
                    colWidth: ilotBoardTop.colW
                    minHeight: 104
                }
            }
        }

        // Ligne 2 : 2 colonnes inférieures (Bas Gauche | Bas Droite)
        Row {
            id: ilotBoardBot
            width: parent ? parent.width : 0
            spacing: 8
            readonly property real colW: Math.floor((width - spacing) / 2)

            Repeater {
                model: [
                    { code: "bottom-left",  label: "Bas Gauche" },
                    { code: "bottom-right", label: "Bas Droite" }
                ]

                delegate: IlotZoneColumn {
                    ilotBloc: bloc
                    panelRoot: root
                    colWidth: ilotBoardBot.colW
                    minHeight: 76
                }
            }
        }

    }
}
