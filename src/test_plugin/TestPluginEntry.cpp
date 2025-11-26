#include "public.sdk/source/main/pluginfactory.h"

#include "TestPluginController.hpp"
#include "TestPluginIDs.hpp"
#include "TestPluginProcessor.hpp"

using namespace Steinberg;
using namespace Steinberg::Vst;

BEGIN_FACTORY_DEF(vstface::test_plugin::kVendor,
                  vstface::test_plugin::kVendorURL, "")

DEF_CLASS2(INLINE_UID_FROM_FUID(vstface::test_plugin::kProcessorUID),
           PClassInfo::kManyInstances, kVstAudioEffectClass,
           vstface::test_plugin::kPluginName, Vst::kDistributable,
           Vst::PlugType::kFx, vstface::test_plugin::kVersionString,
           kVstVersionString,
           vstface::test_plugin::TestPluginProcessor::createInstance)

DEF_CLASS2(INLINE_UID_FROM_FUID(vstface::test_plugin::kControllerUID),
           PClassInfo::kManyInstances, kVstComponentControllerClass,
           vstface::test_plugin::kControllerName, 0, "",
           vstface::test_plugin::kVersionString, kVstVersionString,
           vstface::test_plugin::TestPluginController::createInstance)

END_FACTORY
