// Screenshot capture for VST3 plugin editors on macOS
// Combines VST3 hosting with macOS window capture APIs
//
// This file is Objective-C++ (.mm extension), which allows mixing C++, C, and Objective-C.
// Objective-C syntax key differences from C++:
//   - [object method] instead of object->method() or object.method()
//   - @"string" for NSString literals, @ prefix for other Objective-C literals (@{}, @[], etc.)
//   - nil instead of nullptr for Objective-C objects
//   - YES/NO instead of true/false
//   - NS prefix on most Cocoa classes (NSWindow, NSView, NSString, etc.)
//   - Blocks (^{ }) are like C++ lambdas
//   - ARC (Automatic Reference Counting) manages memory for Objective-C objects

// #import is Objective-C's #include - it automatically prevents duplicate imports
#import "ScreenshotHost.hpp"
#import "EditorHostRunner.hpp"

// Cocoa is the macOS UI framework (NSWindow, NSView, etc.)
#import <Cocoa/Cocoa.h>
// CoreGraphics provides low-level drawing and window capture
#import <CoreGraphics/CoreGraphics.h>
// dispatch is Apple's GCD (Grand Central Dispatch) for threading
#import <dispatch/dispatch.h>
// dlfcn provides dlsym for runtime function loading
#import <dlfcn.h>

#include <optional>

#ifndef VSTSHOT_HAS_VST3_SDK
#    if __has_include(<pluginterfaces/vst/vsttypes.h>)
#        define VSTSHOT_HAS_VST3_SDK 1
#    else
#        define VSTSHOT_HAS_VST3_SDK 0
#    endif
#endif

#if VSTSHOT_HAS_VST3_SDK
#include <pluginterfaces/base/ipluginbase.h>
#include <pluginterfaces/gui/iplugview.h>
#include <pluginterfaces/vst/ivstaudioprocessor.h>
#include <pluginterfaces/vst/ivstcomponent.h>
#include <pluginterfaces/vst/ivsteditcontroller.h>
#include <pluginterfaces/vst/vsttypes.h>
#include <public.sdk/source/vst/hosting/hostclasses.h>
#include <public.sdk/source/vst/hosting/module.h>
#include <public.sdk/source/vst/hosting/plugprovider.h>
using namespace Steinberg;
using namespace Steinberg::Vst;
#endif

namespace vstface {

namespace fs = std::filesystem;

ScreenshotHost::ScreenshotHost() {
    // In Objective-C, square brackets [] are used for method calls
    // [NSApplication sharedApplication] is like NSApplication::sharedApplication() in C++
    // This initializes the macOS application instance (required for UI operations)
    [NSApplication sharedApplication];
}

ScreenshotHost::~ScreenshotHost() {}

#if VSTSHOT_HAS_VST3_SDK
namespace {

// Process macOS event loop for a specified duration
// This allows UI updates and events to be handled
static void pumpRunLoop(double seconds) {
    // NSDate* is an Objective-C object pointer (like std::unique_ptr)
    // Create an end time by adding seconds to current time
    NSDate* until = [NSDate dateWithTimeIntervalSinceNow:seconds];

    // NSOrderedAscending means "current time is before end time" (like < operator)
    while ([[NSDate date] compare:until] == NSOrderedAscending) {
        // @autoreleasepool is Objective-C memory management
        // Similar to a scope guard that releases temporary objects
        @autoreleasepool {
            // Poll for UI events with 10ms timeout
            // NSApp is a global shorthand for [NSApplication sharedApplication]
            NSEvent* event =
                [NSApp nextEventMatchingMask:NSEventMaskAny
                                   untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                      inMode:NSDefaultRunLoopMode
                                     dequeue:YES];
            if (event) {
                // Dispatch the event to the appropriate window/view
                [NSApp sendEvent:event];
            }
        }
    }
}

static bool captureWindowToFile(NSWindow* window,
                                NSView* contentView,
                                const fs::path& outputPng);

// RAII guard that ensures EditorHostRunner is properly closed
// Similar to std::lock_guard or std::unique_ptr
class RunnerScopeGuard {
public:
    explicit RunnerScopeGuard(EditorHostRunner& runner) : runner(runner) {}
    ~RunnerScopeGuard() { runner.close(); }

private:
    EditorHostRunner& runner;
};

// Convert a plugin class name to its VST3 UID
// Loads the plugin bundle and searches for a class with the given name
bool resolveClassFilterToUid(const std::filesystem::path& pluginBundle,
                             const std::string& className,
                             std::optional<std::string>& outUid) {
    using namespace VST3::Hosting;

    std::string error;
    auto module = Module::create(pluginBundle.string(), error);
    if (!module) {
        fprintf(stderr, "Failed to load module %s: %s\n", pluginBundle.c_str(), error.c_str());
        return false;
    }

    // Iterate through all classes in the plugin bundle
    for (auto& info : module->getFactory().classInfos()) {
        // Skip non-audio-effect classes (e.g., factory, controller)
        if (strcmp(info.category().data(), kVstAudioEffectClass) != 0) {
            continue;
        }
        if (info.name() == className) {
            outUid = info.ID().toString();
            return true;
        }
    }

    fprintf(stderr,
            "No audio effect class named %s in %s\n",
            className.c_str(),
            pluginBundle.c_str());
    return false;
}

// RAII guard that sets the VST3 plugin context and clears it on destruction
// This provides host application info to plugins during initialization
class PluginContextGuard {
public:
    explicit PluginContextGuard(FUnknown* ctx) {
        Vst::PluginContextFactory::instance().setPluginContext(ctx);
    }
    ~PluginContextGuard() { Vst::PluginContextFactory::instance().setPluginContext(nullptr); }
};

// Minimal VST3 component handler that accepts all plugin callbacks
// Plugins use this interface to notify the host of parameter changes
class ScreenshotComponentHandler : public IComponentHandler {
public:
    // These methods are called when user edits plugin parameters
    // We don't need to act on them for screenshots, so just return success
    tresult PLUGIN_API beginEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API performEdit(ParamID, ParamValue) override { return kResultOk; }
    tresult PLUGIN_API endEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API restartComponent(int32) override { return kResultOk; }

    // VST3 interface query system (similar to COM QueryInterface)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        if (!obj) {
            return kInvalidArgument;
        }
        // Check if requested interface is one we support
        if (FUnknownPrivate::iidEqual(iid, IComponentHandler::iid) ||
            FUnknownPrivate::iidEqual(iid, FUnknown::iid)) {
            *obj = this;
            addRef();
            return kResultTrue;
        }
        *obj = nullptr;
        return kNoInterface;
    }

    // Reference counting (VST3 uses COM-style manual refcounting)
    // Return constant value since we manage this object's lifetime manually
    uint32 PLUGIN_API addRef() override { return 1000; }
    uint32 PLUGIN_API release() override { return 1000; }
};

// VST3 plug frame that handles window resizing requests from the plugin
class ScreenshotPlugFrame : public IPlugFrame {
public:
    explicit ScreenshotPlugFrame(NSWindow* window) : window(window) {}

    // Called when plugin wants to resize its editor window
    tresult PLUGIN_API resizeView(IPlugView*, ViewRect* newSize) override {
        if (!window || !newSize) {
            return kResultFalse;
        }
        // CGFloat is macOS's floating point type (usually double)
        CGFloat width  = newSize->right - newSize->left;
        CGFloat height = newSize->bottom - newSize->top;
        // NSMakeSize is a helper function that creates an NSSize struct
        NSSize size    = NSMakeSize(width, height);

        // dispatch_async runs a block on another thread
        // The ^{ } syntax is an Objective-C block (like a C++ lambda)
        // All UI operations must happen on the main thread in macOS
        dispatch_async(dispatch_get_main_queue(), ^{
            [window setContentSize:size];
        });
        return kResultTrue;
    }

    // Interface query (see ScreenshotComponentHandler for explanation)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        if (!obj) {
            return kInvalidArgument;
        }
        if (FUnknownPrivate::iidEqual(iid, IPlugFrame::iid) ||
            FUnknownPrivate::iidEqual(iid, FUnknown::iid)) {
            *obj = this;
            addRef();
            return kResultTrue;
        }
        *obj = nullptr;
        return kNoInterface;
    }

    uint32 PLUGIN_API addRef() override { return 1000; }
    uint32 PLUGIN_API release() override { return 1000; }

private:
    // __weak is an Objective-C ARC (Automatic Reference Counting) qualifier
    // It prevents retain cycles (similar to std::weak_ptr)
    // nil is Objective-C's null pointer (like nullptr in C++)
    __weak NSWindow* window = nil;
};

// Capture a macOS window to a PNG file
static bool captureWindowToFile(NSWindow* window,
                                NSView* contentView,
                                const fs::path& outputPng) {
    if (!window || !contentView) {
        return false;
    }

    // Prepare the window for capture
    // YES and NO are Objective-C's true/false (they're just #defines to 1 and 0)
    [NSApp activateIgnoringOtherApps:YES];
    // nil is Objective-C's null (like nullptr)
    [window makeKeyAndOrderFront:nil];  // Show window and bring to front
    [window displayIfNeeded];           // Force window to draw if needed
    pumpRunLoop(0.5);                   // Process events for half a second

    // Try to use private CGWindowListCreateImage API for better capture quality
    // We load it dynamically because it requires Screen Recording permission
    using CaptureFn = CGImageRef (*)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);
    static CaptureFn captureFn = reinterpret_cast<CaptureFn>(dlsym(RTLD_DEFAULT, "CGWindowListCreateImage"));

    // NSBitmapImageRep is an object that holds pixel data
    NSBitmapImageRep* rep = nil;
    if (captureFn) {
        CGWindowImageOption options = kCGWindowImageNominalResolution | kCGWindowImageBoundsIgnoreFraming;
        // CGImageRef is a CoreGraphics image (needs manual release)
        CGImageRef image = captureFn(CGRectNull,
                                     kCGWindowListOptionIncludingWindow,
                                     (CGWindowID)[window windowNumber],
                                     options);
        if (image) {
            // [[Class alloc] init...] is Objective-C object creation
            // Similar to: new NSBitmapImageRep(...) in C++
            // But uses ARC (Automatic Reference Counting) for memory management
            rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
            // CGImageRelease is manual memory management (CoreGraphics uses retain/release)
            CGImageRelease(image);
        } else {
            fprintf(stderr,
                    "CGWindowListCreateImage returned NULL; ensure screen recording permission is granted.\n");
        }
    }

    // If CGWindowListCreateImage failed or wasn't available, use view-based capture
    if (!rep) {
        NSView* targetView = contentView;
        [targetView displayIfNeeded];

        // NSRect is a struct with origin (x,y) and size (width, height)
        NSRect bounds = [targetView bounds];

        // Try optimized caching approach first
        rep = [targetView bitmapImageRepForCachingDisplayInRect:bounds];
        if (rep) {
            [targetView cacheDisplayInRect:bounds toBitmapImageRep:rep];
        } else {
            // Fall back to manual bitmap creation and rendering
            // NSInteger is a platform-dependent signed integer type
            // NSWidth/NSHeight are helper functions to extract dimensions
            NSInteger width  = (NSInteger)NSWidth(bounds);
            NSInteger height = (NSInteger)NSHeight(bounds);
            if (width <= 0 || height <= 0) {
                fprintf(stderr,
                        "Invalid view bounds for capture (%ldx%ld)\n",
                        (long)width,
                        (long)height);
                return false;
            }

            // Manually allocate a bitmap to hold the rendered view
            // NULL means "allocate the pixel buffer for me"
            // The parameters specify RGBA format (4 samples, 8 bits each)
            rep = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL
                              pixelsWide:width
                              pixelsHigh:height
                           bitsPerSample:8
                         samplesPerPixel:4
                                hasAlpha:YES
                                isPlanar:NO
                          colorSpaceName:NSCalibratedRGBColorSpace
                             bytesPerRow:0
                            bitsPerPixel:0];
            if (!rep) {
                fprintf(stderr, "Failed to allocate bitmap rep\n");
                return false;
            }

            // Create a graphics context that draws into our bitmap
            NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            // Save/restore graphics state to avoid affecting other drawing
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            // Render the view into our bitmap
            [targetView displayRectIgnoringOpacity:bounds inContext:ctx];
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    // Convert the bitmap to PNG format
    // @{} is an Objective-C empty dictionary literal (like {} in C++ for std::map)
    // Properties could specify compression level, etc., but we use defaults
    NSData* pngData = [rep representationUsingType:NSBitmapImageFileTypePNG
                                        properties:@{}];

    // Write PNG data to file
    // [NSString stringWithUTF8String:...] converts C string to NSString*
    // ! prefix negates the boolean result
    if (![pngData writeToFile:[NSString stringWithUTF8String:outputPng.c_str()] atomically:YES]) {
        fprintf(stderr, "Failed to write PNG\n");
    }

    return true;
}

// Fallback implementation using VST3 SDK's hosting classes
// Used when the modern EditorHost approach fails
bool captureWithLegacyHost(const fs::path& pluginBundle,
                           const fs::path& outputPng,
                           const ScreenshotOptions& opts) {
    using namespace VST3::Hosting;

    // Load the VST3 plugin bundle
    std::string error;
    auto module = Module::create(pluginBundle.string(), error);
    if (!module) {
        fprintf(stderr, "Failed to load module %s: %s\n", pluginBundle.c_str(), error.c_str());
        return false;
    }

    ClassInfo chosenInfo;
    bool found = false;
    for (auto& info : module->getFactory().classInfos()) {
        if (strcmp(info.category().data(), kVstAudioEffectClass) == 0) {
            if (!opts.classNameFilter.empty() && info.name() != opts.classNameFilter) {
                continue;
            }
            chosenInfo = info;
            found = true;
            break;
        }
    }
    if (!found) {
        fprintf(stderr, "No audio effect class in %s\n", pluginBundle.c_str());
        return false;
    }

    HostApplication hostApp;
    PluginContextGuard contextGuard(&hostApp);

    auto factory = module->getFactory();
    factory.setHostContext(&hostApp);

    PlugProvider provider(factory, chosenInfo, true);
    if (!provider.initialize()) {
        fprintf(stderr, "Failed to initialize plug-in component/controller\n");
        return false;
    }

    IPtr<IComponent> component = provider.getComponentPtr();
    IPtr<IEditController> controller = provider.getControllerPtr();
    if (!controller) {
        fprintf(stderr, "No IEditController\n");
        return false;
    }

    ScreenshotComponentHandler componentHandler;
    controller->setComponentHandler(&componentHandler);

    auto view = FUnknownPtr<IPlugView>(controller->createView(ViewType::kEditor));
    if (!view) {
        fprintf(stderr, "No editor view\n");
        return false;
    }

    // Create a window to host the plugin's editor
    // NSMakeRect(x, y, width, height) creates an NSRect struct
    NSRect frame = NSMakeRect(0, 0, opts.width, opts.height);
    // Create window with standard title bar style
    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    // Prevent automatic deallocation when window is closed
    [window setReleasedWhenClosed:NO];

    // Get the window's content view (the area where we'll embed the plugin UI)
    NSView* contentView = [window contentView];

    // __bridge is an ARC cast that converts Objective-C pointer to void*
    // without transferring ownership (no retain/release)
    void* nsViewPtr = (__bridge void*)contentView;
    ScreenshotPlugFrame plugFrame(window);
    view->setFrame(&plugFrame);

    // Attach the VST3 plugin view to our macOS NSView
    if (view->attached(nsViewPtr, kPlatformTypeNSView) != kResultOk) {
        fprintf(stderr, "PlugView attach failed\n");
        return false;
    }

    // Get the plugin's preferred size and resize our window to match
    ViewRect vr;
    if (view->getSize(&vr) == kResultOk) {
        NSRect newFrame = NSMakeRect(0, 0, vr.right - vr.left, vr.bottom - vr.top);
        // .size extracts the NSSize part of NSRect (width and height only)
        [window setContentSize:newFrame.size];
    }

    // Capture the window with the plugin UI
    bool result = captureWindowToFile(window, contentView, outputPng);

    // Clean up: detach plugin view and hide window
    view->removed();
    view->setFrame(nullptr);
    controller->setComponentHandler(nullptr);
    [window orderOut:nil];  // Hide the window

    return result;
}

} // namespace

// Main entry point: load a VST3 plugin and capture its editor to a PNG file
// Try modern EditorHost first, fall back to legacy implementation if it fails
bool ScreenshotHost::capturePlugin(const fs::path& pluginBundle,
                                   const fs::path& outputPng,
                                   const ScreenshotOptions& opts) {
    // If user specified a plugin class name, resolve it to a VST3 UID
    std::optional<std::string> classUid;
    if (!opts.classNameFilter.empty()) {
        if (!resolveClassFilterToUid(pluginBundle, opts.classNameFilter, classUid)) {
            return false;
        }
    }

    // Try modern EditorHost implementation first
    EditorHostRunner runner;
    std::string hostError;
    if (runner.open(pluginBundle, classUid, hostError)) {
        // RAII guard ensures runner.close() is called on scope exit
        RunnerScopeGuard guard(runner);

        // EditorHost automatically resizes window to match plugin size after attachment
        // No need to manually resize

        // Get the macOS window and view that EditorHost created
        NSWindow* window = runner.window();
        NSView* contentView = runner.contentView();
        if (!window || !contentView) {
            fprintf(stderr, "EditorHost did not provide a capture window\n");
            return false;
        }

        bool captured = captureWindowToFile(window, contentView, outputPng);
        [window orderOut:nil];  // Hide window
        return captured;
    }

    // If EditorHost failed, fall back to legacy VST3 SDK hosting
    fprintf(stderr,
            "EditorHost failed to open %s: %s\nFalling back to legacy host...\n",
            pluginBundle.c_str(),
            hostError.c_str());

    return captureWithLegacyHost(pluginBundle, outputPng, opts);
}
#else
bool ScreenshotHost::capturePlugin(const fs::path& pluginBundle,
                                   const fs::path& outputPng,
                                   const ScreenshotOptions& opts) {
    (void)pluginBundle;
    (void)outputPng;
    (void)opts;
    fprintf(stderr,
            "VST3 SDK headers not found. Install the SDK into third_party/vst3sdk to enable captures.\n");
    return false;
}
#endif

} // namespace vstface
