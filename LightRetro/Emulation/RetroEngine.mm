#import "RetroEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <map>
#include <string>
#include <memory>
#include "libretro.h"
#include "FrameAudio.hpp"
#include "AnalogInput.hpp"
#include "JoypadButtons.hpp"
#import "RetroVideoView.h"
#include <cstdarg>
#include <cstdio>

struct CoreAPI {
    decltype(&retro_init) init;
    decltype(&retro_deinit) deinit;
    decltype(&retro_api_version) api_version;
    decltype(&retro_set_environment) set_environment;
    decltype(&retro_set_video_refresh) set_video_refresh;
    decltype(&retro_set_audio_sample) set_audio_sample;
    decltype(&retro_set_audio_sample_batch) set_audio_sample_batch;
    decltype(&retro_set_input_poll) set_input_poll;
    decltype(&retro_set_input_state) set_input_state;
    decltype(&retro_get_system_info) get_system_info;
    decltype(&retro_get_system_av_info) get_system_av_info;
    decltype(&retro_set_controller_port_device) set_controller_port_device;
    decltype(&retro_load_game) load_game;
    decltype(&retro_unload_game) unload_game;
    decltype(&retro_run) run;
    decltype(&retro_reset) reset;
    decltype(&retro_serialize_size) serialize_size;
    decltype(&retro_serialize) serialize;
    decltype(&retro_unserialize) unserialize;
    decltype(&retro_get_memory_data) get_memory_data;
    decltype(&retro_get_memory_size) get_memory_size;
};
struct CoreContext {
    void* handle=nullptr;
    CoreAPI api{};
    bool initialized=false, loaded=false, hasRun=false;
    std::string system, save, game, corePath;
    std::map<std::string,std::string> options;
    std::vector<uint8_t> rom, pixels;
    unsigned pixelFormat=RETRO_PIXEL_FORMAT_0RGB1555;
    JoypadButtons buttons[4]{};
    AnalogInput analog;
    retro_hw_render_callback hardware{};
    bool hardwareReady=false, audioChanged=false;
    std::string name;
    unsigned rotation=0;
    double fps=60, sampleRate=48000, aspect=4.0/3;
    std::shared_ptr<AudioRing> audio=std::make_shared<AudioRing>();
};
static CoreContext* active=nullptr;
static __weak RetroEngine* frontend=nil;

@interface RetroEngine () {
    std::unique_ptr<CoreContext> _core;
    CADisplayLink *_displayLink;
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_audioSource;
    RetroVideoView *_videoView;
    double _lastTime, _accumulator;
    BOOL _running;
}
- (void)render:(const void*)data width:(unsigned)width height:(unsigned)height pitch:(size_t)pitch;
- (BOOL)configureHardware:(retro_hw_render_callback*)callback;
- (void)applyAVInfo:(const retro_system_av_info*)av;
- (void)applyGeometry:(const retro_game_geometry*)geometry;
- (uintptr_t)framebuffer;
- (void)presentWidth:(unsigned)width height:(unsigned)height;
- (BOOL)prepareStateOperation;
@end

static uintptr_t currentFramebuffer() { return [frontend framebuffer]; }
static retro_proc_address_t getProcAddress(const char* symbol) {
    return reinterpret_cast<retro_proc_address_t>(dlsym(RTLD_DEFAULT,symbol));
}
static void coreLog(enum retro_log_level level,const char* format,...) {
    if(level<RETRO_LOG_WARN || !format) return;
    va_list args; va_start(args,format); vfprintf(stderr,format,args); va_end(args);
}
static const char* forcedOption(const char* key) {
    if(!active || active->name!="mupen64plus_next") return nullptr;
    if(!strcmp(key,"mupen64plus-cpucore")) return "cached_interpreter";
    if(!strcmp(key,"mupen64plus-rdp-plugin")) return "gliden64";
    if(!strcmp(key,"mupen64plus-rsp-plugin")) return "hle";
    if(!strcmp(key,"mupen64plus-ThreadedRenderer")) return "False";
    if(!strcmp(key,"mupen64plus-43screensize")) return "640x480";
    return nullptr;
}
static bool environment(unsigned command, void* data) {
    if(!active) return false;
    switch(command) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: *static_cast<const char**>(data)=active->system.c_str(); return true;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: *static_cast<const char**>(data)=active->save.c_str(); return true;
        case RETRO_ENVIRONMENT_GET_LIBRETRO_PATH: *static_cast<const char**>(data)=active->corePath.c_str(); return true;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE: *static_cast<bool*>(data)=true; return true;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            unsigned value=*static_cast<unsigned*>(data); if(value>2) return false;
            active->pixelFormat=value; return true;
        }
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: static_cast<retro_log_callback*>(data)->log=coreLog; return true;
        case RETRO_ENVIRONMENT_SET_HW_RENDER: return [frontend configureHardware:static_cast<retro_hw_render_callback*>(data)];
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: [frontend applyAVInfo:static_cast<retro_system_av_info*>(data)]; return true;
        case RETRO_ENVIRONMENT_SET_ROTATION: active->rotation=*static_cast<unsigned*>(data)%4; return true;
        case RETRO_ENVIRONMENT_SET_GEOMETRY: {
            [frontend applyGeometry:static_cast<retro_game_geometry*>(data)]; return true;
        }
        case RETRO_ENVIRONMENT_SET_VARIABLES: {
            for(auto* v=static_cast<retro_variable*>(data);v && v->key;v++) {
                std::string value=v->value?v->value:""; auto pos=value.find("; ");
                if(pos!=std::string::npos) value=value.substr(pos+2);
                value=value.substr(0,value.find('|')); active->options[v->key]=value;
            } return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            auto* v=static_cast<retro_variable*>(data);
            if(const char* forced=forcedOption(v->key)) { v->value=forced; return true; }
            auto found=active->options.find(v->key);
            v->value=found==active->options.end()?nullptr:found->second.c_str(); return v->value!=nullptr;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: *static_cast<bool*>(data)=false; return true;
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: *static_cast<unsigned*>(data)=2; return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
            for(auto* d=static_cast<retro_core_option_definition*>(data);d && d->key;d++)
                active->options[d->key]=d->default_value?d->default_value:(d->values[0].value?d->values[0].value:"");
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: return environment(RETRO_ENVIRONMENT_SET_CORE_OPTIONS,static_cast<retro_core_options_intl*>(data)->us);
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
            auto* options=static_cast<retro_core_options_v2*>(data);
            for(auto* d=options->definitions;d && d->key;d++)
                active->options[d->key]=d->default_value?d->default_value:(d->values[0].value?d->values[0].value:"");
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: return environment(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2,static_cast<retro_core_options_v2_intl*>(data)->us);
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS: return true;
        case RETRO_ENVIRONMENT_GET_INPUT_DEVICE_CAPABILITIES: *static_cast<uint64_t*>(data)=(1ULL<<RETRO_DEVICE_JOYPAD)|(1ULL<<RETRO_DEVICE_ANALOG); return true;
        case RETRO_ENVIRONMENT_GET_LANGUAGE: *static_cast<unsigned*>(data)=RETRO_LANGUAGE_ENGLISH; return true;
        case RETRO_ENVIRONMENT_GET_FASTFORWARDING: *static_cast<bool*>(data)=false; return true;
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS: {
            if (active->name != "fbneo" || !frontend.arcadeInputsChanged) return true;
            // The core emits P1 inputs in driver order, followed by optional
            // combination macros. Copy the IDs before it frees the descriptors.
            NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
            for (auto *d = static_cast<const retro_input_descriptor *>(data); d && d->description; ++d) {
                if (d->port || d->index || d->device != RETRO_DEVICE_JOYPAD ||
                    d->id >= 16 || (d->id >= 2 && d->id <= 7)) continue;
                NSString *name = [NSString stringWithUTF8String:d->description];
                if (!name.length || [name hasPrefix:@"Buttons "] || [name containsString:@"(Fake)"] ||
                    [@[@"Select", @"Start", @"Coin", @"Reset", @"Service", @"Test", @"Diagnostics"] containsObject:name]) continue;
                NSNumber *button = @(d->id);
                if (![ids containsObject:button]) [ids addObject:button];
            }
            frontend.arcadeInputsChanged([ids copy]);
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME: return true;
        case RETRO_ENVIRONMENT_SET_MESSAGE: {
            auto* m=static_cast<retro_message*>(data); NSString* message=m->msg?@(m->msg):@"";
            dispatch_async(dispatch_get_main_queue(), ^{ if(frontend.messageHandler) frontend.messageHandler(message); }); return true;
        }
        case RETRO_ENVIRONMENT_SHUTDOWN: dispatch_async(dispatch_get_main_queue(), ^{ [frontend pause]; if(frontend.messageHandler) frontend.messageHandler(@"The game engine stopped."); }); return true;
        default: return false; // Unsupported extensions stay explicitly unavailable.
    }
}
static void video(const void* data,unsigned w,unsigned h,size_t pitch) {
    if(data==RETRO_HW_FRAME_BUFFER_VALID) [frontend presentWidth:w height:h];
    else if(data) [frontend render:data width:w height:h pitch:pitch];
}
static size_t audioBatch(const int16_t* data,size_t frames) { if(active) active->audio->push(data,frames); return frames; }
static void audioSample(int16_t left,int16_t right) { int16_t s[2]={left,right}; audioBatch(s,1); }
static void inputPoll() {}
static int16_t inputState(unsigned port,unsigned device,unsigned index,unsigned id) {
    if(!active || port>=4) return 0;
    if((device&RETRO_DEVICE_MASK)==RETRO_DEVICE_ANALOG) return active->analog.get(port,index,id);
    if((device&RETRO_DEVICE_MASK)!=RETRO_DEVICE_JOYPAD) return 0;
    const auto state = active->buttons[port].state();
    if(id==RETRO_DEVICE_ID_JOYPAD_MASK) return state;
    return id<16 ? ((state>>id)&1) : 0;
}

@implementation RetroEngine
- (instancetype)init {
    if((self=[super init])) {
        _videoView=[[RetroVideoView alloc] init];
    } return self;
}
- (UIView*)videoView { return _videoView; }
- (uintptr_t)framebuffer { return [_videoView framebuffer]; }
- (BOOL)configureHardware:(retro_hw_render_callback*)callback {
    if(!_core || ![_videoView configureHardware:callback]) return NO;
    callback->get_current_framebuffer=currentFramebuffer;
    callback->get_proc_address=getProcAddress;
    _core->hardware=*callback;
    return YES;
}
- (void)applyGeometry:(const retro_game_geometry*)geometry {
    if(!_core || !geometry->base_width || !geometry->base_height) return;
    _core->aspect=geometry->aspect_ratio>0?geometry->aspect_ratio:double(geometry->base_width)/geometry->base_height;
    [_videoView setAspect:_core->aspect rotation:_core->rotation];
}
- (void)applyAVInfo:(const retro_system_av_info*)av {
    if(!_core) return;
    _core->fps=av->timing.fps>1 && av->timing.fps<300?av->timing.fps:60;
    double rate=av->timing.sample_rate>1000 && av->timing.sample_rate<=192000?av->timing.sample_rate:48000;
    if(rate!=_core->sampleRate) { _core->sampleRate=rate; _core->audioChanged=true; }
    [self applyGeometry:&av->geometry];
}
- (void)presentWidth:(unsigned)width height:(unsigned)height {
    if(!_core || !_core->hardwareReady) return;
    [_videoView setAspect:_core->aspect rotation:_core->rotation];
    [_videoView presentWidth:width height:height];
}
- (double)aspectRatio { return _core?_core->aspect:4.0/3; }
- (BOOL)running { return _running; }
- (NSString*)loadCore:(NSString*)core game:(NSString*)game system:(NSString*)system save:(NSString*)save {
    [self stop];
    if(active) return @"Another game is already running.";
    NSString* binary=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@",core,core]];
    _core=std::make_unique<CoreContext>();
    _core->name=core.UTF8String;
    _core->corePath=binary.UTF8String; _core->game=game.UTF8String; _core->system=system.UTF8String; _core->save=save.UTF8String;
    _core->handle=dlopen(binary.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
    if(!_core->handle) { _core.reset(); return @"This engine could not be loaded. Install a complete signed build of Light Retro."; }
#define LOAD(field) _core->api.field=reinterpret_cast<decltype(_core->api.field)>(dlsym(_core->handle,"retro_" #field)); if(!_core->api.field) { [self stop]; return @"The bundled game engine is incomplete."; }
    LOAD(init); LOAD(deinit); LOAD(api_version); LOAD(set_environment); LOAD(set_video_refresh); LOAD(set_audio_sample); LOAD(set_audio_sample_batch); LOAD(set_input_poll); LOAD(set_input_state); LOAD(get_system_info); LOAD(get_system_av_info); LOAD(set_controller_port_device); LOAD(load_game); LOAD(unload_game); LOAD(run); LOAD(reset); LOAD(serialize_size); LOAD(serialize); LOAD(unserialize); LOAD(get_memory_data); LOAD(get_memory_size);
#undef LOAD
    if(_core->api.api_version()!=RETRO_API_VERSION) { [self stop]; return @"Unsupported engine API version."; }
    active=_core.get(); frontend=self;
    auto& api=_core->api;
    api.set_environment(environment); api.set_video_refresh(video); api.set_audio_sample(audioSample); api.set_audio_sample_batch(audioBatch); api.set_input_poll(inputPoll); api.set_input_state(inputState);
    api.init(); _core->initialized=true;
    retro_system_info info{}; api.get_system_info(&info);
    retro_game_info content{}; content.path=_core->game.c_str();
    if(!info.need_fullpath) {
        NSError* error=nil; NSData* bytes=[NSData dataWithContentsOfFile:game options:NSDataReadingMappedIfSafe error:&error];
        if(!bytes || bytes.length>512*1024*1024) { [self stop]; return @"Could not read this ROM. Download the file locally and try again."; }
        const auto* start=static_cast<const uint8_t*>(bytes.bytes); _core->rom.assign(start,start+bytes.length);
        content.data=_core->rom.data(); content.size=_core->rom.size();
    }
    if(!api.load_game(&content)) { [self stop]; return @"The engine could not open this game. Check its format, matching ROM set, BIOS and companion files."; }
    _core->loaded=true;
    for(unsigned port=0;port<4;port++) api.set_controller_port_device(port,RETRO_DEVICE_JOYPAD);
    retro_system_av_info av{}; api.get_system_av_info(&av);
    [self applyAVInfo:&av];
    if(_core->hardware.context_type!=RETRO_HW_CONTEXT_NONE) {
        if(![_videoView prepareHardwareWidth:av.geometry.max_width height:av.geometry.max_height]) {
            [self stop]; return @"Could not create the N64 graphics surface on this device.";
        }
        [_videoView makeCurrent];
        if(_core->hardware.context_reset) _core->hardware.context_reset();
        _core->hardwareReady=true;
    }
    NSString* ramPath=[save stringByAppendingPathComponent:@"battery.srm"];
    NSData* ram=[NSData dataWithContentsOfFile:ramPath];
    size_t size=api.get_memory_size(RETRO_MEMORY_SAVE_RAM); void* memory=api.get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if(ram && memory && ram.length==size) memcpy(memory,ram.bytes,size);
    return nil;
}
- (void)configureAudio {
    NSError* error=nil;
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error];
    [AVAudioSession.sharedInstance setActive:YES error:&error];
    _audioEngine=[[AVAudioEngine alloc] init];
    AVAudioFormat* format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:_core->sampleRate channels:2];
    auto ring=_core->audio;
    _audioSource=[[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL* silence,const AudioTimeStamp* time,AVAudioFrameCount count,AudioBufferList* list) {
        if(list->mNumberBuffers==2) ring->pop(static_cast<float*>(list->mBuffers[0].mData),static_cast<float*>(list->mBuffers[1].mData),count);
        else for(unsigned i=0;i<list->mNumberBuffers;i++) memset(list->mBuffers[i].mData,0,list->mBuffers[i].mDataByteSize);
        return noErr;
    }];
    [_audioEngine attachNode:_audioSource]; [_audioEngine connect:_audioSource to:_audioEngine.mainMixerNode format:format];
    [_audioEngine startAndReturnError:&error];
    if(error && self.messageHandler) self.messageHandler(@"Audio is unavailable. Pause and resume after checking your audio device.");
}
- (void)start {
    if(!_core || !_core->loaded || _running) return;
    _core->audio->reset(); [self configureAudio]; _core->audioChanged=false;
    _lastTime=0; _accumulator=0; _running=YES;
    _displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _displayLink.preferredFrameRateRange=CAFrameRateRangeMake(60,120,60);
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)tick:(CADisplayLink*)link {
    if(!_core || !_running) return;
    double elapsed=_lastTime?link.timestamp-_lastTime:1.0/_core->fps;
    _lastTime=link.timestamp; _accumulator+=fmin(elapsed,0.1);
    double step=1.0/_core->fps;
    int frames=0;
    [_videoView makeCurrent];
    while(_accumulator>=step && frames<4) {
        _core->api.run();
        for (auto& port : _core->buttons) port.finishFrame();
        _core->hasRun=true; _accumulator-=step; frames++; step=1.0/_core->fps;
    }
    if(frames==4) _accumulator=0;
    if(_core->audioChanged) {
        [_audioEngine stop]; _audioEngine=nil; _audioSource=nil;
        _core->audio->reset(); [self configureAudio]; _core->audioChanged=false;
    }
}
- (void)render:(const void*)data width:(unsigned)width height:(unsigned)height pitch:(size_t)pitch {
    if(!_core || !convertFrame(data,width,height,pitch,_core->pixelFormat,_core->pixels)) return;
    NSData* bytes=[NSData dataWithBytes:_core->pixels.data() length:_core->pixels.size()];
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)bytes);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGImageRef frame=CGImageCreate(width,height,8,32,width*4,space,kCGBitmapByteOrderDefault|kCGImageAlphaLast,provider,nullptr,false,kCGRenderingIntentDefault);
    [_videoView setAspect:_core->aspect rotation:_core->rotation];
    [_videoView showImage:[UIImage imageWithCGImage:frame]];
    CGImageRelease(frame); CGColorSpaceRelease(space); CGDataProviderRelease(provider);
}
- (void)pause {
    if(_running) [_videoView finish];
    _running=NO; [_displayLink invalidate]; _displayLink=nil;
    [_audioEngine stop]; _audioEngine=nil; _audioSource=nil;
    [self clearButtons];
}
- (BOOL)saveRAM {
    if(!_core || !_core->loaded) return YES;
    auto& api=_core->api; size_t size=api.get_memory_size(RETRO_MEMORY_SAVE_RAM); void* memory=api.get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if(!memory || !size) return YES;
    NSData* data=[NSData dataWithBytes:memory length:size];
    return [data writeToFile:[@(_core->save.c_str()) stringByAppendingPathComponent:@"battery.srm"] options:NSDataWritingAtomic error:nil];
}
- (BOOL)prepareStateOperation {
    if(!_core || !_core->loaded) return NO;
    if(UIApplication.sharedApplication.applicationState==UIApplicationStateBackground) return NO;
    [_videoView makeCurrent];
    // Some cores (including N64) finish initialization on their first frame.
    // A saved game may be selected before the display link has ever run.
    if(!_core->hasRun) { _core->api.run(); _core->hasRun=true; }
    return YES;
}
- (BOOL)saveState:(NSString*)path {
    if(![self prepareStateOperation]) return NO;
    size_t size=_core->api.serialize_size(); if(!size || size>128*1024*1024) return NO;
    NSMutableData* bytes=[NSMutableData dataWithLength:size];
    if(!_core->api.serialize(bytes.mutableBytes,size)) return NO;
    return [bytes writeToFile:path options:NSDataWritingAtomic error:nil];
}
- (BOOL)loadState:(NSString*)path {
    if(![self prepareStateOperation]) return NO;
    NSData* data=[NSData dataWithContentsOfFile:path]; if(!data || data.length!=_core->api.serialize_size()) return NO;
    return _core->api.unserialize(data.bytes,data.length);
}
- (void)resetGame { if(_core && _core->loaded) { [_videoView makeCurrent]; _core->api.reset(); } }
- (void)setButton:(NSInteger)button pressed:(BOOL)pressed port:(NSInteger)port {
    if(!_core || port<0 || port>=4 || button<0 || button>=16) return;
    _core->buttons[port].set((unsigned)button, pressed);
}
- (void)setAxis:(NSInteger)axis value:(float)value stick:(NSInteger)stick port:(NSInteger)port {
    if(_core) _core->analog.set((int)port,(int)stick,(int)axis,value);
}
- (void)clearButtons { if(_core) { for (auto& port : _core->buttons) port = {}; _core->analog.clear(); } }
- (void)finishGraphics { [_videoView finish]; }
- (void)stop {
    [self pause]; [self saveRAM];
    if(_core) {
        [_videoView makeCurrent];
        if(_core->loaded) _core->api.unload_game();
        if(_core->hardwareReady && _core->hardware.context_destroy) _core->hardware.context_destroy();
        if(_core->initialized) _core->api.deinit();
        if(active==_core.get()) { active=nullptr; frontend=nil; }
        if(_core->handle) dlclose(_core->handle);
        _core.reset();
    }
    [_videoView clear];
    [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}
- (void)dealloc { [self stop]; }
@end
