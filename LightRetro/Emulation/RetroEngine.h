#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface LREmulatorOption : NSObject
@property(nonatomic, readonly) NSString *key;
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) NSString *helpText;
@property(nonatomic, readonly) NSString *value;
@property(nonatomic, readonly) NSArray<NSString *> *values;
@property(nonatomic, readonly) NSArray<NSString *> *labels;
@end

@interface RetroEngine : NSObject
@property(nonatomic, readonly) UIView *videoView;
@property(nonatomic, readonly) double aspectRatio;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, copy, nullable) void (^displayAspectChanged)(double aspect);
@property(nonatomic, copy, nullable) void (^messageHandler)(NSString *message);
@property(nonatomic, copy, nullable) void (^arcadeInputsChanged)(NSArray<NSNumber *> *buttonIDs);
// All frontend calls are on the main thread; only audio playback runs elsewhere.
- (nullable NSString *)loadCore:(NSString *)core game:(NSString *)game system:(NSString *)system save:(NSString *)save;
- (void)start;
- (void)pause;
- (void)stop;
- (void)resetGame;
- (BOOL)toggleMAMEMenu;
- (NSArray<LREmulatorOption *> *)emulatorOptions;
- (BOOL)setOption:(NSString *)key value:(NSString *)value NS_SWIFT_NAME(setOption(_:value:));
- (void)setButton:(NSInteger)button pressed:(BOOL)pressed port:(NSInteger)port;
- (void)clearButtons;
- (void)setAxis:(NSInteger)axis value:(float)value stick:(NSInteger)stick port:(NSInteger)port;
- (void)finishGraphics;
- (BOOL)saveState:(NSString *)path;
- (BOOL)loadState:(NSString *)path;
- (BOOL)saveRAM;
@end
NS_ASSUME_NONNULL_END
