#pragma once

#include "pluginterfaces/base/funknown.h"

namespace vstface::test_plugin {

inline const Steinberg::FUID kProcessorUID(0x8116D923, 0x7B7E425B, 0x9C8C084F,
                                           0x09F6123A);
inline const Steinberg::FUID kControllerUID(0x9348CF09, 0x5F2F4DD4, 0xB5190363,
                                            0x8B6F9A5E);

inline constexpr auto kPluginName = "VSTFace Static Fixture";
inline constexpr auto kControllerName = "VSTFace Static Fixture Controller";
inline constexpr auto kVendor = "vstface";
inline constexpr auto kVendorURL = "https://github.com/andrewh/vstface";
inline constexpr auto kVersionString = "1.0.0";

} // namespace vstface::test_plugin
