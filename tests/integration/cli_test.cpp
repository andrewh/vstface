// Integration tests for vstface CLI
// Tests the command-line interface with the test fixture plugin

#include <gtest/gtest.h>
#include <gmock/gmock.h>

#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace fs = std::filesystem;

// Test fixture for CLI integration tests
class CLITest : public ::testing::Test {
protected:
    void SetUp() override {
        // Find the vstface binary
        vstfaceBinary = fs::current_path() / "vstface";
        if (!fs::exists(vstfaceBinary)) {
            GTEST_SKIP() << "vstface binary not found at " << vstfaceBinary;
        }

        // Find the test fixture plugin
        testFixturePlugin = fs::current_path() / "VST3" / "Release" / "vstface_test_fixture.vst3";
        if (!fs::exists(testFixturePlugin)) {
            testFixturePlugin = fs::current_path() / "VST3" / "Debug" / "vstface_test_fixture.vst3";
            if (!fs::exists(testFixturePlugin)) {
                GTEST_SKIP() << "Test fixture plugin not found";
            }
        }

        // Create test output directory
        testOutputDir = fs::temp_directory_path() / "vstface_cli_test";
        fs::create_directories(testOutputDir);
    }

    void TearDown() override {
        // Clean up test output
        if (fs::exists(testOutputDir)) {
            fs::remove_all(testOutputDir);
        }
    }

    // Helper to run vstface command and capture return code
    int runVstface(const std::string& pluginPath, const std::string& outputPath) {
        std::ostringstream cmd;
        cmd << vstfaceBinary.string() << " "
            << "\"" << pluginPath << "\" "
            << "\"" << outputPath << "\" "
            << "> /dev/null 2>&1";

        return system(cmd.str().c_str());
    }

    fs::path vstfaceBinary;
    fs::path testFixturePlugin;
    fs::path testOutputDir;
};

// Test that vstface displays usage when called without arguments
TEST_F(CLITest, ShowsUsageWithoutArguments) {
    std::ostringstream cmd;
    cmd << vstfaceBinary.string() << " 2>&1";

    FILE* pipe = popen(cmd.str().c_str(), "r");
    ASSERT_NE(pipe, nullptr);

    std::array<char, 128> buffer;
    std::string output;
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        output += buffer.data();
    }

    int returnCode = pclose(pipe);
    EXPECT_NE(WEXITSTATUS(returnCode), 0);
    EXPECT_THAT(output, ::testing::HasSubstr("Usage"));
}

// Test that vstface successfully captures the test fixture
TEST_F(CLITest, CapturesTestFixture) {
    fs::path outputPng = testOutputDir / "test_fixture.png";

    int result = runVstface(testFixturePlugin.string(), outputPng.string());

    EXPECT_EQ(WEXITSTATUS(result), 0) << "vstface should exit with code 0 on success";
    EXPECT_TRUE(fs::exists(outputPng)) << "Output PNG should be created";

    if (fs::exists(outputPng)) {
        auto fileSize = fs::file_size(outputPng);
        EXPECT_GT(fileSize, 100) << "PNG file should not be empty";

        // Verify it's actually a PNG file by checking magic bytes
        std::ifstream file(outputPng, std::ios::binary);
        std::array<unsigned char, 8> pngSignature = {137, 80, 78, 71, 13, 10, 26, 10};
        std::array<unsigned char, 8> fileHeader;
        file.read(reinterpret_cast<char*>(fileHeader.data()), 8);

        EXPECT_EQ(fileHeader, pngSignature) << "Output should be a valid PNG file";
    }
}

// Test that vstface handles non-existent plugin gracefully
TEST_F(CLITest, FailsOnNonExistentPlugin) {
    fs::path fakPlugin = "/tmp/nonexistent_plugin.vst3";
    fs::path outputPng = testOutputDir / "should_not_exist.png";

    int result = runVstface(fakPlugin.string(), outputPng.string());

    EXPECT_NE(WEXITSTATUS(result), 0) << "vstface should exit with non-zero code on failure";
    EXPECT_FALSE(fs::exists(outputPng)) << "Output PNG should not be created on failure";
}

// Test that vstface handles invalid plugin bundles
TEST_F(CLITest, FailsOnInvalidPlugin) {
    // Create a fake .vst3 directory that's not actually a plugin
    fs::path fakePlugin = testOutputDir / "fake.vst3";
    fs::create_directories(fakePlugin);

    fs::path outputPng = testOutputDir / "should_not_exist.png";

    int result = runVstface(fakePlugin.string(), outputPng.string());

    EXPECT_NE(WEXITSTATUS(result), 0) << "vstface should fail on invalid plugin bundle";
}

// Test that vstface can write to different output locations
TEST_F(CLITest, WritesToDifferentLocations) {
    fs::path outputPng1 = testOutputDir / "output1.png";
    fs::path outputPng2 = testOutputDir / "subdir" / "output2.png";

    // Create subdirectory
    fs::create_directories(outputPng2.parent_path());

    int result1 = runVstface(testFixturePlugin.string(), outputPng1.string());
    int result2 = runVstface(testFixturePlugin.string(), outputPng2.string());

    EXPECT_EQ(WEXITSTATUS(result1), 0);
    EXPECT_EQ(WEXITSTATUS(result2), 0);
    EXPECT_TRUE(fs::exists(outputPng1));
    EXPECT_TRUE(fs::exists(outputPng2));
}

// Test that vstface overwrites existing output files
TEST_F(CLITest, OverwritesExistingOutput) {
    fs::path outputPng = testOutputDir / "overwrite_test.png";

    // Create a dummy file
    {
        std::ofstream dummyFile(outputPng);
        dummyFile << "This is not a PNG";
    }

    ASSERT_TRUE(fs::exists(outputPng));
    auto originalSize = fs::file_size(outputPng);

    int result = runVstface(testFixturePlugin.string(), outputPng.string());

    EXPECT_EQ(WEXITSTATUS(result), 0);
    EXPECT_TRUE(fs::exists(outputPng));

    auto newSize = fs::file_size(outputPng);
    EXPECT_NE(newSize, originalSize) << "File should be overwritten with new content";

    // Verify it's now a valid PNG
    std::ifstream file(outputPng, std::ios::binary);
    std::array<unsigned char, 8> pngSignature = {137, 80, 78, 71, 13, 10, 26, 10};
    std::array<unsigned char, 8> fileHeader;
    file.read(reinterpret_cast<char*>(fileHeader.data()), 8);

    EXPECT_EQ(fileHeader, pngSignature);
}

// Test multiple consecutive captures
TEST_F(CLITest, HandlesMultipleConsecutiveCaptures) {
    std::vector<fs::path> outputs;

    for (int i = 0; i < 3; ++i) {
        fs::path output = testOutputDir / ("capture_" + std::to_string(i) + ".png");
        outputs.push_back(output);

        int result = runVstface(testFixturePlugin.string(), output.string());
        EXPECT_EQ(WEXITSTATUS(result), 0);
    }

    // Verify all captures were successful
    for (const auto& output : outputs) {
        EXPECT_TRUE(fs::exists(output));
        EXPECT_GT(fs::file_size(output), 0);
    }
}
