import QtQuick
import "."

// ════════════════════════════════════════════════════════════════════════════
// CARTE D'APERÇU (CarteApercu.qml)
//
// Même modèle pour les trois listes d'apparence : profils de thème (inline dans
// OngletApparence), curseurs et packs d'icônes. Grande vignette, actions DANS
// l'image (pas de ligne de boutons par élément), pastille d'état et badge.
//
// Deux présentations selon `images` :
//   - 1 élément  → photo plein cadre (`PreserveAspectCrop`) + voile bas ;
//   - n éléments → grille d'icônes sur le fond de la carte (packs d'icônes).
// Les chemins sont des chemins de fichiers bruts : le composant ajoute
// `file://`, pour que les appelants n'aient pas deux conventions.
// ════════════════════════════════════════════════════════════════════════════
Rectangle {
    id: carte

    property var images: []
    property string titre: ""
    property string sousTitre: ""
    property string badge: ""
    property bool actif: false
    property bool montrerSupprimer: true
    property bool montrerMaj: false
    /// `true` : l'image remplit la carte (photo, fond d'écran). `false` : elle
    /// est contenue avec une marge — un curseur rendu plein cadre était zoomé
    /// à l'absurde, la flèche débordait de la carte.
    property bool pleinCadre: true

    signal appliquer()
    signal supprimer()
    signal maj()

    readonly property bool photo: images.length === 1
    /// Texte et boutons posés SUR l'image (photo plein cadre) ou sur le fond.
    readonly property bool surImage: photo && pleinCadre
    // Tailles dérivées de la cellule : le panneau rétrécit, la carte suit.
    readonly property int tPetit: Math.max(9, Math.round(width * 0.042))
    readonly property int tTitre: Math.max(11, Math.round(width * 0.062))

    radius: 12
    clip: true
    color: Qt.alpha(Theme.surfaceVariant, 0.5)
    border.width: actif ? 2 : 1
    border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

    // ── Aperçu ──────────────────────────────────────────────────────────────
    Image {
        id: photoImg
        anchors.fill: parent
        anchors.margins: carte.pleinCadre ? 0 : 18
        // Mode « contenu » : on réserve le bas de la carte au nom et aux
        // boutons, sinon la flèche passe sous le texte.
        anchors.bottomMargin: carte.pleinCadre ? 0 : Math.round(carte.height * 0.42)
        visible: carte.photo
        asynchronous: true
        // `cache: false` : un aperçu de curseur peut apparaître après coup
        // (généré en tâche de fond), et une entrée en cache négative figerait
        // la carte vide.
        cache: false
        fillMode: carte.pleinCadre ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        source: carte.photo && carte.images[0] ? "file://" + carte.images[0] : ""
    }

    Grid {
        id: grilleImages
        visible: !carte.photo && carte.images.length > 1
        // Zone d'icônes : sous le badge, au-dessus du bloc nom/résumé/boutons.
        // Sans ces deux réserves, les icônes débordaient sur le texte (cartes
        // de 138 px de haut pour une grille de 150 px).
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 34
        anchors.bottomMargin: Math.round(carte.height * 0.40)
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        columns: 2
        spacing: 6

        Repeater {
            model: carte.photo ? [] : carte.images

            delegate: Image {
                required property string modelData
                width: Math.round((grilleImages.width - grilleImages.spacing) / 2)
                height: Math.min(width, Math.round((grilleImages.height - grilleImages.spacing) / 2))
                sourceSize.width: 128
                sourceSize.height: 128
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                source: modelData ? "file://" + modelData : ""
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: carte.images.length === 0
        text: "▧"
        color: Qt.alpha(Theme.fg, 0.35)
        font.pixelSize: Math.round(carte.width * 0.2)
    }

    // Voile du bas : uniquement sur une photo, pour lire le texte et les
    // boutons quelle que soit l'image.
    Rectangle {
        visible: carte.surImage
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(parent.height * 0.8)
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.85) }
        }
    }

    // ── Nom, résumé, actions ────────────────────────────────────────────────
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        anchors.bottomMargin: 8
        spacing: 2

        Text {
            width: parent.width
            text: carte.titre
            color: carte.surImage ? "white" : Theme.fg
            font.pixelSize: carte.tTitre
            font.bold: carte.actif
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: carte.sousTitre !== ""
            text: carte.sousTitre
            color: carte.surImage ? Qt.rgba(1, 1, 1, 0.72) : Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: carte.tPetit
            elide: Text.ElideRight
        }

        Row {
            id: actions
            anchors.right: parent.right
            spacing: 6

            Rectangle {
                width: carte.actif ? 88 : 74
                height: 24
                radius: 12
                color: carte.actif
                    ? Theme.accent
                    : (carte.surImage
                        ? (applMa.containsMouse ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(1, 1, 1, 0.8))
                        : (applMa.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.fg, 0.1)))

                Text {
                    anchors.centerIn: parent
                    text: carte.actif ? "✓ Appliqué" : "Appliquer"
                    color: carte.actif ? Theme.bg : (carte.surImage ? "#101014" : Theme.fg)
                    font.pixelSize: Theme.text2xs
                    font.bold: true
                }

                MouseArea {
                    id: applMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!carte.actif) carte.appliquer()
                }
            }

            Rectangle {
                id: btnSuppr
                visible: carte.montrerSupprimer
                width: 24
                height: 24
                radius: 12
                color: supprMa.containsMouse
                    ? Qt.rgba(1, 1, 1, 0.95)
                    : (carte.surImage ? Qt.rgba(0, 0, 0, 0.55) : Qt.alpha(Theme.error, 0.16))
                border.width: 1
                border.color: carte.surImage ? Qt.rgba(1, 1, 1, 0.4) : Qt.alpha(Theme.error, 0.45)

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: supprMa.containsMouse ? "#8a1c1c"
                         : (carte.surImage ? "white" : Theme.error)
                    font.pixelSize: Theme.text2xs
                }

                MouseArea {
                    id: supprMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: carte.supprimer()
                }
            }
        }
    }

    // ── Badges ──────────────────────────────────────────────────────────────
    Rectangle {
        visible: carte.montrerMaj
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        width: 24
        height: 22
        radius: 11
        color: majMa.containsMouse
            ? Qt.rgba(1, 1, 1, 0.9)
            : (carte.surImage ? Qt.rgba(0, 0, 0, 0.45) : Qt.alpha(Theme.fg, 0.1))

        Text {
            anchors.centerIn: parent
            text: "⟳"
            color: majMa.containsMouse ? "#101014" : (carte.surImage ? "white" : Theme.fg)
            font.pixelSize: Theme.text2xs
        }

        MouseArea {
            id: majMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: carte.maj()
        }
    }

    Rectangle {
        visible: carte.badge !== ""
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 8
        width: badgeTexte.width + 14
        height: 19
        radius: 9
        color: carte.surImage ? Qt.rgba(0, 0, 0, 0.5) : Qt.alpha(Theme.bg, 0.55)

        Text {
            id: badgeTexte
            anchors.centerIn: parent
            text: carte.badge
            color: carte.surImage ? "white" : Theme.accent
            font.pixelSize: Theme.text2xs
        }
    }
}
