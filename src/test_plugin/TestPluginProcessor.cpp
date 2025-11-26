#include "TestPluginProcessor.hpp"

#include <algorithm>
#include <cstring>

#include "TestPluginIDs.hpp"

namespace vstface::test_plugin {
namespace {

template <typename SampleType>
void copyInputToOutput(SampleType **inputs, SampleType **outputs,
                       Steinberg::int32 inputChannels,
                       Steinberg::int32 outputChannels,
                       Steinberg::int32 sampleCount) {
  for (Steinberg::int32 channel = 0; channel < outputChannels; ++channel) {
    SampleType *destination = outputs[channel];
    if (!destination) {
      continue;
    }

    if (inputs && channel < inputChannels && inputs[channel]) {
      std::memcpy(destination, inputs[channel],
                  static_cast<size_t>(sampleCount) * sizeof(SampleType));
    } else {
      std::fill_n(destination, sampleCount, static_cast<SampleType>(0));
    }
  }
}

} // namespace

TestPluginProcessor::TestPluginProcessor() {
  setControllerClass(kControllerUID);
}

Steinberg::FUnknown *TestPluginProcessor::createInstance(void * /*context*/) {
  return static_cast<Steinberg::Vst::IAudioProcessor *>(
      new TestPluginProcessor());
}

Steinberg::tresult PLUGIN_API
TestPluginProcessor::initialize(Steinberg::FUnknown *context) {
  const auto result = AudioEffect::initialize(context);
  if (result != Steinberg::kResultTrue) {
    return result;
  }

  addAudioInput(STR16("Main Input"), Steinberg::Vst::SpeakerArr::kStereo);
  addAudioOutput(STR16("Main Output"), Steinberg::Vst::SpeakerArr::kStereo);

  return Steinberg::kResultTrue;
}

Steinberg::tresult PLUGIN_API
TestPluginProcessor::process(Steinberg::Vst::ProcessData &data) {
  if (data.numSamples <= 0 || data.numOutputs == 0) {
    return Steinberg::kResultTrue;
  }

  auto &outputBus = data.outputs[0];
  Steinberg::Vst::AudioBusBuffers *inputBus =
      data.numInputs > 0 ? &data.inputs[0] : nullptr;

  outputBus.silenceFlags = 0;

  if (processSetup.symbolicSampleSize == Steinberg::Vst::kSample64) {
    auto **inputs64 = inputBus ? inputBus->channelBuffers64 : nullptr;
    const auto inputChannels = inputBus ? inputBus->numChannels : 0;
    copyInputToOutput(inputs64, outputBus.channelBuffers64, inputChannels,
                      outputBus.numChannels, data.numSamples);
  } else {
    auto **inputs32 = inputBus ? inputBus->channelBuffers32 : nullptr;
    const auto inputChannels = inputBus ? inputBus->numChannels : 0;
    copyInputToOutput(inputs32, outputBus.channelBuffers32, inputChannels,
                      outputBus.numChannels, data.numSamples);
  }
  return Steinberg::kResultTrue;
}

} // namespace vstface::test_plugin
