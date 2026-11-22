#include "../LightRetro/Emulation/FrameAudio.hpp"
#include "../LightRetro/Emulation/VideoAspect.hpp"
#include <cassert>
#include <iostream>
int main() {
    std::vector<uint8_t> pixels;
    uint16_t rgb565[]={0xf800,0x07e0,0x001f,0};
    assert(convertFrame(rgb565,3,1,8,2,pixels));
    assert(pixels[0]==255 && pixels[1]==0 && pixels[5]==255 && pixels[10]==255);
    assert(!convertFrame(rgb565,3,1,4,2,pixels));
    assert(!convertFrame(rgb565,5000,1,10000,2,pixels));
    uint16_t rgb555[]={0x7c00,0x03e0,0x001f};
    assert(convertFrame(rgb555,3,1,6,0,pixels));
    assert(pixels[0]==255 && pixels[5]==255 && pixels[10]==255);
    uint32_t xrgb[]={0x00123456};
    assert(convertFrame(xrgb,1,1,4,1,pixels)); assert(pixels[0]==0x12 && pixels[1]==0x34 && pixels[2]==0x56 && pixels[3]==255);
    AudioRing ring; int16_t input[]={32767,-32768,16384,-16384};
    assert(ring.push(input,2)==2); float l[3],r[3];ring.pop(l,r,3);
    assert(l[0]>.999f && r[0]==-1.f && l[1]==.5f && r[1]==-.5f && l[2]==0 && r[2]==0);
    std::vector<int16_t> large(80000,100);assert(ring.push(large.data(),40000)==32768);
    assert(ring.push(input,2)==0);
    std::vector<float> left(32768),right(32768);ring.pop(left.data(),right.data(),32768);
    assert(ring.push(input,2)==2);ring.pop(l,r,2);assert(r[1]==-.5f);
    // FBNeo vertical cabinets: the game supplies display aspect 3:4 and
    // requests 90° rotation of its *landscape* framebuffer. The finished
    // display must remain 3:4 in either iPhone orientation.
    using LightRetroVideo::aspectBeforeRotation;
    using LightRetroVideo::resultingDisplayAspect;
    auto near = [](double actual, double expected) {
        return std::fabs(actual - expected) < 0.00001;
    };
    assert(near(aspectBeforeRotation("fbneo", 3.0/4.0, 1), 4.0/3.0));
    assert(near(resultingDisplayAspect("fbneo", 3.0/4.0, 1), 3.0/4.0));
    assert(near(resultingDisplayAspect("fbneo", 3.0/4.0, 3), 3.0/4.0));
    assert(near(resultingDisplayAspect("fbneo", 4.0/3.0, 0), 4.0/3.0));
    // FBNeo vertical-mode rotation settings can intentionally make a game
    // horizontal; preserve the core's selected display ratio unchanged.
    assert(near(resultingDisplayAspect("fbneo", 4.0/3.0, 2), 4.0/3.0));
    assert(near(resultingDisplayAspect("fbneo", 3.0/4.0, 3), 3.0/4.0));
    // Pinned MAME libretro in its default "Libretro" Screen Rotation Mode
    // reports post-rotation display geometry too. A 3:4 portrait game must
    // remain 3:4 after the frontend applies its own 90/270-degree rotation.
    assert(near(aspectBeforeRotation("mamearcade", 3.0/4.0, 1), 4.0/3.0));
    assert(near(resultingDisplayAspect("mamearcade", 3.0/4.0, 1), 3.0/4.0));
    assert(near(resultingDisplayAspect("mamearcade", 3.0/4.0, 3), 3.0/4.0));
    // Do not force horizontal or multi-monitor MAME into 4:3; preserve
    // the game and core option's actual display aspect.
    assert(near(resultingDisplayAspect("mamearcade", 4.0/3.0, 0), 4.0/3.0));
    assert(near(resultingDisplayAspect("mamearcade", 8.0/3.0, 0), 8.0/3.0));
    assert(near(resultingDisplayAspect("mamearcade", 3.0/4.0, 2), 3.0/4.0));
    // MAME's "Internal" rotation does not request a Libretro quarter-turn.
    assert(near(aspectBeforeRotation("mamearcade", 3.0/4.0, 0), 3.0/4.0));
    // Do not change any console aspect/rotation conventions.
    assert(near(resultingDisplayAspect("genesis_plus_gx", 4.0/3.0, 0), 4.0/3.0));
    assert(near(resultingDisplayAspect("mupen64plus_next", 4.0/3.0, 1), 3.0/4.0));
    assert(near(resultingDisplayAspect("fbneo", 0.0, 0), 4.0/3.0));
    std::cout<<"MAME and FBNeo vertical display geometry tests passed\n";
    std::cout<<"Frame conversion and audio ring tests passed\n";
}
