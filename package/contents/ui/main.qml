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
