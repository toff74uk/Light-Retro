#import "RetroVideoView.h"
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/EAGL.h>
#include <algorithm>
#include <cmath>

@interface RetroGLSurface : UIView
@end
@implementation RetroGLSurface
+ (Class)layerClass { return CAEAGLLayer.class; }
@end

@implementation RetroVideoView {
    UIImageView *_image;
    RetroGLSurface *_surface;
    EAGLContext *_context;
    GLuint _framebuffer, _color, _depth, _displayFramebuffer, _displayColor;
    unsigned _width, _height;
    GLint _displayWidth, _displayHeight;
    CGSize _drawableSize;
    BOOL _needsDepth, _needsStencil, _bottomLeft;
    double _aspect;
    unsigned _rotation;
}
- (instancetype)init {
    if ((self=[super init])) {
        self.backgroundColor=UIColor.blackColor;
        self.clipsToBounds=YES;
        self.accessibilityLabel=@"Game screen";
        _aspect=4.0/3;
        _image=[[UIImageView alloc] init];
        _image.contentMode=UIViewContentModeScaleToFill;
        _image.layer.magnificationFilter=kCAFilterNearest;
        _surface=[[RetroGLSurface alloc] init];
        _surface.hidden=YES;
        _surface.contentScaleFactor=UIScreen.mainScreen.scale;
        CAEAGLLayer *layer=(CAEAGLLayer *)_surface.layer;
        layer.opaque=YES;
        layer.drawableProperties=@{kEAGLDrawablePropertyRetainedBacking:@NO, kEAGLDrawablePropertyColorFormat:kEAGLColorFormatRGBA8};
        [self addSubview:_image]; [self addSubview:_surface];
    }
    return self;
}
- (void)setAspect:(double)aspect rotation:(unsigned)rotation {
    if (!(aspect>0 && std::isfinite(aspect))) aspect=4.0/3;
    if (_aspect==aspect && _rotation==rotation%4) return;
    _aspect=aspect; _rotation=rotation%4; [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    double ratio=(_rotation%2)?1.0/_aspect:_aspect;
    CGFloat w=MIN(self.bounds.size.width,self.bounds.size.height*ratio), h=w/ratio;
    for (UIView *view in @[_image,_surface]) {
        view.transform=CGAffineTransformIdentity;
        view.bounds=CGRectMake(0,0,(_rotation%2)?h:w,(_rotation%2)?w:h);
        view.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
        view.transform=CGAffineTransformMakeRotation(-M_PI_2*_rotation);
    }
    // Never issue GL calls from layout: UIKit may lay out a backgrounded app.
}
- (BOOL)configureHardware:(const retro_hw_render_callback *)callback {
    if (_context) return NO; // Context replacement is not offered during a session.
    if (callback->context_type!=RETRO_HW_CONTEXT_OPENGLES3 &&
        !(callback->context_type==RETRO_HW_CONTEXT_OPENGLES_VERSION && callback->version_major==3 && callback->version_minor==0)) return NO;
    _context=[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!_context || ![EAGLContext setCurrentContext:_context]) { _context=nil; return NO; }
    _needsDepth=callback->depth; _needsStencil=callback->stencil; _bottomLeft=callback->bottom_left_origin;
    _surface.hidden=NO; _image.hidden=YES;
    return YES;
}
- (void)makeCurrent { if (_context) [EAGLContext setCurrentContext:_context]; }
- (uintptr_t)framebuffer { return _framebuffer; }
- (BOOL)prepareHardwareWidth:(unsigned)width height:(unsigned)height {
    if (!_context || !width || !height) return NO;
    [self makeCurrent];
    GLint limit=0; glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE,&limit);
    if (width>(unsigned)limit || height>(unsigned)limit || width>4096 || height>4096) return NO;
    if (_framebuffer && width==_width && height==_height) return YES;
    GLint read=0,draw=0,render=0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read); glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw); glGetIntegerv(GL_RENDERBUFFER_BINDING,&render);
    if (!_framebuffer) glGenFramebuffers(1,&_framebuffer);
    if (!_color) glGenRenderbuffers(1,&_color);
    glBindFramebuffer(GL_FRAMEBUFFER,_framebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER,_color);
    glRenderbufferStorage(GL_RENDERBUFFER,GL_RGBA8,width,height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,_color);
    if (_needsDepth || _needsStencil) {
        if (!_depth) glGenRenderbuffers(1,&_depth);
        glBindRenderbuffer(GL_RENDERBUFFER,_depth);
        glRenderbufferStorage(GL_RENDERBUFFER,_needsStencil?GL_DEPTH24_STENCIL8:GL_DEPTH_COMPONENT24,width,height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_RENDERBUFFER,_depth);
        if (_needsStencil) glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_STENCIL_ATTACHMENT,GL_RENDERBUFFER,_depth);
    }
    BOOL valid=glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
    glBindFramebuffer(GL_READ_FRAMEBUFFER,read); glBindFramebuffer(GL_DRAW_FRAMEBUFFER,draw); glBindRenderbuffer(GL_RENDERBUFFER,render);
    if (valid) { _width=width; _height=height; }
    return valid;
}
- (void)presentWidth:(unsigned)width height:(unsigned)height {
    if (!_context || !_framebuffer || !width || !height || width>_width || height>_height) return;
    [self makeCurrent]; [self layoutIfNeeded];
    CGSize size=_surface.bounds.size;
    if (size.width<=0 || size.height<=0 || !_surface.window) return;
    GLint read=0,draw=0,render=0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read); glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw); glGetIntegerv(GL_RENDERBUFFER_BINDING,&render);
    GLboolean scissor=glIsEnabled(GL_SCISSOR_TEST);
    if (!_displayFramebuffer) glGenFramebuffers(1,&_displayFramebuffer);
    if (!_displayColor) glGenRenderbuffers(1,&_displayColor);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER,_displayFramebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER,_displayColor);
    if (!CGSizeEqualToSize(size,_drawableSize)) {
        if (![_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)_surface.layer]) goto restore;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_WIDTH,&_displayWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER,GL_RENDERBUFFER_HEIGHT,&_displayHeight);
        glFramebufferRenderbuffer(GL_DRAW_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,_displayColor);
        if (glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE) goto restore;
        _drawableSize=size;
    }
    glDisable(GL_SCISSOR_TEST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER,_framebuffer);
    glBlitFramebuffer(0,_bottomLeft?0:height,width,_bottomLeft?height:0,0,0,_displayWidth,_displayHeight,GL_COLOR_BUFFER_BIT,GL_NEAREST);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
restore:
    if (scissor) glEnable(GL_SCISSOR_TEST); else glDisable(GL_SCISSOR_TEST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER,read); glBindFramebuffer(GL_DRAW_FRAMEBUFFER,draw); glBindRenderbuffer(GL_RENDERBUFFER,render);
}
- (void)showImage:(UIImage *)image { _image.image=image; }
- (void)finish { if (_context) { [self makeCurrent]; glFinish(); } }
- (void)clear {
    if (_context) {
        [self makeCurrent];
        glDeleteFramebuffers(1,&_framebuffer); glDeleteFramebuffers(1,&_displayFramebuffer);
        glDeleteRenderbuffers(1,&_color); glDeleteRenderbuffers(1,&_depth); glDeleteRenderbuffers(1,&_displayColor);
        [EAGLContext setCurrentContext:nil]; _context=nil;
    }
    _framebuffer=_displayFramebuffer=_color=_depth=_displayColor=0;
    _width=_height=0; _drawableSize=CGSizeZero;
    _image.image=nil; _image.hidden=NO; _surface.hidden=YES;
    [self setAspect:4.0/3 rotation:0];
}
@end
