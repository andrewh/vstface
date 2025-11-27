#pragma once
#include <string>
#include <filesystem>

namespace vstface {

struct ScreenshotOptions {
    int width = 1024;
    int height = 768;
    std::string classNameFilter; // optional
};

class ScreenshotHost {
public:
    ScreenshotHost();
    ~ScreenshotHost();

    bool capturePlugin(const std::filesystem::path& pluginBundle,
                       const std::filesystem::path& outputPng,
                       const ScreenshotOptions& opts);
};

} // namespace vstface
