/*
 * SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import "ShellQuote.js" as ShellQuote

Item {
    id: root
    anchors.fill: parent

    property var sessions: []
    property var status: ({})
    property var quota: ({})
    property bool addingSession: false
    property bool soundEnabled: true

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
        property var pending: ({})
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            const callback = pending[sourceName]
            delete pending[sourceName]
            if (callback)
                callback(data)
        }
    }

    function runCommand(cmd, callback) {
        executable.pending[cmd] = callback || null
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
        })
    }

    function persist() {
        writeFile("~/.config/kclaude/sessions.json", JSON.stringify(sessions))
    }

    function reloadStatus() {
        readFile("~/.config/kclaude/status.json", function(text) {
            try {
                root.status = text ? JSON.parse(text) : ({})
            } catch (e) {
                root.status = ({})
            }
        })
    }

    function reloadQuota() {
        readFile("~/.config/kclaude/quota.json", function(text) {
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

    function removeSession(index) {
        const copy = sessions.slice()
        copy.splice(index, 1)
        sessions = copy
        persist()
    }

    function launch(session) {
        const cmd = "konsole --workdir " + ShellQuote.shellQuote(session.directory) +
            " -e claude --resume " + ShellQuote.shellQuote(session.sessionId)
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
            visible: !root.addingSession
            model: root.sessions
            clip: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                anchors.centerIn: parent
                visible: root.sessions.length === 0
                opacity: 0.6
                text: i18n("No sessions saved yet.")
            }

            delegate: PlasmaComponents.ItemDelegate {
                id: delegateRoot
                width: ListView.view.width
                onClicked: root.launch(modelData)

                readonly property var sessionStatus: root.status[modelData.sessionId]

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
                        icon.name: "edit-delete"
                        onClicked: root.removeSession(index)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.addingSession
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
                placeholderText: i18n("Directory, e.g. /home/alec/projects/KClaude")
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

            PlasmaComponents.Button {
                text: i18n("Cancel")
                visible: root.addingSession
                onClicked: root.addingSession = false
            }
            PlasmaComponents.Button {
                text: i18n("Save")
                visible: root.addingSession
                enabled: nameField.text.length > 0 && directoryField.text.length > 0 && sessionIdField.text.length > 0
                onClicked: {
                    root.sessions = root.sessions.concat([{
                        name: nameField.text,
                        description: descriptionField.text,
                        directory: directoryField.text,
                        sessionId: sessionIdField.text
                    }])
                    root.persist()
                    nameField.text = ""
                    descriptionField.text = ""
                    directoryField.text = ""
                    sessionIdField.text = ""
                    root.addingSession = false
                }
            }
            PlasmaComponents.Button {
                text: i18n("Add session")
                visible: !root.addingSession
                onClicked: root.addingSession = true
            }
        }
    }
}
