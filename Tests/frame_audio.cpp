#include "../LightRetro/Emulation/FrameAudio.hpp"
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
    std::cout<<"Frame conversion and audio ring tests passed\n";
}
