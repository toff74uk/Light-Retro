#pragma once
#include <cmath>
#include <string>

namespace LightRetroVideo {

// FBNeo and the pinned MAME libretro core report the aspect ratio of the
// *displayed* arcade monitor, while independently requesting quarter-turn
// rotation through RETRO_ENVIRONMENT_SET_ROTATION. For vertical games such as
// 1942 / Galaga, that final display ratio is typically 3:4.
//
// RetroVideoView's layout expects the *unrotated framebuffer* aspect, then
// performs the requested rotation itself. Passing 3:4 straight through
// makes its rotated image 4:3: a portrait shooter becomes stretched wide.
//
// Both arcade cores therefore need their reported ratio inverted *only* for
// 90/270-degree rotation. Horizontal, upside-down and unusual native display
// ratios remain untouched. MAME "Internal" rotation also needs no change
// because it requests no quarter-turn. Console cores retain their established
// independent aspect handling.
inline double aspectBeforeRotation(const std::string &coreName,
                                   double reportedAspect, unsigned rotation) {
    if (!std::isfinite(reportedAspect) || reportedAspect <= 0.0)
        reportedAspect = 4.0 / 3.0;
    return (coreName == "fbneo" || coreName == "mamearcade") && (rotation % 2 != 0)
        ? 1.0 / reportedAspect : reportedAspect;
}

inline double resultingDisplayAspect(const std::string &coreName,
                                     double reportedAspect, unsigned rotation) {
    const double unrotated = aspectBeforeRotation(coreName, reportedAspect, rotation);
    return rotation % 2 ? 1.0 / unrotated : unrotated;
}

} // namespace LightRetroVideo
