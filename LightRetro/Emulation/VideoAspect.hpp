#pragma once
#include <cmath>
#include <string>

namespace LightRetroVideo {

// FBNeo reports the aspect ratio of the *displayed* arcade monitor. For a
// vertical cabinet (e.g. 1942: 3:4), it supplies a landscape framebuffer and
// requests a 90-degree rotation through RETRO_ENVIRONMENT_SET_ROTATION.
//
// RetroVideoView applies that rotation when laying out the image. It needs
// the ratio *before* rotation; passing 3:4 straight through would turn it
// into 4:3, stretching a portrait shooter into a wide image.
//
// Other cores already use the existing frontend geometry convention. Do not
// alter their ratios, especially MAME and console titles.
inline double aspectBeforeRotation(const std::string &coreName,
                                   double reportedAspect, unsigned rotation) {
    if (!std::isfinite(reportedAspect) || reportedAspect <= 0.0)
        reportedAspect = 4.0 / 3.0;
    return coreName == "fbneo" && (rotation % 2 != 0)
        ? 1.0 / reportedAspect : reportedAspect;
}

inline double resultingDisplayAspect(const std::string &coreName,
                                     double reportedAspect, unsigned rotation) {
    const double unrotated = aspectBeforeRotation(coreName, reportedAspect, rotation);
    return rotation % 2 ? 1.0 / unrotated : unrotated;
}

} // namespace LightRetroVideo
