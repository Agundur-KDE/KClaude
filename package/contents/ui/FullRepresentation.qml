/*
 * SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Window as Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.components 3.0 as PlasmaComponents
import de.agundur.kclaude
import "ShellQuote.js" as ShellQuote

Item {
    id: root
    anchors.fill: parent

    property var sessions: []
    property bool terminalActive: false
    property bool addingSession: false

    // ponytail: JSON file instead of KConfig — sessions are a list of objects,
    // kcfg has no clean way to store that; a flat file + FileReader does.
    FileReader {
        id: store
        path: "~/.config/kclaude/sessions.json"
        onContentChanged: root.reload()
    }

    TerminalHost {
        id: terminal
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
        terminalActive = true
        terminal.runInDirectory(session.directory, "claude --resume " + ShellQuote.shellQuote(session.sessionId))
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: !root.terminalActive

        PlasmaComponents.Label {
            text: i18n("KClaude Sessions")
            font.bold: true
            Layout.fillWidth: true
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
                width: ListView.view.width
                onClicked: root.launch(modelData)

                contentItem: RowLayout {
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

    ColumnLayout {
        anchors.fill: parent
        visible: root.terminalActive
        spacing: 0

        PlasmaComponents.ToolButton {
            icon.name: "go-previous"
            text: i18n("Back to sessions")
            onClicked: root.terminalActive = false
        }

        Window.WindowContainer {
            id: terminalContainer
            window: terminal.window
            focus: true
            Layout.fillWidth: true
            Layout.fillHeight: true

            Component.onCompleted: terminal.activate()
        }
    }

    onTerminalActiveChanged: if (terminalActive) terminal.activate()
}
