/*
 * SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import de.agundur.kclaude
import "ShellQuote.js" as ShellQuote

Item {
    id: root
    anchors.fill: parent

    property var sessions: []
    property var status: ({})
    property var quota: ({})
    property bool addingSession: false
    property bool soundEnabled: true

    // ponytail: JSON file instead of KConfig — sessions are a list of objects,
    // kcfg has no clean way to store that; a flat file + FileReader does.
    FileReader {
        id: store
        path: "~/.config/kclaude/sessions.json"
        onContentChanged: root.reload()
    }

    // Written by claude-notify.sh/claude-running.sh (per-session running/waiting).
    FileReader {
        id: statusStore
        path: "~/.config/kclaude/status.json"
        onContentChanged: {
            try {
                root.status = statusStore.content ? JSON.parse(statusStore.content) : ({})
            } catch (e) {
                root.status = ({})
            }
        }
    }

    // Written by claude-statusline.sh: account-wide rate-limit quota
    // (5h/7d window, NOT per-session context window).
    FileReader {
        id: quotaStore
        path: "~/.config/kclaude/quota.json"
        onContentChanged: {
            try {
                root.quota = quotaStore.content ? JSON.parse(quotaStore.content) : ({})
            } catch (e) {
                root.quota = ({})
            }
        }
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

    // Same toggle the claude-notify.sh Notification hook reads before playing a sound.
    FileReader {
        id: notifyStore
        path: "~/.config/kclaude/notify.json"
        onContentChanged: {
            try {
                root.soundEnabled = notifyStore.content ? (JSON.parse(notifyStore.content).sound !== false) : true
            } catch (e) {
                root.soundEnabled = true
            }
        }
    }

    function setSoundEnabled(enabled) {
        soundEnabled = enabled
        notifyStore.write(JSON.stringify({ sound: enabled }))
    }

    // ponytail: no C++ process launcher needed — the executable dataengine
    // is the standard Plasma way to run a shell command from QML.
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    function reload() {
        try {
            sessions = store.content ? JSON.parse(store.content) : []
        } catch (e) {
            sessions = []
        }
    }

    function persist() {
        store.write(JSON.stringify(sessions))
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
                text: i18n("Warning sound on prompts")
                checked: root.soundEnabled
                onToggled: root.setSoundEnabled(checked)
            }

            PlasmaComponents.ToolButton {
                icon.name: "accessories-screenshot-tool"
                text: i18n("Region screenshot to clipboard")
                display: PlasmaComponents.ToolButton.IconOnly
                onClicked: executable.connectSource("spectacle -r -b -n -c")
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
