#pragma once

#include <memory>

#include "public.sdk/source/common/pluginview.h"

namespace vstface::test_plugin {

class TestPluginView : public Steinberg::CPluginView {
public:
  TestPluginView();

  Steinberg::tresult PLUGIN_API
  isPlatformTypeSupported(Steinberg::FIDString type) override;
  Steinberg::tresult PLUGIN_API attached(void *parent,
                                         Steinberg::FIDString type) override;
  Steinberg::tresult PLUGIN_API removed() override;
  Steinberg::tresult PLUGIN_API onSize(Steinberg::ViewRect *newSize) override;

private:
  void updateContentFrame();

  struct NativeView;
  std::unique_ptr<NativeView> nativeView_;
};

} // namespace vstface::test_plugin
