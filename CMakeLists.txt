cmake_minimum_required(VERSION 3.22)
project(vst3_screenshooter VERSION 0.1.0 LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

# Path to VST3 SDK (you must provide this; see README)
set(VST3_SDK_DIR "${CMAKE_SOURCE_DIR}/third_party/vst3sdk")
set(SDK_ROOT "${VST3_SDK_DIR}")
set(public_sdk_SOURCE_DIR "${VST3_SDK_DIR}/public.sdk")
list(APPEND CMAKE_MODULE_PATH "${VST3_SDK_DIR}/cmake/modules")
include(SMTG_VST3_SDK)
set(SMTG_CREATE_PLUGIN_LINK OFF CACHE BOOL "Disable VST3 bundle symlinks" FORCE)
smtg_create_lib_base_target()
smtg_create_pluginterfaces_target()
smtg_create_public_sdk_common_target()
smtg_create_public_sdk_target()
smtg_create_public_sdk_hosting_target()
add_subdirectory(
    ${VST3_SDK_DIR}/public.sdk/samples/vst-utilities/moduleinfotool
    ${CMAKE_BINARY_DIR}/moduleinfotool
    EXCLUDE_FROM_ALL
)

# We maintain our own copy of EditorHost with custom modifications
# Original SDK editorhost build target is disabled

if (NOT EXISTS "${VST3_SDK_DIR}/pluginterfaces")
    message(FATAL_ERROR "VST3 SDK not found in ${VST3_SDK_DIR}. See README.md.")
endif()

include_directories(
    "${CMAKE_SOURCE_DIR}/src/editorhost/source"
    "${VST3_SDK_DIR}"
    "${VST3_SDK_DIR}/pluginterfaces"
    "${VST3_SDK_DIR}/public.sdk/source/vst"
)

# macOS frameworks
find_library(COCOA_FRAMEWORK Cocoa)
find_library(FOUNDATION_FRAMEWORK Foundation)
find_library(APPKIT_FRAMEWORK AppKit)
find_library(QUARTZCORE_FRAMEWORK QuartzCore)

add_executable(vstface
    src/main.cpp
    src/ScreenshotHost.mm
    src/ScreenshotHost.hpp
    src/EditorHostRunner.mm
    src/EditorHostRunner.hpp
    src/editorhost/source/editorhost.cpp
    src/editorhost/source/platform/mac/window.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/plugprovider.cpp
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/connectionproxy.cpp
)
set_target_properties(vstface PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}"
)

target_link_libraries(vstface
    ${COCOA_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${APPKIT_FRAMEWORK}
    ${QUARTZCORE_FRAMEWORK}
    sdk_hosting
)

set_source_files_properties(
    src/ScreenshotHost.mm
    src/EditorHostRunner.mm
    src/editorhost/source/platform/mac/window.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc"
)

set(TEST_PLUGIN_SOURCES
    src/test_plugin/TestPluginController.cpp
    src/test_plugin/TestPluginController.hpp
    src/test_plugin/TestPluginEntry.cpp
    src/test_plugin/TestPluginIDs.hpp
    src/test_plugin/TestPluginProcessor.cpp
    src/test_plugin/TestPluginProcessor.hpp
    src/test_plugin/TestPluginView.hpp
    src/test_plugin/TestPluginView.mm
)

smtg_add_vst3plugin(vstface_test_fixture ${TEST_PLUGIN_SOURCES})
target_compile_features(vstface_test_fixture PUBLIC cxx_std_17)
target_link_libraries(vstface_test_fixture
    PRIVATE
        sdk
        ${COCOA_FRAMEWORK}
        ${FOUNDATION_FRAMEWORK}
        ${APPKIT_FRAMEWORK}
        ${QUARTZCORE_FRAMEWORK}
)

if(SMTG_MAC)
    smtg_target_set_bundle(vstface_test_fixture
        BUNDLE_IDENTIFIER "com.vstface.fixture"
        COMPANY_NAME "vstface"
    )
endif()

set_source_files_properties(
    src/test_plugin/TestPluginView.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc"
)
