import QtQuick
import ".."

// VISUALISEUR BUREAU — permet de détacher le visualiseur audio hors de la barre ou de l'îlot.
Item {
    id: root

    property var options: ({})
    property real widgetW: 0
    property real widgetH: 0
    property bool widgetResizing: false
    property real widgetOpacity: 0.35
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }
    property string widgetId: ""

    implicitWidth: widgetW > 0 ? widgetW : Math.round(280 * echelle)
    implicitHeight: widgetH > 0 ? widgetH : Math.round(78 * echelle)

    Visualiseur {
        id: viz
        anchors.fill: parent
        anchors.margins: 8
        barre: ""
        autorise: true
        placeholder: true
        placeholderOpacity: root.widgetResizing ? Math.max(0.65, root.widgetOpacity) : root.widgetOpacity
        styleOverride: (options && options.viz_style) ? String(options.viz_style) : ""
    }
}
