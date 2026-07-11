import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    preferredRepresentation: {
        const edge = Plasmoid.location;
        if (edge === PlasmaCore.Types.TopEdge || edge === PlasmaCore.Types.BottomEdge
                || edge === PlasmaCore.Types.LeftEdge || edge === PlasmaCore.Types.RightEdge)
            return compactRepresentation;
        return fullRepresentation;
    }

    Plasmoid.title: i18n("KClaude")
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    toolTipMainText: Plasmoid.title

    // hideOnWindowDeactivate belongs to the root PlasmoidItem (AppletQuickItem
    // in C++), not to the Plasmoid interface object — it can't be reached as
    // Plasmoid.hideOnWindowDeactivate from FullRepresentation.qml. Routing the
    // pin state through Plasmoid.configuration (KConfigXT, config/main.xml)
    // instead makes it reachable from anywhere in the package, same pattern
    // plasma-workspace's systemtray applet uses for its own pin button.
    hideOnWindowDeactivate: !Plasmoid.configuration.pin

    fullRepresentation: FullRepresentation {
        Layout.minimumWidth: 480
        Layout.minimumHeight: 420
        Layout.preferredWidth: 560
        Layout.preferredHeight: 480
    }

    compactRepresentation: Item {
        DropArea {
            anchors.fill: parent
            z: 1
            onEntered: (drag) => {
                if (drag.hasUrls)
                    expanded = !expanded;
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 0
            cursorShape: Qt.PointingHandCursor
            onClicked: expanded = !expanded
        }

        Kirigami.Icon {
            source: Plasmoid.icon
            anchors.fill: parent
        }
    }
}
