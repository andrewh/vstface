#pragma once

#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "public.sdk/source/vst/vstaudioeffect.h"

namespace vstface::test_plugin {

class TestPluginProcessor : public Steinberg::Vst::AudioEffect {
public:
  TestPluginProcessor();

  static Steinberg::FUnknown *createInstance(void * /*context*/);

  Steinberg::tresult PLUGIN_API
  initialize(Steinberg::FUnknown *context) override;
  Steinberg::tresult PLUGIN_API
  process(Steinberg::Vst::ProcessData &data) override;
};

} // namespace vstface::test_plugin
