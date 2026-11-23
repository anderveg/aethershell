import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "."

// Lanceur d'applications tactile plein écran (swipe bas → haut en mode tablette) :
// dossiers par catégorie avec icône pertinente, ouverture par appui,
// centré en largeur et hauteur si le contenu ne remplit pas l'écran,
// icônes ≥ 64 px de taille réglable (64 / 80 / 96 / 128 px).
PanelWindow {
    id: root
    required property var targetScreen

    screen: root.targetScreen
    visible: TabletMode.launcherOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: TabletMode.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "shell-tablet-launcher"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    margins {
        bottom: TabletMode.keyboardOpen ? 314 : 0
    }

    property string query: ""
    property string selectedCategory: ""
    readonly property var sizeChoices: [64, 80, 96, 128]

    readonly property var categoryIcons: ({
        "Audio":         "headphones",
        "Bureautique":   "file-document",
        "Développement": "robot",
        "Graphisme":     "palette",
        "Jeu":           "rocket",
        "Média":         "music",
        "Navigateur":    "cloud",
        "Réglages":      "cog",
        "Réseau":        "wifi",
        "Système":       "speedometer",
        "Utilitaire":    "widgets",
        "Autres":        "folder"
    })

    function glyphForCategory(cat) {
        return root.categoryIcons[String(cat || "")] || "folder"
    }

    readonly property var folders: {
        const all = LauncherEngine.appIndex || []
        const byCat = ({})
        const cats = []
        for (let i = 0; i < all.length; ++i) {
            const a = all[i]
            if (!a) continue
            const cat = String(a.category || "Autres").trim() || "Autres"
            if (!byCat[cat]) {
                byCat[cat] = []
                cats.push(cat)
            }
            byCat[cat].push(a)
        }
        cats.sort(function(a, b) { return a.localeCompare(b) })
        const out = []
        for (let i = 0; i < cats.length; ++i) {
            out.push({
                category: cats[i],
                glyph: root.glyphForCategory(cats[i]),
                apps: byCat[cats[i]]
            })
        }
        return out
    }

    readonly property var displayedApps: {
        const all = LauncherEngine.appIndex || []
        const q = root.query.trim().toLowerCase()
        if (q) {
            const out = []
            for (let i = 0; i < all.length; ++i) {
                const a = all[i]
                if (!a) continue
                const hay = (String(a.name || "") + " " + String(a.comment || "") + " " + String(a.category || "") + " " + String(a.exec || "")).toLowerCase()
                if (hay.indexOf(q) >= 0) out.push(a)
            }
            return out
        }
        if (root.selectedCategory !== "") {
            for (let i = 0; i < root.folders.length; ++i) {
                if (root.folders[i].category === root.selectedCategory) return root.folders[i].apps
            }
        }
        return []
    }

    readonly property bool showingFolders: root.query.trim() === "" && root.selectedCategory === ""

    onVisibleChanged: {
        if (visible) {
            LauncherEngine.rebuildIndex()
        } else {
            root.query = ""
            root.selectedCategory = ""
            TabletMode.keyboardOpen = false
        }
    }

    Connections {
        target: TabletMode
        function onLauncherKeyInjected(keyText, keySpec) {
            if (!root.visible) return
            searchInput.forceActiveFocus()
            if (keySpec === "ACTION_SELECT_ALL") {
                searchInput.selectAll()
            } else if (keySpec === "ACTION_COPY") {
                searchInput.copy()
            } else if (keySpec === "ACTION_CUT") {
                searchInput.cut()
            } else if (keySpec === "ACTION_PASTE") {
                searchInput.paste()
            } else if (keySpec === "KEY_LEFT") {
                if (searchInput.selectedText.length > 0) searchInput.cursorPosition = searchInput.selectionStart
                else searchInput.cursorPosition = Math.max(0, searchInput.cursorPosition - 1)
            } else if (keySpec === "KEY_RIGHT") {
                if (searchInput.selectedText.length > 0) searchInput.cursorPosition = searchInput.selectionEnd
                else searchInput.cursorPosition = Math.min(searchInput.text.length, searchInput.cursorPosition + 1)
            } else if (keySpec === "SHIFT+KEY_LEFT") {
                searchInput.moveCursorSelection(Math.max(0, searchInput.cursorPosition - 1), TextInput.SelectCharacters)
            } else if (keySpec === "SHIFT+KEY_RIGHT") {
                searchInput.moveCursorSelection(Math.min(searchInput.text.length, searchInput.cursorPosition + 1), TextInput.SelectCharacters)
            } else if (keySpec === "CTRL+SHIFT+KEY_LEFT") {
                searchInput.moveCursorSelection(Math.max(0, searchInput.cursorPosition - 1), TextInput.SelectWords)
            } else if (keySpec === "CTRL+SHIFT+KEY_RIGHT") {
                searchInput.moveCursorSelection(Math.min(searchInput.text.length, searchInput.cursorPosition + 1), TextInput.SelectWords)
            } else if (keySpec === "KEY_BACKSPACE") {
                if (searchInput.selectedText.length > 0) {
                    searchInput.remove(searchInput.selectionStart, searchInput.selectionEnd)
                } else if (searchInput.cursorPosition > 0) {
                    searchInput.remove(searchInput.cursorPosition - 1, searchInput.cursorPosition)
                }
            } else if (keySpec === "KEY_SPACE") {
                if (searchInput.selectedText.length > 0) {
                    searchInput.remove(searchInput.selectionStart, searchInput.selectionEnd)
                }
                searchInput.insert(searchInput.cursorPosition, " ")
            } else if (keySpec === "KEY_ENTER") {
                if (root.displayedApps.length > 0) {
                    root.launchApp(root.displayedApps[0])
                }
            } else if (keyText !== "") {
                if (searchInput.selectedText.length > 0) {
                    searchInput.remove(searchInput.selectionStart, searchInput.selectionEnd)
                }
                searchInput.insert(searchInput.cursorPosition, keyText)
            }
        }
    }

    function iconSource(ic) {
        const s = String(ic || "").trim()
        if (!s) return ""
        return s.indexOf("/") === 0 ? ("file://" + s) : ("image://icon/" + s)
    }

    function launchApp(app) {
        if (!app || !app.exec) return
        Quickshell.execDetached(["sh", "-c", String(app.exec) + " &"])
        TabletMode.launcherOpen = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg, 0.86)

        MouseArea {
            anchors.fill: parent
            property real startY: 0
            onPressed: mouse => startY = mouse.y
            onReleased: mouse => {
                if (mouse.y - startY > 70) TabletMode.launcherOpen = false
                else if (Math.abs(mouse.y - startY) < 10) {
                    if (root.selectedCategory !== "") root.selectedCategory = ""
                    else TabletMode.launcherOpen = false
                }
            }
        }

        // Bande supérieure dédiée : swipe bas depuis le haut de l'écran -> ferme le tiroir
        MouseArea {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 28
            z: 10
            preventStealing: true
            property real startY: 0
            property bool fired: false
            onPressed: mouse => { startY = mouse.y; fired = false }
            onPositionChanged: mouse => {
                if (!fired && pressed && mouse.y - startY > 24) {
                    fired = true
                    TabletMode.launcherOpen = false
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 18

            // Barre supérieure : retour dossier (si ouvert) + recherche + réglage taille icônes + fermer
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    visible: root.selectedCategory !== "" && root.query.trim() === ""
                    Layout.preferredWidth: backRow.implicitWidth + 24
                    Layout.preferredHeight: 46
                    radius: 14
                    color: backMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.85)
                    border.color: Theme.accent
                    border.width: 1

                    Row {
                        id: backRow
                        anchors.centerIn: parent
                        spacing: 6

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "chevron-left"
                            size: 16
                            color: Theme.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.selectedCategory
                            font.family: Theme.fontUi
                            font.pixelSize: 15
                            font.bold: true
                            color: Theme.fg
                        }
                    }

                    MouseArea {
                        id: backMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedCategory = ""
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 14
                    color: Qt.alpha(Theme.surfaceVariant, 0.85)
                    border.color: searchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.16)
                    border.width: 1

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: 16
                        selectByMouse: true
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.bg
                        text: root.query
                        onTextChanged: root.query = text
                        onActiveFocusChanged: if (activeFocus) TabletMode.keyboardOpen = true
                        Keys.onEscapePressed: {
                            if (TabletMode.keyboardOpen) TabletMode.keyboardOpen = false
                            else if (root.selectedCategory !== "") root.selectedCategory = ""
                            else TabletMode.launcherOpen = false
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Rechercher une application…"
                            color: Qt.alpha(Theme.fg, 0.45)
                            font: parent.font
                            visible: parent.text === "" && !parent.activeFocus
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed: mouse => {
                            searchInput.forceActiveFocus()
                            TabletMode.keyboardOpen = true
                            mouse.accepted = false
                        }
                    }
                }

                // Bouton clavier virtuel intégré
                Rectangle {
                    width: 46
                    height: 46
                    radius: 12
                    color: TabletMode.keyboardOpen ? Theme.accent : Qt.alpha(Theme.surfaceVariant, 0.75)
                    border.color: TabletMode.keyboardOpen ? Theme.accent : Qt.alpha(Theme.fg, 0.14)
                    border.width: 1

                    Icon {
                        anchors.centerIn: parent
                        glyph: "keyboard"
                        size: 20
                        color: TabletMode.keyboardOpen ? Theme.bg : Theme.fg
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.forceActiveFocus()
                            TabletMode.toggleVirtualKeyboard()
                        }
                    }
                }

                // Sélecteur de taille d'icônes (>= 64 px)
                Row {
                    spacing: 6

                    Repeater {
                        model: root.sizeChoices
                        delegate: Rectangle {
                            required property int modelData
                            readonly property bool sel: TabletMode.launcherIconSize === modelData
                            width: 48
                            height: 46
                            radius: 12
                            color: sel ? Theme.accent : Qt.alpha(Theme.surfaceVariant, 0.75)
                            border.color: sel ? Theme.accent : Qt.alpha(Theme.fg, 0.14)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData + "px"
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.bold: true
                                color: sel ? Theme.bg : Theme.fg
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: TabletMode.launcherIconSize = modelData
                            }
                        }
                    }
                }

                Rectangle {
                    width: 46
                    height: 46
                    radius: 12
                    color: closeMa.containsMouse ? Qt.alpha(Theme.error, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.75)

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 18
                        color: Theme.fg
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: TabletMode.launcherOpen = false
                    }
                }
            }

            // Contenu centré en largeur et en hauteur s'il tient dans l'écran
            Flickable {
                id: appsFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, contentGrid.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                readonly property int iconPx: Math.max(64, TabletMode.launcherIconSize)
                readonly property int cellW: iconPx + 52
                readonly property int cellH: iconPx + 58
                readonly property int maxCols: Math.max(1, Math.floor(width / cellW))
                readonly property int itemCount: root.showingFolders ? root.folders.length : root.displayedApps.length

                Grid {
                    id: contentGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, (appsFlick.height - implicitHeight) / 2)
                    columns: Math.max(1, Math.min(appsFlick.itemCount, appsFlick.maxCols))

                    // Vue 1 : Dossiers de catégories
                    Repeater {
                        model: root.showingFolders ? root.folders : []

                        delegate: Item {
                            required property var modelData
                            width: appsFlick.cellW
                            height: appsFlick.cellH

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 8
                                radius: 18
                                color: fldMa.containsMouse || fldMa.pressed ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.58)
                                border.color: fldMa.pressed ? Theme.accent : Qt.alpha(Theme.accent, 0.28)
                                border.width: 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    width: parent.width - 14

                                    Icon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        glyph: modelData.glyph
                                        size: Math.round(appsFlick.iconPx * 0.72)
                                        color: Theme.accent
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.category
                                        color: Theme.fg
                                        font.family: Theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                    }
                                }

                                // Pastille nombre d'apps
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 8
                                    width: Math.max(22, cntTxt.implicitWidth + 10)
                                    height: 20
                                    radius: 10
                                    color: Qt.alpha(Theme.accent, 0.22)

                                    Text {
                                        id: cntTxt
                                        anchors.centerIn: parent
                                        text: String(modelData.apps.length)
                                        font.family: Theme.fontUi
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Theme.accent
                                    }
                                }

                                MouseArea {
                                    id: fldMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedCategory = modelData.category
                                }
                            }
                        }
                    }

                    // Vue 2 : Applications du dossier sélectionné ou résultats de recherche
                    Repeater {
                        model: root.showingFolders ? [] : root.displayedApps

                        delegate: Item {
                            required property var modelData
                            width: appsFlick.cellW
                            height: appsFlick.cellH

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 8
                                radius: 18
                                color: appMa.containsMouse || appMa.pressed ? Qt.alpha(Theme.accent, 0.18) : Qt.alpha(Theme.surface, 0.45)
                                border.color: appMa.pressed ? Theme.accent : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    width: parent.width - 14

                                    Image {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: appsFlick.iconPx
                                        height: appsFlick.iconPx
                                        sourceSize.width: appsFlick.iconPx
                                        sourceSize.height: appsFlick.iconPx
                                        fillMode: Image.PreserveAspectFit
                                        source: root.iconSource(modelData.icon)
                                        smooth: true
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: String(modelData.name || "")
                                        color: Theme.fg
                                        font.family: Theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: appMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.launchApp(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
