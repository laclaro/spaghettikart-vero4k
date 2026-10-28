# Minimal package config for the Vero's header-only nlohmann-json3-dev 3.9.1.
if(NOT TARGET nlohmann_json::nlohmann_json)
    add_library(nlohmann_json::nlohmann_json INTERFACE IMPORTED)
    set_target_properties(nlohmann_json::nlohmann_json PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SYSROOT}/usr/include"
    )
endif()
set(nlohmann_json_FOUND TRUE)
set(nlohmann_json_VERSION 3.9.1)
