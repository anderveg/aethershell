import QtQuick

// Barre de capture (SUPER + SHIFT + S) : 4 modes (photo région/écran, vidéo région/écran)
// ou bouton d'arrêt pendant un enregistrement, hébergée dans une surface plein écran (main.qml).
Item {
    id: root

    readonly property int barWidth: 60
    readonly property int buttonSize: 44
    readonly property int pad: 8
    readonly property int gap: 6
    readonly property color surfaceColor: Theme.surfaceBg


    // Renseigné à l'ouverture de la barre par un `pgrep -x wf-recorder` dans
    // main.qml : un enregistrement peut tourner depuis une ouverture précédente.
    property bool recording: false
    property bool recordWithAudio: false

    // Étiquette du bouton survolé, posée à droite de la pastille (elle déborde
    // volontairement la largeur de l'Item : la surface qui l'héberge est plein
    // écran). Une icône seule ne dit pas « région » ou « écran entier ».
    property string hoveredLabel: ""
    property real hoveredCenterY: 0

    signal regionRequested()
    signal fullRequested()
    signal recordRegionRequested(bool withAudio)
    signal recordFullRequested(bool withAudio)
    signal recordStopRequested()

    readonly property var entries: recording
        ? [
            { glyph: "selection",   action: "region",       label: "Capturer une région",      video: false },
            { glyph: "screen-shot", action: "full",         label: "Capturer l'écran",         video: false },
            { glyph: "stop",        action: "recordStop",   label: "Arrêter l'enregistrement", video: true, sep: true }
          ]
        : [
            { glyph: "selection",    action: "region",       label: "Capturer une région", video: false },
            { glyph: "screen-shot",  action: "full",         label: "Capturer l'écran",     video: false },
            { glyph: "video-region", action: "recordRegion", label: "Filmer une région",   video: true, sep: true },
            { glyph: "video-full",   action: "recordFull",   label: "Filmer l'écran",      video: true }
          ]

    implicitWidth: barWidth
    implicitHeight: pill.height

    Item {
        id: pill
        width: root.barWidth
        height: stack.implicitHeight + root.pad * 2

        SurfaceFloutee {
            anchors.fill: parent
            rayon: 22
            teinte: root.surfaceColor
            bordureCouleur: Qt.alpha(Theme.accent, 0.22)
            bordureLargeur: 1
        }

        Column {
            id: stack
            anchors.top: parent.top
            anchors.topMargin: root.pad
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.gap

            Repeater {
                model: root.entries

                Column {
                    id: entry
                    required property var modelData
                    spacing: root.gap

                    Rectangle {
                        visible: entry.modelData.sep === true
                        width: root.buttonSize - 14
                        height: 1
                        x: 7
                        color: Qt.alpha(Theme.fg, 0.09)
                    }

                    Rectangle {
                        id: entryButton
                        width: root.buttonSize
                        height: root.buttonSize
                        radius: 14
                        color: entryMouse.containsMouse
                            ? Qt.alpha(entry.modelData.video ? Theme.error : Theme.accent, 0.14)
                            : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            glyph: entry.modelData.glyph
                            size: 21
                            color: entry.modelData.video ? Theme.error : Theme.accent
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // L'étiquette est posée dans le repère de `root` : on y
                            // remonte le centre du bouton, pas celui du délégué.
                            onEntered: {
                                const p = entryButton.mapToItem(root, 0, 0)
                                root.hoveredLabel = entry.modelData.label
                                root.hoveredCenterY = p.y + entryButton.height / 2
                            }
                            onExited: root.hoveredLabel = ""
                            onClicked: {
                                switch (entry.modelData.action) {
                                case "region":       root.regionRequested(); break
                                case "full":         root.fullRequested(); break
                                case "recordRegion": root.recordRegionRequested(root.recordWithAudio); break
                                case "recordFull":   root.recordFullRequested(root.recordWithAudio); break
                                case "recordStop":   root.recordStopRequested(); break
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Extension audio en face de la section vidéo : permet d'inclure le son joué
    // (monitor du sink par défaut) avant de lancer l'enregistrement.
    Item {
        id: audioExtPill
        visible: !root.recording
        x: root.barWidth + 8
        y: pill.height - root.pad - root.buttonSize - root.gap / 2 - height / 2
        width: 40
        height: 40

        SurfaceFloutee {
            anchors.fill: parent
            rayon: 14
            teinte: root.recordWithAudio
                ? Qt.alpha(Theme.error, 0.22)
                : root.surfaceColor
            bordureCouleur: root.recordWithAudio
                ? Theme.error
                : Qt.alpha(Theme.accent, 0.22)
            bordureLargeur: 1
        }

        Icon {
            anchors.centerIn: parent
            glyph: root.recordWithAudio ? "volume" : "volume-off"
            size: 19
            color: root.recordWithAudio
                ? Theme.error
                : (audioExtMouse.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55))
        }

        MouseArea {
            id: audioExtMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                const p = audioExtPill.mapToItem(root, 0, 0)
                root.hoveredLabel = root.recordWithAudio ? "Son système : activé" : "Son système : désactivé"
                root.hoveredCenterY = p.y + audioExtPill.height / 2
            }
            onExited: root.hoveredLabel = ""
            onClicked: {
                root.recordWithAudio = !root.recordWithAudio
                root.hoveredLabel = root.recordWithAudio ? "Son système : activé" : "Son système : désactivé"
            }
        }
    }

    // Étiquette du bouton survolé : elle sort de la pastille (à droite), suit la
    // ligne du bouton et s'efface avec le survol. Pas de MouseArea dedans, donc
    // elle ne mange ni clic ni survol.
    Rectangle {
        id: tooltip
        visible: opacity > 0.01
        opacity: root.hoveredLabel !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        x: (!root.recording && root.hoveredCenterY > (pill.height - root.pad - root.buttonSize * 2 - root.gap - 12))
            ? (root.barWidth + 56) : (root.barWidth + 10)
        y: root.hoveredCenterY - height / 2
        width: tooltipText.implicitWidth + Theme.space3 * 2
        height: tooltipText.implicitHeight + Theme.space2
        radius: 8
        color: Qt.alpha(Theme.surface, 0.95)
        border.color: Qt.alpha(Theme.fg, 0.10)
        border.width: 1

        Text {
            id: tooltipText
            anchors.centerIn: parent
            text: root.hoveredLabel
            font.family: Theme.fontUi
            font.pixelSize: Theme.textSm
            color: Theme.fg
        }
    }
}
