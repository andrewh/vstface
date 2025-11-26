#pragma once

#include "public.sdk/source/vst/vsteditcontroller.h"

namespace vstface::test_plugin {

class TestPluginController : public Steinberg::Vst::EditControllerEx1 {
public:
  TestPluginController() = default;

  static Steinberg::FUnknown *createInstance(void * /*context*/);

  Steinberg::tresult PLUGIN_API
  initialize(Steinberg::FUnknown *context) override;
  Steinberg::IPlugView *PLUGIN_API
  createView(Steinberg::FIDString name) override;
};

} // namespace vstface::test_plugin
