/*
 * SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#pragma once

#include <QObject>
#include <QPointer>
#include <QWindow>
#include <qqmlregistration.h>

class QWidget;

namespace KParts
{
class ReadOnlyPart;
}

// Embeds konsolepart (the same KPart Kate/Yakuake use for their built-in terminals)
// and exposes its window as a QWindow so QML's WindowContainer can host it.
class TerminalHost : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QWindow *window READ window NOTIFY windowChanged)
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit TerminalHost(QObject *parent = nullptr);
    ~TerminalHost() override;

    QWindow *window() const;
    bool available() const { return m_available; }

    // Starts a shell in `directory`, then types `command` into it — mirrors how
    // Kate's konsolepart integration does "cd" via sendInput rather than a
    // separate startProgram() call, so a login shell (aliases, venv, etc.) is set up first.
    Q_INVOKABLE void runInDirectory(const QString &directory, const QString &command);
    Q_INVOKABLE void sendInput(const QString &text);

    // WindowContainer embeds the QWindow visually, but input focus (keyboard,
    // wheel) doesn't follow automatically — the platform has to be told this
    // foreign window is the active one, and the part's widget has to hold focus.
    Q_INVOKABLE void activate();

Q_SIGNALS:
    void windowChanged();

private:
    QPointer<QWidget> m_hostWidget;
    // QPointer, not a raw pointer: konsolepart deletes itself when the shell
    // inside exits (e.g. typing "exit"), so this must auto-null instead of dangling.
    QPointer<KParts::ReadOnlyPart> m_part;
    bool m_available = false;
};
