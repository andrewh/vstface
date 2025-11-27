#include "ScreenshotHost.hpp"
#include <filesystem>
#include <iostream>

using namespace vstface;
namespace fs = std::filesystem;

int main(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "Usage: vstface <plugin.vst3> <out.png>\n";
        return 1;
    }

    fs::path plugin = argv[1];
    fs::path out    = argv[2];

    ScreenshotOptions opts;

    ScreenshotHost host;
    if (!host.capturePlugin(plugin, out, opts)) {
        return 2;
    }
    return 0;
}
