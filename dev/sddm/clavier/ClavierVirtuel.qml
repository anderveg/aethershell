// Bouton discret (en bas à droite) qui affiche le clavier virtuel du greeter.
//
// Posé par `dev/sddm/install.sh` dans chaque thème de connexion qui n'en a pas
// déjà un : la ligne `ClavierVirtuel { echelle: root.s }` est insérée dans son
// Main.qml. Le panneau est chargé par un Loader — sur une machine sans module
// Qt Virtual Keyboard, la source échoue, le bouton reste caché et le greeter
// fonctionne normalement.
//
// `echelle` suit la taille de l'écran du thème hôte (`root.s`).
import QtQuick

Item {
    id: racine

    property real echelle: 1
    property bool ouvert: panneau.item ? panneau.item.montre === true : false

    anchors.fill: parent
    z: 200

    function basculer() {
        if (!panneau.item)
            return
        const etat = !panneau.item.montre
        panneau.item.montre = etat
        if (etat)
            Qt.inputMethod.show()
        else
            Qt.inputMethod.hide()
    }

    Loader {
        id: panneau

        asynchronous: true
        source: "PanneauClavier.qml"
        width: parent.width
        height: item ? item.height : 0
        anchors.bottom: parent.bottom
    }

    // Bouton : rectangle fin + touche « clavier » dessinée (aucune police à
    // charger, donc rien à installer sur une machine neuve).
    Item {
        id: bouton

        visible: panneau.status === Loader.Ready
        width: 36 * racine.echelle
        height: 26 * racine.echelle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16 * racine.echelle
        opacity: racine.ouvert ? 0.92 : (souris.containsMouse ? 0.85 : 0.34)

        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.fill: parent
            radius: 5 * racine.echelle
            color: "transparent"
            border.width: 1
            border.color: racine.ouvert ? "#e8f0ff" : "#9aa4b8"
        }

        // Trois rangées de touches, dessinées.
        Column {
            anchors.centerIn: parent
            spacing: 2 * racine.echelle

            Repeater {
                model: [4, 5, 3]

                delegate: Row {
                    required property int modelData
                    spacing: 2 * racine.echelle
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: parent.modelData

                        delegate: Rectangle {
                            width: 3 * racine.echelle
                            height: 3 * racine.echelle
                            radius: 0.6 * racine.echelle
                            color: racine.ouvert ? "#e8f0ff" : "#9aa4b8"
                        }
                    }
                }
            }
        }

        MouseArea {
            id: souris

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: racine.basculer()
        }
    }
}
