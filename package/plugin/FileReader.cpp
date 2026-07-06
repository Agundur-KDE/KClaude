/*
 * SPDX-FileCopyrightText: 2025 Agundur <info@agundur.de>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "FileReader.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>

// ponytail: "~" expansion is the one bit of shell convenience QFile doesn't do for us.
static QString expandTilde(const QString &path)
{
    if (path.startsWith(QLatin1Char('~')))
        return QDir::homePath() + path.mid(1);
    return path;
}

FileReader::FileReader(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &FileReader::readFile);
}

void FileReader::setPath(const QString &path)
{
    const QString resolved = expandTilde(path);
    if (m_path == resolved)
        return;

    if (!m_path.isEmpty())
        m_watcher.removePath(m_path);

    m_path = resolved;

    if (!m_path.isEmpty()) {
        if (QFile::exists(m_path))
            m_watcher.addPath(m_path);
        readFile();
    }

    Q_EMIT pathChanged();
}

void FileReader::reload()
{
    readFile();
}

bool FileReader::write(const QString &content)
{
    if (m_path.isEmpty())
        return false;

    QDir().mkpath(QFileInfo(m_path).absolutePath());

    QFile f(m_path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream(&f) << content;
    f.close();

    if (!m_watcher.files().contains(m_path))
        m_watcher.addPath(m_path);

    if (content != m_content) {
        m_content = content;
        Q_EMIT contentChanged();
    }
    return true;
}

void FileReader::readFile()
{
    QFile f(m_path);
    QString newContent;

    if (f.open(QIODevice::ReadOnly | QIODevice::Text))
        newContent = QTextStream(&f).readAll();

    if (newContent == m_content)
        return;

    m_content = newContent;
    Q_EMIT contentChanged();
}
