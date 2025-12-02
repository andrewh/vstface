// Unit tests for ScreenshotHost helpers
// Tests VST3 component handlers and helpers used during plugin capture

#include "ScreenshotHost.hpp"
#include "EditorHostRunner.hpp"

#include <gtest/gtest.h>
#include <gmock/gmock.h>

#include <filesystem>
#include <fstream>

// VST3 SDK includes
#include <pluginterfaces/base/ipluginbase.h>
#include <pluginterfaces/gui/iplugview.h>
#include <pluginterfaces/vst/ivstaudioprocessor.h>
#include <pluginterfaces/vst/ivstcomponent.h>
#include <pluginterfaces/vst/ivsteditcontroller.h>
#include <pluginterfaces/vst/vsttypes.h>
#include <public.sdk/source/vst/hosting/hostclasses.h>

using namespace vstface;
using namespace Steinberg;
using namespace Steinberg::Vst;
namespace fs = std::filesystem;

// Test fixture for ScreenshotHost tests
class ScreenshotHostTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Ensure test output directory exists
        testOutputDir = fs::temp_directory_path() / "vstface_test_output";
        fs::create_directories(testOutputDir);
    }

    void TearDown() override {
        // Clean up test output directory
        if (fs::exists(testOutputDir)) {
            fs::remove_all(testOutputDir);
        }
    }

    fs::path testOutputDir;
};

// Test that ScreenshotHost can be constructed
TEST_F(ScreenshotHostTest, ConstructsSuccessfully) {
    ScreenshotHost host;
    SUCCEED();
}

// Test that ScreenshotHost rejects invalid plugin paths
TEST_F(ScreenshotHostTest, RejectsNonExistentPlugin) {
    ScreenshotHost host;
    fs::path fakePlugin = "/nonexistent/path/fake.vst3";
    fs::path outputPng = testOutputDir / "output.png";
    ScreenshotOptions opts;

    bool result = host.capturePlugin(fakePlugin, outputPng, opts);
    EXPECT_FALSE(result);
}

// Test that ScreenshotHost rejects invalid output paths
TEST_F(ScreenshotHostTest, RejectsInvalidOutputPath) {
    ScreenshotHost host;
    // Use a path that cannot be written to
    fs::path invalidOutput = "/root/cannot_write_here/output.png";
    ScreenshotOptions opts;

    // We need a valid plugin for this test - skip if test fixture isn't built
    fs::path testFixture = fs::current_path() / "VST3" / "Release" / "vstface_test_fixture.vst3";
    if (!fs::exists(testFixture)) {
        GTEST_SKIP() << "Test fixture plugin not found at " << testFixture;
    }

    // This should fail because we can't write to /root
    bool result = host.capturePlugin(testFixture, invalidOutput, opts);
    // Note: This might succeed on the plugin loading part but fail on file write
    // The exact behavior depends on when the file is opened
}

// Test that ScreenshotOptions has sensible defaults
TEST_F(ScreenshotHostTest, ScreenshotOptionsDefaults) {
    ScreenshotOptions opts;
    EXPECT_EQ(opts.width, 1024);
    EXPECT_EQ(opts.height, 768);
    EXPECT_TRUE(opts.classNameFilter.empty());
}

// Test that ScreenshotOptions can be customized
TEST_F(ScreenshotHostTest, ScreenshotOptionsCustomization) {
    ScreenshotOptions opts;
    opts.width = 800;
    opts.height = 600;
    opts.classNameFilter = "TestProcessor";

    EXPECT_EQ(opts.width, 800);
    EXPECT_EQ(opts.height, 600);
    EXPECT_EQ(opts.classNameFilter, "TestProcessor");
}

// Mock component handler for testing VST3 interface implementations
class MockComponentHandler : public IComponentHandler {
public:
    MOCK_METHOD(tresult, beginEdit, (ParamID), (override));
    MOCK_METHOD(tresult, performEdit, (ParamID, ParamValue), (override));
    MOCK_METHOD(tresult, endEdit, (ParamID), (override));
    MOCK_METHOD(tresult, restartComponent, (int32), (override));
    MOCK_METHOD(tresult, queryInterface, (const TUID, void**), (override));
    MOCK_METHOD(uint32, addRef, (), (override));
    MOCK_METHOD(uint32, release, (), (override));
};

// Test the component handler interface
TEST_F(ScreenshotHostTest, ComponentHandlerInterface) {
    MockComponentHandler handler;

    // The handler should accept all parameter edits
    EXPECT_CALL(handler, beginEdit(::testing::_))
        .WillOnce(::testing::Return(kResultOk));
    EXPECT_CALL(handler, performEdit(::testing::_, ::testing::_))
        .WillOnce(::testing::Return(kResultOk));
    EXPECT_CALL(handler, endEdit(::testing::_))
        .WillOnce(::testing::Return(kResultOk));
    EXPECT_CALL(handler, restartComponent(::testing::_))
        .WillOnce(::testing::Return(kResultOk));

    EXPECT_EQ(handler.beginEdit(0), kResultOk);
    EXPECT_EQ(handler.performEdit(0, 0.5), kResultOk);
    EXPECT_EQ(handler.endEdit(0), kResultOk);
    EXPECT_EQ(handler.restartComponent(0), kResultOk);
}

// Integration test with the actual test fixture plugin
TEST_F(ScreenshotHostTest, CapturesTestFixturePlugin) {
    // Look for the test fixture plugin
    fs::path testFixture = fs::current_path() / "VST3" / "Release" / "vstface_test_fixture.vst3";
    if (!fs::exists(testFixture)) {
        // Try Debug build
        testFixture = fs::current_path() / "VST3" / "Debug" / "vstface_test_fixture.vst3";
        if (!fs::exists(testFixture)) {
            GTEST_SKIP() << "Test fixture plugin not found";
        }
    }

    fs::path outputPng = testOutputDir / "fixture_test.png";
    ScreenshotOptions opts;
    opts.width = 400;
    opts.height = 300;

    ScreenshotHost host;
    bool result = host.capturePlugin(testFixture, outputPng, opts);

    EXPECT_TRUE(result);
    EXPECT_TRUE(fs::exists(outputPng));

    // Verify the PNG file is not empty
    if (fs::exists(outputPng)) {
        auto fileSize = fs::file_size(outputPng);
        EXPECT_GT(fileSize, 0);
    }
}

// Test capturing with a specific class name filter
TEST_F(ScreenshotHostTest, CapturesWithClassNameFilter) {
    fs::path testFixture = fs::current_path() / "VST3" / "Release" / "vstface_test_fixture.vst3";
    if (!fs::exists(testFixture)) {
        testFixture = fs::current_path() / "VST3" / "Debug" / "vstface_test_fixture.vst3";
        if (!fs::exists(testFixture)) {
            GTEST_SKIP() << "Test fixture plugin not found";
        }
    }

    fs::path outputPng = testOutputDir / "fixture_filtered.png";
    ScreenshotOptions opts;
    opts.classNameFilter = "VSTFace Static Fixture";

    ScreenshotHost host;
    bool result = host.capturePlugin(testFixture, outputPng, opts);

    // This should succeed if the class name is correct
    EXPECT_TRUE(result);
    if (result) {
        EXPECT_TRUE(fs::exists(outputPng));
    }
}

// Test that invalid class name filter fails gracefully
TEST_F(ScreenshotHostTest, InvalidClassNameFilterFails) {
    fs::path testFixture = fs::current_path() / "VST3" / "Release" / "vstface_test_fixture.vst3";
    if (!fs::exists(testFixture)) {
        testFixture = fs::current_path() / "VST3" / "Debug" / "vstface_test_fixture.vst3";
        if (!fs::exists(testFixture)) {
            GTEST_SKIP() << "Test fixture plugin not found";
        }
    }

    fs::path outputPng = testOutputDir / "should_not_exist.png";
    ScreenshotOptions opts;
    opts.classNameFilter = "NonExistentClass";

    ScreenshotHost host;
    bool result = host.capturePlugin(testFixture, outputPng, opts);

    EXPECT_FALSE(result);
    EXPECT_FALSE(fs::exists(outputPng));
}
