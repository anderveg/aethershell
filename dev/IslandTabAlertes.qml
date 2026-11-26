import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 3 DE L'ÎLOT : ALERTES & TÂCHES (icône bell)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var todoItems: []
    property int todoOpenCount: 0
    property bool todoSurveillance: false

    function refreshTasks() {
        if (!todoProc.running) {
            todoProc.command = [Quickshell.shellPath("core/as-core"), "todo", "--tous"]
            todoProc.running = true
        }
    }

    Component.onCompleted: refreshTasks()

    Connections {
        target: Theme
        function onTodoRevChanged() {
            if (!todoProc.running) {
                todoProc.command = [Quickshell.shellPath("core/as-core"), "todo", "--tous"]
                todoProc.running = true
            }
        }
    }

    Process {
        id: todoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    root.todoSurveillance = Boolean(d.surveillance)
                    let items = d.taches || d.items || []
                    let open = []
                    for (let i = 0; i < items.length; i++) {
                        if (!items[i].fait && !items[i].done) open.push(items[i])
                    }
                    root.todoOpenCount = open.length
                    root.todoItems = open.slice(0, ShellState.notifCount === 0 ? 5 : 3)
                } catch (e) {
                    root.todoItems = []
                }
            }
        }
    }

    Process {
        id: todoActionProc
        onExited: root.refreshTasks()
    }

    Process {
        id: dndBridge
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // En-tête + boutons Presse-papiers, N.P.D. et Tout effacer
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: I18n.t("island.tab.prod")
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: clipBtnRow.implicitWidth + 14
                radius: 7
                color: Theme.islandSidePanel === "clipboard"
                    ? Qt.alpha(Theme.accent, 0.25)
                    : (clipBtnMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.08))
                border.width: 1
                border.color: Theme.islandSidePanel === "clipboard" ? Theme.accent : "transparent"

                Row {
                    id: clipBtnRow
                    anchors.centerIn: parent
                    spacing: 4

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "clipboard"
                        size: 12
                        color: Theme.islandSidePanel === "clipboard" ? Theme.accent : Theme.fg
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.t("island.tab.clipboard")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Theme.islandSidePanel === "clipboard" ? Theme.accent : Theme.fg
                    }
                }

                MouseArea {
                    id: clipBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.islandSidePanel = (Theme.islandSidePanel === "clipboard" ? "" : "clipboard")
                }
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: dndLbl.implicitWidth + 14
                radius: 7
                color: ShellState.doNotDisturb ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                border.width: 1
                border.color: ShellState.doNotDisturb ? Theme.accent : "transparent"

                Row {
                    id: dndLbl
                    anchors.centerIn: parent
                    spacing: 4

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: ShellState.doNotDisturb ? "bell-off" : "bell"
                        size: 12
                        color: ShellState.doNotDisturb ? Theme.accent : Theme.fg
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ShellState.doNotDisturb ? "N.P.D. ON" : "N.P.D."
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: ShellState.doNotDisturb ? Theme.accent : Theme.fg
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ShellState.doNotDisturb = !ShellState.doNotDisturb
                        dndBridge.command = [Quickshell.shellPath("core/as-core"), "config",
                                             "style", "do_not_disturb", ShellState.doNotDisturb ? "true" : "false"]
                        dndBridge.running = true
                    }
                }
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: clearLbl.implicitWidth + 14
                radius: 7
                color: ShellState.notifCount > 0 ? Qt.alpha(Theme.error, 0.18) : Qt.alpha(Theme.fg, 0.05)
                opacity: ShellState.notifCount > 0 ? 1.0 : 0.45

                Text {
                    id: clearLbl
                    anchors.centerIn: parent
                    text: I18n.t("island.tab.clear_all")
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: ShellState.notifCount > 0 ? Theme.error : Theme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: ShellState.notifCount > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (ShellState.notifOps && ShellState.notifOps.clear) ShellState.notifOps.clear()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // Sous-titre Notifications + Historique
        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "NOTIFICATIONS ACTIVES (" + ShellState.notifCount + ")"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Qt.alpha(Theme.fg, 0.65)
            }

            Text {
                text: I18n.t("island.tab.history")
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: histMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                MouseArea {
                    id: histMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Theme.islandPanelOpen = false
                        ShellState.notifHistoryVisible = true
                    }
                }
            }
        }

        // Liste Notifications
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: ShellState.notifCount === 0 ? 40 : 112
            clip: true
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.25)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.07)

            Text {
                visible: ShellState.notifCount === 0
                anchors.centerIn: parent
                text: "Aucune notification récente"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.55)
            }

            Flickable {
                visible: ShellState.notifCount > 0
                anchors.fill: parent
                anchors.margins: 6
                contentHeight: notifCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: notifCol
                    width: parent.width
                    spacing: 6

                    property var expandedGroups: ({})
                    property string ruleToastApp: ""
                    Timer {
                        id: ruleToastTimer
                        interval: 1800
                        onTriggered: notifCol.ruleToastApp = ""
                    }

                    function toggleGroup(appName) {
                        const copy = Object.assign({}, notifCol.expandedGroups)
                        copy[appName] = !Boolean(copy[appName])
                        notifCol.expandedGroups = copy
                    }

                    function createRuleForApp(appName) {
                        const key = String(appName || "").trim()
                        if (!key) return
                        const cmd = key.toLowerCase().replace(/\s+/g, "-")
                        ConfigStore.runCmd(["notif_app_set", key, cmd])
                        notifCol.ruleToastApp = key
                        ruleToastTimer.restart()
                    }

                    readonly property var groupedNotifs: {
                        const list = ShellState.notifList || []
                        const order = []
                        const map = ({})
                        for (let i = 0; i < list.length; ++i) {
                            const item = list[i]
                            const app = String(item.appName || "Notification")
                            if (!map[app]) {
                                map[app] = { appName: app, items: [] }
                                order.push(map[app])
                            }
                            map[app].items.push(item)
                        }
                        return order
                    }

                    Repeater {
                        model: notifCol.groupedNotifs
                        delegate: ColumnLayout {
                            required property var modelData
                            readonly property string appName: modelData.appName
                            readonly property var items: modelData.items
                            readonly property bool isGroup: items.length > 1
                            readonly property bool isExpanded: Boolean(notifCol.expandedGroups[appName])
                            Layout.fillWidth: true
                            spacing: 4

                            // En-tête de pile repliable quand une app a >= 2 notifications
                            Rectangle {
                                visible: isGroup
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: 8
                                color: grpMa.containsMouse ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.surfaceVariant, 0.55)
                                border.color: Qt.alpha(Theme.accent, 0.28)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: isExpanded ? "▾" : "▸"
                                        font.pixelSize: 11
                                        color: Theme.accent
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: appName + " (" + items.length + ")" + (items[0] && items[0].summary ? (" · " + items[0].summary) : "")
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.textXs
                                        font.weight: Font.DemiBold
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: ruleGrpTxt.implicitWidth + 10
                                        Layout.preferredHeight: 20
                                        radius: 5
                                        color: ruleGrpMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                        z: 2

                                        Text {
                                            id: ruleGrpTxt
                                            anchors.centerIn: parent
                                            text: notifCol.ruleToastApp === appName ? "✓ Règle" : "+ Règle"
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: notifCol.ruleToastApp === appName ? Theme.success : Theme.accent
                                        }

                                        MouseArea {
                                            id: ruleGrpMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: notifCol.createRuleForApp(appName)
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: clrGrpTxt.implicitWidth + 10
                                        Layout.preferredHeight: 20
                                        radius: 5
                                        color: clrGrpMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.fg, 0.08)
                                        z: 2

                                        Text {
                                            id: clrGrpTxt
                                            anchors.centerIn: parent
                                            text: "Tout effacer"
                                            font.pixelSize: 9
                                            color: clrGrpMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.75)
                                        }

                                        MouseArea {
                                            id: clrGrpMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (ShellState.notifOps && ShellState.notifOps.clearApp) {
                                                    ShellState.notifOps.clearApp(appName)
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: grpMa
                                    anchors.fill: parent
                                    anchors.rightMargin: 130
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: notifCol.toggleGroup(appName)
                                }
                            }

                            // Cartes individuelles (toujours visibles si count === 1, sinon si déplié)
                            Repeater {
                                model: (!isGroup || isExpanded) ? items : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.leftMargin: isGroup ? 10 : 0
                                    Layout.preferredHeight: 48
                                    radius: 8
                                    color: nMa.containsMouse ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.surfaceVariant, 0.45)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                Layout.fillWidth: true
                                                text: (modelData.appName || "Notification") + (modelData.summary ? (" · " + modelData.summary) : "")
                                                font.family: Theme.fontUi
                                                font.pixelSize: Theme.textXs
                                                font.weight: Font.DemiBold
                                                color: Theme.fg
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.body || ""
                                                font.family: Theme.fontUi
                                                font.pixelSize: 10
                                                color: Qt.alpha(Theme.fg, 0.7)
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            visible: !isGroup
                                            Layout.preferredWidth: ruleBtnTxt.implicitWidth + 10
                                            Layout.preferredHeight: 20
                                            radius: 5
                                            color: ruleMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                                            z: 2

                                            Text {
                                                id: ruleBtnTxt
                                                anchors.centerIn: parent
                                                text: notifCol.ruleToastApp === appName ? "✓ Règle" : "+ Règle"
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: notifCol.ruleToastApp === appName ? Theme.success : Theme.accent
                                            }

                                            MouseArea {
                                                id: ruleMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: notifCol.createRuleForApp(appName)
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 22
                                            Layout.preferredHeight: 22
                                            radius: 6
                                            color: closeNMa.containsMouse ? Qt.alpha(Theme.error, 0.25) : "transparent"
                                            z: 2

                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                font.pixelSize: 11
                                                color: closeNMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.6)
                                            }

                                            MouseArea {
                                                id: closeNMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (ShellState.notifOps && ShellState.notifOps.forget) {
                                                        ShellState.notifOps.forget(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: nMa
                                        anchors.fill: parent
                                        anchors.rightMargin: isGroup ? 28 : 84
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (ShellState.notifOps && ShellState.notifOps.open) {
                                                ShellState.notifOps.open(modelData, function() { Theme.islandPanelOpen = false })
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Section Tâches & Agenda
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "TÂCHES (" + root.todoOpenCount + ") & AGENDA"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Qt.alpha(Theme.fg, 0.65)
            }

            // Taquet surveillance Hermès
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: hermesRow.implicitWidth + 12
                radius: 6
                color: root.todoSurveillance
                    ? Qt.alpha(Theme.accent, 0.22)
                    : (hermesMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.7) : Qt.alpha(Theme.surfaceVariant, 0.45))
                border.width: 1
                border.color: root.todoSurveillance ? Qt.alpha(Theme.accent, 0.55) : Qt.alpha(Theme.fg, 0.14)

                Row {
                    id: hermesRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hermès"
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        font.weight: root.todoSurveillance ? Font.DemiBold : Font.Normal
                        color: root.todoSurveillance ? Theme.accent : Qt.alpha(Theme.fg, 0.75)
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 13
                        radius: 7
                        color: root.todoSurveillance ? Theme.accent : Qt.alpha(Theme.fg, 0.22)

                        Rectangle {
                            width: 9
                            height: 9
                            radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.todoSurveillance ? 13 : 2
                            color: root.todoSurveillance ? Theme.bg : Theme.fg
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                MouseArea {
                    id: hermesMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (todoActionProc.running) return
                        root.todoSurveillance = !root.todoSurveillance
                        todoActionProc.command = [
                            Quickshell.shellPath("core/as-core"), "todo",
                            "surveillance", root.todoSurveillance ? "on" : "off"
                        ]
                        todoActionProc.running = true
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 6
                color: Theme.islandSidePanel === "todo-add"
                    ? Theme.accent
                    : (addTodoMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.45))
                border.width: 1
                border.color: Theme.islandSidePanel === "todo-add" ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
                    color: Theme.islandSidePanel === "todo-add" ? Theme.bg : (addTodoMa.containsMouse ? Theme.accent : Theme.fg)
                }

                MouseArea {
                    id: addTodoMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.islandSidePanel = (Theme.islandSidePanel === "todo-add" ? "" : "todo-add")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.30)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: todoListCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: todoListCol
                        width: parent.width
                        spacing: 5

                        Text {
                            visible: root.todoItems.length === 0
                            text: "Aucune tâche ouverte"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            color: Qt.alpha(Theme.fg, 0.55)
                        }

                        Repeater {
                            model: root.todoItems
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    radius: 4
                                    color: "transparent"
                                    border.width: 1.5
                                    border.color: Theme.accent

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            let tid = String(modelData.id || "")
                                            if (tid !== "") {
                                                todoActionProc.command = [Quickshell.shellPath("core/as-core"), "todo", "cocher", tid]
                                                todoActionProc.running = true
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.texte || modelData.text || modelData.titre || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: String(modelData.nom_fichier || "") !== ""
                                    text: String(modelData.nom_fichier || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    color: Qt.alpha(Theme.fg, 0.45)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
