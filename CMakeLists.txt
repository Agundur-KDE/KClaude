cmake_minimum_required(VERSION 3.16)
project(kclaude)

set(QT_MIN_VERSION "6.7.0")
set(KF6_MIN_VERSION "6.10.0")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMFindQmlModule)
include(ECMQmlModule)
include(ECMAddTests)
include(ECMInstallIcons)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS
    Core
    Quick
    Test
    QuickTest
)

find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    I18n
)

enable_testing()

add_test(NAME validate-metadata
    COMMAND python3 ${CMAKE_SOURCE_DIR}/scripts/validate-metadata.py
                    ${CMAKE_SOURCE_DIR}/package/metadata.json
)

ki18n_install(translate
    INSTALL_DESTINATION ${KDE_INSTALL_LOCALEDIR}
)

ecm_install_icons(
    ICONS icons/16-apps-kclaude.png
          icons/22-apps-kclaude.png
          icons/32-apps-kclaude.png
          icons/48-apps-kclaude.png
          icons/64-apps-kclaude.png
          icons/128-apps-kclaude.png
          icons/256-apps-kclaude.png
    DESTINATION ${KDE_INSTALL_ICONDIR}
)

add_subdirectory(package)
add_subdirectory(tests)

install(
    DIRECTORY package/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/de.agundur.kclaude
)
