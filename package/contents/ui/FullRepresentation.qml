/*
 * SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "ShellQuote.js" as ShellQuote

Item {
    id: root
    anchors.fill: parent

    property var sessions: []
    property var status: ({})
    property var quota: ({})
    property string lastStatusText: ""
    property string lastQuotaText: ""
    property bool addingSession: false
    property int editingIndex: -1
    property bool showSettings: false
    property bool showImport: false
    property var importCandidates: []
    property var liveSessions: ({})
    property string exportMessage: ""
    property bool soundEnabled: true
    property string defaultDir: ""
    property int cleanupPeriodDays: 30
    property var expiredSessionIds: []
    property bool hasTmux: false
    property string lastMarker: ""
    readonly property string homeDir: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0] || ""

    signal sessionStartedWaiting(string sessionId)
    property bool statusInitialized: false

    // ponytail: no C++ file-IO plugin — read/write via the same executable
    // dataengine already used for launching sessions, so the plasmoid stays
    // pure QML (GHNS-installable, no compiled plugin to build).
    // QML's XMLHttpRequest can't read local files without a global env var
    // (QML_XHR_ALLOW_FILE_READ) we have no way to set for a panel widget —
    // verified empirically, not assumed. `cat`/shell redirection has no such
    // restriction and reuses infrastructure already proven to work here.
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        // Map, not a plain object: status/quota poll the same two command
        // strings forever, and repeatedly inserting+deleting the same keys
        // on a QML `property var` object (JS object shape churn) was
        // tripping a Qt6 QML engine crash (QV4::Object::insertMember) after
        // enough cycles. Map.set/get/delete don't touch object-shape
        // machinery the same way.
        property var pending: new Map()
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            const callback = pending.get(sourceName)
            pending.delete(sourceName)
            if (callback)
                callback(data)
        }
    }

    function runCommand(cmd, callback) {
        executable.pending.set(cmd, callback || null)
        executable.connectSource(cmd)
    }

    function readFile(path, callback) {
        runCommand("cat " + path, function(data) {
            callback(data["exit code"] === 0 ? data.stdout : "")
        })
    }

    function writeFile(path, content) {
        runCommand("mkdir -p ~/.config/kclaude && printf '%s' " +
            ShellQuote.shellQuote(content) + " > " + path)
    }

    function reload() {
        readFile("~/.config/kclaude/sessions.json", function(text) {
            try {
                root.sessions = text ? JSON.parse(text) : []
            } catch (e) {
                root.sessions = []
            }
            root.checkExpiredSessions()
        })
    }

    // Read-only: Claude Code's own cleanupPeriodDays setting (default 30),
    // from its global settings.json — never write to that file, it's not
    // ours and other Claude Code windows write to it too (race risk).
    function reloadCleanupPeriodDays() {
        readFile("~/.claude/settings.json", function(text) {
            try {
                const parsed = text ? JSON.parse(text) : {}
                root.cleanupPeriodDays = (typeof parsed.cleanupPeriodDays === "number") ? parsed.cleanupPeriodDays : 30
            } catch (e) {
                root.cleanupPeriodDays = 30
            }
        })
    }

    // A session's underlying transcript can be gone even though the
    // sessions.json shortcut still lists it — Claude Code deletes local
    // transcripts older than cleanupPeriodDays on its own. Checking the
    // actual file is more accurate than estimating from a saved date.
    function transcriptPath(session) {
        const dir = expandHome(session.directory).replace(/\/+$/, "")
        const encoded = dir.replace(/\//g, "-")
        return root.homeDir + "/.claude/projects/" + encoded + "/" + session.sessionId + ".jsonl"
    }

    function checkExpiredSessions() {
        for (const session of root.sessions) {
            if (!session.sessionId)
                continue
            const path = root.transcriptPath(session)
            runCommand("test -f " + ShellQuote.shellQuote(path), function(sessionId) {
                return function(data) {
                    const isExpired = data["exit code"] !== 0
                    const ids = root.expiredSessionIds.slice()
                    const pos = ids.indexOf(sessionId)
                    if (isExpired && pos === -1) ids.push(sessionId)
                    else if (!isExpired && pos !== -1) ids.splice(pos, 1)
                    root.expiredSessionIds = ids
                }
            }(session.sessionId))
        }
    }

    function persist() {
        writeFile("~/.config/kclaude/sessions.json", JSON.stringify(sessions))
    }

    function exportSessions() {
        runCommand("cp ~/.config/kclaude/sessions.json ~/kclaude-sessions-backup-$(date +%Y%m%d-%H%M%S).json",
            function(data) {
                root.exportMessage = data["exit code"] === 0
                    ? i18n("Backup saved to your home folder.")
                    : i18n("Export failed — no sessions saved yet?")
                exportMessageTimer.restart()
            })
    }

    // Finds Claude Code sessions on disk that aren't in sessions.json yet, so
    // they can be added without copy-pasting the session ID out of a
    // terminal. Reads only ai-title (last one wins — it's regenerated many
    // times over a session's life) as a name suggestion and cwd as the
    // directory; both are plain grep/sed, no jq (the widget itself has no
    // dependency beyond coreutils/konsole/kwin, jq is only used by the
    // separate hook scripts under scripts/).
    function reloadImportCandidates() {
        const cmd = "for f in ~/.claude/projects/*/*.jsonl; do "
            + "[ -f \"$f\" ] || continue; "
            + "sid=$(basename \"$f\" .jsonl); "
            + "cwd=$(grep -m1 -o '\"cwd\":\"[^\"]*\"' \"$f\" 2>/dev/null | sed 's/^\"cwd\":\"//;s/\"$//'); "
            + "title=$(grep -o '\"aiTitle\":\"[^\"]*\"' \"$f\" 2>/dev/null | tail -1 | sed 's/^\"aiTitle\":\"//;s/\"$//'); "
            + "printf '%s\\t%s\\t%s\\n' \"$sid\" \"$cwd\" \"$title\"; "
            + "done"
        runCommand(cmd, function(data) {
            const known = {}
            for (const s of root.sessions) known[s.sessionId] = true
            const candidates = []
            for (const line of (data.stdout || "").split("\n")) {
                if (!line) continue
                const parts = line.split("\t")
                const sid = parts[0] || ""
                if (!sid || known[sid]) continue
                candidates.push({ sessionId: sid, directory: parts[1] || "", name: parts[2] || "" })
            }
            root.importCandidates = candidates
        })
    }

    function addImportCandidate(index) {
        const c = root.importCandidates[index]
        if (!c) return
        root.sessions = root.sessions.concat([{
            name: c.name,
            description: "",
            directory: c.directory,
            sessionId: c.sessionId
        }])
        root.persist()
        const remaining = root.importCandidates.slice()
        remaining.splice(index, 1)
        root.importCandidates = remaining
    }

    // Live sessions (~/.claude/sessions/<pid>.json, one file per currently
    // running `claude` process) carry the name set via /rename or --name.
    // Mirrored into our own sessions one-way (Claude Code wins while
    // running) so KClaude's list and Claude Code's own /resume picker don't
    // silently drift apart — see FullRepresentation edit-lock below for the
    // other half of this (editing is disabled while a session is live).
    // ai-title is deliberately NOT synced this way: it's regenerated
    // constantly during normal use and would make the list flicker: it's
    // only used as a one-time suggestion in reloadImportCandidates() above.
    function reloadLiveSessions() {
        const cmd = "for f in ~/.claude/sessions/*.json; do [ -f \"$f\" ] && { cat \"$f\"; echo; }; done 2>/dev/null"
        runCommand(cmd, function(data) {
            const map = {}
            for (const line of (data.stdout || "").split("\n")) {
                if (!line) continue
                try {
                    const obj = JSON.parse(line)
                    if (obj.sessionId) map[obj.sessionId] = { name: obj.name || "", status: obj.status || "" }
                } catch (e) { /* partial/torn read this poll, skip */ }
            }
            root.liveSessions = map

            let changed = false
            const copy = root.sessions.slice()
            for (let i = 0; i < copy.length; i++) {
                const live = map[copy[i].sessionId]
                if (live && live.name && live.name !== copy[i].name) {
                    copy[i] = Object.assign({}, copy[i], { name: live.name })
                    changed = true
                }
            }
            if (changed) {
                root.sessions = copy
                root.persist()
            }
        })
    }

    // Polled every 2s -- skip the reassignment when the file hasn't
    // changed, a fresh object every tick was tripping a Qt6 QML engine
    // GC/property-store crash (QV4::Object::insertMember) after enough
    // repeated churn.
    function reloadStatus() {
        readFile("~/.config/kclaude/status.json", function(text) {
            if (text === root.lastStatusText) return
            root.lastStatusText = text
            const previous = root.status
            let next
            try {
                next = text ? JSON.parse(text) : ({})
            } catch (e) {
                next = ({})
            }
            // Flash only on the transition into "waiting", not on every poll
            // tick while it stays waiting, and never on the very first load
            // (nothing "transitioned", it was just read for the first time).
            if (root.statusInitialized) {
                for (const sessionId in next) {
                    const wasWaiting = previous[sessionId] && previous[sessionId].state === "waiting"
                    if (next[sessionId].state === "waiting" && !wasWaiting)
                        root.sessionStartedWaiting(sessionId)
                }
            }
            root.statusInitialized = true
            root.status = next
        })
    }

    function reloadQuota() {
        readFile("~/.config/kclaude/quota.json", function(text) {
            if (text === root.lastQuotaText) return
            root.lastQuotaText = text
            try {
                root.quota = text ? JSON.parse(text) : ({})
            } catch (e) {
                root.quota = ({})
            }
        })
    }

    function reloadNotify() {
        readFile("~/.config/kclaude/notify.json", function(text) {
            try {
                root.soundEnabled = text ? (JSON.parse(text).sound !== false) : true
            } catch (e) {
                root.soundEnabled = true
            }
        })
    }

    function setSoundEnabled(enabled) {
        soundEnabled = enabled
        writeFile("~/.config/kclaude/notify.json", JSON.stringify({ sound: enabled }))
    }

    function reloadSettings() {
        readFile("~/.config/kclaude/settings.json", function(text) {
            try {
                root.defaultDir = text ? (JSON.parse(text).defaultDir || "") : ""
            } catch (e) {
                root.defaultDir = ""
            }
        })
    }

    function setDefaultDir(dir) {
        defaultDir = dir
        writeFile("~/.config/kclaude/settings.json", JSON.stringify({ defaultDir: dir }))
    }

    function removeSession(index) {
        const copy = sessions.slice()
        copy.splice(index, 1)
        sessions = copy
        persist()
    }

    function expandHome(dir) {
        if (dir === "~") return root.homeDir || dir
        if (dir.indexOf("~/") === 0 && root.homeDir) return root.homeDir + dir.slice(1)
        return dir
    }

    // Already running -> raise its window, otherwise start it.
    function launch(session) {
        const dir = expandHome(session.directory)
        // setsid -f detaches konsole into its own session immediately, so it
        // survives even if this DataSource (and its QProcess) gets torn down
        // later (e.g. applet reload) — otherwise QProcess kills the still-
        // running child on destruction, taking the Claude session with it.
        let spawn = "setsid -f konsole --hold --workdir " + ShellQuote.shellQuote(dir) + " -e claude"

        // --name makes Claude Code itself show this session's KClaude name
        // in its own prompt box and /resume picker (live-verified: Konsole's
        // -p tabtitle= marker below, used for window-focus matching, is NOT
        // overwritten by this — a fixed tabtitle wins over the app's own
        // terminal-title escape sequences).
        if (session.name)
            spawn += " --name " + ShellQuote.shellQuote(session.name)

        if (!session.sessionId) {
            executable.connectSource(spawn)
            return
        }

        // sessionId is Claude Code's own UUID, safe to use unquoted as both
        // a pgrep pattern and a window-title marker. If a konsole tagged
        // with this session is already running, raise it via a KWin script
        // instead of spawning a duplicate — cheaper and more reliable than
        // embedding a terminal in the popup (no separate process lifetime
        // to manage, keeps normal window-manager behavior).
        const marker = "kclaude-" + session.sessionId
        root.lastMarker = marker
        spawn = spawn.replace("konsole --hold", "konsole --hold -p tabtitle=" + ShellQuote.shellQuote(marker))
        // Wrap claude in tmux so the cookie button can inject text via
        // `tmux send-keys` later — only when starting fresh (the "found"
        // branch below just raises the window, tmux is already running
        // inside from the original launch).
        if (root.hasTmux)
            spawn = spawn.replace("-e claude", "-e tmux new-session -s " + ShellQuote.shellQuote(marker) + " claude")
        spawn += " --resume " + ShellQuote.shellQuote(session.sessionId)

        // Plain `pgrep -f marker` self-matches: the whole command below is
        // passed as this very shell's own argv, so the marker text is always
        // present in ps output regardless of whether a real konsole is
        // running. Restrict to processes whose actual executable
        // (/proc/<pid>/comm) is konsole.
        const found = "found=0; for pid in $(pgrep -f " + ShellQuote.shellQuote(marker) + "); do "
            + "[ \"$(cat /proc/$pid/comm 2>/dev/null)\" = konsole ] && found=1; done; [ \"$found\" = 1 ]"

        const activate = focusCommand(marker)

        executable.connectSource("if " + found + "; then " + activate + "; else " + spawn + "; fi")
    }

    // KWin script that raises whichever window's caption contains `marker`.
    // Shared by launch() (raise instead of respawn) and sendCookie() (bring
    // the target session forward before the keystroke lands, so it doesn't
    // silently land in whatever else happens to be focused — e.g. KRunner).
    function focusCommand(marker) {
        const focusScript = "/tmp/" + marker + ".kwinscript.js"
        const js = "var w=workspace.windowList();for(var i=0;i<w.length;i++){"
            + "if(w[i].caption&&w[i].caption.indexOf(" + JSON.stringify(marker) + ")!==-1){"
            + "workspace.activeWindow=w[i];}}"
        // loadScript fails (-1) if a plugin under this name is already
        // loaded — unload first so every activation starts from a clean
        // slate regardless of leftover state from a previous call.
        return "cat > " + ShellQuote.shellQuote(focusScript) + " <<'EOF'\n" + js + "\nEOF\n"
            + "qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript kclaude-focus\n"
            + "qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "
            + ShellQuote.shellQuote(focusScript) + " kclaude-focus\n"
            + "qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start"
    }

    function formatResetTime(epochSeconds) {
        if (!epochSeconds) return "?"
        const d = new Date(epochSeconds * 1000)
        const pad = n => n.toString().padStart(2, "0")
        const today = new Date()
        const time = pad(d.getHours()) + ":" + pad(d.getMinutes())
        if (d.toDateString() === today.toDateString()) return time
        return pad(d.getDate()) + "." + pad(d.getMonth() + 1) + ". " + time
    }

    Component.onCompleted: {
        reload()
        reloadNotify()
        reloadSettings()
        reloadCleanupPeriodDays()
        checkTmux()
    }

    // Cookie injection (tmux send-keys) needs tmux wrapping the claude
    // process, not just installed — check once, sessions launched before
    // this check runs still spawn the old (unwrapped) way this run.
    function checkTmux() {
        runCommand("command -v tmux", function(data) {
            root.hasTmux = data["exit code"] === 0
        })
    }

    // tmux send-keys writes straight into the pty, works identically on
    // X11 and Wayland — unlike xdotool/ydotool it needs no global input-
    // injection daemon or /dev/uinput permissions. lastMarker is whichever
    // session KClaude most recently launched/focused; there's no separate
    // "active session" query, so this is the practical proxy for it.
    function sendCookie() {
        if (!root.hasTmux || !root.lastMarker) return
        const marker = root.lastMarker
        const cookie = "tmux send-keys -t " + ShellQuote.shellQuote(marker)
            + " " + ShellQuote.shellQuote("🍪") + " Enter"
        runCommand(focusCommand(marker) + "\n" + cookie)
    }

    // status.json/quota.json are written by external Claude Code hook
    // scripts, ~/.claude/sessions/*.json by Claude Code's own CLI — poll
    // instead of the instant push a file watcher would give, since pure QML
    // has no cross-process file-change notification.
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.reloadStatus()
            root.reloadQuota()
            root.reloadLiveSessions()
        }
    }

    Timer {
        id: exportMessageTimer
        interval: 3000
        onTriggered: root.exportMessage = ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents.Label {
                text: i18n("KClaude Sessions")
                font.bold: true
                Layout.fillWidth: true
            }

            PlasmaComponents.CheckBox {
                id: soundCheckbox
                text: i18n("Warning sound on prompts")
                checked: root.soundEnabled
                onToggled: root.setSoundEnabled(checked)
            }

            Kirigami.Separator {
                Layout.preferredHeight: soundCheckbox.height * 0.7
            }

            PlasmaComponents.ToolButton {
                icon.name: "accessories-screenshot-tool"
                text: i18n("Region screenshot to clipboard")
                display: PlasmaComponents.ToolButton.IconOnly
                onClicked: executable.connectSource("spectacle -r -b -n -c")

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Screenshot a region → clipboard. Paste with Ctrl+V, e.g. into the Claude Code terminal.")
            }

            PlasmaComponents.ToolButton {
                icon.name: "document-import"
                text: i18n("Import sessions from disk")
                display: PlasmaComponents.ToolButton.IconOnly
                checkable: true
                checked: root.showImport
                onClicked: {
                    root.showImport = !root.showImport
                    if (root.showImport) {
                        root.addingSession = false
                        root.showSettings = false
                        root.editingIndex = -1
                        root.reloadImportCandidates()
                    }
                }

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Find existing Claude Code sessions on disk that aren't saved here yet")
            }

            PlasmaComponents.ToolButton {
                icon.name: "document-export"
                text: i18n("Export sessions as backup")
                display: PlasmaComponents.ToolButton.IconOnly
                onClicked: root.exportSessions()

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Save a timestamped backup copy of your saved sessions to your home folder")
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                text: i18n("Settings")
                display: PlasmaComponents.ToolButton.IconOnly
                checkable: true
                checked: root.showSettings
                onClicked: {
                    root.showSettings = !root.showSettings
                    if (root.showSettings) {
                        root.addingSession = false
                        root.showImport = false
                        root.editingIndex = -1
                    }
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "window-pin"
                text: i18n("Keep window open")
                display: PlasmaComponents.ToolButton.IconOnly
                checkable: true
                checked: Plasmoid.configuration.pin
                onToggled: Plasmoid.configuration.pin = checked
                // Only meaningful when there's a popup to keep open. Desktop
                // placement embeds directly, nothing to pin. Checking
                // membership in the panel edges (not just "!== Desktop") is
                // KDE Connect's own proven pattern for this — the modern
                // org.kde.plasma.folder desktop containment reports
                // Floating, not Desktop, so excluding only Desktop still
                // showed the pin there.
                visible: [
                    PlasmaCore.Types.TopEdge, PlasmaCore.Types.RightEdge,
                    PlasmaCore.Types.BottomEdge, PlasmaCore.Types.LeftEdge,
                ].includes(Plasmoid.location)

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: i18n("Keep this window open even when it loses focus")
            }
        }

        PlasmaComponents.Label {
            visible: !!root.quota.five_hour || !!root.quota.seven_day
            opacity: 0.85
            text: i18n("5h: %1% (Reset %2)   ·   7d: %3% (Reset %4)",
                root.quota.five_hour ? root.quota.five_hour.used_percentage : "?",
                root.quota.five_hour ? root.formatResetTime(root.quota.five_hour.resets_at) : "?",
                root.quota.seven_day ? root.quota.seven_day.used_percentage : "?",
                root.quota.seven_day ? root.formatResetTime(root.quota.seven_day.resets_at) : "?")
        }

        PlasmaComponents.Label {
            visible: root.exportMessage.length > 0
            opacity: 0.7
            font.italic: true
            text: root.exportMessage
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.addingSession && !root.showSettings && !root.showImport
            model: root.sessions
            clip: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.ScrollBar.vertical: PlasmaComponents.ScrollBar {}

            PlasmaComponents.Label {
                anchors.centerIn: parent
                visible: root.sessions.length === 0
                opacity: 0.6
                text: i18n("No sessions saved yet.")
            }

            delegate: PlasmaComponents.ItemDelegate {
                id: delegateRoot
                width: ListView.view.width
                rightPadding: Kirigami.Units.gridUnit
                opacity: isExpired ? 0.5 : 1
                // Single click: already running -> raise it, otherwise start it.
                onClicked: root.launch(modelData)

                background: Rectangle {
                    id: flashBackground
                    color: "red"
                    opacity: 0
                }
                SequentialAnimation {
                    id: flashAnimation
                    PropertyAction { target: flashBackground; property: "opacity"; value: 0.6 }
                    PauseAnimation { duration: 1000 }
                    NumberAnimation { target: flashBackground; property: "opacity"; to: 0; duration: 1800; easing.type: Easing.OutQuad }
                }
                Connections {
                    target: root
                    function onSessionStartedWaiting(sessionId) {
                        if (sessionId === modelData.sessionId) flashAnimation.restart()
                    }
                }

                readonly property var sessionStatus: root.status[modelData.sessionId]
                readonly property bool isExpired: root.expiredSessionIds.indexOf(modelData.sessionId) !== -1
                readonly property bool isLive: !!root.liveSessions[modelData.sessionId]

                PlasmaComponents.ToolTip.visible: isExpired && hovered
                PlasmaComponents.ToolTip.text: i18n("Claude Code already deleted this session's local transcript (older than %1 days) — resuming will start a fresh session instead.", root.cleanupPeriodDays)

                contentItem: RowLayout {
                    Rectangle {
                        Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.5
                        Layout.preferredHeight: Layout.preferredWidth
                        radius: width / 2
                        color: !delegateRoot.sessionStatus ? "transparent"
                            : delegateRoot.sessionStatus.state === "waiting" ? "orange"
                            : "green"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        PlasmaComponents.Label {
                            text: modelData.name
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            text: modelData.description || modelData.directory
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    PlasmaComponents.ToolButton {
                        icon.name: "edit-entry"
                        enabled: !delegateRoot.isLive
                        onClicked: {
                            nameField.text = modelData.name || ""
                            descriptionField.text = modelData.description || ""
                            directoryField.text = modelData.directory || ""
                            sessionIdField.text = modelData.sessionId || ""
                            root.editingIndex = index
                            root.addingSession = true
                        }

                        PlasmaComponents.ToolTip.visible: delegateRoot.isLive && hovered
                        PlasmaComponents.ToolTip.text: i18n("Managed by the running Claude Code session — use /rename there instead")
                    }
                    PlasmaComponents.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: root.removeSession(index)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showSettings && !root.showImport
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: i18n("Default directory for \"New session\"")
                opacity: 0.7
            }
            PlasmaComponents.TextField {
                id: defaultDirField
                Layout.fillWidth: true
                placeholderText: i18n("e.g. ~/projects")
                text: root.defaultDir
            }

            Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

            PlasmaComponents.Label {
                text: i18n("Session retention (Claude Code setting, read-only)")
                opacity: 0.7
            }
            PlasmaComponents.Label {
                text: i18n("Claude Code keeps a session's local transcript for %1 days, then deletes it automatically — resuming an older one here starts fresh instead. Change cleanupPeriodDays in ~/.claude/settings.json if you want longer retention.", root.cleanupPeriodDays)
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.6
                font.italic: true
            }

            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                PlasmaComponents.Button {
                    text: i18n("Save")
                    onClicked: {
                        root.setDefaultDir(defaultDirField.text)
                        root.showSettings = false
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.addingSession && !root.showSettings && !root.showImport
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: i18n("Name")
            }
            PlasmaComponents.TextField {
                id: descriptionField
                Layout.fillWidth: true
                placeholderText: i18n("Description (optional)")
            }
            PlasmaComponents.TextField {
                id: directoryField
                Layout.fillWidth: true
                placeholderText: i18n("Directory, e.g. ~/projects/KClaude")
            }
            PlasmaComponents.TextField {
                id: sessionIdField
                Layout.fillWidth: true
                placeholderText: i18n("Session ID (from claude --resume)")
            }
            Item { Layout.fillHeight: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showImport
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: i18n("Sessions found on disk, not saved yet")
                    opacity: 0.7
                    Layout.fillWidth: true
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    text: i18n("Refresh")
                    display: PlasmaComponents.ToolButton.IconOnly
                    onClicked: root.reloadImportCandidates()

                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.text: i18n("Scan again")
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.importCandidates
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.ScrollBar.vertical: PlasmaComponents.ScrollBar {}

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Kirigami.Units.gridUnit
                    visible: root.importCandidates.length === 0
                    opacity: 0.6
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: i18n("No new sessions found. Sessions already saved here are skipped.")
                }

                delegate: PlasmaComponents.ItemDelegate {
                    width: ListView.view.width
                    contentItem: RowLayout {
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            PlasmaComponents.Label {
                                text: modelData.name || i18n("(unnamed)")
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PlasmaComponents.Label {
                                text: modelData.directory
                                opacity: 0.7
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        PlasmaComponents.ToolButton {
                            icon.name: "list-add"
                            text: i18n("Add")
                            display: PlasmaComponents.ToolButton.IconOnly
                            onClicked: root.addImportCandidate(index)

                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.text: i18n("Save this session to the list above")
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                PlasmaComponents.Button {
                    text: i18n("Close")
                    onClicked: root.showImport = false
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.showSettings && !root.showImport

            PlasmaComponents.Button {
                text: "🍪"
                visible: !root.addingSession
                enabled: root.hasTmux && root.lastMarker.length > 0
                onClicked: root.sendCookie()

                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.text: !root.hasTmux
                    ? i18n("Requires tmux (not installed)")
                    : (root.lastMarker ? i18n("Send a cookie to the active session") : i18n("Open a session first"))
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents.Button {
                text: i18n("Cancel")
                visible: root.addingSession
                onClicked: {
                    root.addingSession = false
                    root.editingIndex = -1
                }
            }
            PlasmaComponents.Button {
                text: root.editingIndex >= 0 ? i18n("Change") : i18n("Save")
                visible: root.addingSession
                enabled: nameField.text.length > 0 && directoryField.text.length > 0 && sessionIdField.text.length > 0
                onClicked: {
                    // Trim: pasting a session ID/path often drags along a
                    // trailing newline, which silently breaks both the
                    // transcript-path lookup and the actual --resume call.
                    const entry = {
                        name: nameField.text.trim(),
                        description: descriptionField.text.trim(),
                        directory: directoryField.text.trim(),
                        sessionId: sessionIdField.text.trim()
                    }
                    if (root.editingIndex >= 0) {
                        const copy = root.sessions.slice()
                        copy[root.editingIndex] = entry
                        root.sessions = copy
                    } else {
                        root.sessions = root.sessions.concat([entry])
                    }
                    root.persist()
                    nameField.text = ""
                    descriptionField.text = ""
                    directoryField.text = ""
                    sessionIdField.text = ""
                    root.addingSession = false
                    root.editingIndex = -1
                }
            }
            PlasmaComponents.Button {
                text: i18n("New session")
                visible: !root.addingSession
                enabled: root.defaultDir.length > 0
                onClicked: root.launch({ directory: root.defaultDir, sessionId: "" })

                PlasmaComponents.ToolTip.visible: hovered && !enabled
                PlasmaComponents.ToolTip.text: i18n("Set a default directory in Settings first.")
            }
            PlasmaComponents.Button {
                text: i18n("Add session")
                visible: !root.addingSession
                onClicked: root.addingSession = true
            }
        }
    }
}
