#import "YLKakaoController.h"
#import "YLNavigationSpeech.h"
#import <KNSDK/KNSDK.h>
#import <KNSDK/KNMapView.h>
#import <KNSDK/KNMapCameraUpdate.h>
#import <KNSDK/KNMapTheme.h>
#import <KNSDK/KNMapUserLocation.h>
#import <KNSDK/KNMapCoordinateRegion.h>
#import <KNSDK/KNMapRouteProperties.h>
#import <KNSDK/KNMapRouteTheme.h>
#import <KNSDK/KNMapViewEventListener.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>


// Fail compilation if the pinned SDK changes a speech maneuver ID.
_Static_assert(KNRGCode_Start == 100, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Goal == 101, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Via == 1000, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Straight == 0, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftTurn == 1, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightTurn == 2, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_UTurn == 3, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftDirection == 5, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightDirection == 6, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_OutHighway == 7, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftOutHighway == 8, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightOutHighway == 9, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_InHighway == 10, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftInHighway == 11, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightInHighway == 12, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_OverPath == 14, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_UnderPath == 15, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_OverPathSide == 16, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_UnderPathSide == 17, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_1 == 18, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_2 == 19, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_3 == 20, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_4 == 21, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_5 == 22, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_6 == 23, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_7 == 24, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_8 == 25, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_9 == 26, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_10 == 27, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_11 == 28, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Direction_12 == 29, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_1 == 30, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_2 == 31, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_3 == 32, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_4 == 33, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_5 == 34, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_6 == 35, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_7 == 36, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_8 == 37, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_9 == 38, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_10 == 39, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_11 == 40, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RotaryDirection_12 == 41, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_OutCityway == 42, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftOutCityway == 43, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightOutCityway == 44, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_InCityway == 45, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftInCityway == 46, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightInCityway == 47, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_ChangeLeftHighway == 48, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_ChangeRightHighway == 49, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_InFerry == 61, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_OutFerry == 62, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_UnprotectedLeftTurn == 63, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Tunnel == 64, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_TunnelSide == 65, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftTunnel == 66, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftTunnelSide == 67, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightTunnel == 68, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightTunnelSide == 69, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_1 == 70, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_2 == 71, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_3 == 72, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_4 == 73, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_5 == 74, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_6 == 75, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_7 == 76, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_8 == 77, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_9 == 78, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_10 == 79, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_11 == 80, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RoundaboutDirection_12 == 81, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftStraight == 82, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightStraight == 83, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_Tollgate == 84, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_NonstopTollgate == 85, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_JoinAfterBranch == 86, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftOverPath == 87, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftOverPathSide == 88, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightOverPath == 89, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightOverPathSide == 90, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftUnderPath == 91, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_LeftUnderPathSide == 92, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightUnderPath == 93, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_RightUnderPathSide == 94, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_IndoorEnterance == 900, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_IndoorExit == 901, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_IndoorToUpFloor == 902, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_IndoorToDownFloor == 903, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_IndoorToAdjacentParkingLot == 904, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_IndoorFromAdjacentParkingLot == 905, "KNRGCode speech contract changed");
_Static_assert(KNRGCode_IndoorRotationPoint == 906, "KNRGCode speech contract changed");

// Contract: official UI binary 1.12.19, not the older Swift snippets on the website.
// No simulation, URL handoff, screenshot map, private Tesla API or vehicle commands.
static NSString *YLInitializedKey;
static BOOL YLInitializing;
static __weak YLKakaoController *YLGuidanceOwner;
static NSArray *YLLifecycleObservers;

@interface YLKakaoController () <KNGuidance_GuideStateDelegate, KNGuidance_LocationGuideDelegate,
    KNGuidance_RouteGuideDelegate, KNGuidance_SafetyGuideDelegate, KNGuidance_VoiceGuideDelegate, KNGuidance_CitsGuideDelegate, KNMapViewEventListener>
@property(nonatomic, strong) KNGuidance *guidance;
@property(nonatomic, strong) KNMapView *map;
@property(nonatomic, copy) NSString *markerStyle;
/// KNMapUserLocation.icon is an `assign` property, so the image must be owned here.
@property(nonatomic, strong) UIImage *markerIcon;
@property(nonatomic, strong) KNGuide_Route *routeGuide;
@property(nonatomic, strong) KNGuide_Location *locationGuide;
@property(nonatomic, strong) KNGuide_Safety *safetyGuide;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *speechTargets;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *preparedSpeechPoints;
@property(nonatomic) BOOL forceImminent;
@property(nonatomic, strong) NSMutableSet<NSString *> *announcedPoints;
@property(nonatomic, strong) KNLocation *imminentTarget;
@property(nonatomic) FloatPoint mapAnchor;
@property(nonatomic) BOOL cameraReady;
@property(nonatomic) float trustedBearing;
@property(nonatomic) NSTimeInterval positionReceivedAt;
@property(nonatomic) BOOL pendingRecenter;
@property(nonatomic, copy) NSString *displayTheme;
@property(nonatomic, strong) KNMapRouteTheme *routeStyle;
@property(nonatomic, strong) KNRouteColors *routeColors;
@property(nonatomic, strong) KNRouteColors *routeStrokeColors;
@property(nonatomic, strong) UIColor *routeColor;
@property(nonatomic, strong) UIColor *routeStrokeColor;
@property(nonatomic, strong) NSTimer *freshnessTimer;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimeInterval validUntil;
@property(nonatomic, copy) NSString *previousAudioCategory;
@property(nonatomic, copy) NSString *previousAudioMode;
@property(nonatomic) AVAudioSessionCategoryOptions previousAudioOptions;
@property(nonatomic, readwrite) BOOL guiding;
@property(atomic) BOOL voiceEnabled;
@property(atomic) BOOL safetyVoiceEnabled;
@property(atomic) NSInteger voiceDetail;
@property(nonatomic) float voiceVolume;
@property(nonatomic) BOOL duckAudio;
// v30 map follow mode: user pan/rotate/tilt pauses camera tracking until recenter or idle timeout.
@property(nonatomic) BOOL following;
@property(nonatomic) BOOL userZooming;
@property(nonatomic, strong) NSTimer *followTimer;
// v30 road model: lane count persists per road; route shape is sampled ahead of the car.
@property(nonatomic) NSInteger lastLaneCount;
@property(nonatomic) NSTimeInterval lastLaneAt;
@property(nonatomic, copy) NSString *lastLaneRoad;
@property(nonatomic, copy) NSArray *routePath;
@property(nonatomic) NSTimeInterval routePathAt;
@end

@implementation YLKakaoController
- (instancetype)init {
    self = [super init];
    if (self) { _voiceEnabled = YES; _safetyVoiceEnabled = YES; _voiceDetail = 1; _voiceVolume = 1.0; _duckAudio = YES; _mapAnchor = FloatPointMake(0.52, 0.68); _following = YES; }
    return self;
}
- (void)configureVoiceDetail:(NSInteger)level {
    self.voiceDetail = MAX(0, MIN(2, level));
    KNGuideFrequencyMode mode = self.voiceDetail == 0 ? KNGuideFrequencyMode_Rare :
        self.voiceDetail == 1 ? KNGuideFrequencyMode_Often : KNGuideFrequencyMode_Always;
    self.guidance.directionFreqModeNormalWay = mode;
    self.guidance.directionFreqModeHighWay = mode;
    self.guidance.safetyFreqModeNormalWay = mode;
    self.guidance.safetyFreqModeHighWay = mode;
}
- (void)configureVoice:(BOOL)enabled safety:(BOOL)safety volume:(float)volume duck:(BOOL)duck {
    self.voiceEnabled = enabled; self.safetyVoiceEnabled = safety;
    self.voiceVolume = fmaxf(0, fminf(1, volume)); self.duckAudio = duck;
    // v30: the SDK never plays audio (all speech goes through the app voice), so the audio session is left to the app.
}
- (double)junctionDistance {
    KNImageDirection *image = self.routeGuide.imgDirection;
    if (!self.guiding || !image.directionImg || !image.location || !self.locationGuide.location ||
        [NSDate timeIntervalSinceReferenceDate] - self.positionReceivedAt > 8) return -1;
    return [self.locationGuide.location distToLocation:image.location];
}
- (UIImage *)junctionImage {
    double distance = self.junctionDistance;
    return distance >= 0 && distance <= 800 ? self.routeGuide.imgDirection.directionImg : nil;
}
- (void)configureMapTheme:(NSString *)theme {
    BOOL changed = ![self.displayTheme isEqualToString:theme];
    self.displayTheme = theme;
    if (!self.map || (!changed && self.routeStyle)) return;
    self.map.isVisibleBuilding = YES;
    BOOL night = [theme hasSuffix:@":night"];
    self.map.mapTheme = night ? [KNMapTheme driveNight] : [KNMapTheme driveDay];
    self.routeStyle = night ? [KNMapRouteTheme driveNight] : [KNMapRouteTheme driveDay];
    self.routeStyle.lineWidth = 10; self.routeStyle.strokeWidth = 2.5;
    self.routeColor = [UIColor colorWithRed:0.10 green:0.48 blue:1.0 alpha:1];
    self.routeStrokeColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    self.routeColors = [KNRouteColors routeColors];
    // Live traffic on the route: free flow stays brand blue, congestion reads yellow / orange / red.
    self.routeColors.normal = self.routeColor;
    self.routeColors.trafficJamModerate = [UIColor colorWithRed:1.0 green:0.80 blue:0.10 alpha:1];
    self.routeColors.trafficJamHeavy = [UIColor colorWithRed:1.0 green:0.50 blue:0.08 alpha:1];
    self.routeColors.trafficJamVeryHeavy = [UIColor colorWithRed:0.92 green:0.16 blue:0.14 alpha:1];
    self.routeColors.unknown = self.routeColor; self.routeColors.blocked = UIColor.systemRedColor;
    self.routeStyle.lineColors = self.routeColors;
    self.routeStrokeColors = [KNRouteColors routeColors];
    self.routeStrokeColors.normal = self.routeStrokeColor;
    self.routeStrokeColors.trafficJamModerate = self.routeStrokeColor;
    self.routeStrokeColors.trafficJamHeavy = self.routeStrokeColor;
    self.routeStrokeColors.trafficJamVeryHeavy = self.routeStrokeColor;
    self.routeStrokeColors.unknown = self.routeStrokeColor;
    self.routeStrokeColors.blocked = self.routeStrokeColor;
    self.routeStyle.strokeColors = self.routeStrokeColors;
    self.map.routeProperties.theme = self.routeStyle;
}
+ (void)initialize {
    if (self != YLKakaoController.class) return;
    // UIApplication notifications also work with SwiftUI scene lifecycle. Register once.
    NSArray *events = @[UIApplicationWillResignActiveNotification, UIApplicationDidEnterBackgroundNotification,
        UIApplicationWillEnterForegroundNotification, UIApplicationDidBecomeActiveNotification, UIApplicationWillTerminateNotification];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSUInteger i = 0; i < events.count; i++) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:events[i] object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (!YLInitializedKey && !YLInitializing) return;
            switch (i) {
                case 0: [KNSDK handleWillResignActive]; break;
                case 1: [KNSDK handleDidEnterBackground]; break;
                case 2: [KNSDK handleWillEnterForeground]; break;
                case 3: [KNSDK handleDidBecomeActive]; break;
                case 4: [KNSDK handleWillTerminate]; break;
            }
        }];
        [tokens addObject:token];
    }
    YLLifecycleObservers = [tokens copy];
}
- (void)emit:(NSString *)event message:(NSString *)message {
    if (self.eventHandler) self.eventHandler(event, message);
}
- (BOOL)isCurrent:(NSUInteger)generation {
    // v29: SDK callbacks that complete while the screen is locked/backgrounded are still valid.
    // Dropping them silently left the Swift side waiting and then blocked the destination.
    return generation == self.generation && NSDate.date.timeIntervalSince1970 <= self.validUntil;
}
- (void)fail:(NSString *)message generation:(NSUInteger)generation {
    if (generation != self.generation) return;
    [self stopNavigation];
    [self emit:@"error" message:message];
}
- (void)prepareWithAppKey:(NSString *)key latitude:(double)latitude longitude:(double)longitude
     destinationLatitude:(double)destinationLatitude destinationLongitude:(double)destinationLongitude
                    name:(NSString *)name hipass:(BOOL)hipass validUntil:(NSTimeInterval)validUntil {
    NSAssert(NSThread.isMainThread, @"Main queue required");
    [self stopNavigation];
    self.validUntil = validUntil;
    NSUInteger generation = self.generation;
    if (![self isCurrent:generation]) return;
    if (!isfinite(latitude) || !isfinite(longitude) || !isfinite(destinationLatitude) || !isfinite(destinationLongitude)
        || fabs(latitude) > 90 || fabs(longitude) > 180 || fabs(destinationLatitude) > 90 || fabs(destinationLongitude) > 180
        || key.length != 32 || name.length == 0) {
        [self fail:@"위치 또는 앱 키 형식 확인 필요" generation:generation]; return;
    }
    if (YLInitializing) { [self fail:@"SDK 인증 처리 중 · 잠시 후 직접 재시도" generation:generation]; return; }
    if (YLInitializedKey && ![YLInitializedKey isEqualToString:key]) {
        [self fail:@"앱 키 변경됨 · 앱을 완전히 종료한 뒤 다시 실행 필요" generation:generation]; return;
    }
    KNSDK *sdk = [KNSDK sharedInstance];
    if (!sdk) { [self fail:@"카카오 SDK 초기화 불가" generation:generation]; return; }
    __weak typeof(self) weakSelf = self;
    void (^buildTrip)(void) = ^{
        typeof(self) self = weakSelf;
        if (!self || ![self isCurrent:generation]) return;
        IntPoint startPoint = [sdk convertWGS84ToKATECWithLongitude:longitude latitude:latitude];
        IntPoint endPoint = [sdk convertWGS84ToKATECWithLongitude:destinationLongitude latitude:destinationLatitude];
        KNPOI *start = [[KNPOI alloc] initWithName:@"현재 위치" pos:startPoint];
        KNPOI *goal = [[KNPOI alloc] initWithName:name pos:endPoint];
        [sdk makeTripWithStart:start goal:goal vias:nil completion:^(KNError *error, KNTrip *trip) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                if (!self || ![self isCurrent:generation]) return;
                if (error || !trip) { [self fail:@"카카오 목적지 요청 실패 · 키·등록 Bundle ID·네트워크·쿼터 확인" generation:generation]; return; }
                trip.routeConfig = [[KNRouteConfiguration alloc] initWithCarType:KNCarType_1 fuel:KNCarFuel_Electric useHipass:hipass];
                [trip routeWithPriority:KNRoutePriority_Recommand avoidOptions:KNRouteAvoidOption_None completion:^(KNError *error, NSArray<KNRoute *> *routes) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        typeof(self) self = weakSelf;
                        if (!self || ![self isCurrent:generation]) return;
                        if (error || routes.count == 0) { [self fail:@"카카오 경로 탐색 실패 · 자동 반복 요청 중단됨" generation:generation]; return; }
                        [self attachTrip:trip sdk:sdk generation:generation];
                    });
                }];
            });
        }];
    };
    if (YLInitializedKey) { buildTrip(); return; }
    YLInitializing = YES;
    [sdk initializeWithAppKey:key clientVersion:@"0.22" completion:^(KNError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YLInitializing = NO;
            if (!error) YLInitializedKey = [key copy];
            if (!error && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) [KNSDK handleDidBecomeActive];
            typeof(self) self = weakSelf;
            if (!self || ![self isCurrent:generation]) return;
            if (error) { [self fail:@"카카오 SDK 인증 실패 · Native App Key와 iOS Bundle ID 확인" generation:generation]; return; }
            buildTrip();
        });
    }];
}
- (void)prepareStandbyWithAppKey:(NSString *)key latitude:(double)latitude longitude:(double)longitude {
    NSAssert(NSThread.isMainThread, @"Main queue required");
    [self stopNavigation];
    self.validUntil = DBL_MAX;
    NSUInteger generation = self.generation;
    if (key.length != 32) {
        [self fail:@"앱 키 형식 확인 필요" generation:generation]; return;
    }
    if (YLInitializing) { [self fail:@"SDK 인증 처리 중 · 잠시 후 직접 재시도" generation:generation]; return; }
    if (YLInitializedKey && ![YLInitializedKey isEqualToString:key]) {
        [self fail:@"앱 키 변경됨 · 앱을 완전히 종료한 뒤 다시 실행 필요" generation:generation]; return;
    }
    KNSDK *sdk = [KNSDK sharedInstance];
    if (!sdk) { [self fail:@"카카오 SDK 초기화 불가" generation:generation]; return; }
    __weak typeof(self) weakSelf = self;
    void (^setupStandby)(void) = ^{
        typeof(self) self = weakSelf;
        if (!self || ![self isCurrent:generation]) return;
        [self loadViewIfNeeded];
        self.map = [sdk makeMapViewWithFrame:self.view.bounds];
        if (!self.map) { [self fail:@"카카오 지도 생성 실패" generation:generation]; return; }
        self.map.mapTheme = [KNMapTheme driveNight];
        [self configureMapTheme:self.displayTheme ?: @"cluster"];
        self.map.isVisibleTraffic = YES;
        self.map.userLocation.isVisible = NO;
        self.map.viewEventListener = self;
        [self applyMarkerIcon];
        self.following = YES;
        self.userZooming = NO;
        self.map.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.map];
        [NSLayoutConstraint activateConstraints:@[
            [self.map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.map.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [self.map.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
        if (isfinite(latitude) && isfinite(longitude) && fabs(latitude) <= 90 && fabs(longitude) <= 180 && (latitude != 0 || longitude != 0)) {
            IntPoint point = [sdk convertWGS84ToKATECWithLongitude:longitude latitude:latitude];
            KNMapCoordinateRegion *region = [KNMapCoordinateRegion regionWithMin:FloatPointMake(point.x-300, point.y-300) max:FloatPointMake(point.x+300, point.y+300)];
            [self.map moveCamera:[KNMapCameraUpdate fitToRegion:region] withUserLocation:NO];
            self.cameraReady = YES;
        }
        [self emit:@"ready" message:@"카카오 실시간 지도 준비됨"];
    };
    if (YLInitializedKey) { setupStandby(); return; }
    YLInitializing = YES;
    [sdk initializeWithAppKey:key clientVersion:@"0.22" completion:^(KNError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YLInitializing = NO;
            if (!error) YLInitializedKey = [key copy];
            if (!error && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) [KNSDK handleDidBecomeActive];
            typeof(self) self = weakSelf;
            if (!self || ![self isCurrent:generation]) return;
            if (error) { [self fail:@"카카오 SDK 인증 실패 · Native App Key와 iOS Bundle ID 확인" generation:generation]; return; }
            setupStandby();
        });
    }];
}
- (void)attachTrip:(KNTrip *)trip sdk:(KNSDK *)sdk generation:(NSUInteger)generation {
    if (![self isCurrent:generation]) return;
    [YLGuidanceOwner stopNavigation];
    self.guidance = [sdk sharedGuidance];
    if (!self.guidance) { [self fail:@"카카오 길안내 엔진 준비 실패" generation:generation]; return; }
    YLGuidanceOwner = self;
    [self configureVoiceDetail:self.voiceDetail];
    // v30: do not activate/duck the shared audio session for the whole trip; the app voice activates it per announcement.
    [self emit:@"audioAcquired" message:@""];
    self.guidance.guideStateDelegate = self;
    self.guidance.locationGuideDelegate = self;
    self.guidance.routeGuideDelegate = self;
    self.guidance.safetyGuideDelegate = self;
    self.guidance.voiceGuideDelegate = self;
    self.guidance.citsGuideDelegate = self;
    self.guidance.useAutoReroute = YES;
    self.guidance.useBackgroundUpdate = YES;
    [self loadViewIfNeeded];
    self.map = [sdk makeMapViewWithFrame:self.view.bounds];
    if (!self.map) { [self fail:@"카카오 지도 생성 실패" generation:generation]; return; }
    self.map.mapTheme = [KNMapTheme driveNight];
    [self configureMapTheme:self.displayTheme ?: @"cluster"];
    self.map.isVisibleTraffic = NO;
    self.map.userLocation.isVisible = NO;
    self.map.viewEventListener = self;
    [self applyMarkerIcon];
    self.following = YES; self.userZooming = NO;
    self.map.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.map];
    [NSLayoutConstraint activateConstraints:@[
        [self.map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.map.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.map.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    __weak typeof(self) weakSelf = self;
    self.freshnessTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        if (![weakSelf locationIsFresh]) weakSelf.map.userLocation.isVisible = NO;
        [weakSelf publishTelemetry];
    }];
    // Raw map is presentation only. Start the engine exactly once, after delegates are ready.
    [self.guidance startWithTrip:trip priority:KNRoutePriority_Recommand avoidOptions:KNRouteAvoidOption_None];
    [self emit:@"ready" message:@"지도 준비 · 안내 시작 응답 대기"];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; self.map.paused = NO; [self emit:@"visible" message:@""]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; self.map.paused = YES; }
static NSString *const YLCarMarkerPNG = @"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";
/// Top-down navigation arrow with a white rim, drawn once per colour.
static UIImage *YLArrowIcon(UIColor *fill) {
    CGSize size = CGSizeMake(44, 44);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(22, 4)];
        [p addLineToPoint:CGPointMake(38, 38)];
        [p addLineToPoint:CGPointMake(22, 30)];
        [p addLineToPoint:CGPointMake(6, 38)];
        [p closePath];
        p.lineJoinStyle = kCGLineJoinRound;
        CGContextSetShadowWithColor(ctx.CGContext, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:0.45].CGColor);
        [fill setFill]; [p fill];
        CGContextSetShadowWithColor(ctx.CGContext, CGSizeZero, 0, NULL);
        p.lineWidth = 3; [[UIColor whiteColor] setStroke]; [p stroke];
    }];
}
- (void)applyMarkerIcon {
    if (!self.map) return;
    NSString *style = self.markerStyle ?: @"arrow.blue";
    UIImage *icon = nil;
    if ([style isEqualToString:@"car"]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:YLCarMarkerPNG options:0];
        icon = data ? [UIImage imageWithData:data scale:3] : nil;
    } else if ([style isEqualToString:@"arrow.green"]) {
        icon = YLArrowIcon([UIColor colorWithRed:0.19 green:0.82 blue:0.35 alpha:1]);
    } else if ([style isEqualToString:@"arrow.orange"]) {
        icon = YLArrowIcon([UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1]);
    } else {
        icon = YLArrowIcon([UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1]);
    }
    if (icon) { self.markerIcon = icon; self.map.userLocation.icon = self.markerIcon; self.map.userLocation.isFlat = YES; }
}
- (void)configureMarkerStyle:(NSString *)style {
    if ([self.markerStyle isEqualToString:style]) return;
    self.markerStyle = style;
    [self applyMarkerIcon];
}
- (void)configureMapAnchorX:(double)x y:(double)y {
    if (!isfinite(x) || !isfinite(y)) return;
    self.mapAnchor = FloatPointMake(fmax(0.2, fmin(0.8, x)), fmax(0.3, fmin(0.85, y)));
    [self updateMap];
}
- (void)stopNavigation {
    self.generation++;
    self.guiding = NO; self.positionReceivedAt = 0; self.pendingRecenter = NO; self.trustedBearing = 0;
    [self.freshnessTimer invalidate]; self.freshnessTimer = nil;
    if (YLGuidanceOwner == self) {
        self.guidance.guideStateDelegate = nil; self.guidance.locationGuideDelegate = nil;
        self.guidance.routeGuideDelegate = nil; self.guidance.safetyGuideDelegate = nil;
        self.guidance.voiceGuideDelegate = nil; self.guidance.citsGuideDelegate = nil;
        [self.guidance stop];
        YLGuidanceOwner = nil;
        // v30: never deactivate the shared session here — it cut off app speech mid-sentence on every reroute/stop.
    }
    [self.followTimer invalidate]; self.followTimer = nil; self.following = YES; self.userZooming = NO;
    self.routePath = nil; self.lastLaneCount = 0; self.lastLaneRoad = nil; self.lastLaneAt = 0;
    self.map.viewEventListener = nil;
    self.map.paused = YES; [self.map removeRoutesAll]; [self.map removeMarkersAll]; [self.map removeFromSuperview];
    self.map = nil; self.routeStyle = nil; self.guidance = nil; self.locationGuide = nil; self.routeGuide = nil; self.safetyGuide = nil; self.cameraReady = NO;
    [self.speechTargets removeAllObjects]; [self.preparedSpeechPoints removeAllObjects];
    if (self.telemetryHandler) self.telemetryHandler(@{});
}

// Engine callbacks must reach the UI. Dispatching also handles synchronous init callbacks.
#define YL_FORWARD(CALL) dispatch_async(dispatch_get_main_queue(), ^{ if (self.guidance == guidance && YLGuidanceOwner == self) { CALL; } })
- (void)guidanceGuideStarted:(KNGuidance *)guidance {
    YL_FORWARD(self.guiding = YES; if (guidance.routesOnGuide.count) [self.map setRoutes:guidance.routesOnGuide]; [self emit:@"started" message:@"길안내 중"]);
}
- (void)guidanceCheckingRouteChange:(KNGuidance *)guidance { YL_FORWARD([self emit:@"rerouting" message:@"경로 다시 확인 중"]); }
- (void)guidanceOutOfRoute:(KNGuidance *)guidance { YL_FORWARD(self.routeGuide = nil; [self publishTelemetry]; [self emit:@"rerouting" message:@"경로 이탈 · 다시 탐색 중"]); }
- (void)guidanceRouteUnchanged:(KNGuidance *)guidance { YL_FORWARD([self emit:@"status" message:@"길안내 중"]); }
- (void)guidance:(KNGuidance *)guidance routeUnchangedWithError:(KNError *)error { YL_FORWARD([self emit:@"status" message:@"경로 갱신 지연"]); }
- (void)guidanceRouteChanged:(KNGuidance *)guidance fromRoute:(KNRoute *)fromRoute fromLocation:(KNLocation *)fromLocation toRoute:(KNRoute *)toRoute toLocation:(KNLocation *)toLocation reason:(KNGuideRouteChangeReason)reason {
    YL_FORWARD(self.routeGuide = nil; self.locationGuide = nil; [self.map removeRoutesAll]; if (toRoute) [self.map setRoute:toRoute]; [self publishTelemetry]);
}
- (void)guidanceGuideEnded:(KNGuidance *)guidance {
    YL_FORWARD(self.guiding = NO; self.routeGuide = nil; self.safetyGuide = nil; [self.map removeRoutesAll]; [self publishTelemetry]; [self emit:@"ended" message:@"길안내 종료됨"]);
}
- (void)guidance:(KNGuidance *)guidance didUpdateRoutes:(NSArray<KNRoute *> *)routes multiRouteInfo:(KNMultiRouteInfo *)info { YL_FORWARD([self.speechTargets removeAllObjects]; [self.preparedSpeechPoints removeAllObjects]; if (routes.count) [self.map setRoutes:routes]; else [self.map removeRoutesAll]); }
- (void)guidance:(KNGuidance *)guidance didUpdateIndoorRoute:(KNRoute *)route { if (route) YL_FORWARD([self.map setRoute:route]); }
- (void)guidance:(KNGuidance *)guidance didUpdateLocation:(KNGuide_Location *)location { YL_FORWARD(self.locationGuide = location; self.positionReceivedAt = [NSDate timeIntervalSinceReferenceDate]; [self updateMap]; [self publishTelemetry]; [self emitImminentTurn]; [self emitAreaAndHumpCues]); }
- (void)guidance:(KNGuidance *)guidance didUpdateRouteGuide:(KNGuide_Route *)route { YL_FORWARD(self.routeGuide = route; [self publishTelemetry]); }
- (void)guidance:(KNGuidance *)guidance didUpdateSafetyGuide:(KNGuide_Safety *)safety { YL_FORWARD(self.safetyGuide = safety; [self publishTelemetry]); }
- (void)guidance:(KNGuidance *)guidance didUpdateAroundSafeties:(NSArray<__kindof KNSafety *> *)safeties { }
- (BOOL)guidance:(KNGuidance *)guidance shouldPlayVoiceGuide:(KNGuide_Voice *)voice replaceSndData:(NSData **)data {
    // Synchronous SDK callback: never dispatch_sync to main (SDK may be waiting on it).
    BOOL safety = voice.voiceCode == KNVoiceCode_Safety || voice.voiceCode == KNVoiceCode_Alert || voice.voiceCode == KNVoiceCode_SchoolZone || voice.voiceCode == KNVoiceCode_Alram;
    if (self.guidance != guidance || YLGuidanceOwner != self || (safety ? !self.safetyVoiceEnabled : !self.voiceEnabled)) return NO;
    // SDK supplies timing and guide objects only. All speech uses the app's selected voice.
    KNVoiceCode code = voice.voiceCode;
    id object = voice.guideObj;
    YL_FORWARD([self emitTimedSpeech:code object:object safety:safety]);
    return NO;
}
- (KNLocation *)speechLocation:(id)object {
    if ([object isKindOfClass:KNDirection.class]) return ((KNDirection *)object).location;
    if ([object isKindOfClass:KNSafety.class]) return ((KNSafety *)object).location;
    return nil;
}
- (BOOL)isSpeechTargetAhead:(NSString *)identifier {
    NSDictionary *record = self.speechTargets[identifier];
    if (!record || ![self locationIsFresh] || YLGuidanceOwner != self) return NO;
    if (-self.locationGuide.gpsMatched.timestamp.timeIntervalSinceNow > 2.5) return NO;
    SInt32 distance = [self.locationGuide.location distToLocation:record[@"target"]];
    return distance > 0 && distance <= [record[@"distance"] intValue] + 10;
}
- (void)emitTimedSpeech:(KNVoiceCode)code object:(id)object safety:(BOOL)safety {
    NSString *text = [self spokenTextForCode:code object:object];
    if (!text.length) return;
    NSMutableDictionary *message = [@{@"text":text, @"validUntil":@(NSDate.date.timeIntervalSince1970 + 12)} mutableCopy];
    KNLocation *target = [self speechLocation:object];
    BOOL stateChange = code == KNVoiceCode_StartGuide || code == KNVoiceCode_EndGuide || code == KNVoiceCode_OutOfRoute || code == KNVoiceCode_RouteChanged;
    message[@"stateChange"] = @(stateChange);
    message[@"incidental"] = @(code == KNVoiceCode_Alert && !target);
    if (stateChange) [self.speechTargets removeAllObjects];
    if (target) {
        if (![self locationIsFresh]) return;
        SInt32 distance = [self.locationGuide.location distToLocation:target];
        BOOL arrival = [object isKindOfClass:KNDirection.class] && distance == 0 &&
            (((KNDirection *)object).rgCode == 101 || ((KNDirection *)object).rgCode == 1000);
        if (distance <= 0 && !arrival) return;
        if (arrival) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
            if (data) [self emit:@"spokenGuide" message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
            return;
        }
        NSString *identifier = NSUUID.UUID.UUIDString;
        if (!self.speechTargets) self.speechTargets = [NSMutableDictionary dictionary];
        if (self.speechTargets.count >= 16) [self.speechTargets removeAllObjects];
        self.speechTargets[identifier] = @{@"target":target, @"distance":@(distance)};
        message[@"targetID"] = identifier;
        KNGPSData *gps = self.locationGuide.gpsMatched;
        double speed = gps.speedTrust ? fmax(0, gps.speed / 3.6) : 0;
        // Keep at least 3 s so a close maneuver survives the bridge and synthesis hop.
        double lifetime = speed > 1 ? fmin(12, fmax(3, distance / speed - 1.5)) : 12;
        message[@"validUntil"] = @(NSDate.date.timeIntervalSince1970 + lifetime);
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (data) [self emit:safety ? @"spokenSafety" : @"spokenGuide" message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}
- (void)prepareUpcomingSpeech {
    if (![self locationIsFresh] || (!self.voiceEnabled && !self.safetyVoiceEnabled)) return;
    NSMutableArray *objects = [NSMutableArray array];
    if (self.voiceEnabled && self.routeGuide.curDirection) [objects addObject:self.routeGuide.curDirection];
    if (self.safetyVoiceEnabled && self.safetyGuide.safetiesOnGuide.count) [objects addObjectsFromArray:self.safetyGuide.safetiesOnGuide];
    id nearest = nil; SInt32 nearestDistance = 2500;
    for (id object in objects) {
        KNLocation *target = [self speechLocation:object];
        if (!target) continue;
        SInt32 distance = [self.locationGuide.location distToLocation:target];
        if (distance >= 150 && distance < nearestDistance) { nearest = object; nearestDistance = distance; }
    }
    if (!nearest) return;
    NSString *text = [self spokenTextForCode:KNVoiceCode_Safety object:nearest];
    NSString *prefix = YLNavigationDistancePrefix(nearestDistance);
    if (!text.length || ![text hasPrefix:prefix]) return;
    NSString *body = [text substringFromIndex:prefix.length];
    if (!self.preparedSpeechPoints) self.preparedSpeechPoints = [NSMutableDictionary dictionary];
    NSDate *last = self.preparedSpeechPoints[body];
    if (last && -last.timeIntervalSinceNow < 5) return;
    if (self.preparedSpeechPoints.count >= 128) [self.preparedSpeechPoints removeAllObjects];
    self.preparedSpeechPoints[body] = NSDate.date;
    // Re-offer as the vehicle advances: Swift may have been busy or rate-limited.
    // Cached phrases incur no network request; the shared synthesis budget remains bounded.
    NSMutableArray *phrases = [NSMutableArray array];
    // Must match YLNavigationDistancePrefix bands exactly so live cues are cache hits.
    for (NSNumber *distance in @[@2000, @1000, @900, @800, @700, @600, @500, @400, @300, @200, @100, @0]) {
        if (distance.intValue <= nearestDistance) [phrases addObject:[YLNavigationDistancePrefix(distance.intValue) stringByAppendingString:body]];
        if (phrases.count == 3) break;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:phrases options:0 error:nil];
    if (data) [self emit:@"prepareSpeech" message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}
/// Distance the driver will be at when the sentence is actually heard (~3 s bridge + playback lead).
- (SInt32)spokenMetres:(KNLocation *)target {
    SInt32 raw = [self.locationGuide.location distToLocation:target];
    if (raw <= 0) return raw;
    if (self.forceImminent) return 40;
    KNGPSData *gps = self.locationGuide.gpsMatched;
    double speed = gps.speedTrust ? fmax(0, gps.speed / 3.6) : 0;
    return (SInt32)fmax(1, raw - speed * 3.0);
}
/// "잠시 후" cue a few seconds before the maneuver; the SDK's own last call comes too early for it.
/// Free-form cue (zones, tunnels) using the same timed message the SDK-driven cues use.
- (void)emitPlainSpeech:(NSString *)text safety:(BOOL)safety {
    NSDictionary *message = @{@"text": text, @"validUntil": @(NSDate.date.timeIntervalSince1970 + 8), @"stateChange": @NO, @"incidental": @NO};
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (data) [self emit:safety ? @"spokenSafety" : @"spokenGuide" message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}
/// Protection zones, tunnels and speed humps are announced by the app itself: the SDK only
/// voices some of them, and humps came through intermittently.
- (void)emitAreaAndHumpCues {
    if (!self.safetyVoiceEnabled || ![self locationIsFresh] || YLGuidanceOwner != self) return;
    if (!self.announcedPoints) self.announcedPoints = [NSMutableSet set];
    if (self.announcedPoints.count > 400) [self.announcedPoints removeAllObjects];
    KNGPSData *gps = self.locationGuide.gpsMatched;
    double speed = gps.speedTrust ? fmax(0, gps.speed / 3.6) : 0;
    for (KNSafetyZone *zone in self.routeGuide.safetyZones ?: @[]) {
        if (!zone.fromLocation) continue;
        SInt32 d = [self.locationGuide.location distToLocation:zone.fromLocation];
        NSString *key = [NSString stringWithFormat:@"zone:%d:%d", (int)zone.fromLocation.pos.x, (int)zone.fromLocation.pos.y];
        if (d <= 0 || d > fmax(150, fmin(400, speed * 12)) || [self.announcedPoints containsObject:key]) continue;
        [self.announcedPoints addObject:key];
        NSString *name = (zone.safetyZoneType & KNSafetyZoneType_SchoolZone) ? @"어린이 보호구역" : (zone.safetyZoneType & KNSafetyZoneType_SilverZone) ? @"노인 보호구역" : @"장애인 보호구역";
        [self emitPlainSpeech:[NSString stringWithFormat:@"%@%@입니다. 속도를 줄이고 주의하세요.", YLNavigationDistancePrefix((NSInteger)fmax(1, d - speed * 3)), name] safety:YES];
    }
    for (KNSafety *point in self.safetyGuide.safetiesOnGuide ?: @[]) {
        if (point.code != KNSafetyCode_Hump || !point.location) continue;
        SInt32 d = [self.locationGuide.location distToLocation:point.location];
        NSString *key = [NSString stringWithFormat:@"hump:%d", (int)point.safetyId];
        if (d <= 0 || d > fmax(60, fmin(150, speed * 5)) || [self.announcedPoints containsObject:key]) continue;
        [self.announcedPoints addObject:key];
        [self emitTimedSpeech:KNVoiceCode_Safety object:point safety:YES];
    }
    // Tunnels ahead come from the route's facility list: "500미터 앞, OO터널입니다. 길이 1.2킬로미터."
    KNRoute *route = self.guidance.routesOnGuide.firstObject;
    for (KNRoadInfo_Facility *f in [route mainFacilityList] ?: @[]) {
        if (f.facilityType != KNFacilityType_Tunnel || !f.fromLocation) continue;
        SInt32 d = [self.locationGuide.location distToLocation:f.fromLocation];
        NSString *key = [NSString stringWithFormat:@"tunnel:%d:%d", (int)f.fromLocation.pos.x, (int)f.fromLocation.pos.y];
        if (d <= 0 || d > fmax(300, fmin(700, speed * 15)) || [self.announcedPoints containsObject:key]) continue;
        [self.announcedPoints addObject:key];
        SInt32 len = f.toLocation ? [f.fromLocation distToLocation:f.toLocation] : 0;
        NSString *name = f.name.length ? ([f.name hasSuffix:@"터널"] ? f.name : [f.name stringByAppendingString:@" 터널"]) : @"터널";
        NSString *length = len >= 1000 ? [NSString stringWithFormat:@" 길이 %@킬로미터.", YLNavigationCompactNumber(round(len / 100.0) / 10.0)]
                                       : len >= 100 ? [NSString stringWithFormat:@" 길이 %d미터.", (int)(len / 100 * 100)] : @"";
        [self emitPlainSpeech:[NSString stringWithFormat:@"%@%@입니다.%@", YLNavigationDistancePrefix((NSInteger)fmax(1, d - speed * 3)), name, length] safety:YES];
    }
}
- (void)emitImminentTurn {
    if (!self.voiceEnabled || ![self locationIsFresh] || YLGuidanceOwner != self) return;
    KNDirection *dir = self.routeGuide.curDirection;
    if (!dir.location || dir.rgCode == 101 || dir.rgCode == 1000) return;
    if (self.imminentTarget && [self.imminentTarget distToLocation:dir.location] < 5) return;
    SInt32 raw = [self.locationGuide.location distToLocation:dir.location];
    KNGPSData *gps = self.locationGuide.gpsMatched;
    double speed = gps.speedTrust ? fmax(0, gps.speed / 3.6) : 0;
    if (speed < 2 || raw <= 10 || raw > fmax(60, fmin(180, speed * 5))) return;
    self.imminentTarget = dir.location;
    self.forceImminent = YES;
    [self emitTimedSpeech:KNVoiceCode_Turn object:dir safety:NO];
    self.forceImminent = NO;
}
- (NSString *)spokenTextForCode:(KNVoiceCode)code object:(id)object {
    NSString *prefix = @"";
    KNLocation *target = nil;
    if ([object isKindOfClass:KNDirection.class]) target = ((KNDirection *)object).location;
    if ([object isKindOfClass:KNSafety.class]) target = ((KNSafety *)object).location;
    if (target && [self locationIsFresh]) prefix = YLNavigationDistancePrefix([self spokenMetres:target]);
    if ([object isKindOfClass:KNDirection.class]) {
        KNDirection *dir = (KNDirection *)object;
        SInt32 metres = target && [self locationIsFresh] ? [self spokenMetres:target] : -1;
        return YLNavigationSpeech(dir.rgCode, dir.nodeName, dir.directionNames, metres);
    }
    if ([object isKindOfClass:KNSafety.class]) {
        KNSafety *point = object;
        NSDictionary *labels = @{@0:@"사고 다발 구간", @1:@"급커브 구간", @2:@"낙석 주의 구간", @3:@"안개 주의 구간", @4:@"추락 주의", @5:@"미끄러운 도로", @6:@"과속 방지턱", @10:@"철도 건널목", @11:@"어린이 보호 구역", @12:@"도로 폭 좁아짐", @13:@"급경사 내리막", @14:@"야생동물 출몰 지역", @15:@"졸음 쉼터", @16:@"졸음운전 사고 다발 구간", @17:@"오르막 구간", @18:@"신호등 주의", @20:@"무정차 요금소", @21:@"차량 사고 다발 구간", @22:@"보행자 사고 다발 구간", @23:@"어린이 사고 다발 구간", @24:@"상습 결빙 구간", @26:@"고의성 교통사고 다발 지점", @28:@"높이 제한", @29:@"중량 제한", @31:@"안개 주의 구간", @32:@"상습 결빙 구간", @40:@"지하차도 침수 주의", @80:@"단속 지점", @81:@"이동식 과속 단속 구간", @82:@"과속 단속", @83:@"교통 정보 수집 카메라", @84:@"버스 전용 차로 단속 구간", @85:@"과적 단속", @86:@"신호 과속 단속 구간", @87:@"주정차 단속 구간", @88:@"적재 불량 단속", @89:@"버스 전용 차로 및 신호 단속 구간", @90:@"고정식 단속 구간", @91:@"차로 및 과속 단속", @92:@"구간 단속 시작", @93:@"구간 단속 종료", @94:@"갓길 단속", @95:@"끼어들기 단속", @96:@"구간 단속", @97:@"지정차로 단속", @98:@"구간 단속 시작", @99:@"구간 단속 종료", @100:@"과속 단속", @101:@"안전띠 단속", @102:@"후면 과속 단속", @103:@"후면 신호 과속 단속 구간", @104:@"노후 경유차 운행 제한 단속", @105:@"후면 구간 단속 시작", @106:@"후면 구간 단속 종료", @692:@"구간 단속 시작", @693:@"구간 단속 종료", @696:@"구간 단속", @705:@"후면 구간 단속 시작", @706:@"후면 구간 단속 종료"};
        // Announce the point ahead, not an event that has supposedly already happened.
        NSDictionary *sentences = @{@93:@"구간 단속 종료 지점입니다.", @99:@"차로 변경 단속 종료 지점입니다.", @106:@"후면 구간 단속 종료 지점입니다.",
                                    @693:@"구간 단속 종료 지점입니다.", @706:@"후면 구간 단속 종료 지점입니다.",
                                    @90:@"신호 위반 단속 지점입니다.", @98:@"차로 변경 단속 시작 지점입니다.",
                                    @12:@"도로 폭이 좁아집니다.", @15:@"졸음쉼터가 있습니다.",
                                    @6:@"과속 방지턱이 있습니다. 속도를 줄이세요.",
                                    @11:@"어린이 보호구역입니다. 속도를 줄이고 주의하세요.",
                                    @14:@"야생동물 보호구역입니다. 주의하세요.",
                                    @23:@"어린이 사고 다발 구간입니다. 주의하세요."};
        // Speed cameras: "N미터 앞, 과속 단속 카메라가 있습니다. 제한 속도는 … 과속에 주의하세요."
        NSSet *speedCameras = [NSSet setWithArray:@[@81, @82, @86, @91, @100, @102, @103]];
        if ([speedCameras containsObject:@(point.code)]) {
            NSString *kind = point.code == 81 ? @"이동식 과속 단속 카메라" : (point.code == 86 || point.code == 103) ? @"신호 과속 단속 카메라" : @"과속 단속 카메라";
            NSString *limit = ([point isKindOfClass:KNSafety_Camera.class] && ((KNSafety_Camera *)point).speedLimit > 0)
                ? [NSString stringWithFormat:@" 제한 속도는 시속 %d킬로미터입니다.", (int)((KNSafety_Camera *)point).speedLimit] : @"";
            return [NSString stringWithFormat:@"%@%@가 있습니다.%@ 과속에 주의하세요.", prefix, kind, limit];
        }
        NSString *limitSentence = @"";
        if ([point isKindOfClass:KNSafety_Camera.class] && ((KNSafety_Camera *)point).speedLimit > 0)
            limitSentence = [NSString stringWithFormat:@" 제한 속도는 시속 %d킬로미터입니다.", (int)((KNSafety_Camera *)point).speedLimit];
        NSString *whole = sentences[@(point.code)];
        if (whole) return [[prefix stringByAppendingString:whole] stringByAppendingString:limitSentence];
        NSString *label = labels[@(point.code)];
        if (!label.length) return @""; // Unknown hazards need a supported meaning, not a filler sentence.
        if ([point isKindOfClass:KNSafety_Caution.class]) {
            SInt32 limit = ((KNSafety_Caution *)point).limit;
            if (limit > 0 && point.code == KNSafetyCode_HeightLimitPos) label = [label stringByAppendingFormat:@", %@미터", YLNavigationCompactNumber(limit/100.0)];
            if (limit > 0 && point.code == KNSafetyCode_WeightLimitPos) label = [label stringByAppendingFormat:@", %@톤", YLNavigationCompactNumber(limit/10.0)];
        }
        return [[[prefix stringByAppendingString:label] stringByAppendingString:@"입니다."] stringByAppendingString:limitSentence];
    }
    switch (code) {
        case KNVoiceCode_StartGuide: return @"안내를 시작합니다.";
        case KNVoiceCode_EndGuide: return @"목적지에 도착했습니다. 안내를 종료합니다.";
        case KNVoiceCode_DetalDir:
        case KNVoiceCode_MultiRoute:
            return @""; // SDK does not expose the source sentence for these audio-only events.
        case KNVoiceCode_SchoolZone: return @"어린이 보호 구역입니다.";
        case KNVoiceCode_Alert: return @"주의하세요.";
        case KNVoiceCode_Hipass: return @"하이패스 차로를 확인하세요.";
        case KNVoiceCode_StrateToNext: return @"계속 직진하세요.";
        case KNVoiceCode_CheckingRouteChange: return @"교통 상황을 확인합니다.";
        case KNVoiceCode_RouteChanged: return @"새로운 경로로 안내합니다.";
        case KNVoiceCode_RouteUnchanged: return @"현재 경로를 유지합니다.";
        case KNVoiceCode_OutOfRoute: return @"경로 이탈. 재탐색 중입니다.";
        case KNVoiceCode_GPSConnected: return @"위치 신호가 연결되었습니다.";
        case KNVoiceCode_BusLaneGuide: return @"버스 전용 차로입니다.";
        case KNVoiceCode_Alram: return @"";
        case KNVoiceCode_LinkSound: return @"";
        // Missing event objects cannot be replaced by a possibly different screen maneuver.
        case KNVoiceCode_Safety: return @"";
        case KNVoiceCode_Turn: return @"";
        default: return @"";
    }
}
// v30: shouldPlayVoiceGuide always returns NO, so the SDK never owns audio. Emitting voiceStart here used to cancel the
// app's own sentence and could leave the queue blocked when no matching finish arrived.
- (void)guidance:(KNGuidance *)guidance willPlayVoiceGuide:(KNGuide_Voice *)voice { }
- (void)guidance:(KNGuidance *)guidance didFinishPlayVoiceGuide:(KNGuide_Voice *)voice { }
- (void)guidance:(KNGuidance *)guidance didUpdateCitsGuide:(KNGuide_Cits *)cits { }
#undef YL_FORWARD

- (BOOL)locationIsFresh {
    KNGPSData *gps = self.locationGuide.gpsMatched;
    NSTimeInterval age = gps.timestamp ? -gps.timestamp.timeIntervalSinceNow : INFINITY;
    // Stale fixes must not drive the camera or navigation distances.
    return gps && gps.valid && age >= -3 && age <= 15 && isfinite(gps.pos.x) && isfinite(gps.pos.y);
}
- (void)updateMap {
    // Route properties may not exist until the SDK asynchronously installs a route.
    if (self.routeStyle && self.map.routeProperties && self.map.routeProperties.theme != self.routeStyle) {
        self.map.routeProperties.theme = self.routeStyle;
    }
    KNLocation *loc = self.locationGuide.location;
    KNGPSData *gps = self.locationGuide.gpsMatched;
    BOOL fresh = [self locationIsFresh];
    if (!fresh) { self.map.userLocation.isVisible = NO; return; }
    FloatPoint pos;
    float angle = self.trustedBearing;
    if (loc && isfinite(loc.pos.x) && isfinite(loc.pos.y)) {
        pos = FloatPointMake(loc.pos.x, loc.pos.y);
        if (gps && gps.angleTrust && gps.angle >= 0 && gps.angle < 360) angle = gps.angle;
    } else if (gps && isfinite(gps.pos.x) && isfinite(gps.pos.y)) {
        pos = FloatPointMake(gps.pos.x, gps.pos.y);
        if (gps.angleTrust && gps.angle >= 0 && gps.angle < 360) angle = gps.angle;
    } else {
        self.map.userLocation.isVisible = NO;
        return;
    }
    self.trustedBearing = angle;
    self.map.userLocation.coordinate = pos;
    self.map.userLocation.isVisible = YES;
    self.map.userLocation.angle = angle;
    if (!self.cameraReady && self.map.bounds.size.width > 100) {
        KNMapCoordinateRegion *region = [KNMapCoordinateRegion regionWithMin:FloatPointMake(pos.x-250, pos.y-250) max:FloatPointMake(pos.x+250, pos.y+250)];
        [self.map moveCamera:[KNMapCameraUpdate fitToRegion:region] withUserLocation:NO];
        self.cameraReady = YES;
    }
    if (loc) [self.map cullPassedRouteWithLocation:loc isAnimate:NO];
    if (self.pendingRecenter) { self.following = YES; self.userZooming = NO; self.pendingRecenter = NO; [self emit:@"follow" message:@"1"]; }
    if (!self.following || self.userZooming) return; // manual map browsing: keep the user's view
    KNMapCameraUpdate *update = [[[[KNMapCameraUpdate targetTo:pos] anchorTo:self.mapAnchor] bearingTo:angle] tiltTo:0];
    // Fit a real coordinate region once; retain subsequent pinch zoom rather than web-map zoom constants.
    [self.map moveCamera:update withUserLocation:YES];
}
- (void)updateStandbyLocationWithLatitude:(double)latitude longitude:(double)longitude bearing:(double)bearing speed:(double)speed timestamp:(double)timestamp {
    if (self.guiding || !self.map) return;
    if (!isfinite(latitude) || !isfinite(longitude) || fabs(latitude) > 90 || fabs(longitude) > 180) return;
    KNSDK *sdk = [KNSDK sharedInstance];
    if (!sdk) return;
    IntPoint pt = [sdk convertWGS84ToKATECWithLongitude:longitude latitude:latitude];
    FloatPoint pos = FloatPointMake(pt.x, pt.y);
    float angle = isfinite(bearing) && bearing >= 0 && bearing < 360 ? (float)bearing : self.trustedBearing;
    self.positionReceivedAt = timestamp - NSTimeIntervalSince1970;
    self.trustedBearing = angle;
    self.map.userLocation.coordinate = pos;
    self.map.userLocation.isVisible = YES;
    self.map.userLocation.angle = angle;
    if (!self.cameraReady && self.map.bounds.size.width > 100) {
        KNMapCoordinateRegion *region = [KNMapCoordinateRegion regionWithMin:FloatPointMake(pos.x-300, pos.y-300) max:FloatPointMake(pos.x+300, pos.y+300)];
        [self.map moveCamera:[KNMapCameraUpdate fitToRegion:region] withUserLocation:NO];
        self.cameraReady = YES;
    }
    if (self.pendingRecenter) { self.following = YES; self.userZooming = NO; self.pendingRecenter = NO; [self emit:@"follow" message:@"1"]; }
    if (!self.following || self.userZooming) return;
    KNMapCameraUpdate *update = [[[[KNMapCameraUpdate targetTo:pos] anchorTo:self.mapAnchor] bearingTo:angle] tiltTo:0];
    [self.map moveCamera:update withUserLocation:YES];
}
- (void)recenter {
    [self.followTimer invalidate]; self.followTimer = nil;
    BOOL usable = self.guiding ? [self locationIsFresh] :
        self.map.userLocation.isVisible && self.positionReceivedAt > 0 &&
        [NSDate timeIntervalSinceReferenceDate] - self.positionReceivedAt <= 15;
    if (!self.map || !usable) {
        self.pendingRecenter = YES;
        [self emit:@"positionWaiting" message:@"현재 위치 수신 대기"];
        return;
    }
    self.pendingRecenter = NO; self.following = YES; self.userZooming = NO;
    if (self.guiding) [self updateMap];
    else {
        FloatPoint pos = self.map.userLocation.coordinate;
        KNMapCameraUpdate *update = [[[[KNMapCameraUpdate targetTo:pos] anchorTo:self.mapAnchor] bearingTo:self.trustedBearing] tiltTo:0];
        [self.map moveCamera:update withUserLocation:YES];
    }
    [self emit:@"follow" message:@"1"];
}
- (void)pauseFollowing {
    self.pendingRecenter = NO;
    [self.followTimer invalidate]; self.followTimer = nil;
    if (self.following) { self.following = NO; [self emit:@"follow" message:@"0"]; }
}
- (void)scheduleFollowResume {
    [self.followTimer invalidate];
    __weak typeof(self) weakSelf = self;
    // App browsing timeout; not a claimed Kakao standard. Explicit recenter is always available.
    self.followTimer = [NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer *timer) { [weakSelf recenter]; }];
}
#pragma mark KNMapViewEventListener
- (void)mapView:(KNMapView *)aMapView singleTappedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView doubleTappedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView longPressedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView panningStartedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { [self pauseFollowing]; }
- (void)mapView:(KNMapView *)aMapView panningChangingWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView panningEndedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { [self scheduleFollowResume]; }
- (void)mapView:(KNMapView *)aMapView zoomingStartedWithScreenPoint:(CGPoint)aScreenPoint zoom:(float)aZoom { self.pendingRecenter = NO; self.userZooming = YES; }
- (void)mapView:(KNMapView *)aMapView zoomingChangingWithScreenPoint:(CGPoint)aScreenPoint zoom:(float)aZoom { }
- (void)mapView:(KNMapView *)aMapView zoomingEndedWithScreenPoint:(CGPoint)aScreenPoint zoom:(float)aZoom { self.userZooming = NO; if (!self.following) [self scheduleFollowResume]; }
- (void)mapView:(KNMapView *)aMapView bearingStartedWithScreenPoint:(CGPoint)aScreenPoint bearing:(float)aBearing { [self pauseFollowing]; }
- (void)mapView:(KNMapView *)aMapView bearingChangingWithScreenPoint:(CGPoint)aScreenPoint bearing:(float)aBearing { }
- (void)mapView:(KNMapView *)aMapView bearingEndedWithScreenPoint:(CGPoint)aScreenPoint bearing:(float)aBearing { [self scheduleFollowResume]; }
- (void)mapView:(KNMapView *)aMapView tiltingStartedWithScreenPoint:(CGPoint)aScreenPoint tilt:(float)aTilt { [self pauseFollowing]; }
- (void)mapView:(KNMapView *)aMapView tiltingChangingWithScreenPoint:(CGPoint)aScreenPoint tilt:(float)aTilt { }
- (void)mapView:(KNMapView *)aMapView tiltingEndedWithScreenPoint:(CGPoint)aScreenPoint tilt:(float)aTilt { [self scheduleFollowResume]; }
- (void)mapView:(KNMapView *)aMapView cameraAnimationCanceledWithCameraUpdate:(KNMapCameraUpdate *)aCameraUpdate { }
- (void)mapView:(KNMapView *)aMapView cameraAnimationEndedWithCameraUpdate:(KNMapCameraUpdate *)aCameraUpdate { }
- (void)onCameraAnimationChanging:(KNMapView *)mapView cameraUpdate:(KNMapCameraUpdate *)cameraUpdate { }

/// Route shape ahead in the car frame as [left m, forward m] pairs every 10 m up to 160 m.
/// Heading comes from the route itself (valid while stopped); KATEC units are calibrated by the SDK's own distance.
- (NSArray *)routeShapeFrom:(KNLocation *)location {
    KNLocation *ahead = [location locationAfterDist:8];
    if (!ahead) return nil;
    double hx = ahead.pos.x - location.pos.x, hy = ahead.pos.y - location.pos.y, len = hypot(hx, hy);
    SInt32 d8 = [location distToLocation:ahead];
    if (!(len > 0.001) || d8 <= 0 || !isfinite(len)) return nil;
    double scale = d8 / len;
    hx /= len; hy /= len;
    NSMutableArray *points = [NSMutableArray arrayWithCapacity:16];
    for (SInt32 d = 10; d <= 160; d += 10) {
        KNLocation *p = [location locationAfterDist:d];
        if (!p) break;
        double rx = (p.pos.x - location.pos.x) * scale, ry = (p.pos.y - location.pos.y) * scale;
        double forward = rx * hx + ry * hy, right = rx * hy - ry * hx;
        if (!isfinite(forward) || !isfinite(right) || fabs(right) > 400 || fabs(forward) > 400) break;
        [points addObject:@[@(round(-right * 10) / 10), @(round(forward * 10) / 10)]];
    }
    return points.count >= 2 ? points : nil;
}
- (NSDictionary *)directionInfo:(KNDirection *)direction {
    if (!direction) return @{};
    NSString *symbol = @"location.north", *action = @"진행", *highway = @"";
    NSInteger exitClock = 0;
    switch (direction.rgCode) {
        case KNRGCode_LeftTurn: symbol = @"arrow.turn.up.left"; action = @"좌회전"; break;
        case KNRGCode_UnprotectedLeftTurn: symbol = @"arrow.turn.up.left"; action = @"비보호 좌회전"; break;
        case KNRGCode_RightTurn: symbol = @"arrow.turn.up.right"; action = @"우회전"; break;
        case KNRGCode_UTurn: symbol = @"arrow.uturn.down"; action = @"유턴"; break;
        case KNRGCode_LeftDirection: case KNRGCode_LeftStraight: symbol = @"arrow.up.left"; action = @"왼쪽 방향"; break;
        case KNRGCode_RightDirection: case KNRGCode_RightStraight: symbol = @"arrow.up.right"; action = @"오른쪽 방향"; break;
        case KNRGCode_LeftOutHighway: case KNRGCode_LeftOutCityway: symbol = @"arrow.up.left"; action = @"왼쪽 출구"; highway = @"진출"; break;
        case KNRGCode_RightOutHighway: case KNRGCode_RightOutCityway: symbol = @"arrow.up.right"; action = @"오른쪽 출구"; highway = @"진출"; break;
        case KNRGCode_OutHighway: case KNRGCode_OutCityway: action = @"출구"; highway = @"진출"; break;
        case KNRGCode_LeftInHighway: case KNRGCode_LeftInCityway: symbol = @"arrow.up.left"; action = @"왼쪽 진입"; highway = @"진입"; break;
        case KNRGCode_RightInHighway: case KNRGCode_RightInCityway: symbol = @"arrow.up.right"; action = @"오른쪽 진입"; highway = @"진입"; break;
        case KNRGCode_InHighway: case KNRGCode_InCityway: action = @"진입"; highway = @"진입"; break;
        case KNRGCode_ChangeLeftHighway: symbol = @"arrow.up.left"; action = @"왼쪽 분기"; highway = @"분기점"; break;
        case KNRGCode_ChangeRightHighway: symbol = @"arrow.up.right"; action = @"오른쪽 분기"; highway = @"분기점"; break;
        case KNRGCode_JoinAfterBranch: action = @"분기 후 합류"; highway = @"분기·합류"; break;
        case KNRGCode_Goal: symbol = @"flag.checkered"; action = @"도착"; break;
        case KNRGCode_Via: symbol = @"mappin"; action = @"경유지"; break;
        case KNRGCode_Straight: symbol = @"arrow.up"; action = @"직진"; break;
        case KNRGCode_Tollgate: case KNRGCode_NonstopTollgate: action = @"요금소"; break;
        default:
            if ((direction.rgCode >= KNRGCode_RotaryDirection_1 && direction.rgCode <= KNRGCode_RotaryDirection_12) || (direction.rgCode >= KNRGCode_RoundaboutDirection_1 && direction.rgCode <= KNRGCode_RoundaboutDirection_12)) { symbol = @"arrow.triangle.2.circlepath"; action = @"회전교차로"; }
            break;
    }
    NSString *name = direction.nodeName ?: @"";
    if (direction.rgCode >= KNRGCode_RotaryDirection_1 && direction.rgCode <= KNRGCode_RotaryDirection_12) exitClock = direction.rgCode - KNRGCode_RotaryDirection_1 + 1;
    if (direction.rgCode >= KNRGCode_RoundaboutDirection_1 && direction.rgCode <= KNRGCode_RoundaboutDirection_12) exitClock = direction.rgCode - KNRGCode_RoundaboutDirection_1 + 1;
    NSString *toward = [direction.directionNames componentsJoinedByString:@" · "] ?: @"";
    NSString *text = [@[name, toward, action] componentsJoinedByString:@" "];
    return @{@"text": [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], @"symbol":symbol, @"highway":highway, @"exitClock":@(exitClock)};
}
- (void)publishTelemetry {
    if (YLGuidanceOwner != self || !self.telemetryHandler) return;
    // v29: route/turn/remaining data does not depend on a fresh GPS fix. "at" is the publish time;
    // "gps" tells the UI whether the position is live.
    BOOL gpsFresh = [self locationIsFresh];
    KNGPSData *gps = self.locationGuide.gpsMatched;
    NSMutableDictionary *s = [@{@"valid":@(self.guiding || gpsFresh), @"gps":@(gpsFresh), @"at":@(NSDate.date.timeIntervalSince1970),
        @"road":self.locationGuide.location.roadName ?: @""} mutableCopy];
    if (gpsFresh && gps.speedTrust && gps.speed >= 0) s[@"gpsSpeedKmh"] = @(gps.speed);
    KNLocation *location = self.locationGuide.location;
    // v30 route shape (throttled to 2 Hz) drives the 3D road; bend is derived from the same shape.
    if (location) {
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        if (!self.routePath || now - self.routePathAt >= 0.5) { self.routePath = [self routeShapeFrom:location]; self.routePathAt = now; }
        if (self.routePath) {
            s[@"routePath"] = self.routePath;
            NSArray *p40 = self.routePath.count > 3 ? self.routePath[3] : self.routePath.lastObject;
            double left = [p40[0] doubleValue], forward = [p40[1] doubleValue];
            if (forward > 2) { s[@"routeBend"] = @(fmax(-1, fmin(1, atan2(-left, forward) / 0.6))); s[@"motionValid"] = @YES; }
        }
        s[@"roadType"] = @(location.roadType);
    }
    if (!s[@"routeBend"] && gpsFresh && location && gps.angleTrust) {
        KNLocation *ahead = [location locationAfterDist:45];
        if (ahead) {
            double dx = ahead.pos.x-location.pos.x, dy = ahead.pos.y-location.pos.y;
            double heading = gps.angle*M_PI/180.0;
            double lateral = dx*cos(heading)-dy*sin(heading), forward = dx*sin(heading)+dy*cos(heading);
            if (isfinite(lateral) && isfinite(forward) && hypot(dx,dy)>2) {
                s[@"routeBend"] = @(fmax(-1,fmin(1,atan2(lateral,forward)/1.2)));
                s[@"motionValid"] = @YES;
            }
        }
    }
    KNDirection *cur = self.routeGuide.curDirection, *next = self.routeGuide.nextDirection;
    if (cur) {
        NSDictionary *info = [self directionInfo:cur];
        s[@"turn"] = info[@"text"]; s[@"symbol"] = info[@"symbol"]; s[@"highway"] = info[@"highway"]; s[@"exitClock"] = info[@"exitClock"];
        SInt32 metres = location ? [location distToLocation:cur.location] : -1; if (metres >= 0) s[@"turnMetres"] = @(metres);
        if (next) {
            NSDictionary *info2 = [self directionInfo:next]; s[@"nextTurn"] = info2[@"text"]; s[@"nextSymbol"] = info2[@"symbol"]; s[@"nextExitClock"] = info2[@"exitClock"];
            SInt32 nextMetres = location ? [location distToLocation:next.location] : -1; if (nextMetres >= 0) s[@"nextMetres"] = @(nextMetres);
        }
    }
    if (self.guidance.trip) {
        SInt32 dist = [self.guidance.trip remainDist], seconds = [self.guidance.trip remainTime];
        if (dist >= 0) s[@"remainMetres"] = @(dist);
        if (seconds >= 0) s[@"remainSeconds"] = @(seconds);
    }
    // v29 lane guidance: count and recommended lanes (left→right) at the next lane-info point.
    KNLane *lane = self.routeGuide.lane;
    if (lane.laneInfos.count >= 1 && lane.laneInfos.count <= 12) {
        SInt32 laneMetres = (location && lane.location) ? [location distToLocation:lane.location] : -1;
        if (laneMetres >= 0 && laneMetres <= 1500) {
            NSMutableArray *suggested = [NSMutableArray array];
            NSMutableArray *raw = [NSMutableArray array];
            __block NSInteger through = 0;
            [lane.laneInfos enumerateObjectsUsingBlock:^(KNLane_LaneInfo *info, NSUInteger i, BOOL *stop) {
                if (info.suggest > 0 || info.highlightType > 0) [suggested addObject:@(i)];
                // pocketType marks a lane that only exists at the junction (turn pocket), so the road
                // itself has fewer lanes than the guidance shows.
                if (info.pocketType == 0) through++;
                [raw addObject:[NSString stringWithFormat:@"%d/%d/%d/%d", info.turnType, info.suggest, info.highlightType, info.pocketType]];
            }];
            s[@"laneCount"] = @(lane.laneInfos.count);
            // If no through-lanes were specifically marked (e.g. all lanes turn at a T-junction or ramp),
            // through is the total lane count.
            if (through == 0) through = lane.laneInfos.count;
            s[@"laneThrough"] = @(through);
            // Through-lane count is the real lane count of this road, so it stays valid along the road.
            if (through > 0 && laneMetres <= 800) {
                self.lastLaneCount = through; self.lastLaneRoad = location.roadName ?: @"";
                self.lastLaneAt = [NSDate timeIntervalSinceReferenceDate];
            }
            s[@"laneSuggested"] = suggested;
            s[@"laneMetres"] = @(laneMetres);
            s[@"laneRaw"] = [raw componentsJoinedByString:@","];
        }
    }
    s[@"following"] = @(self.following);
    for (KNSafety *safety in self.safetyGuide.safetiesOnGuide) {
        if ([safety isKindOfClass:KNSafety_Camera.class] && ((KNSafety_Camera *)safety).speedLimit > 0) {
            s[@"speedLimit"] = @(((KNSafety_Camera *)safety).speedLimit);
            if (location) { SInt32 d = [location distToLocation:safety.location]; if (d >= 0) s[@"speedLimitMetres"] = @(d); }
            break;
        }
    }
    self.telemetryHandler(s);
    [self prepareUpcomingSpeech];
}
@end
