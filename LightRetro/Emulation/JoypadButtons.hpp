#pragma once
#include <cstdint>

// The UI and libretro run on the main thread. Keep a short action-button tap
// visible to the next emulated frame, even when the finger has already lifted.
struct JoypadButtons {
    uint16_t held = 0;
    uint16_t pending = 0;

    void set(unsigned button, bool down) {
        if (button >= 16) return;
        const uint16_t bit = uint16_t(1u << button);
        if (down) {
            // Directions use their live state so a slide never adds an old diagonal.
            if (!(held & bit) && (button < 4 || button > 7)) pending |= bit;
            held |= bit;
        } else {
            held &= ~bit;
        }
    }
    uint16_t state() const { return held | pending; }
    void finishFrame() { pending = 0; }
};
