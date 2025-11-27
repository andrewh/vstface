#pragma once

#include <filesystem>
#include <optional>
#include <string>

#ifndef VSTSHOT_HAS_VST3_SDK
#    if __has_include(<pluginterfaces/vst/vsttypes.h>)
#        define VSTSHOT_HAS_VST3_SDK 1
#    else
#        define VSTSHOT_HAS_VST3_SDK 0
#    endif
#endif

#if VSTSHOT_HAS_VST3_SDK

#include <public.sdk/samples/vst-hosting/editorhost/source/platform/iwindow.h>

@class NSWindow;
@class NSView;

namespace vstface {

class EditorHostRunner {
public:
    EditorHostRunner() = default;

    bool open(const std::filesystem::path& pluginBundle,
              const std::optional<std::string>& effectUid,
              std::string& errorMessage);

    void resizeContent(int width, int height);

    NSWindow* window() const { return nsWindow; }
    NSView* contentView() const { return nsContentView; }

    void close();

private:
    Steinberg::Vst::EditorHost::WindowPtr activeWindow;
    NSWindow* nsWindow = nullptr;
    NSView* nsContentView = nullptr;
};

} // namespace vstface

#endif // VSTSHOT_HAS_VST3_SDK
