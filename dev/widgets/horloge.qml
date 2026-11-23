import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Hyprland

// ────────────────────────────────────────────────────────────────────────────
// WIDGETS DE BUREAU — un composant par type, chargé par un Loader depuis
// main.qml. Chaque widget est une surface layer `Bottom` (namespace
// `shell-widget`) : elle vit DERRIÈRE les fenêtres, ne prend jamais le clavier
// et ne doit mesurer QUE son contenu — une surface layer consomme les clics sur
// toute son étendue, même transparente.
//
// Taille : toujours implicite (implicitWidth/Height), jamais `width`/`height`
// littéraux ; les tailles de texte viennent de Theme (widgetClock, widgetDate…).
// ────────────────────────────────────────────────────────────────────────────

// HORLOGE — heure seule, option secondes.
Item {
    id: root
    property var options: ({})
    property real widgetW: 0
    property real widgetH: 0

    // Échelle du texte, réglée par widget depuis le panneau (options.text_scale,
    // en pourcentage). 100 = taille du thème ; les widgets de compte LLM partent
    // plus petit (85) parce qu'ils affichent deux lignes de texte dense.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }
    // Renseigné par main.qml : identité de l'entrée dans widgets.json.
    property string widgetId: ""

    readonly property bool showDate: widgetH >= Math.round(78 * echelle)
    readonly property bool showWeather: widgetH >= Math.round(118 * echelle)
    readonly property bool showWeatherDetails: widgetH >= Math.round(158 * echelle)
    readonly property var meteo: SystemServices.meteoData || ({})
    readonly property bool meteoOk: Boolean(meteo && meteo.ok)
    readonly property string dateTexte: {
        const d = clock.date
        if (!d || isNaN(d.getTime())) return ""
        const jours = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        const mois = ["janvier", "février", "mars", "avril", "mai", "juin",
                      "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
        return jours[d.getDay()] + " " + d.getDate() + " " + mois[d.getMonth()]
    }

    onShowWeatherChanged: if (showWeather && !meteoOk) SystemServices.rafraichirMeteo(false)
    Component.onCompleted: if (showWeather && !meteoOk) SystemServices.rafraichirMeteo(false)

    // widget_set écrit les options en chaîne ("true") : tester les deux formes,
    // sinon l'option ne s'active jamais depuis la CLI ou le panneau.
    readonly property bool withSeconds: {
        const s = options ? options.seconds : undefined
        return s === true || s === "true" || s === 1 || s === "1"
    }

    implicitWidth: widgetW > 0 ? Math.max(contentCol.implicitWidth, widgetW) : contentCol.implicitWidth
    implicitHeight: widgetH > 0 ? Math.max(contentCol.implicitHeight, widgetH) : contentCol.implicitHeight

    SystemClock {
        id: clock
        precision: root.withSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Column {
        id: contentCol
        spacing: Math.round(6 * root.echelle)

        Row {
            id: clockRow
            spacing: Theme.space2

            Text {
                id: hhmm
                text: Qt.formatTime(clock.date, "HH:mm")
                color: Theme.fg
                font.pixelSize: Math.round(Theme.widgetClock * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                // Lisible sur un wallpaper clair sans ajouter de carte.
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                visible: root.withSeconds
                text: Qt.formatTime(clock.date, "ss")
                color: Theme.accent
                font.pixelSize: Math.round(Theme.widgetClockSm * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                anchors.baseline: hhmm.baseline
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }
        }

        Text {
            visible: root.showDate
            text: root.dateTexte
            color: Qt.alpha(Theme.fg, 0.85)
            font.pixelSize: Math.round(Theme.widgetDate * 0.85 * root.echelle)
            font.capitalization: Font.Capitalize
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }

        Row {
            visible: root.showWeather
            spacing: Theme.space2

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: (root.meteoOk && root.meteo.icon === "sun") ? "sun" : "cloud"
                size: Math.round(18 * root.echelle)
                color: Theme.accent
                opacityLevel: root.meteoOk ? 1.0 : 0.45
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.meteoOk
                    ? (Math.round(root.meteo.temp) + "° · " + String(root.meteo.label || "") + " · " + String(root.meteo.city || ""))
                    : "météo…"
                color: Qt.alpha(Theme.fg, 0.78)
                font.pixelSize: Math.round(Theme.widgetLabel * root.echelle)
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }
        }

        Text {
            visible: root.showWeatherDetails && root.meteoOk
            text: root.meteoOk
                ? ("min " + Math.round(Number(root.meteo.tmin) || 0) + "° · max " + Math.round(Number(root.meteo.tmax) || 0) + "° · ressenti " + Math.round(Number(root.meteo.feels) || 0) + "°")
                : ""
            color: Qt.alpha(Theme.fg, 0.62)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.9 * root.echelle)
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }
    }
}
