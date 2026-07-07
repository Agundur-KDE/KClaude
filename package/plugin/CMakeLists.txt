find_package(Qt6 REQUIRED COMPONENTS Core Qml)

include(ECMQmlModule)

ecm_add_qml_module(kclaudeplugin
    URI de.agundur.kclaude
    VERSION 1.0
    GENERATE_PLUGIN_SOURCE
)

target_sources(kclaudeplugin PRIVATE
    FileReader.cpp FileReader.h
)

target_link_libraries(kclaudeplugin PRIVATE Qt6::Core Qt6::Qml)

ecm_finalize_qml_module(kclaudeplugin)
