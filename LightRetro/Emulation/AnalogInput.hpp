#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
struct AnalogInput {
    int16_t axes[4][2][2]{};
    void set(int port,int stick,int axis,float value) {
        if(port<0 || port>=4 || stick<0 || stick>=2 || axis<0 || axis>=2) return;
        if(!std::isfinite(value)) value=0;
        value=std::clamp(value,-1.0f,1.0f);
        axes[port][stick][axis]=int16_t(std::lround(value*(value<0?32768:32767)));
    }
    int16_t get(unsigned port,unsigned stick,unsigned axis) const {
        return port<4 && stick<2 && axis<2?axes[port][stick][axis]:0;
    }
    void clear() { *this=AnalogInput{}; }
};
