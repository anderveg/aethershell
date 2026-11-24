import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 5 DE L'ÎLOT : APPARENCE & DISPOSITION (icône palette)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property bool themesExpanded: false
    readonly property var tousThemes: (Theme.paletteNoms && Theme.paletteNoms.length > 0)
        ? Theme.paletteNoms : ["dynamic", "catppuccin"]
    readonly property var themesAffiches: themesExpanded
        ? tousThemes : tousThemes.slice(0, 6)

    Process {
        id: cfgProc
    }

    // Les profils vivent dans le singleton EnvPresets : cet onglet est détruit
    // par le Loader de IslandPanel à chaque changement d'onglet, donc plus aucun
    // état de liste ici. `rafraichir()` ne fait que demander une relecture.
    function rafraichir() {
        EnvPresets.refresh()
        ThemeProfiles.refresh()
        if (!themesScanProc.running) themesScanProc.running = true
    }

    Component.onCompleted: root.rafraichir()

    Process {
        id: themesScanProc
        command: [Quickshell.shellPath("core/as-core"), "themes-scan", "--sync"]
        running: false
    }

    onVisibleChanged: if (visible) root.rafraichir()

    function runStyle(key, val) {
        cfgProc.command = [Quickshell.shellPath("core/as-core"), "config", "style", String(key), String(val)]
        cfgProc.running = true
    }

    // Mode clair/sombre : on écrit le choix puis on régénère la palette, qui
    // diffuse (gsettings color-scheme, gtk.css, bordure Hyprland) sans relance.
    function setThemeMode(mode) {
        const m = String(mode)
        Theme.themeMode = m
        root.runStyle("theme_mode", m)
        Quickshell.execDetached(["bash", Quickshell.shellPath("core/generate_colors.sh")])
    }

    function applyPreset(name) {
        const nom = String(name)
        Theme.activeTheme = nom
        Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "theme-manager", nom])
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: mainCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainCol
            width: flick.width
            height: Math.max(flick.height, implicitHeight)
            spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: "APPARENCE & DISPOSITION"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }
            Text {
                text: "Réglages visuels immédiats du shell."
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.6)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // Thème & fond d'écran
        Text {
            text: "THÈME & FOND D'ÉCRAN"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        // Profils de thème (lot B3) : le geste principal. Un profil applique
        // fond + palette + icônes + curseur + modes d'un coup ; la rangée de
        // palettes brutes qui suit reste le réglage de finesse.
        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: 6
            visible: ThemeProfiles.profils.length > 0

            Repeater {
                model: ThemeProfiles.profils
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool actif: ThemeProfiles.dernierApplique === modelData.name
                    width: Math.max(96, Math.floor((mainCol.width - 12) / 2))
                    height: 44
                    radius: 10
                    color: actif ? Qt.alpha(Theme.accent, 0.26)
                         : (tpMa.containsMouse ? Qt.alpha(Theme.accent, 0.18)
                                               : Qt.alpha(Theme.surfaceVariant, 0.4))
                    border.width: 1
                    border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        width: parent.width - 12

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.name
                            color: actif ? Theme.accent : Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            font.weight: actif ? Font.Bold : Font.Normal
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: String(modelData.palette_label || "")
                                  + (modelData.env_ref ? " · " + modelData.env_ref : "")
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: tpMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ThemeProfiles.apply(modelData.name)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: ThemeProfiles.message !== ""
            text: ThemeProfiles.message
            color: Theme.accent
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            elide: Text.ElideRight
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: 6

            Repeater {
                model: root.themesAffiches
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool active: Theme.activeTheme === modelData
                    readonly property string libelle: String(Theme.paletteEtiquettes[modelData]
                                                              || modelData.replace(/^kde-/, ""))
                    width: Math.max(82, Math.floor((mainCol.width - 12) / 3))
                    height: 28
                    radius: 8
                    color: active ? Qt.alpha(Theme.accent, 0.28)
                         : (preMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.65) : Qt.alpha(Theme.surfaceVariant, 0.4))
                    border.width: 1
                    border.color: active ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: parent.libelle
                        font.capitalization: Font.Capitalize
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: parent.active ? Font.Bold : Font.Normal
                        color: parent.active ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        id: preMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyPreset(parent.modelData)
                    }
                }
            }
        }

        Rectangle {
            visible: root.tousThemes.length > 6
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            radius: 6
            color: moreMa.containsMouse ? Qt.alpha(Theme.accent, 0.16) : Qt.alpha(Theme.surfaceVariant, 0.25)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            Text {
                anchors.centerIn: parent
                text: root.themesExpanded
                    ? "▴ Réduire les thèmes"
                    : "▾ Afficher tous les thèmes (" + root.tousThemes.length + ")"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.8)
            }

            MouseArea {
                id: moreMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.themesExpanded = !root.themesExpanded
            }
        }

        // Mode clair/sombre (lot B8) : un axe à part, transversal aux profils.
        // `auto` suit la luminance du fond, `dark`/`light` imposent le mode.
        Text {
            text: "MODE CLAIR / SOMBRE"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { key: "auto", label: "Auto (fond)" },
                    { key: "light", label: "Clair" },
                    { key: "dark", label: "Sombre" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: Theme.themeMode === modelData.key
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 8
                    color: active ? Qt.alpha(Theme.accent, 0.24) : Qt.alpha(Theme.surfaceVariant, 0.34)
                    border.width: 1
                    border.color: active ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                    Text {
                        anchors.centerIn: parent
                        text: (active ? "✓ " : "") + parent.modelData.label
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: active ? Font.Bold : Font.Normal
                        color: active ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setThemeMode(parent.modelData.key)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 8
            color: wpMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.35)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.3)

            Row {
                anchors.centerIn: parent
                spacing: 6

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "image"
                    size: Theme.iconSm
                    color: Theme.fg
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Changer de fond d'écran (SUPER+W)"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.weight: Font.DemiBold
                    color: Theme.fg
                }
            }

            MouseArea {
                id: wpMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Theme.islandPanelOpen = false
                    Quickshell.execDetached(["quickshell", "-n", "-p", Quickshell.env("HOME") + "/.config/quickshell/hyprquickpaper"])
                }
            }
        }

        // Disposition de la barre
        Text {
            text: "DISPOSITION DE LA BARRE"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { key: "classic", label: "Barre classique" },
                    { key: "island", label: "Îlot dynamique" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: Theme.barStyle === modelData.key
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: active ? Qt.alpha(Theme.accent, 0.24) : Qt.alpha(Theme.surfaceVariant, 0.34)
                    border.width: 1
                    border.color: active ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                    Text {
                        anchors.centerIn: parent
                        text: (active ? "✓ " : "") + parent.modelData.label
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: active ? Font.Bold : Font.Normal
                        color: active ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.runStyle("bar_style", parent.modelData.key)
                            Theme.barStyle = parent.modelData.key
                        }
                    }
                }
            }
        }

        // Surfaces & verre
        Text {
            text: "SURFACES & VERRE"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        // Opacité
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 72
                text: "Opacité"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Theme.fg, 0.14)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (Theme.shellOpacity - 0.3) / 0.7))
                        height: parent.height
                        radius: 2.5
                        color: Theme.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function setOp(mx) {
                        let v = 0.3 + Math.max(0, Math.min(1, mx / width)) * 0.7
                        v = Math.round(v * 20) / 20
                        Theme.shellOpacity = v
                        root.runStyle("shell_opacity", v.toFixed(2))
                    }
                    onPressed: mouse => setOp(mouse.x)
                    onPositionChanged: mouse => { if (pressed) setOp(mouse.x) }
                }
            }
            Text {
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
                text: Math.round(Theme.shellOpacity * 100) + " %"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
        }

        // Flou (Blur)
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 72
                text: "Flou (Blur)"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Theme.fg, 0.14)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (Theme.blurSize - 1) / 19))
                        height: parent.height
                        radius: 2.5
                        color: Theme.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function setBlur(mx) {
                        let b = Math.round(1 + Math.max(0, Math.min(1, mx / width)) * 19)
                        Theme.blurSize = b
                        root.runStyle("blur_size", b)
                    }
                    onPressed: mouse => setBlur(mouse.x)
                    onPositionChanged: mouse => { if (pressed) setBlur(mouse.x) }
                }
            }
            Text {
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
                text: String(Theme.blurSize)
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
        }

        // Profils d'environnement complets (Presets en 1 clic)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "PROFILS D'ENVIRONNEMENT"
                font.family: Theme.fontUi
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Qt.alpha(Theme.fg, 0.55)
            }

            // Retour d'action : sans lui, appliquer un profil identique à l'état
            // courant ne produit aucun changement visible et passe pour un bug.
            Text {
                Layout.fillWidth: true
                visible: EnvPresets.message !== ""
                text: EnvPresets.message
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.accent
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 8
                    color: Qt.alpha(Theme.surfaceVariant, 0.55)
                    border.color: presetInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.14)
                    border.width: 1

                    TextInput {
                        id: presetInput
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        clip: true
                        onAccepted: {
                            const n = text.trim()
                            if (!n) return
                            EnvPresets.save(n)
                            text = ""
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Nom du profil (ex: Travail, Nuit)…"
                            color: Qt.alpha(Theme.fg, 0.4)
                            font: parent.font
                            visible: parent.text === "" && !parent.activeFocus
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: savePrTxt.implicitWidth + 16
                    Layout.preferredHeight: 28
                    radius: 8
                    color: savePrMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.22)
                    border.color: Theme.accent
                    border.width: 1

                    Text {
                        id: savePrTxt
                        anchors.centerIn: parent
                        text: "Sauver"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: Font.Bold
                        color: savePrMa.containsMouse ? Theme.bg : Theme.fg
                    }

                    MouseArea {
                        id: savePrMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const n = presetInput.text.trim()
                            if (!n) return
                            EnvPresets.save(n)
                            presetInput.text = ""
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: EnvPresets.presets.length > 0

                Repeater {
                    model: EnvPresets.presets
                    delegate: Rectangle {
                        required property var modelData
                        width: prRow.implicitWidth + 14
                        height: 26
                        radius: 8
                        readonly property bool actif: EnvPresets.dernierApplique === modelData.name
                        color: actif ? Qt.alpha(Theme.accent, 0.28)
                             : (prMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.5))
                        border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.14)
                        border.width: 1

                        Row {
                            id: prRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name + " · " + modelData.theme
                                      + (modelData.env_v2 === false ? " · style seul" : "")
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                color: Theme.fg
                            }

                            // ⟳ : réenregistre le profil sous le même nom avec l'état
                            // courant, ce qui lui ajoute les modes (bloc `env`). Les
                            // profils antérieurs n'en ont pas et ne peuvent donc pas
                            // les restaurer.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "⟳"
                                font.pixelSize: 11
                                color: majPrMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.55)

                                MouseArea {
                                    id: majPrMa
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: EnvPresets.save(modelData.name)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "✕"
                                font.pixelSize: 10
                                color: delPrMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.5)

                                MouseArea {
                                    id: delPrMa
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: EnvPresets.remove(modelData.name)
                                }
                            }
                        }

                        MouseArea {
                            id: prMa
                            anchors.fill: parent
                            anchors.rightMargin: 18
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: EnvPresets.apply(modelData.name)
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Bouton ouvrir panneau complet
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 10
            color: fullCfgMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.22)
            border.width: 1
            border.color: Theme.accent

            Row {
                anchors.centerIn: parent
                spacing: 6

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "cog"
                    size: Theme.iconSm
                    color: fullCfgMa.containsMouse ? Theme.bg : Theme.fg
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Ouvrir tous les réglages (SUPER+SHIFT+H)"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
                    color: fullCfgMa.containsMouse ? Theme.bg : Theme.fg
                }
            }

            MouseArea {
                id: fullCfgMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Theme.islandPanelOpen = false
                    Theme.configPanelVisible = true
                }
            }
        }
        }
    }
}
