/*
 * SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "TerminalHost.h"

#include <KParts/ReadOnlyPart>
#include <KPluginFactory>
#include <kde_terminal_interface.h>

#include <QVBoxLayout>
#include <QWidget>
#include <QWindow>

TerminalHost::TerminalHost(QObject *parent)
    : QObject(parent)
{
    KPluginFactory *factory = KPluginFactory::loadFactory(QStringLiteral("kf6/parts/konsolepart")).plugin;
    m_available = factory != nullptr;
    if (!factory)
        return;

    m_part = factory->create<KParts::ReadOnlyPart>(this);
    if (!m_part) {
        m_available = false;
        return;
    }

    // Top-level (parent-less) so it can become its own native QWindow below —
    // WindowContainer in QML can only embed a real top-level QWindow.
    m_hostWidget = new QWidget;
    auto *layout = new QVBoxLayout(m_hostWidget);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->addWidget(m_part->widget());

    m_part->widget()->setFocusPolicy(Qt::StrongFocus);
    m_hostWidget->setFocusProxy(m_part->widget());

    m_hostWidget->winId(); // forces creation of the native window WindowContainer needs
    Q_EMIT windowChanged();
}

TerminalHost::~TerminalHost()
{
    delete m_hostWidget;
}

QWindow *TerminalHost::window() const
{
    return m_hostWidget ? m_hostWidget->windowHandle() : nullptr;
}

void TerminalHost::runInDirectory(const QString &directory, const QString &command)
{
    auto *iface = qobject_cast<TerminalInterface *>(m_part);
    if (!iface)
        return;

    iface->showShellInDir(directory);
    iface->sendInput(command + QLatin1Char('\n'));
}

void TerminalHost::sendInput(const QString &text)
{
    if (auto *iface = qobject_cast<TerminalInterface *>(m_part))
        iface->sendInput(text);
}

void TerminalHost::activate()
{
    if (auto *w = window())
        w->requestActivate();
    if (m_part)
        m_part->widget()->setFocus(Qt::OtherFocusReason);
}
