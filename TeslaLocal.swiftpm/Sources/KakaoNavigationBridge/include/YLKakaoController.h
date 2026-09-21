#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// One process-wide owner of the official KNSDK guidance singleton. Main queue only.
@interface YLKakaoController : UIViewController
@property(nonatomic, copy, nullable) void (^eventHandler)(NSString *event, NSString *message);
@property(nonatomic, copy, nullable) void (^telemetryHandler)(NSDictionary<NSString *, id> *snapshot);
@property(nonatomic, readonly) BOOL guiding;
- (void)configureMapAnchorX:(double)x y:(double)y NS_SWIFT_NAME(configureMapAnchor(x:y:));
- (void)configureMapTheme:(NSString *)theme NS_SWIFT_NAME(configureMapTheme(_:));
- (void)configureVoice:(BOOL)enabled safety:(BOOL)safety volume:(float)volume duck:(BOOL)duck
    NS_SWIFT_NAME(configureVoice(enabled:safety:volume:duck:));
/// 0 = brief (turns close to the junction and real hazards), 1 = normal, 2 = everything the SDK offers.
- (void)configureVoiceDetail:(NSInteger)level NS_SWIFT_NAME(configureVoiceDetail(_:));
- (void)prepareWithAppKey:(NSString *)key latitude:(double)latitude longitude:(double)longitude
     destinationLatitude:(double)destinationLatitude destinationLongitude:(double)destinationLongitude
                    name:(NSString *)name hipass:(BOOL)hipass validUntil:(NSTimeInterval)validUntil
    NS_SWIFT_NAME(prepare(appKey:latitude:longitude:destinationLatitude:destinationLongitude:name:hipass:validUntil:));
- (void)prepareStandbyWithAppKey:(NSString *)key latitude:(double)latitude longitude:(double)longitude
    NS_SWIFT_NAME(prepareStandby(appKey:latitude:longitude:));
- (void)updateStandbyLocationWithLatitude:(double)latitude longitude:(double)longitude bearing:(double)bearing speed:(double)speed
    NS_SWIFT_NAME(updateStandbyLocation(latitude:longitude:bearing:speed:));
- (void)stopNavigation NS_SWIFT_NAME(stopNavigation());
/// Resume camera tracking after manual map browsing.
- (void)recenter NS_SWIFT_NAME(recenter());
@end
NS_ASSUME_NONNULL_END
