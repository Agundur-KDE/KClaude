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
    property bool soundEnabled: true
    property string defaultDir: ""
    property int cleanupPeriodDays: 30
    property var expiredSessionIds: []
    readonly property string homeDir: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0] || ""

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

    // Polled every 2s -- skip the reassignment when the file hasn't
    // changed, a fresh object every tick was tripping a Qt6 QML engine
    // GC/property-store crash (QV4::Object::insertMember) after enough
    // repeated churn.
    function reloadStatus() {
        readFile("~/.config/kclaude/status.json", function(text) {
            if (text === root.lastStatusText) return
            root.lastStatusText = text
            try {
                root.status = text ? JSON.parse(text) : ({})
            } catch (e) {
                root.status = ({})
            }
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

    function launch(session) {
        const dir = expandHome(session.directory)
        // setsid -f detaches konsole into its own session immediately, so it
        // survives even if this DataSource (and its QProcess) gets torn down
        // later (e.g. applet reload) — otherwise QProcess kills the still-
        // running child on destruction, taking the Claude session with it.
        let cmd = "setsid -f konsole --hold --workdir " + ShellQuote.shellQuote(dir) + " -e claude"
        if (session.sessionId)
            cmd += " --resume " + ShellQuote.shellQuote(session.sessionId)
        executable.connectSource(cmd)
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
    }

    // status.json/quota.json are written by external Claude Code hook
    // scripts — poll instead of the instant push a file watcher would give,
    // since pure QML has no cross-process file-change notification.
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.reloadStatus()
            root.reloadQuota()
        }
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
                icon.name: "configure"
                text: i18n("Settings")
                display: PlasmaComponents.ToolButton.IconOnly
                checkable: true
                checked: root.showSettings
                onClicked: root.showSettings = !root.showSettings
            }

            PlasmaComponents.ToolButton {
                icon.name: "window-pin"
                text: i18n("Keep window open")
                display: PlasmaComponents.ToolButton.IconOnly
                checkable: true
                checked: Plasmoid.configuration.pin
                onToggled: Plasmoid.configuration.pin = checked
                // Only meaningful when there's a popup to keep open. A
                // desktop-placed instance is embedded directly, nothing to
                // pin — same convention KDE Connect's own applet follows.
                visible: Plasmoid.location !== PlasmaCore.Types.Desktop

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

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.addingSession && !root.showSettings
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
                onClicked: root.launch(modelData)

                readonly property var sessionStatus: root.status[modelData.sessionId]
                readonly property bool isExpired: root.expiredSessionIds.indexOf(modelData.sessionId) !== -1

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
                        onClicked: {
                            nameField.text = modelData.name || ""
                            descriptionField.text = modelData.description || ""
                            directoryField.text = modelData.directory || ""
                            sessionIdField.text = modelData.sessionId || ""
                            root.editingIndex = index
                            root.addingSession = true
                        }
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
            visible: root.showSettings
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
            visible: root.addingSession && !root.showSettings
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

        RowLayout {
            Layout.alignment: Qt.AlignRight
            visible: !root.showSettings

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
