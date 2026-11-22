pragma Singleton
import QtQuick
import Quickshell

// Activités en direct & minuteur de l'Îlot dynamique.
QtObject {
    id: root

    property var ipcActivities: []
    property int timerTotalSec: 0
    property int timerRemainingSec: 0
    property bool timerRunning: false
    property bool timerPaused: false
    property string timerLabel: "Minuteur"

    property Timer liveTimerTick: Timer {
        interval: 1000
        repeat: true
        running: root.timerRunning && !root.timerPaused
        onTriggered: {
            if (root.timerRemainingSec > 1) {
                root.timerRemainingSec -= 1
            } else {
                const lbl = root.timerLabel || "Minuteur"
                root.timerRunning = false
                root.timerPaused = false
                root.timerRemainingSec = 0
                root.timerTotalSec = 0
                Quickshell.execDetached(["notify-send", "-a", "AetherShell", lbl + " terminé", "Le décompte est arrivé à 0."])
            }
        }
    }

    function startTimer(minutes, label) {
        const mins = Math.max(1, Math.round(Number(minutes) || 0))
        root.timerTotalSec = mins * 60
        root.timerRemainingSec = mins * 60
        root.timerLabel = (label && String(label).trim() !== "") ? String(label).trim() : ("Minuteur " + mins + "m")
        root.timerPaused = false
        root.timerRunning = true
    }

    function togglePauseTimer() {
        if (!root.timerRunning) return
        root.timerPaused = !root.timerPaused
    }

    function stopTimer() {
        root.timerRunning = false
        root.timerPaused = false
        root.timerRemainingSec = 0
        root.timerTotalSec = 0
    }

    function handleLiveActivity(action, actId, title, progress) {
        const a = String(action || "").toLowerCase()
        const id = String(actId || "").trim()
        if (a === "clear") {
            root.ipcActivities = []
            return "ok"
        }
        if (!id) return "missing_id"
        const list = root.ipcActivities.slice()
        const idx = list.findIndex(x => x && x.id === id)
        if (a === "stop" || a === "remove" || a === "done") {
            if (idx >= 0) {
                list.splice(idx, 1)
                root.ipcActivities = list
            }
            return "ok"
        }
        const p = (progress !== undefined && progress !== null) ? Number(progress) : -1
        const prog = isNaN(p) ? -1 : (p < 0 ? -1 : Math.max(0, Math.min(100, Math.round(p))))
        if (a === "start" || (a === "update" && idx < 0)) {
            const item = {
                id: id,
                title: String(title || id),
                progress: prog,
                startedAt: Date.now()
            }
            if (idx >= 0) list[idx] = item
            else list.push(item)
            root.ipcActivities = list
            return "ok"
        }
        if (a === "update" && idx >= 0) {
            const cur = list[idx]
            list[idx] = {
                id: id,
                title: (title !== undefined && String(title) !== "") ? String(title) : cur.title,
                progress: prog,
                startedAt: cur.startedAt || Date.now()
            }
            root.ipcActivities = list
            return "ok"
        }
        return "unknown_action"
    }
}
