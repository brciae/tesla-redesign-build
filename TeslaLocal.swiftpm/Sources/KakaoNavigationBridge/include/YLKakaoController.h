#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// One process-wide owner of the official KNSDK guidance singleton. Main queue only.
@interface YLKakaoController : UIViewController
@property(nonatomic, copy, nullable) void (^eventHandler)(NSString *event, NSString *message);
@property(nonatomic, copy, nullable) void (^telemetryHandler)(NSDictionary<NSString *, id> *snapshot);
@property(nonatomic, readonly) BOOL guiding;
@property(nonatomic, readonly, nullable) UIImage *junctionImage;
@property(nonatomic, readonly) double junctionDistance;
@property(nonatomic, readonly) BOOL offlineMapDownloaded;
@property(nonatomic, readonly) BOOL offlineMapInUse;
- (void)downloadOfflineMap NS_SWIFT_NAME(downloadOfflineMap());
- (void)pauseOfflineMapDownload NS_SWIFT_NAME(pauseOfflineMapDownload());
- (void)useOfflineMap:(BOOL)enabled NS_SWIFT_NAME(useOfflineMap(_:));
- (BOOL)refreshTrafficRoute NS_SWIFT_NAME(refreshTrafficRoute());
- (void)configureAutoTrafficReroute:(BOOL)enabled NS_SWIFT_NAME(configureAutoTrafficReroute(_:));
- (void)configureMapAnchorX:(double)x y:(double)y NS_SWIFT_NAME(configureMapAnchor(x:y:));
- (void)configureMapTheme:(NSString *)theme NS_SWIFT_NAME(configureMapTheme(_:));
/// "arrow.blue" | "arrow.green" | "arrow.orange" | "car" — the map's own-vehicle marker.
- (void)configureMarkerStyle:(NSString *)style NS_SWIFT_NAME(configureMarkerStyle(_:));
- (void)configureVoice:(BOOL)enabled safety:(BOOL)safety volume:(float)volume duck:(BOOL)duck
    NS_SWIFT_NAME(configureVoice(enabled:safety:volume:duck:));
/// Official SDK frequency: 0 = Rare, 1 = Often, 2 = Always.
- (void)configureVoiceDetail:(NSInteger)level NS_SWIFT_NAME(configureVoiceDetail(_:));
- (void)prepareWithAppKey:(NSString *)key latitude:(double)latitude longitude:(double)longitude
     destinationLatitude:(double)destinationLatitude destinationLongitude:(double)destinationLongitude
                    name:(NSString *)name hipass:(BOOL)hipass validUntil:(NSTimeInterval)validUntil
    NS_SWIFT_NAME(prepare(appKey:latitude:longitude:destinationLatitude:destinationLongitude:name:hipass:validUntil:));
- (void)prepareStandbyWithAppKey:(NSString *)key latitude:(double)latitude longitude:(double)longitude
    NS_SWIFT_NAME(prepareStandby(appKey:latitude:longitude:));
- (void)updateStandbyLocationWithLatitude:(double)latitude longitude:(double)longitude bearing:(double)bearing speed:(double)speed timestamp:(double)timestamp
    NS_SWIFT_NAME(updateStandbyLocation(latitude:longitude:bearing:speed:timestamp:));
- (void)stopNavigation NS_SWIFT_NAME(stopNavigation());
- (void)endGuidanceKeepingMap NS_SWIFT_NAME(endGuidanceKeepingMap());
- (void)resumeRendering NS_SWIFT_NAME(resumeRendering());
- (BOOL)isSpeechTargetAhead:(NSString *)identifier NS_SWIFT_NAME(isSpeechTargetAhead(_:));
- (BOOL)canFinishSpeech:(NSString *)identifier duration:(double)duration NS_SWIFT_NAME(canFinishSpeech(_:duration:));
/// Resume camera tracking after manual map browsing.
- (void)recenter NS_SWIFT_NAME(recenter());
@end
NS_ASSUME_NONNULL_END
