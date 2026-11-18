#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface RetroEngine : NSObject
@property(nonatomic, readonly) UIView *videoView;
@property(nonatomic, readonly) double aspectRatio;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, copy, nullable) void (^messageHandler)(NSString *message);
@property(nonatomic, copy, nullable) void (^arcadeInputsChanged)(NSArray<NSNumber *> *buttonIDs);
// All frontend calls are on the main thread; only audio playback runs elsewhere.
- (nullable NSString *)loadCore:(NSString *)core game:(NSString *)game system:(NSString *)system save:(NSString *)save;
- (void)start;
- (void)pause;
- (void)stop;
- (void)resetGame;
- (void)setButton:(NSInteger)button pressed:(BOOL)pressed port:(NSInteger)port;
- (void)clearButtons;
- (void)setAxis:(NSInteger)axis value:(float)value stick:(NSInteger)stick port:(NSInteger)port;
- (void)finishGraphics;
- (BOOL)saveState:(NSString *)path;
- (BOOL)loadState:(NSString *)path;
- (BOOL)saveRAM;
@end
NS_ASSUME_NONNULL_END
