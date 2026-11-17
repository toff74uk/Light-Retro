#include "../LightRetro/Emulation/AnalogInput.hpp"
#include <cassert>
#include <limits>
#include <iostream>
int main() {
    AnalogInput input;
    assert(input.get(0,0,0)==0);
    input.set(0,0,0,1); input.set(0,0,1,-1);
    assert(input.get(0,0,0)==32767 && input.get(0,0,1)==-32768);
    input.set(1,1,0,2); input.set(1,1,1,-2);
    assert(input.get(1,1,0)==32767 && input.get(1,1,1)==-32768);
    input.set(0,1,0,0.5f); assert(input.get(0,1,0)==16384);
    assert(input.get(1,0,0)==0 && input.get(0,0,0)==32767);
    input.set(-1,0,0,1); input.set(4,0,0,1); input.set(0,2,0,1); input.set(0,0,2,1);
    assert(input.get(4,0,0)==0 && input.get(0,2,0)==0 && input.get(0,0,2)==0);
    input.set(3,0,0,std::numeric_limits<float>::quiet_NaN()); assert(input.get(3,0,0)==0);
    input.set(3,0,1,std::numeric_limits<float>::infinity()); assert(input.get(3,0,1)==0);
    input.clear();
    for(unsigned p=0;p<4;p++) for(unsigned s=0;s<2;s++) for(unsigned a=0;a<2;a++) assert(input.get(p,s,a)==0);
    std::cout << "Analogue input tests passed\n";
}
