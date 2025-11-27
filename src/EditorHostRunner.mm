#include "EditorHostRunner.hpp"

#if VSTSHOT_HAS_VST3_SDK

#import <Cocoa/Cocoa.h>

#include <public.sdk/samples/vst-hosting/editorhost/source/editorhost.h>
#include <public.sdk/samples/vst-hosting/editorhost/source/platform/iapplication.h>
#include <public.sdk/samples/vst-hosting/editorhost/source/platform/iplatform.h>
#include <public.sdk/samples/vst-hosting/editorhost/source/platform/mac/window.h>
#include <pluginterfaces/gui/iplugview.h>

#include <cstring>
#include <optional>
#include <stdexcept>
#include <utility>
#include <vector>

namespace {

namespace EH = Steinberg::Vst::EditorHost;

class EditorHostError : public std::runtime_error {
public:
    EditorHostError(int code, std::string reason)
        : std::runtime_error(std::move(reason)), exitCode(code) {}

    int exitCode;
};

class EmbeddedPlatform : public EH::IPlatform {
public:
    static EmbeddedPlatform& instance() {
        static EmbeddedPlatform platform;
        return platform;
    }

    void setApplication(EH::ApplicationPtr&& app) override {
        application = std::move(app);
    }

    EH::WindowPtr createWindow(const std::string& title,
                               EH::Size size,
                               bool resizeable,
                               const EH::WindowControllerPtr& controller) override {
        auto created = EH::Window::make(title, size, resizeable, controller);
        activeWindow = created;
        return created;
    }

    void quit() override {}

    void kill(int resultCode, const std::string& reason) override {
        throw EditorHostError(resultCode, reason);
    }

    Steinberg::FUnknown* getPluginFactoryContext() override { return factoryContext; }

    EH::IApplication* applicationInstance() const { return application.get(); }

    const EH::WindowPtr& currentWindow() const { return activeWindow; }

    void clearWindow() { activeWindow.reset(); }

private:
    EmbeddedPlatform() = default;

    EH::ApplicationPtr application;
    EH::WindowPtr activeWindow;
    Steinberg::FUnknown* factoryContext = nullptr;
};

} // namespace

namespace Steinberg {
namespace Vst {
namespace EditorHost {
IPlatform& IPlatform::instance() {
    return EmbeddedPlatform::instance();
}
} // namespace EditorHost
} // namespace Vst
} // namespace Steinberg

namespace vstface {

namespace {
EH::IApplication* getEditorHostApplication() {
    return EmbeddedPlatform::instance().applicationInstance();
}
}

bool EditorHostRunner::open(const std::filesystem::path& pluginBundle,
                            const std::optional<std::string>& effectUid,
                            std::string& errorMessage) {
    close();

    auto* application = getEditorHostApplication();
    if (!application) {
        errorMessage = "EditorHost application is not available";
        return false;
    }

    auto cleanupOnFailure = [&]() {
        EmbeddedPlatform::instance().clearWindow();
        activeWindow.reset();
        nsWindow = nullptr;
        nsContentView = nullptr;
        if (application) {
            application->terminate();
        }
    };

    std::vector<std::string> args;
    args.reserve(4);
    args.emplace_back("--componentHandler");
    if (effectUid && !effectUid->empty()) {
        args.emplace_back("--uid");
        args.emplace_back(*effectUid);
    }
    args.emplace_back(pluginBundle.string());

    try {
        application->init(args);
    } catch (const EditorHostError& err) {
        errorMessage = err.what();
        cleanupOnFailure();
        return false;
    } catch (const std::exception& ex) {
        errorMessage = ex.what();
        cleanupOnFailure();
        return false;
    }

    activeWindow = EmbeddedPlatform::instance().currentWindow();
    if (!activeWindow) {
        errorMessage = "EditorHost failed to create a window";
        cleanupOnFailure();
        return false;
    }

    auto nativeWindow = activeWindow->getNativePlatformWindow();
    if (!nativeWindow.ptr || nativeWindow.type == nullptr ||
        std::strcmp(nativeWindow.type, Steinberg::kPlatformTypeNSView) != 0) {
        errorMessage = "EditorHost window does not expose an NSView";
        cleanupOnFailure();
        return false;
    }

    nsContentView = (__bridge NSView*)nativeWindow.ptr;
    nsWindow = [nsContentView window];
    if (!nsWindow) {
        errorMessage = "EditorHost view is missing an NSWindow";
        cleanupOnFailure();
        return false;
    }

    return true;
}

void EditorHostRunner::resizeContent(int width, int height) {
    if (!activeWindow || width <= 0 || height <= 0) {
        return;
    }

    Steinberg::Vst::EditorHost::Size newSize {static_cast<Steinberg::Vst::EditorHost::Coord>(width),
                                              static_cast<Steinberg::Vst::EditorHost::Coord>(height)};
    activeWindow->resize(newSize);
}

void EditorHostRunner::close() {
    if (!activeWindow && !nsWindow && !nsContentView) {
        return;
    }

    auto* application = getEditorHostApplication();
    if (application) {
        application->terminate();
    }

    if (nsWindow) {
        [nsWindow orderOut:nil];
        [nsWindow close];
    }

    EmbeddedPlatform::instance().clearWindow();

    activeWindow.reset();
    nsWindow = nullptr;
    nsContentView = nullptr;
}

} // namespace vstface

#endif // VSTSHOT_HAS_VST3_SDK
