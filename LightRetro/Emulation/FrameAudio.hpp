#pragma once
#include <atomic>
#include <cstdint>
#include <cstddef>
#include <vector>

// One emulation producer and one real-time audio consumer. Never allocate or lock
// in the AVAudioSourceNode callback. Capacity is a power of two, in stereo frames.
class AudioRing {
    static constexpr uint32_t capacity = 32768;
    float samples[capacity * 2]{};
    std::atomic<uint32_t> readIndex{0}, writeIndex{0};
public:
    size_t push(const int16_t* data, size_t frames) {
        auto w = writeIndex.load(std::memory_order_relaxed);
        auto r = readIndex.load(std::memory_order_acquire);
        size_t count = frames < capacity - (w-r) ? frames : capacity - (w-r);
        for(size_t i=0;i<count;i++) {
            auto slot = ((w + uint32_t(i)) & (capacity-1))*2;
            samples[slot] = data[i*2]/32768.f; samples[slot+1] = data[i*2+1]/32768.f;
        }
        writeIndex.store(w+uint32_t(count), std::memory_order_release);
        return count;
    }
    void pop(float* left, float* right, size_t frames) {
        auto r = readIndex.load(std::memory_order_relaxed);
        auto w = writeIndex.load(std::memory_order_acquire);
        size_t count = frames < w-r ? frames : w-r;
        for(size_t i=0;i<frames;i++) {
            auto slot = ((r + uint32_t(i)) & (capacity-1))*2;
            left[i] = i<count ? samples[slot] : 0;
            right[i] = i<count ? samples[slot+1] : 0;
        }
        readIndex.store(r+uint32_t(count), std::memory_order_release);
    }
    // Only reset after stopping the audio engine.
    void reset() { readIndex.store(0); writeIndex.store(0); }
};

inline bool convertFrame(const void* source, unsigned width, unsigned height,
                         size_t pitch, unsigned format, std::vector<uint8_t>& rgba) {
    const unsigned bytes = format == 1 ? 4 : 2;
    if(!source || !width || !height || width>4096 || height>4096 || pitch < width*bytes || format>2) return false;
    rgba.resize(size_t(width)*height*4);
    for(unsigned y=0;y<height;y++) for(unsigned x=0;x<width;x++) {
        const auto* p = static_cast<const uint8_t*>(source)+y*pitch+x*bytes;
        auto* d = rgba.data()+(size_t(y)*width+x)*4;
        if(format==1) { d[0]=p[2]; d[1]=p[1]; d[2]=p[0]; }
        else {
            uint16_t v = uint16_t(p[0]) | (uint16_t(p[1])<<8);
            unsigned r = (v>>(format==2?11:10))&31, g=(v>>5)&(format==2?63:31), b=v&31;
            d[0]=(r<<3)|(r>>2); d[1]=format==2?((g<<2)|(g>>4)):((g<<3)|(g>>2)); d[2]=(b<<3)|(b>>2);
        }
        d[3]=255;
    }
    return true;
}
