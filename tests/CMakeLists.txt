# Test infrastructure for vstface
# Unit tests for ScreenshotHost helpers and integration tests for the CLI

include_directories(
    "${CMAKE_SOURCE_DIR}/src"
    "${CMAKE_SOURCE_DIR}/src/editorhost/source"
)

# Unit tests for ScreenshotHost helper functions
add_executable(unit_tests
    unit/screenshot_host_test.mm
    ${CMAKE_SOURCE_DIR}/src/ScreenshotHost.mm
    ${CMAKE_SOURCE_DIR}/src/ScreenshotHost.hpp
    ${CMAKE_SOURCE_DIR}/src/EditorHostRunner.mm
    ${CMAKE_SOURCE_DIR}/src/EditorHostRunner.hpp
    ${CMAKE_SOURCE_DIR}/src/editorhost/source/editorhost.cpp
    ${CMAKE_SOURCE_DIR}/src/editorhost/source/platform/mac/window.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/plugprovider.cpp
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/connectionproxy.cpp
)

target_link_libraries(unit_tests
    GTest::gtest_main
    GTest::gmock
    ${COCOA_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${APPKIT_FRAMEWORK}
    ${QUARTZCORE_FRAMEWORK}
    sdk_hosting
)

set_source_files_properties(
    unit/screenshot_host_test.mm
    ${CMAKE_SOURCE_DIR}/src/ScreenshotHost.mm
    ${CMAKE_SOURCE_DIR}/src/EditorHostRunner.mm
    ${CMAKE_SOURCE_DIR}/src/editorhost/source/platform/mac/window.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc"
)

include(GoogleTest)
gtest_discover_tests(unit_tests)

# Integration tests that drive the CLI
add_executable(integration_tests
    integration/cli_test.cpp
)

target_link_libraries(integration_tests
    GTest::gtest_main
    GTest::gmock
    ${COCOA_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${APPKIT_FRAMEWORK}
    ${QUARTZCORE_FRAMEWORK}
)

gtest_discover_tests(integration_tests)
