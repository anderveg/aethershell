import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// COMBO — horloge, date et météo dans une seule carte.
//
// Même source de données que widgets/meteo.qml (core/weather_service.py, cache
// partagé de dix minutes, donc aucun appel réseau en double si la météo seule
// est aussi posée quelque part).
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

    // Progression adaptative : horloge -> horloge + date -> horloge + date + météo (-> + calendrier)
    readonly property bool showDate: widgetH === 0 || widgetH >= Math.round(75 * echelle)
    readonly property bool showWeather: widgetH === 0 || widgetH >= Math.round(115 * echelle)

    // Calendrier replié/étendu, comme dans le widget « date » : même grille, même
    // composant (CalendrierCompact), la carte grandit et sa fenêtre suit.
    property bool ouvert: false
    readonly property bool showCalendrier: ouvert || widgetH >= Math.round(230 * echelle)

    property var meteoLocal: ({})
    property bool loadedLocal: false
    readonly property var meteo: root.cityOption === "" ? SystemServices.meteoData : meteoLocal
    readonly property bool loaded: root.cityOption === "" ? SystemServices.meteoLoaded : loadedLocal

    readonly property bool ok: loaded && meteo && meteo.ok === true
    readonly property bool withSeconds: {
        const s = options ? options.seconds : undefined
        return s === true || s === "true" || s === 1 || s === "1"
    }
    readonly property string cityOption: (options && options.city) ? String(options.city) : ""

    // Deux tables plutôt que Qt.formatDate à trois arguments : cette surcharge
    // n'existe pas dans ce Qt et laisse le texte vide (voir widgets/date.qml).
    readonly property var jours: ["dimanche", "lundi", "mardi", "mercredi",
                                  "jeudi", "vendredi", "samedi"]
    readonly property var mois: ["janvier", "février", "mars", "avril", "mai",
                                 "juin", "juillet", "août", "septembre",
                                 "octobre", "novembre", "décembre"]

    readonly property string libelleDate: {
        const d = clock.date
        if (!d || isNaN(d.getTime()))
            return ""
        return jours[d.getDay()] + " " + d.getDate() + " " + mois[d.getMonth()]
    }

    // Largeur du calendrier : la plus large des lignes de la carte. Calculée sur
    // les textes seuls, jamais sur la colonne qui contient la grille (boucle).
    readonly property real largeurCalendrier: Math.max(ligneDate.width,
                                                       ligneMeteo.implicitWidth,
                                                       Math.max(Math.round(196 * echelle), widgetW))

    implicitWidth: widgetW > 0 ? Math.max(stack.implicitWidth, widgetW) : stack.implicitWidth
    implicitHeight: widgetH > 0 ? Math.max(stack.implicitHeight, widgetH) : stack.implicitHeight


    function refresh(force) {
        if (root.cityOption === "") {
            SystemServices.rafraichirMeteo(force)
            return
        }
        const args = [Quickshell.shellPath("core/as-core"), "weather",
                      "--city", root.cityOption]
        if (force)
            args.push("--force")
        proc.command = args
        proc.running = true
    }

    Component.onCompleted: refresh(false)

    SystemClock {
        id: clock
        precision: root.withSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Timer {
        interval: 600000
        repeat: true
        running: root.cityOption !== ""
        onTriggered: root.refresh(false)
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.meteoLocal = JSON.parse(text.trim())
                } catch (e) {
                    root.meteoLocal = { ok: false, error: "réponse illisible" }
                }
                root.loadedLocal = true
            }
        }
    }

    Column {
        id: stack
        spacing: Theme.space1

        // Heure
        Row {
            spacing: Theme.space2

            Text {
                id: hhmm
                text: Qt.formatTime(clock.date, "HH:mm")
                color: Theme.fg
                font.pixelSize: Math.round(Theme.widgetClock * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
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

        // Date + chevron. Item et non Row : le chevron s'ancre au coin bas-droit
        // de la ligne, ce qu'une rangée interdit à ses enfants.
        Item {
            id: ligneDate
            visible: root.showDate
            width: texteDate.implicitWidth + 11
            height: texteDate.implicitHeight

            Text {
                id: texteDate
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.libelleDate
                color: Qt.alpha(Theme.fg, 0.92)
                font.pixelSize: Math.round(Theme.widgetComboDate * root.echelle)
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: "›"
                color: flecheCombo.containsMouse || root.ouvert
                    ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.max(12, Math.round(15 * root.echelle))
                rotation: root.ouvert ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: flecheCombo
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvert = !root.ouvert
                }
            }
        }

        // Météo
        Row {
            id: ligneMeteo
            visible: root.showWeather
            spacing: Theme.space2
            topPadding: Theme.space1

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: (root.ok && root.meteo.icon === "sun") ? "sun" : "cloud"
                size: Math.round(Theme.widgetWeatherIcon * root.echelle)
                color: Theme.accent
                opacityLevel: root.ok ? 1.0 : 0.45
            }

            Text {
                id: tempText
                text: root.ok ? Math.round(root.meteo.temp) + "°" : "—"
                color: Theme.fg
                font.pixelSize: Math.round(Theme.widgetComboWeather * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                text: root.ok ? (root.meteo.label + " · " + root.meteo.city)
                              : (root.loaded ? "météo indisponible" : "…")
                color: Qt.alpha(Theme.fg, 0.78)
                font.pixelSize: Math.round(Theme.widgetLabel * root.echelle)
                anchors.baseline: tempText.baseline
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }
        }

        CalendrierCompact {
            id: calendrier
            visible: root.showCalendrier
            width: root.largeurCalendrier
            echelle: root.echelle
            extraHeight: Math.max(0, root.widgetH - Math.round(115 * root.echelle))
        }
    }
}
