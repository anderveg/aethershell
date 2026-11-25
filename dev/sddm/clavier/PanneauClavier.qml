// Panneau du clavier virtuel du greeter — chargé par ClavierVirtuel.qml.
//
// Séparé pour que l'absence du module Qt Virtual Keyboard ne casse pas le
// thème : un Loader dont la source échoue reste en Error, le greeter continue.
//
// `active` est piloté directement par `montre` : dépendre de
// `Qt.inputMethod.visible` marchait sur le greeter Wayland mais empêchait le
// panneau de s'afficher quand la plateforme ne fournit pas de contexte
// d'entrée (vérifié hors session). Le bouton appelle aussi
// `Qt.inputMethod.show()` pour que la saisie soit bien routée vers le champ
// qui a le focus.
import QtQuick
import QtQuick.VirtualKeyboard

InputPanel {
    id: panneau

    property bool montre: false

    active: montre
    visible: montre
    width: parent ? parent.width : 0
}
