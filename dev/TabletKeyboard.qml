import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// Clavier virtuel tactile natif (AZERTY + symboles) pilotant evdev UInput sans
// jamais voler le focus clavier (WlrKeyboardFocus.None).
PanelWindow {
    id: root
    required property var targetScreen

    screen: root.targetScreen
    visible: TabletMode.keyboardOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: visible ? implicitHeight : 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "shell-tablet-keyboard"

    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: 314

    property bool shiftOn: false
    property int pageMode: 0 // 0 = Lettres AZERTY, 1 = Caractères spéciaux (?123), 2 = Chiffres & symboles mathématiques (123 / =+<)
    property bool ctrlOn: false
    property bool selectModeOn: false

    Process {
        id: kbdProc
        stdinEnabled: true
        command: [Quickshell.shellPath("core/as-core"), "tablet-mode", "kbd-pipe"]
        running: TabletMode.active || TabletMode.keyboardOpen
    }

    function sendKeySpec(spec) {
        if (!kbdProc.running) kbdProc.running = true
        let full = String(spec || "")
        if (!full) return
        if (root.ctrlOn && full.indexOf("CTRL+") < 0) {
            full = "CTRL+" + full
            root.ctrlOn = false
        }
        kbdProc.write(full + "\n")
    }

    function triggerAction(actionCode, uinputSpec) {
        if (TabletMode.launcherOpen || Theme.overviewVisible || Theme.islandNotesOpen) {
            TabletMode.sendLauncherKey("", actionCode)
        } else {
            root.sendKeySpec(uinputSpec)
        }
    }

    function stepCursorOrSelect(dir) {
        const base = dir < 0 ? "KEY_LEFT" : "KEY_RIGHT"
        const withShift = (root.selectModeOn || root.shiftOn)
        const spec = withShift ? ("SHIFT+" + base) : base
        if (TabletMode.launcherOpen || Theme.overviewVisible || Theme.islandNotesOpen) {
            TabletMode.sendLauncherKey("", spec)
        } else {
            root.sendKeySpec(spec)
        }
    }

    function pressChar(keyObj) {
        if (!keyObj) return
        if (keyObj.action === "shift") {
            if (root.pageMode === 0) root.shiftOn = !root.shiftOn
            else if (root.pageMode === 1) root.pageMode = 2
            else root.pageMode = 1
            return
        }
        if (keyObj.action === "sym") {
            if (root.pageMode === 0) root.pageMode = 1
            else root.pageMode = 0
            root.shiftOn = false
            return
        }
        if (keyObj.action === "ctrl") { root.ctrlOn = !root.ctrlOn; return }
        if (keyObj.action === "hide") { TabletMode.keyboardOpen = false; return }

        const rawSpec = String(keyObj.spec || "")
        if ((rawSpec === "KEY_LEFT" || rawSpec === "KEY_RIGHT") && (root.selectModeOn || root.shiftOn)) {
            root.stepCursorOrSelect(rawSpec === "KEY_LEFT" ? -1 : 1)
            return
        }

        if (TabletMode.launcherOpen || Theme.overviewVisible || Theme.islandNotesOpen) {
            const isSpecial = (rawSpec === "KEY_BACKSPACE" || rawSpec === "KEY_SPACE" || rawSpec === "KEY_ENTER" || rawSpec === "KEY_LEFT" || rawSpec === "KEY_RIGHT")
            const ch = isSpecial ? "" : root.keyLabel(keyObj)
            TabletMode.sendLauncherKey(ch, rawSpec)
            if (root.pageMode === 0 && root.shiftOn && !keyObj.keepShift) root.shiftOn = false
            return
        }

        let spec = ""
        if (root.pageMode === 2 && keyObj.mathSpec) spec = keyObj.mathSpec
        else if (root.pageMode === 1 && keyObj.symSpec) spec = keyObj.symSpec
        else if (root.pageMode === 0 && root.shiftOn && keyObj.shiftSpec) spec = keyObj.shiftSpec
        else if (root.pageMode === 0 && root.shiftOn && keyObj.alpha) spec = "SHIFT+" + keyObj.spec
        else spec = keyObj.spec

        root.sendKeySpec(spec)
        if (root.pageMode === 0 && root.shiftOn && !keyObj.keepShift) root.shiftOn = false
    }

    function keyLabel(k) {
        if (!k) return ""
        if (k.action === "shift") {
            if (root.pageMode === 0) return "⇧"
            if (root.pageMode === 1) return "123+"
            return "?#@"
        }
        if (k.action === "sym") {
            return root.pageMode === 0 ? "?123" : "ABC"
        }
        if (k.spec === "KEY_SPACE") {
            return (root.selectModeOn || (root.pageMode === 0 && root.shiftOn))
                ? "◂  Glisser pour sélectionner  ▸"
                : "◂  Espace · glisser = curseur  ▸"
        }
        if (root.pageMode === 2 && k.math !== undefined) return k.math
        if (root.pageMode === 1 && k.sym !== undefined) return k.sym
        if (root.pageMode === 0 && root.shiftOn && k.sh !== undefined) return k.sh
        if (root.pageMode === 0 && root.shiftOn && k.alpha) return k.lbl.toUpperCase()
        return k.lbl
    }

    readonly property var rows: [
        [
            { lbl: "é", alpha: true, sym: "!",  math: "1", spec: "KEY_2",                  shiftSpec: "UNICODE+00c9",             symSpec: "KEY_SLASH",            mathSpec: "SHIFT+KEY_1" },
            { lbl: "è", alpha: true, sym: "?",  math: "2", spec: "KEY_7",                  shiftSpec: "UNICODE+00c8",             symSpec: "SHIFT+KEY_M",          mathSpec: "SHIFT+KEY_2" },
            { lbl: "ê", alpha: true, sym: "@",  math: "3", spec: "KEY_LEFTBRACE,KEY_E",    shiftSpec: "KEY_LEFTBRACE,SHIFT+KEY_E",symSpec: "RALT+KEY_0",           mathSpec: "SHIFT+KEY_3" },
            { lbl: "ë", alpha: true, sym: "#",  math: "4", spec: "SHIFT+KEY_LEFTBRACE,KEY_E", shiftSpec: "SHIFT+KEY_LEFTBRACE,SHIFT+KEY_E", symSpec: "RALT+KEY_3", mathSpec: "SHIFT+KEY_4" },
            { lbl: "à", alpha: true, sym: "&",  math: "5", spec: "KEY_0",                  shiftSpec: "UNICODE+00c0",             symSpec: "KEY_1",                mathSpec: "SHIFT+KEY_5" },
            { lbl: "â", alpha: true, sym: "_",  math: "6", spec: "KEY_LEFTBRACE,KEY_Q",    shiftSpec: "KEY_LEFTBRACE,SHIFT+KEY_Q",symSpec: "KEY_8",                mathSpec: "SHIFT+KEY_6" },
            { lbl: "ù", alpha: true, sym: "-",  math: "7", spec: "KEY_APOSTROPHE",         shiftSpec: "UNICODE+00d9",             symSpec: "KEY_6",                mathSpec: "SHIFT+KEY_7" },
            { lbl: "û", alpha: true, sym: "'",  math: "8", spec: "KEY_LEFTBRACE,KEY_U",    shiftSpec: "KEY_LEFTBRACE,SHIFT+KEY_U",symSpec: "KEY_4",                mathSpec: "SHIFT+KEY_8" },
            { lbl: "ô", alpha: true, sym: "\"", math: "9", spec: "KEY_LEFTBRACE,KEY_O",    shiftSpec: "KEY_LEFTBRACE,SHIFT+KEY_O",symSpec: "KEY_3",                mathSpec: "SHIFT+KEY_9" },
            { lbl: "ç", alpha: true, sym: "/",  math: "0", spec: "KEY_9",                  shiftSpec: "UNICODE+00c7",             symSpec: "SHIFT+KEY_DOT",        mathSpec: "SHIFT+KEY_0" }
        ],
        [
            { lbl: "a", alpha: true, spec: "KEY_Q", sym: ":",  math: "+", symSpec: "KEY_DOT",        mathSpec: "SHIFT+KEY_EQUAL" },
            { lbl: "z", alpha: true, spec: "KEY_W", sym: ";",  math: "-", symSpec: "KEY_COMMA",      mathSpec: "KEY_6" },
            { lbl: "e", alpha: true, spec: "KEY_E", sym: ",",  math: "*", symSpec: "KEY_M",          mathSpec: "KEY_BACKSLASH" },
            { lbl: "r", alpha: true, spec: "KEY_R", sym: "(",  math: "/", symSpec: "KEY_5",          mathSpec: "SHIFT+KEY_DOT" },
            { lbl: "t", alpha: true, spec: "KEY_T", sym: ")",  math: "=", symSpec: "KEY_MINUS",      mathSpec: "KEY_EQUAL" },
            { lbl: "y", alpha: true, spec: "KEY_Y", sym: "[",  math: "%", symSpec: "RALT+KEY_5",     mathSpec: "SHIFT+KEY_APOSTROPHE" },
            { lbl: "u", alpha: true, spec: "KEY_U", sym: "]",  math: "^", symSpec: "RALT+KEY_MINUS", mathSpec: "RALT+KEY_9" },
            { lbl: "i", alpha: true, spec: "KEY_I", sym: "{",  math: "<", symSpec: "RALT+KEY_4",     mathSpec: "KEY_102ND" },
            { lbl: "o", alpha: true, spec: "KEY_O", sym: "}",  math: ">", symSpec: "RALT+KEY_EQUAL", mathSpec: "SHIFT+KEY_102ND" },
            { lbl: "p", alpha: true, spec: "KEY_P", sym: "\\", math: "~", symSpec: "RALT+KEY_8",     mathSpec: "RALT+KEY_2" }
        ],
        [
            { lbl: "q", alpha: true, spec: "KEY_A",         sym: "€", math: "(",  symSpec: "RALT+KEY_E",            mathSpec: "KEY_5" },
            { lbl: "s", alpha: true, spec: "KEY_S",         sym: "$", math: ")",  symSpec: "KEY_RIGHTBRACE",        mathSpec: "KEY_MINUS" },
            { lbl: "d", alpha: true, spec: "KEY_D",         sym: "£", math: "[",  symSpec: "SHIFT+KEY_RIGHTBRACE",  mathSpec: "RALT+KEY_5" },
            { lbl: "f", alpha: true, spec: "KEY_F",         sym: "§", math: "]",  symSpec: "SHIFT+KEY_8",           mathSpec: "RALT+KEY_MINUS" },
            { lbl: "g", alpha: true, spec: "KEY_G",         sym: "°", math: "{",  symSpec: "SHIFT+KEY_MINUS",       mathSpec: "RALT+KEY_4" },
            { lbl: "h", alpha: true, spec: "KEY_H",         sym: "~", math: "}",  symSpec: "RALT+KEY_2",            mathSpec: "RALT+KEY_EQUAL" },
            { lbl: "j", alpha: true, spec: "KEY_J",         sym: "|", math: "|",  symSpec: "RALT+KEY_6",            mathSpec: "RALT+KEY_6" },
            { lbl: "k", alpha: true, spec: "KEY_K",         sym: "`", math: "\\", symSpec: "RALT+KEY_7,KEY_SPACE",  mathSpec: "RALT+KEY_8" },
            { lbl: "l", alpha: true, spec: "KEY_L",         sym: "^", math: "²",  symSpec: "RALT+KEY_9",            mathSpec: "KEY_GRAVE" },
            { lbl: "m", alpha: true, spec: "KEY_SEMICOLON", sym: "*", math: "°",  symSpec: "KEY_BACKSLASH",         mathSpec: "SHIFT+KEY_MINUS" },
            { lbl: "⌫", spec: "KEY_BACKSPACE", w: 1.35, accent: true }
        ],
        [
            { lbl: "⇧", action: "shift", w: 1.35, activeProp: "shift" },
            { lbl: "w", alpha: true, spec: "KEY_Z", sym: "«", math: "±", symSpec: "RALT+KEY_Z",           mathSpec: "UNICODE+00b1" },
            { lbl: "x", alpha: true, spec: "KEY_X", sym: "»", math: "×", symSpec: "RALT+KEY_X",           mathSpec: "UNICODE+00d7" },
            { lbl: "c", alpha: true, spec: "KEY_C", sym: "+", math: "÷", symSpec: "SHIFT+KEY_EQUAL",      mathSpec: "UNICODE+00f7" },
            { lbl: "v", alpha: true, spec: "KEY_V", sym: "=", math: "≠", symSpec: "KEY_EQUAL",            mathSpec: "UNICODE+2260" },
            { lbl: "b", alpha: true, spec: "KEY_B", sym: "<", math: "≤", symSpec: "KEY_102ND",            mathSpec: "UNICODE+2264" },
            { lbl: "n", alpha: true, spec: "KEY_N", sym: ">", math: "≥", symSpec: "SHIFT+KEY_102ND",      mathSpec: "UNICODE+2265" },
            { lbl: "î", alpha: true, spec: "KEY_LEFTBRACE,KEY_I",       shiftSpec: "KEY_LEFTBRACE,SHIFT+KEY_I",       sym: "%", math: "≈", symSpec: "SHIFT+KEY_APOSTROPHE", mathSpec: "UNICODE+2248" },
            { lbl: "ï", alpha: true, spec: "SHIFT+KEY_LEFTBRACE,KEY_I", shiftSpec: "SHIFT+KEY_LEFTBRACE,SHIFT+KEY_I", sym: "µ", math: "√", symSpec: "SHIFT+KEY_BACKSLASH",  mathSpec: "UNICODE+221a" },
            { lbl: ",", sh: "?",     spec: "KEY_M", shiftSpec: "SHIFT+KEY_M", sym: "²", math: "π", symSpec: "KEY_GRAVE", mathSpec: "UNICODE+03c0" },
            { lbl: "↵", spec: "KEY_ENTER", w: 1.5, accent: true }
        ],
        [
            { lbl: "?123", action: "sym", w: 1.5, activeProp: "sym" },
            { lbl: "Ctrl", action: "ctrl", w: 1.2, activeProp: "ctrl" },
            { lbl: "←", spec: "KEY_LEFT", w: 1.0 },
            { lbl: "Espace", spec: "KEY_SPACE", w: 4.8 },
            { lbl: "→", spec: "KEY_RIGHT", w: 1.0 },
            { lbl: ".", spec: "SHIFT+KEY_COMMA", w: 1.0 },
            { lbl: "⌄", action: "hide", w: 1.2 }
        ]
    ]

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.surfaceBg, 0.96)
        border.color: Qt.alpha(Theme.accent, 0.35)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            // Barre supérieure d'actions rapides : sélection tactile au doigt & presse-papiers
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 28
                Layout.minimumHeight: 28
                Layout.maximumHeight: 28
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: 1.35 * 40
                    radius: 7
                    color: root.selectModeOn ? Theme.accent : Qt.alpha(Theme.surfaceVariant, 0.78)
                    border.color: root.selectModeOn ? Theme.accent : Qt.alpha(Theme.fg, 0.14)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.selectModeOn ? "✓ Sélect." : "Sélect."
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.bold: true
                        color: root.selectModeOn ? Theme.bg : Theme.fg
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selectModeOn = !root.selectModeOn
                    }
                }

                Repeater {
                    model: [
                        { lbl: "≪ Mot",  act: "CTRL+SHIFT+KEY_LEFT",  uinput: "CTRL+SHIFT+KEY_LEFT" },
                        { lbl: "Mot ≫",  act: "CTRL+SHIFT+KEY_RIGHT", uinput: "CTRL+SHIFT+KEY_RIGHT" },
                        { lbl: "Tout",   act: "ACTION_SELECT_ALL",    uinput: "CTRL+KEY_A" },
                        { lbl: "Copier", act: "ACTION_COPY",          uinput: "CTRL+KEY_C" },
                        { lbl: "Couper", act: "ACTION_CUT",           uinput: "CTRL+KEY_X" },
                        { lbl: "Coller", act: "ACTION_PASTE",         uinput: "CTRL+KEY_V" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: 40
                        radius: 7
                        color: actMa.pressed ? Theme.accent : Qt.alpha(Theme.surfaceVariant, 0.72)
                        border.color: Qt.alpha(Theme.accent, 0.25)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.lbl
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: actMa.pressed ? Theme.bg : Theme.fg
                        }

                        MouseArea {
                            id: actMa
                            anchors.fill: parent
                            onClicked: root.triggerAction(modelData.act, modelData.uinput)
                        }
                    }
                }
            }

            Repeater {
                model: root.rows
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 48
                    spacing: 6

                    Repeater {
                        model: modelData
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isActive: (modelData.activeProp === "shift" && ((root.pageMode === 0 && root.shiftOn) || root.pageMode === 2))
                                || (modelData.activeProp === "sym" && root.pageMode === 1)
                                || (modelData.activeProp === "num" && root.pageMode === 2)
                                || (modelData.activeProp === "ctrl" && root.ctrlOn)
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: 48
                            Layout.preferredWidth: (modelData.w || 1.0) * 40
                            radius: 10
                            color: keyMa.pressed
                                ? Theme.accent
                                : isActive
                                    ? Qt.alpha(Theme.accent, 0.35)
                                    : modelData.accent
                                        ? Qt.alpha(Theme.accent, 0.18)
                                        : Qt.alpha(Theme.surfaceVariant, 0.85)
                            border.color: isActive ? Theme.accent : Qt.alpha(Theme.fg, 0.12)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.keyLabel(modelData)
                                font.family: Theme.fontUi
                                font.pixelSize: modelData.spec === "KEY_SPACE" ? 13 : 17
                                font.weight: Font.DemiBold
                                color: keyMa.pressed
                                    ? Theme.bg
                                    : (modelData.spec === "KEY_SPACE" && (root.selectModeOn || root.shiftOn) ? Theme.accent : Theme.fg)
                            }

                            Timer {
                                id: repeatTimer
                                interval: 75
                                repeat: true
                                onTriggered: { if (keyMa.pressed) root.pressChar(modelData); else stop() }
                            }

                            Timer {
                                id: repeatDelay
                                interval: 380
                                onTriggered: { if (keyMa.pressed) repeatTimer.start() }
                            }

                            MouseArea {
                                id: keyMa
                                anchors.fill: parent
                                preventStealing: true
                                property real lastStepX: 0
                                property bool spaceDragged: false
                                onPressed: mouse => {
                                    const sp = String(modelData.spec || "")
                                    if (sp === "KEY_SPACE") {
                                        lastStepX = mouse.x
                                        spaceDragged = false
                                        return
                                    }
                                    root.pressChar(modelData)
                                    if (sp === "KEY_BACKSPACE" || sp === "KEY_LEFT" || sp === "KEY_RIGHT") repeatDelay.restart()
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed || String(modelData.spec || "") !== "KEY_SPACE") return
                                    const dx = mouse.x - lastStepX
                                    const stepPx = 14
                                    if (Math.abs(dx) >= stepPx) {
                                        const steps = Math.trunc(dx / stepPx)
                                        lastStepX += steps * stepPx
                                        spaceDragged = true
                                        const dir = steps > 0 ? 1 : -1
                                        const count = Math.min(6, Math.abs(steps))
                                        for (let i = 0; i < count; ++i) {
                                            root.stepCursorOrSelect(dir)
                                        }
                                    }
                                }
                                onReleased: {
                                    repeatDelay.stop()
                                    repeatTimer.stop()
                                    if (String(modelData.spec || "") === "KEY_SPACE" && !spaceDragged) {
                                        root.pressChar(modelData)
                                    }
                                    spaceDragged = false
                                }
                                onCanceled: {
                                    repeatDelay.stop()
                                    repeatTimer.stop()
                                    spaceDragged = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
