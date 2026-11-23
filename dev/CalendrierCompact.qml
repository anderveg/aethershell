import QtQuick
import Quickshell
import Quickshell.Io

// ────────────────────────────────────────────────────────────────────────────
// CALENDRIER COMPACT — la grille du mois, à l'intérieur du widget « date »
//
// Même source que le panneau de l'applet (core/nextcloud_service.py month …),
// mais une autre présentation : pas de formulaire, pas de cache multi-mois, pas
// de fenêtre à ancrer. Le widget s'étend et la grille apparaît dessous.
//
// Le service est interrogé à l'ouverture et à chaque changement de mois ; sa
// propre réponse contient déjà les jours précédents et suivants, qu'on ignore.
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: racine

    property real echelle: 1.0
    property int moisOffset: 0
    property real extraHeight: 0

    readonly property var moisNoms: ["janvier", "février", "mars", "avril", "mai",
                                     "juin", "juillet", "août", "septembre",
                                     "octobre", "novembre", "décembre"]
    readonly property var moisCourts: ["janv.", "févr.", "mars", "avr.", "mai",
                                       "juin", "juil.", "août", "sept.",
                                       "oct.", "nov.", "déc."]
    readonly property var joursCourts: ["L", "M", "M", "J", "V", "S", "D"]

    readonly property date reference: {
        const d = new Date()
        return new Date(d.getFullYear(), d.getMonth() + moisOffset, 1)
    }
    readonly property int annee: reference.getFullYear()
    readonly property int mois: reference.getMonth() + 1

    readonly property string cleMois: String(annee) + "-" + String(mois).padStart(2, "0")
    readonly property string cleAujourdhui: {
        const d = new Date()
        return String(d.getFullYear()) + "-" + String(d.getMonth() + 1).padStart(2, "0")
               + "-" + String(d.getDate()).padStart(2, "0")
    }

    property var parMois: ({})        // "YYYY-MM" → { "YYYY-MM-DD": [...] }
    readonly property var parJour: (parMois && parMois[cleMois]) ? parMois[cleMois] : ({})
    property string statut: "idle"
    property bool charge: false
    property int jourChoisi: 0        // 0 = aujourd'hui / rien de choisi
    property bool ncQueued: false
    property bool ncQueuedForce: false

    // Cases de la grille : "" pour les blancs avant le 1er, puis 1..31.
    readonly property var cases: {
        const premier = new Date(annee, mois - 1, 1)
        const decalage = (premier.getDay() + 6) % 7      // lundi = 0
        const nb = new Date(annee, mois, 0).getDate()
        const out = []
        for (let i = 0; i < decalage; ++i) out.push(0)
        for (let j = 1; j <= nb; ++j) out.push(j)
        return out
    }

    function cleDe(jour) {
        return String(annee) + "-" + String(mois).padStart(2, "0") + "-" + String(jour).padStart(2, "0")
    }

    function evenementsDu(jour) {
        if (!jour) return []
        const l = parJour[cleDe(jour)]
        return Array.isArray(l) ? l : []
    }

    readonly property var jourAffiche: {
        if (jourChoisi > 0) return jourChoisi
        // Par défaut : aujourd'hui s'il est dans le mois affiché.
        if (cleAujourdhui.indexOf(cleMois) === 0) return Number(cleAujourdhui.slice(8, 10))
        return 0
    }

    readonly property var listeJour: jourAffiche > 0 ? evenementsDu(jourAffiche) : []

    // Aperçu chronologique des événements futurs (à partir d'aujourd'hui dans les mois chargés)
    readonly property var evenementsFuturs: {
        const tousMois = parMois || ({})
        const clesMois = Object.keys(tousMois).sort()
        const out = []
        for (let m = 0; m < clesMois.length; ++m) {
            const mk = clesMois[m]
            const joursMap = tousMois[mk] || ({})
            const clesJours = Object.keys(joursMap).sort()
            for (let j = 0; j < clesJours.length; ++j) {
                const dk = clesJours[j]
                if (dk < cleAujourdhui) continue
                const evs = Array.isArray(joursMap[dk]) ? joursMap[dk] : []
                const parts = dk.split("-")
                const mIdx = Math.max(0, Math.min(11, (parseInt(parts[1], 10) || 1) - 1))
                const dNum = parseInt(parts[2], 10) || 1
                const dateLbl = (dk === cleAujourdhui) ? "Auj." : (dNum + " " + moisCourts[mIdx])
                for (let k = 0; k < evs.length; ++k) {
                    const ev = evs[k]
                    if (!ev) continue
                    out.push({
                        dateKey: dk,
                        dateLabel: dateLbl,
                        time: String(ev.time || ""),
                        summary: String(ev.summary || "Événement")
                    })
                }
            }
        }
        return out
    }

    readonly property int maxFutursAffiches: {
        if (extraHeight <= 0) return 3
        const dispo = Math.max(0, extraHeight - Math.round(185 * echelle))
        return Math.max(2, Math.min(10, Math.floor(dispo / Math.round(16 * echelle))))
    }

    function _lancerChargement(force) {
        if (!parMois || !parMois[cleMois]) statut = "loading"
        proc.command = [Quickshell.shellPath("core/as-core"), "nextcloud",
                        "month", String(annee), String(mois)]
        if (force) proc.command = proc.command.concat(["--force"])
        proc.running = true
    }

    function charger(force) {
        if (proc.running) {
            ncQueued = true
            ncQueuedForce = ncQueuedForce || Boolean(force)
            return
        }
        _lancerChargement(force)
    }

    onCleMoisChanged: {
        jourChoisi = 0
        if (!parMois || !parMois[cleMois]) charger(false)
    }

    Component.onCompleted: charger(false)

    Process {
        id: proc
        onExited: {
            if (racine.ncQueued) {
                const f = racine.ncQueuedForce
                racine.ncQueued = false
                racine.ncQueuedForce = false
                racine._lancerChargement(f)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (racine.ncQueued) return
                try {
                    const r = JSON.parse(text.trim())
                    const maj = Object.assign({}, racine.parMois)
                    if (r && r.months && typeof r.months === "object") {
                        for (const mk in r.months) {
                            if (!maj[mk] || Object.keys(r.months[mk] || ({})).length > 0) {
                                maj[mk] = r.months[mk]
                            }
                        }
                    }
                    if (r && r.year && r.month && r.days) {
                        const k = String(r.year) + "-" + String(r.month).padStart(2, "0")
                        maj[k] = r.days
                    }
                    racine.parMois = maj
                    racine.statut = (r && r.status) ? r.status : "ok"
                } catch (e) {
                    racine.statut = "error"
                }
                racine.charge = true
            }
        }
    }

    implicitWidth: 196 * echelle
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: 6

        // ── navigation ──────────────────────────────────────────────────────
        Row {
            width: parent.width

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: prec.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: 14 * racine.echelle

                MouseArea {
                    id: prec
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: racine.moisOffset -= 1
                }
            }

            Item { width: 4; height: 1 }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 28
                height: Math.max(moisTxt.implicitHeight, syncIcon.height)

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        id: moisTxt
                        anchors.verticalCenter: parent.verticalCenter
                        text: racine.moisNoms[racine.mois - 1] + " " + racine.annee
                        color: Theme.fg
                        font.pixelSize: Math.round(11 * racine.echelle)
                        font.bold: true
                    }

                    Icon {
                        id: syncIcon
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "refresh"
                        size: Math.round(11 * racine.echelle)
                        color: racine.statut === "loading" ? Theme.accent : (syncMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.55))

                        MouseArea {
                            id: syncMa
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: racine.charger(true)
                        }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: suiv.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: 14 * racine.echelle

                MouseArea {
                    id: suiv
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: racine.moisOffset += 1
                }
            }
        }

        // ── en-tête des jours ───────────────────────────────────────────────
        Row {
            width: parent.width
            Repeater {
                model: racine.joursCourts
                Text {
                    required property string modelData
                    width: colonne.width / 7
                    text: modelData
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.pixelSize: Math.round(9 * racine.echelle)
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ── grille ──────────────────────────────────────────────────────────
        Grid {
            width: parent.width
            columns: 7
            rowSpacing: 2

            Repeater {
                model: racine.cases

                Item {
                    required property int modelData
                    // La cellule suit la largeur disponible : le widget peut
                    // être plus large que la grille nominale, et une grille
                    // étroite avec des jours tassés serait illisible.
                    readonly property real cote: colonne.width / 7
                    readonly property bool vide: modelData === 0
                    readonly property bool aujourdhui: !vide
                        && racine.cleAujourdhui === racine.cleDe(modelData)
                    readonly property bool choisi: !vide && racine.jourChoisi === modelData
                    readonly property int combien: racine.evenementsDu(modelData).length

                    width: cote
                    height: Math.round(Math.max(19 * racine.echelle, cote * 0.8))

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(Math.min(cote - 6, 22 * racine.echelle))
                        height: width
                        radius: width / 2
                        color: parent.choisi ? Theme.accent
                               : (parent.aujourdhui ? Qt.alpha(Theme.accent, 0.22) : "transparent")
                        border.width: parent.aujourdhui && !parent.choisi ? 1 : 0
                        border.color: Qt.alpha(Theme.accent, 0.55)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !parent.vide
                        text: parent.vide ? "" : String(parent.modelData)
                        color: parent.choisi ? Theme.bg : Theme.fg
                        font.pixelSize: Math.round(11 * racine.echelle)
                        font.bold: parent.aujourdhui
                    }

                    // Pastille : des événements ce jour-là.
                    Rectangle {
                        visible: parent.combien > 0 && !parent.choisi
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        width: 3
                        height: 3
                        radius: 2
                        color: Qt.alpha(Theme.accent, 0.85)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: racine.jourChoisi = parent.modelData
                    }
                }
            }
        }

        // ── la journée choisie ──────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        Column {
            width: parent.width
            spacing: 3

            // Si un jour particulier a été sélectionné dans la grille, montrer ses événements
            Text {
                visible: racine.jourChoisi > 0 || racine.listeJour.length > 0
                width: parent.width
                text: racine.jourChoisi > 0
                      ? (racine.jourChoisi + " " + racine.moisNoms[racine.mois - 1] + " : "
                         + (racine.listeJour.length === 0 ? "aucun événement"
                            : (racine.listeJour.length + (racine.listeJour.length > 1 ? " événements" : " événement"))))
                      : ("Aujourd'hui (" + racine.listeJour.length + ")")
                color: Qt.alpha(Theme.fg, 0.52)
                font.pixelSize: Math.round(9 * racine.echelle)
                font.bold: true
                elide: Text.ElideRight
            }

            Repeater {
                model: (racine.jourChoisi > 0 || racine.listeJour.length > 0) ? racine.listeJour.slice(0, 4) : []

                Row {
                    required property var modelData
                    width: colonne.width
                    spacing: 5

                    Text {
                        text: "•"
                        color: Qt.alpha(Theme.accent, 0.9)
                        font.pixelSize: Math.round(9 * racine.echelle)
                    }

                    Text {
                        width: parent.width - 12
                        text: (modelData.time ? (String(modelData.time) + " · ") : "") + String(modelData.summary || "")
                        color: Theme.fg
                        font.pixelSize: Math.round(9.5 * racine.echelle)
                        elide: Text.ElideRight
                    }
                }
            }

            // Aperçu des événements futurs
            Text {
                width: parent.width
                text: racine.evenementsFuturs.length === 0
                      ? (racine.statut === "loading" ? "chargement…" : "aucun événement à venir")
                      : ("À venir (" + racine.evenementsFuturs.length + ")")
                color: Qt.alpha(Theme.accent, 0.85)
                font.pixelSize: Math.round(9 * racine.echelle)
                font.bold: true
                elide: Text.ElideRight
            }

            Repeater {
                model: racine.evenementsFuturs.slice(0, racine.maxFutursAffiches)

                Row {
                    required property var modelData
                    width: colonne.width
                    spacing: 5

                    Text {
                        width: Math.round(42 * racine.echelle)
                        text: modelData.dateLabel
                        color: Qt.alpha(Theme.accent, 0.9)
                        font.pixelSize: Math.round(9 * racine.echelle)
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width - Math.round(47 * racine.echelle)
                        text: (modelData.time && modelData.time !== "Journée" ? (modelData.time + " ") : "") + modelData.summary
                        color: Theme.fg
                        font.pixelSize: Math.round(9.5 * racine.echelle)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
