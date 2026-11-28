pragma ComponentBehavior: Bound

import QtQuick
import "."

// ────────────────────────────────────────────────────────────────────────────
// ÉCRAN DES RACCOURCIS — CLAVIER VISUEL INTERACTIF (SUPER + K)
//
// Super est toujours en surbrillance (état repos) car tous les raccourcis
// l'utilisent. Cliquer sur Shift, Ctrl ou Alt met à jour les touches affichées.
// ────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    property var binds: []
    property color surfaceColor: Theme.surfaceBg
    property bool etendu: true

    // Modificateurs combinables (état repos : tous à false, Super actif)
    property bool modShift: false
    property bool modCtrl: false
    property bool modAlt: false

    // Touche actuellement survolée pour l'info-bulle détaillée
    property var hoveredKeyInfo: null

    readonly property int unitW: 58
    readonly property int keyGap: 5
    readonly property int fnKeyH: 40
    readonly property int keyH: 62

    // Disposition normalisée depuis ConfigStore.kbLayout ("fr", "us", "de", "es", etc.)
    readonly property string layoutFamily: {
        const raw = (ConfigStore.kbLayout || "us").toLowerCase().split(",")[0].trim();
        if (raw === "fr" || raw === "be") return "azerty";
        if (raw === "de" || raw === "ch" || raw === "at") return "qwertz";
        if (raw === "es" || raw === "latam") return "es";
        return "qwerty";
    }

    // Raccourcis filtrés par Essentiels/Tous et parsés avec leurs modificateurs
    readonly property var parsedBinds: {
        const list = root.binds || [];
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const b = list[i];
            if (!root.etendu && !b.essentiel) continue;
            const parts = (b.key || "").split("+").map(s => s.trim()).filter(s => s.length > 0);
            if (parts.length === 0) continue;
            const desc = (b.description || "").trim();
            if (desc.length === 0) continue;
            const base = parts[parts.length - 1];
            const upperMods = parts.slice(0, parts.length - 1).map(s => s.toUpperCase());
            const needShift = upperMods.indexOf("SHIFT") >= 0;
            const needCtrl = upperMods.indexOf("CTRL") >= 0 || upperMods.indexOf("CONTROL") >= 0;
            const needAlt = upperMods.indexOf("ALT") >= 0;

            // Déplier la boucle F1..F9 des profils de thème
            if (base === "F" && (b.category || "").indexOf("F1") >= 0) {
                for (let fIdx = 1; fIdx <= 9; fIdx++) {
                    const fk = "F" + fIdx;
                    out.push({
                        raw: b,
                        baseKey: fk,
                        baseLower: fk.toLowerCase(),
                        needShift: needShift,
                        needCtrl: needCtrl,
                        needAlt: needAlt,
                        description: desc + " " + fIdx,
                        category: b.category || "",
                        dispatcher: b.dispatcher || "",
                        target: b.target || "",
                        essentiel: !!b.essentiel
                    });
                }
                continue;
            }

            out.push({
                raw: b,
                baseKey: base,
                baseLower: base.toLowerCase(),
                needShift: needShift,
                needCtrl: needCtrl,
                needAlt: needAlt,
                description: desc,
                category: b.category || "",
                dispatcher: b.dispatcher || "",
                target: b.target || "",
                essentiel: !!b.essentiel
            });
        }
        return out;
    }

    // Raccourcis correspondant à l'état actuel des modificateurs (Shift/Ctrl/Alt)
    readonly property var activeBinds: {
        const out = [];
        const all = root.parsedBinds;
        for (let i = 0; i < all.length; i++) {
            const b = all[i];
            if (b.needShift === root.modShift
                    && b.needCtrl === root.modCtrl
                    && b.needAlt === root.modAlt) {
                out.push(b);
            }
        }
        return out;
    }

    // Index des raccourcis actifs par baseLower pour recherche O(1) par touche
    readonly property var activeBindMap: {
        const map = {};
        const list = root.activeBinds;
        for (let i = 0; i < list.length; i++) {
            const b = list[i];
            if (map[b.baseLower] === undefined) {
                map[b.baseLower] = b;
            }
        }
        return map;
    }

    // Définition des rangées du clavier (chaque rangée totalise exactement 15.0u)
    readonly property var keyboardRows: {
        const fam = root.layoutFamily;
        const az = (fam === "azerty");
        const qz = (fam === "qwertz");
        const es = (fam === "es");

        const numRow = [
            { label: az ? "²" : "`", codes: ["grave", "twosuperior"], w: 1 },
            { label: az ? "1 &" : "1", codes: ["1", "ampersand"], w: 1 },
            { label: az ? "2 é" : "2", codes: ["2", "eacute"], w: 1 },
            { label: az ? "3 \"" : "3", codes: ["3", "quotedbl"], w: 1 },
            { label: az ? "4 '" : "4", codes: ["4", "apostrophe"], w: 1 },
            { label: az ? "5 (" : "5", codes: ["5", "parenleft"], w: 1 },
            { label: az ? "6 -" : "6", codes: ["6", "minus", "section"], w: 1 },
            { label: az ? "7 è" : "7", codes: ["7", "egrave"], w: 1 },
            { label: az ? "8 _" : "8", codes: ["8", "underscore"], w: 1 },
            { label: az ? "9 ç" : "9", codes: ["9", "ccedilla"], w: 1 },
            { label: az ? "0 à" : "0", codes: ["0", "agrave"], w: 1 },
            { label: az ? ")" : "-", codes: az ? ["parenright"] : ["minus"], w: 1 },
            { label: "=", codes: ["equal"], w: 1 },
            { label: "⌫", codes: ["BackSpace", "Backspace"], w: 2 }
        ];

        const topAlpha = az
            ? ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"]
            : (qz ? ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P"]
                  : ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]);
        const topRow = [{ label: "Tab", codes: ["Tab"], w: 1.5 }];
        for (let i = 0; i < topAlpha.length; i++) {
            topRow.push({ label: topAlpha[i], codes: [topAlpha[i]], w: 1 });
        }
        topRow.push({ label: az ? "^" : "[", codes: ["bracketleft", "dead_circumflex"], w: 1 });
        topRow.push({ label: az ? "$" : "]", codes: ["bracketright", "dollar"], w: 1 });
        topRow.push({ label: az ? "*" : "\\", codes: ["backslash", "asterisk"], w: 1.5 });

        const homeAlpha = az
            ? ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"]
            : ["A", "S", "D", "F", "G", "H", "J", "K", "L"];
        const homeRow = [{ label: "Caps", codes: ["Caps_Lock"], w: 1.75 }];
        for (let i = 0; i < homeAlpha.length; i++) {
            homeRow.push({ label: homeAlpha[i], codes: [homeAlpha[i]], w: 1 });
        }
        if (!az) {
            homeRow.push({ label: es ? "Ñ" : ";", codes: es ? ["ntilde", "semicolon"] : ["semicolon"], w: 1 });
        }
        homeRow.push({ label: az ? "ù" : "'", codes: az ? ["ugrave"] : ["apostrophe"], w: 1 });
        homeRow.push({ label: "Entrée", codes: ["Return", "KP_Enter"], w: 2.25 });

        const botAlpha = az
            ? ["W", "X", "C", "V", "B", "N"]
            : (qz ? ["Y", "X", "C", "V", "B", "N", "M"]
                  : ["Z", "X", "C", "V", "B", "N", "M"]);
        const botRow = [{ label: "Shift", codes: ["Shift_L"], w: 2.25, mod: "shift" }];
        for (let i = 0; i < botAlpha.length; i++) {
            botRow.push({ label: botAlpha[i], codes: [botAlpha[i]], w: 1 });
        }
        if (az) {
            botRow.push({ label: ",", codes: ["comma"], w: 1 });
            botRow.push({ label: ";", codes: ["semicolon"], w: 1 });
            botRow.push({ label: ":", codes: ["colon"], w: 1 });
            botRow.push({ label: "!", codes: ["exclam"], w: 1 });
        } else {
            botRow.push({ label: ",", codes: ["comma"], w: 1 });
            botRow.push({ label: ".", codes: ["period"], w: 1 });
            botRow.push({ label: qz ? "-" : "/", codes: [qz ? "minus" : "slash"], w: 1 });
        }
        botRow.push({ label: "Shift", codes: ["Shift_R"], w: 1.75, mod: "shift" });
        botRow.push({ label: "↑", codes: ["Up"], w: 1 });

        const modRow = [
            { label: "Ctrl", codes: ["Control_L"], w: 1.5, mod: "ctrl" },
            { label: "Super", codes: ["Super_L"], w: 1.5, mod: "super" },
            { label: "Alt", codes: ["Alt_L"], w: 1.25, mod: "alt" },
            { label: "Espace", codes: ["space"], w: 5.5 },
            { label: "Alt", codes: ["Alt_R"], w: 1.25, mod: "alt" },
            { label: "Ctrl", codes: ["Control_R"], w: 1.0, mod: "ctrl" },
            { label: "←", codes: ["Left"], w: 1 },
            { label: "↓", codes: ["Down"], w: 1 },
            { label: "→", codes: ["Right"], w: 1 }
        ];

        const fnRow = [
            { label: "Échap", codes: ["Escape"], w: 1, compact: true },
            { label: "F1", codes: ["F1"], w: 1, compact: true },
            { label: "F2", codes: ["F2"], w: 1, compact: true },
            { label: "F3", codes: ["F3"], w: 1, compact: true },
            { label: "F4", codes: ["F4"], w: 1, compact: true },
            { label: "F5", codes: ["F5"], w: 1, compact: true },
            { label: "F6", codes: ["F6"], w: 1, compact: true },
            { label: "F7", codes: ["F7"], w: 1, compact: true },
            { label: "F8", codes: ["F8"], w: 1, compact: true },
            { label: "F9", codes: ["F9"], w: 1, compact: true },
            { label: "F10", codes: ["F10"], w: 1, compact: true },
            { label: "F11", codes: ["F11"], w: 1, compact: true },
            { label: "F12", codes: ["F12"], w: 1, compact: true },
            { label: "Suppr", codes: ["Delete", "Print"], w: 2, compact: true }
        ];

        return [fnRow, numRow, topRow, homeRow, botRow, modRow];
    }

    // Ensemble des codes présents sur le clavier pour isoler souris / médias
    readonly property var keyboardCodeSet: {
        const set = {};
        const rows = root.keyboardRows;
        for (let r = 0; r < rows.length; r++) {
            const row = rows[r];
            for (let k = 0; k < row.length; k++) {
                const codes = row[k].codes || [];
                for (let c = 0; c < codes.length; c++) {
                    set[codes[c].toLowerCase()] = true;
                }
            }
        }
        return set;
    }

    // Raccourcis hors clavier (souris, molette, touches médias)
    readonly property var extraBinds: {
        const out = [];
        const list = root.activeBinds;
        const kbSet = root.keyboardCodeSet;
        const labels = {
            "mouse:272": "Clic gauche",
            "mouse:273": "Clic droit",
            "mouse_down": "Molette ↓",
            "mouse_up": "Molette ↑",
            "xf86audioraisevolume": "Vol +",
            "xf86audiolowervolume": "Vol −",
            "xf86audiomute": "Muet",
            "xf86audioplay": "Lecture",
            "xf86audionext": "Suivant",
            "xf86audioprev": "Précédent",
            "xf86monbrightnessup": "Lum +",
            "xf86monbrightnessdown": "Lum −"
        };
        for (let i = 0; i < list.length; i++) {
            const b = list[i];
            if (!kbSet[b.baseLower]) {
                out.push({
                    keyLabel: labels[b.baseLower] || b.baseKey,
                    description: b.description
                });
            }
        }
        return out;
    }

    function bindForKey(codes) {
        if (!codes) return null;
        const map = root.activeBindMap;
        for (let i = 0; i < codes.length; i++) {
            const found = map[codes[i].toLowerCase()];
            if (found) return found;
        }
        return null;
    }

    function allBindsForKey(codes) {
        if (!codes) return [];
        const codeSet = {};
        for (let i = 0; i < codes.length; i++) {
            codeSet[codes[i].toLowerCase()] = true;
        }
        const out = [];
        const all = root.parsedBinds;
        for (let i = 0; i < all.length; i++) {
            if (codeSet[all[i].baseLower]) {
                out.push(all[i]);
            }
        }
        return out;
    }

    function formatCombo(b, fallbackLabel) {
        let s = "SUPER";
        if (b) {
            if (b.needCtrl) s += " + CTRL";
            if (b.needAlt) s += " + ALT";
            if (b.needShift) s += " + SHIFT";
            s += " + " + (fallbackLabel || b.baseKey);
        } else {
            if (root.modCtrl) s += " + CTRL";
            if (root.modAlt) s += " + ALT";
            if (root.modShift) s += " + SHIFT";
            if (fallbackLabel) s += " + " + fallbackLabel;
        }
        return s;
    }

    function toggleModifier(modName) {
        if (modName === "shift") root.modShift = !root.modShift;
        else if (modName === "ctrl") root.modCtrl = !root.modCtrl;
        else if (modName === "alt") root.modAlt = !root.modAlt;
        else if (modName === "super") {
            root.modShift = false;
            root.modCtrl = false;
            root.modAlt = false;
        }
    }

    function keyWidthPx(units) {
        return Math.round(units * root.unitW + (units - 1) * root.keyGap);
    }

    implicitWidth: 15 * unitW + 14 * keyGap + 48
    implicitHeight: Math.max(220, content.implicitHeight + 44)

    SurfaceFloutee {
        anchors.fill: parent
        rayon: Theme.globalRadius
        teinte: root.surfaceColor
        bordureCouleur: Qt.alpha(Theme.accent, 0.22)
        bordureLargeur: 1
        actif: true

        Column {
            id: content
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            spacing: 14

            // ── En-tête ──────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 30

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        text: I18n.t("cheatsheet.title")
                        color: Theme.accent
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textMd
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Indicateur de combinaison active
                    Rectangle {
                        height: 24
                        width: comboRow.implicitWidth + 16
                        radius: Theme.globalRadius > 0 ? Math.min(Theme.globalRadius, 8) : 0
                        color: Qt.alpha(Theme.accent, 0.14)
                        border.width: 1
                        border.color: Qt.alpha(Theme.accent, 0.35)
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                            id: comboRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: {
                                    let s = "SUPER";
                                    if (root.modCtrl) s += " + CTRL";
                                    if (root.modAlt) s += " + ALT";
                                    if (root.modShift) s += " + SHIFT";
                                    return s;
                                }
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                            }

                            Text {
                                text: "(" + root.layoutFamily.toUpperCase() + ")"
                                color: Qt.alpha(Theme.fg, 0.65)
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: (root.modShift || root.modCtrl || root.modAlt)
                                ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.toggleModifier("super")
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    // Bascule Essentiels / Tous
                    Rectangle {
                        width: toggleText.implicitWidth + 20
                        height: 26
                        radius: Theme.globalRadius > 0 ? Math.min(Theme.globalRadius, 8) : 0
                        color: toggleArea.containsMouse
                            ? Qt.alpha(Theme.accent, 0.20)
                            : Qt.alpha(Theme.accent, 0.08)
                        border.color: Qt.alpha(Theme.accent, 0.30)
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: toggleText
                            anchors.centerIn: parent
                            text: root.etendu ? I18n.t("cheatsheet.essential") : I18n.t("cheatsheet.all")
                            color: Theme.accent
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            font.bold: true
                        }

                        MouseArea {
                            id: toggleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.etendu = !root.etendu
                        }
                    }

                    Text {
                        text: I18n.t("cheatsheet.close_hint")
                        color: Qt.alpha(Theme.fg, 0.65)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ── Clavier visuel ───────────────────────────────────────────
            Column {
                id: keyboardCol
                width: parent.width
                spacing: root.keyGap

                Repeater {
                    model: root.keyboardRows

                    delegate: Row {
                        id: rowDelegate
                        required property var modelData
                        required property int index
                        spacing: root.keyGap

                        Repeater {
                            model: rowDelegate.modelData

                            delegate: Rectangle {
                                id: keyRect
                                required property var modelData

                                readonly property string modName: modelData.mod || ""
                                readonly property bool isModifier: modName.length > 0
                                readonly property bool isModActive: modName === "super"
                                    ? true
                                    : (modName === "shift" ? root.modShift
                                       : (modName === "ctrl" ? root.modCtrl
                                          : (modName === "alt" ? root.modAlt : false)))

                                readonly property var matchedBind: isModifier ? null : root.bindForKey(modelData.codes)
                                readonly property bool hasBind: matchedBind !== null
                                readonly property bool isCompact: !!modelData.compact

                                width: root.keyWidthPx(modelData.w || 1)
                                height: isCompact ? root.fnKeyH : root.keyH
                                radius: Theme.globalRadius > 0 ? Math.min(Theme.globalRadius, 8) : 0

                                color: {
                                    if (isModifier && isModActive) {
                                        return modName === "super"
                                            ? Qt.alpha(Theme.accent, 0.28)
                                            : Qt.alpha(Theme.accent, 0.24);
                                    }
                                    if (keyMouse.containsMouse && isModifier) {
                                        return Qt.alpha(Theme.accent, 0.14);
                                    }
                                    if (hasBind) {
                                        return keyMouse.containsMouse
                                            ? Qt.alpha(Theme.accent, 0.20)
                                            : Qt.alpha(Theme.accent, 0.11);
                                    }
                                    return Qt.alpha(Theme.surfaceVariant, 0.38);
                                }

                                border.width: (isModifier && isModActive) ? 1.5 : 1
                                border.color: {
                                    if (isModifier && isModActive) return Theme.accent;
                                    if (isModifier && keyMouse.containsMouse) return Qt.alpha(Theme.accent, 0.55);
                                    if (hasBind) return Qt.alpha(Theme.accent, 0.45);
                                    return Qt.alpha(Theme.fg, 0.10);
                                }

                                Behavior on color { ColorAnimation { duration: 110 } }
                                Behavior on border.color { ColorAnimation { duration: 110 } }

                                // Lettre / légende en haut à gauche
                                Text {
                                    id: capLabel
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.topMargin: 5
                                    anchors.leftMargin: 6
                                    text: keyRect.modelData.label
                                    color: (keyRect.isModifier && keyRect.isModActive)
                                        ? Theme.accent
                                        : (keyRect.hasBind ? Theme.accent : Qt.alpha(Theme.fg, 0.55))
                                    font.family: Theme.fontUi
                                    font.pixelSize: keyRect.isCompact ? 10 : 11
                                    font.bold: true
                                }

                                // État ou action dans le corps de la touche
                                Text {
                                    anchors.top: capLabel.bottom
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.topMargin: 2
                                    anchors.bottomMargin: 4
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 5
                                    text: {
                                        if (keyRect.isModifier) {
                                            if (keyRect.modName === "super") return "Actif";
                                            return keyRect.isModActive ? "ON" : "";
                                        }
                                        return keyRect.hasBind ? keyRect.matchedBind.description : "";
                                    }
                                    color: keyRect.isModifier
                                        ? Theme.accent
                                        : Theme.fg
                                    font.family: Theme.fontUi
                                    font.pixelSize: keyRect.isCompact ? 9 : 10
                                    font.bold: keyRect.isModifier && keyRect.isModActive
                                    wrapMode: Text.Wrap
                                    maximumLineCount: keyRect.isCompact ? 1 : 2
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignBottom
                                    horizontalAlignment: Text.AlignLeft
                                }

                                MouseArea {
                                    id: keyMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: keyRect.isModifier ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onEntered: {
                                        const pos = keyRect.mapToItem(root, 0, 0);
                                        root.hoveredKeyInfo = {
                                            label: keyRect.modelData.label,
                                            codes: keyRect.modelData.codes,
                                            modName: keyRect.modName,
                                            activeBind: keyRect.matchedBind,
                                            allBinds: keyRect.isModifier ? [] : root.allBindsForKey(keyRect.modelData.codes),
                                            x: pos.x,
                                            y: pos.y,
                                            w: keyRect.width,
                                            h: keyRect.height
                                        };
                                    }
                                    onExited: {
                                        if (root.hoveredKeyInfo && root.hoveredKeyInfo.x === keyRect.mapToItem(root, 0, 0).x
                                                && root.hoveredKeyInfo.y === keyRect.mapToItem(root, 0, 0).y) {
                                            root.hoveredKeyInfo = null;
                                        }
                                    }
                                    onClicked: {
                                        if (keyRect.isModifier) {
                                            root.toggleModifier(keyRect.modName);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Bandeau souris & médias (raccourcis hors clavier) ─────────
            Flow {
                id: extraFlow
                width: parent.width
                spacing: 8
                visible: root.extraBinds.length > 0

                Repeater {
                    model: root.extraBinds

                    delegate: Rectangle {
                        id: extraPill
                        required property var modelData
                        height: 26
                        width: extraRow.implicitWidth + 16
                        radius: Theme.globalRadius > 0 ? Math.min(Theme.globalRadius, 8) : 0
                        color: Qt.alpha(Theme.surfaceVariant, 0.45)
                        border.width: 1
                        border.color: Qt.alpha(Theme.accent, 0.25)

                        Row {
                            id: extraRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: extraPill.modelData.keyLabel
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                            }

                            Text {
                                text: extraPill.modelData.description
                                color: Theme.fg
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Info-bulle détaillée au survol d'une touche ──────────────────────────
    Rectangle {
        id: keyTooltip

        readonly property var info: root.hoveredKeyInfo
        readonly property var activeBind: info ? info.activeBind : null
        readonly property var otherBinds: {
            if (!info || !info.allBinds) return [];
            const out = [];
            for (let i = 0; i < info.allBinds.length; i++) {
                const b = info.allBinds[i];
                if (activeBind && b === activeBind) continue;
                out.push(b);
            }
            return out;
        }
        readonly property bool hasContent: info !== null
            && (info.modName.length > 0 || activeBind !== null || otherBinds.length > 0)

        visible: hasContent
        z: 50
        width: 320
        height: tooltipCol.implicitHeight + 20
        radius: Theme.globalRadius > 0 ? Math.min(Theme.globalRadius, 10) : 0
        color: Theme.bg
        border.width: 1
        border.color: Qt.alpha(Theme.accent, 0.55)

        x: info
            ? Math.max(12, Math.min(root.width - width - 12, info.x + info.w / 2 - width / 2))
            : 0
        y: {
            if (!info) return 0;
            const above = info.y - height - 8;
            if (above >= 8) return above;
            return Math.min(root.height - height - 8, info.y + info.h + 8);
        }

        Column {
            id: tooltipCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            spacing: 6

            // En-tête : combinaison + catégorie
            Row {
                width: parent.width
                spacing: 8

                Text {
                    text: {
                        const i = keyTooltip.info;
                        if (!i) return "";
                        if (i.modName === "super") return "SUPER (touche de base)";
                        if (i.modName.length > 0) return "Modificateur " + i.modName.toUpperCase();
                        return root.formatCombo(keyTooltip.activeBind, i.label);
                    }
                    color: Theme.accent
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                Text {
                    visible: keyTooltip.activeBind !== null && keyTooltip.activeBind.category.length > 0
                    text: keyTooltip.activeBind ? ("· " + keyTooltip.activeBind.category) : ""
                    color: Qt.alpha(Theme.fg, 0.60)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Action principale ou aide modificateur
            Text {
                width: parent.width
                visible: text.length > 0
                text: {
                    const i = keyTooltip.info;
                    if (!i) return "";
                    if (i.modName === "super") {
                        return "Toujours actif. Cliquer pour réinitialiser Shift, Ctrl et Alt.";
                    }
                    if (i.modName.length > 0) {
                        return "Cliquer pour activer/désactiver + " + i.modName.toUpperCase() + " sur le clavier.";
                    }
                    if (keyTooltip.activeBind) {
                        return keyTooltip.activeBind.description;
                    }
                    return "Aucun raccourci pour cette combinaison.";
                }
                color: Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                wrapMode: Text.Wrap
            }

            // Dispatcher / commande Hyprland (si présent)
            Text {
                width: parent.width
                visible: keyTooltip.activeBind !== null && keyTooltip.activeBind.dispatcher.length > 0
                text: keyTooltip.activeBind
                    ? (keyTooltip.activeBind.dispatcher
                       + (keyTooltip.activeBind.target.length > 0 ? (" → " + keyTooltip.activeBind.target) : ""))
                    : ""
                color: Qt.alpha(Theme.fg, 0.55)
                font.family: Theme.fontUi
                font.pixelSize: Theme.text2xs
                elide: Text.ElideRight
            }

            // Autres combinaisons disponibles sur cette même touche
            Column {
                width: parent.width
                spacing: 3
                visible: keyTooltip.otherBinds.length > 0

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Theme.fg, 0.12)
                }

                Text {
                    text: "Autres combinaisons :"
                    color: Qt.alpha(Theme.fg, 0.60)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.bold: true
                }

                Repeater {
                    model: keyTooltip.otherBinds

                    delegate: Text {
                        required property var modelData
                        width: parent ? parent.width : 300
                        text: root.formatCombo(modelData, keyTooltip.info ? keyTooltip.info.label : "")
                              + " — " + modelData.description
                        color: Qt.alpha(Theme.fg, 0.82)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
