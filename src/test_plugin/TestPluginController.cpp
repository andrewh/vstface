#include "TestPluginController.hpp"

#include <cstring>

#include "TestPluginIDs.hpp"
#include "TestPluginView.hpp"

namespace vstface::test_plugin {

Steinberg::FUnknown *TestPluginController::createInstance(void * /*context*/) {
  return static_cast<Steinberg::Vst::IEditController *>(
      new TestPluginController());
}

Steinberg::tresult PLUGIN_API
TestPluginController::initialize(Steinberg::FUnknown *context) {
  const auto result = EditControllerEx1::initialize(context);
  if (result != Steinberg::kResultTrue) {
    return result;
  }

  return Steinberg::kResultTrue;
}

Steinberg::IPlugView *PLUGIN_API
TestPluginController::createView(Steinberg::FIDString name) {
  if (name && std::strcmp(name, Steinberg::Vst::ViewType::kEditor) == 0) {
    return new TestPluginView();
  }

  return nullptr;
}

} // namespace vstface::test_plugin
