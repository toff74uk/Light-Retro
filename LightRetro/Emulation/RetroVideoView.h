#import <UIKit/UIKit.h>
#include "libretro.h"

// All methods, including GL presentation, run on the emulation/main thread.
@interface RetroVideoView : UIView
- (BOOL)configureHardware:(const struct retro_hw_render_callback *)callback;
- (BOOL)prepareHardwareWidth:(unsigned)width height:(unsigned)height;
- (uintptr_t)framebuffer;
- (void)makeCurrent;
- (void)finish;
- (void)presentWidth:(unsigned)width height:(unsigned)height;
- (void)showImage:(UIImage *)image;
- (void)setAspect:(double)aspect rotation:(unsigned)rotation;
- (void)clear;
@end
