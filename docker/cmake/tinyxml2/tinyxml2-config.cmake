# Minimal package config for the Vero's Debian tinyxml2 8.0.0 (bullseye ships none).
if(NOT TARGET tinyxml2::tinyxml2)
    add_library(tinyxml2::tinyxml2 SHARED IMPORTED)
    set_target_properties(tinyxml2::tinyxml2 PROPERTIES
        IMPORTED_LOCATION "${CMAKE_SYSROOT}/usr/lib/arm-linux-gnueabihf/libtinyxml2.so"
        INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SYSROOT}/usr/include"
    )
endif()
set(tinyxml2_FOUND TRUE)
