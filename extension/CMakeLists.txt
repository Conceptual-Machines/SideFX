cmake_minimum_required(VERSION 3.15)
project(reaper_sidefx_mod VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Output name
set(PLUGIN_NAME "reaper_sidefx_mod")

# Platform-specific settings
if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Build architectures")
    set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum macOS version")
endif()

# Paths
set(REAPER_SDK_PATH "${CMAKE_CURRENT_SOURCE_DIR}/reaper-sdk/sdk")
set(WDL_PATH "${CMAKE_CURRENT_SOURCE_DIR}/WDL")

# Sources
set(SOURCES
    src/main.cpp
    src/modulator.cpp
    src/audio_hook.cpp
)

set(HEADERS
    include/bezier.h
    include/modulator.h
    include/audio_hook.h
)

# SWELL stub for macOS (required for non-UI extensions)
if(APPLE)
    # Use Objective-C++ version on macOS
    enable_language(OBJCXX)
    add_library(swell_stub STATIC
        ${WDL_PATH}/WDL/swell/swell-modstub.mm
    )
    target_include_directories(swell_stub PUBLIC
        ${WDL_PATH}
    )
    target_compile_definitions(swell_stub PUBLIC
        SWELL_PROVIDED_BY_APP
    )
    # Link AppKit framework
    find_library(APPKIT_LIB AppKit)
    if(APPKIT_LIB)
        target_link_libraries(swell_stub PUBLIC ${APPKIT_LIB})
    endif()
endif()

# Main plugin library
add_library(${PLUGIN_NAME} MODULE ${SOURCES} ${HEADERS})

target_include_directories(${PLUGIN_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${REAPER_SDK_PATH}
    ${WDL_PATH}/WDL
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE
    $<$<PLATFORM_ID:Darwin>:SWELL_PROVIDED_BY_APP>
)

if(APPLE)
    target_link_libraries(${PLUGIN_NAME} PRIVATE swell_stub)
    set_target_properties(${PLUGIN_NAME} PROPERTIES
        BUNDLE FALSE
        SUFFIX ".dylib"
        PREFIX ""
    )
    # Allow undefined symbols for SWELL function pointers (provided by REAPER at runtime)
    target_link_options(${PLUGIN_NAME} PRIVATE
        -undefined dynamic_lookup
    )
elseif(WIN32)
    set_target_properties(${PLUGIN_NAME} PROPERTIES
        SUFFIX ".dll"
        PREFIX ""
    )
else()
    set_target_properties(${PLUGIN_NAME} PROPERTIES
        SUFFIX ".so"
        PREFIX ""
    )
endif()

# Install to REAPER UserPlugins
if(APPLE)
    set(DEFAULT_INSTALL_PATH "$ENV{HOME}/Library/Application Support/REAPER/UserPlugins")
elseif(WIN32)
    set(DEFAULT_INSTALL_PATH "$ENV{APPDATA}/REAPER/UserPlugins")
else()
    set(DEFAULT_INSTALL_PATH "$ENV{HOME}/.config/REAPER/UserPlugins")
endif()

install(TARGETS ${PLUGIN_NAME}
    LIBRARY DESTINATION "${DEFAULT_INSTALL_PATH}"
)

# Copy to portable REAPER for development
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:${PLUGIN_NAME}>
        "${CMAKE_CURRENT_SOURCE_DIR}/../../reaper-portable/UserPlugins/$<TARGET_FILE_NAME:${PLUGIN_NAME}>"
    COMMENT "Copying to portable REAPER UserPlugins"
)

