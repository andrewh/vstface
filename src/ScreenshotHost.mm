#import "ScreenshotHost.hpp"

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>

#if __has_include(<pluginterfaces/vst/vsttypes.h>)
#define VSTSHOT_HAS_VST3_SDK 1
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
#else
#define VSTSHOT_HAS_VST3_SDK 0
#endif

namespace vstshot {

namespace fs = std::filesystem;

ScreenshotHost::ScreenshotHost() {
    [NSApplication sharedApplication];
}

ScreenshotHost::~ScreenshotHost() {}

#if VSTSHOT_HAS_VST3_SDK
namespace {

class PluginContextGuard {
public:
    explicit PluginContextGuard(FUnknown* ctx) {
        Vst::PluginContextFactory::instance().setPluginContext(ctx);
    }
    ~PluginContextGuard() { Vst::PluginContextFactory::instance().setPluginContext(nullptr); }
};

class ScreenshotComponentHandler : public IComponentHandler {
public:
    tresult PLUGIN_API beginEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API performEdit(ParamID, ParamValue) override { return kResultOk; }
    tresult PLUGIN_API endEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API restartComponent(int32) override { return kResultOk; }

    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        if (!obj) {
            return kInvalidArgument;
        }
        if (FUnknownPrivate::iidEqual(iid, IComponentHandler::iid) ||
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
};

class ScreenshotPlugFrame : public IPlugFrame {
public:
    explicit ScreenshotPlugFrame(NSWindow* window) : window(window) {}

    tresult PLUGIN_API resizeView(IPlugView*, ViewRect* newSize) override {
        if (!window || !newSize) {
            return kResultFalse;
        }
        CGFloat width  = newSize->right - newSize->left;
        CGFloat height = newSize->bottom - newSize->top;
        NSSize size    = NSMakeSize(width, height);
        dispatch_async(dispatch_get_main_queue(), ^{
            [window setContentSize:size];
        });
        return kResultTrue;
    }

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
    __weak NSWindow* window = nil;
};

} // namespace

static void pumpRunLoop(double seconds) {
    NSDate* until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([[NSDate date] compare:until] == NSOrderedAscending) {
        @autoreleasepool {
            NSEvent* event =
                [NSApp nextEventMatchingMask:NSEventMaskAny
                                   untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                      inMode:NSDefaultRunLoopMode
                                     dequeue:YES];
            if (event) {
                [NSApp sendEvent:event];
            }
        }
    }
}

bool ScreenshotHost::capturePlugin(const fs::path& pluginBundle,
                                   const fs::path& outputPng,
                                   const ScreenshotOptions& opts) {
    using namespace VST3::Hosting;

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
            if (!opts.classNameFilter.empty() &&
                info.name() != opts.classNameFilter) {
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

    NSRect frame = NSMakeRect(0, 0, opts.width, opts.height);
    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setReleasedWhenClosed:NO];

    NSView* contentView = [window contentView];

    void* nsViewPtr = (__bridge void*)contentView;
    ScreenshotPlugFrame plugFrame(window);
    view->setFrame(&plugFrame);

    if (view->attached(nsViewPtr, kPlatformTypeNSView) != kResultOk) {
        fprintf(stderr, "PlugView attach failed\n");
        return false;
    }

    ViewRect vr;
    if (view->getSize(&vr) == kResultOk) {
        NSRect newFrame = NSMakeRect(0, 0, vr.right - vr.left, vr.bottom - vr.top);
        [window setContentSize:newFrame.size];
    }

    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    [window displayIfNeeded];
    pumpRunLoop(0.5); // give complex UI frameworks time to draw

    using CaptureFn = CGImageRef (*)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption);
    static CaptureFn captureFn = reinterpret_cast<CaptureFn>(dlsym(RTLD_DEFAULT, "CGWindowListCreateImage"));

    NSBitmapImageRep* rep = nil;
    if (captureFn) {
        CGWindowImageOption options = kCGWindowImageNominalResolution | kCGWindowImageBoundsIgnoreFraming;
        CGImageRef image = captureFn(CGRectNull,
                                     kCGWindowListOptionIncludingWindow,
                                     (CGWindowID)[window windowNumber],
                                     options);
        if (image) {
            rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
            CGImageRelease(image);
        } else {
            fprintf(stderr, "CGWindowListCreateImage returned NULL; ensure screen recording permission is granted.\n");
        }
    }

    if (!rep) {
        NSView* targetView = contentView;
        [targetView displayIfNeeded];

        NSRect bounds = [targetView bounds];
        rep = [targetView bitmapImageRepForCachingDisplayInRect:bounds];
        if (rep) {
            [targetView cacheDisplayInRect:bounds toBitmapImageRep:rep];
        } else {
            NSInteger width  = (NSInteger)NSWidth(bounds);
            NSInteger height = (NSInteger)NSHeight(bounds);
            if (width <= 0 || height <= 0) {
                fprintf(stderr, "Invalid view bounds for capture (%ldx%ld)\n",
                        (long)width,
                        (long)height);
                return false;
            }

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

            NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            [targetView displayRectIgnoringOpacity:bounds inContext:ctx];
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    NSData* pngData = [rep representationUsingType:NSBitmapImageFileTypePNG
                                        properties:@{}];
    if (![pngData writeToFile:[NSString stringWithUTF8String:outputPng.c_str()] atomically:YES]) {
        fprintf(stderr, "Failed to write PNG\n");
    }

    view->removed();
    view->setFrame(nullptr);
    controller->setComponentHandler(nullptr);
    [window orderOut:nil];

    return true;
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

} // namespace vstshot
