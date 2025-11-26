#import <Cocoa/Cocoa.h>

#include <cstdint>
#include <cstring>

#include "TestPluginIDs.hpp"
#include "TestPluginView.hpp"

#include "pluginterfaces/gui/iplugview.h"

namespace {

constexpr int32_t kDefaultWidth = 320;
constexpr int32_t kDefaultHeight = 200;

NSString *StringFromLiteral(const char *literal) {
  if (literal == nullptr) {
    return @"";
  }
  return [NSString stringWithUTF8String:literal];
}

NSFont *TitleFont() { return [NSFont boldSystemFontOfSize:22.0]; }

NSFont *DetailFont() {
  return [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
}

NSFont *CaptionFont() {
  return [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular];
}

} // namespace

@interface VSTFaceFixtureContentView : NSView
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *subtitleLabel;
@property(nonatomic, strong) NSTextField *versionLabel;
@end

@implementation VSTFaceFixtureContentView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    self.layer.cornerRadius = 12.0;

    NSString *pluginName = StringFromLiteral(vstface::test_plugin::kPluginName);
    _titleLabel = [NSTextField
        labelWithString:(pluginName.length > 0 ? pluginName : @"Fixture")];
    _titleLabel.font = TitleFont();
    _titleLabel.textColor = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
    [self addSubview:_titleLabel];

    _subtitleLabel = [NSTextField labelWithString:@"Static UI Fixture"];
    _subtitleLabel.font = DetailFont();
    _subtitleLabel.textColor = [NSColor colorWithCalibratedWhite:0.85
                                                           alpha:1.0];
    [self addSubview:_subtitleLabel];

    NSString *version =
        [NSString stringWithFormat:@"Version %@",
                                   StringFromLiteral(
                                       vstface::test_plugin::kVersionString)];
    _versionLabel = [NSTextField labelWithString:version];
    _versionLabel.font = CaptionFont();
    _versionLabel.textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    [self addSubview:_versionLabel];
  }
  return self;
}

- (void)layout {
  [super layout];

  const CGFloat padding = 20.0;
  const CGFloat titleHeight = 32.0;
  const CGFloat subtitleHeight = 22.0;

  NSRect bounds = self.bounds;
  self.titleLabel.frame =
      NSMakeRect(padding, bounds.size.height - padding - titleHeight,
                 bounds.size.width - padding * 2, titleHeight);

  self.subtitleLabel.frame =
      NSMakeRect(padding, NSMinY(self.titleLabel.frame) - subtitleHeight,
                 bounds.size.width - padding * 2, subtitleHeight);

  self.versionLabel.frame = NSMakeRect(
      padding, padding, bounds.size.width - padding * 2, subtitleHeight);
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
    [NSColor colorWithCalibratedRed:0.10 green:0.12 blue:0.20 alpha:1.0],
    [NSColor colorWithCalibratedRed:0.18 green:0.19 blue:0.32 alpha:1.0],
    [NSColor colorWithCalibratedRed:0.32 green:0.24 blue:0.38 alpha:1.0]
  ]];
  [gradient drawInRect:self.bounds angle:90.0];

  [[NSColor colorWithCalibratedWhite:1.0 alpha:0.12] setStroke];
  NSBezierPath *border =
      [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                      xRadius:12.0
                                      yRadius:12.0];
  border.lineWidth = 1.0;
  [border stroke];
}

@end

namespace vstface::test_plugin {

struct TestPluginView::NativeView {
  NSView *parent = nil;
  NSView *content = nil;

  ~NativeView() {
    if (content) {
      [content removeFromSuperview];
    }
    parent = nil;
    content = nil;
  }
};

TestPluginView::TestPluginView() : CPluginView(nullptr) {
  Steinberg::ViewRect defaultRect(0, 0, kDefaultWidth, kDefaultHeight);
  setRect(defaultRect);
}

Steinberg::tresult PLUGIN_API
TestPluginView::isPlatformTypeSupported(Steinberg::FIDString type) {
  if (type && std::strcmp(type, Steinberg::kPlatformTypeNSView) == 0) {
    return Steinberg::kResultTrue;
  }
  return Steinberg::kResultFalse;
}

Steinberg::tresult PLUGIN_API
TestPluginView::attached(void *parent, Steinberg::FIDString type) {
  if (!parent || !type ||
      std::strcmp(type, Steinberg::kPlatformTypeNSView) != 0) {
    return Steinberg::kInvalidArgument;
  }

  const auto result = CPluginView::attached(parent, type);
  if (result != Steinberg::kResultTrue) {
    return result;
  }

  nativeView_ = std::make_unique<NativeView>();
  nativeView_->parent = (__bridge NSView *)parent;

  NSRect frame = NSMakeRect(0, 0, getRect().getWidth(), getRect().getHeight());
  nativeView_->content =
      [[VSTFaceFixtureContentView alloc] initWithFrame:frame];
  nativeView_->content.autoresizingMask =
      NSViewWidthSizable | NSViewHeightSizable;

  [nativeView_->parent addSubview:nativeView_->content];
  updateContentFrame();

  return Steinberg::kResultTrue;
}

Steinberg::tresult PLUGIN_API TestPluginView::removed() {
  nativeView_.reset();
  return CPluginView::removed();
}

Steinberg::tresult PLUGIN_API
TestPluginView::onSize(Steinberg::ViewRect *newSize) {
  const auto result = CPluginView::onSize(newSize);
  if (result == Steinberg::kResultTrue) {
    updateContentFrame();
  }
  return result;
}

void TestPluginView::updateContentFrame() {
  if (!nativeView_ || !nativeView_->content) {
    return;
  }

  const auto &bounds = getRect();
  nativeView_->content.frame =
      NSMakeRect(0, 0, bounds.getWidth(), bounds.getHeight());
}

} // namespace vstface::test_plugin
