#import "YLKakaoController.h"
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
@property(nonatomic, strong) KNGuide_Route *routeGuide;
@property(nonatomic, strong) KNGuide_Location *locationGuide;
@property(nonatomic, strong) KNGuide_Safety *safetyGuide;
@property(nonatomic) FloatPoint mapAnchor;
@property(nonatomic) BOOL cameraReady;
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
@property(nonatomic, assign) NSTimeInterval lastSpokenTurnTime;
@property(nonatomic, assign) NSInteger lastSpokenSpeedLimit;
@property(nonatomic, assign) NSTimeInterval lastSpokenSpeedLimitTime;
@property(nonatomic, assign) NSInteger lastSpokenSafetyCode;
@property(nonatomic, assign) NSTimeInterval lastSpokenSafetyTime;
@property(nonatomic, assign) NSTimeInterval lastSpokenAnyTime;
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
- (void)configureVoiceDetail:(NSInteger)level { self.voiceDetail = MAX(0, MIN(2, level)); }
- (void)configureVoice:(BOOL)enabled safety:(BOOL)safety volume:(float)volume duck:(BOOL)duck {
    self.voiceEnabled = enabled; self.safetyVoiceEnabled = safety;
    self.voiceVolume = fmaxf(0, fminf(1, volume)); self.duckAudio = duck;
    // v30: the SDK never plays audio (all speech goes through the app voice), so the audio session is left to the app.
}
- (void)configureMapTheme:(NSString *)theme {
    BOOL changed = ![self.displayTheme isEqualToString:theme];
    self.displayTheme = theme;
    if (!self.map || (!changed && self.routeStyle)) return;
    self.map.isVisibleBuilding = YES;
    self.routeStyle = [KNMapRouteTheme driveNight];
    self.routeStyle.lineWidth = 10; self.routeStyle.strokeWidth = 2.5;
    self.routeColor = [UIColor colorWithRed:0.87 green:0.89 blue:0.91 alpha:1];
    self.routeStrokeColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    self.routeColors = [KNRouteColors routeColors];
    self.routeColors.normal = self.routeColor; self.routeColors.trafficJamModerate = self.routeColor;
    self.routeColors.trafficJamHeavy = self.routeColor; self.routeColors.trafficJamVeryHeavy = self.routeColor;
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
        self.map.userLocation.isVisible = YES;
        self.map.viewEventListener = self;
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
    self.freshnessTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf publishTelemetry]; }];
    // Raw map is presentation only. Start the engine exactly once, after delegates are ready.
    [self.guidance startWithTrip:trip priority:KNRoutePriority_Recommand avoidOptions:KNRouteAvoidOption_None];
    [self emit:@"ready" message:@"지도 준비 · 안내 시작 응답 대기"];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; self.map.paused = NO; [self emit:@"visible" message:@""]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; self.map.paused = YES; }
- (void)configureMapAnchorX:(double)x y:(double)y {
    if (!isfinite(x) || !isfinite(y)) return;
    self.mapAnchor = FloatPointMake(fmax(0.2, fmin(0.8, x)), fmax(0.3, fmin(0.85, y)));
    [self updateMap];
}
- (void)stopNavigation {
    self.generation++;
    self.guiding = NO;
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
- (void)guidance:(KNGuidance *)guidance didUpdateRoutes:(NSArray<KNRoute *> *)routes multiRouteInfo:(KNMultiRouteInfo *)info { YL_FORWARD(if (routes.count) [self.map setRoutes:routes]; else [self.map removeRoutesAll]); }
- (void)guidance:(KNGuidance *)guidance didUpdateIndoorRoute:(KNRoute *)route { if (route) YL_FORWARD([self.map setRoute:route]); }
- (void)guidance:(KNGuidance *)guidance didUpdateLocation:(KNGuide_Location *)location { YL_FORWARD(self.locationGuide = location; [self updateMap]; [self publishTelemetry]); }
- (void)guidance:(KNGuidance *)guidance didUpdateRouteGuide:(KNGuide_Route *)route { YL_FORWARD(self.routeGuide = route; [self publishTelemetry]); }
- (void)guidance:(KNGuidance *)guidance didUpdateSafetyGuide:(KNGuide_Safety *)safety { YL_FORWARD(self.safetyGuide = safety; [self publishTelemetry]); }
- (void)guidance:(KNGuidance *)guidance didUpdateAroundSafeties:(NSArray<__kindof KNSafety *> *)safeties { }
- (BOOL)guidance:(KNGuidance *)guidance shouldPlayVoiceGuide:(KNGuide_Voice *)voice replaceSndData:(NSData **)data {
    // Synchronous SDK callback: never dispatch_sync to main (SDK may be waiting on it).
    BOOL safety = voice.voiceCode == KNVoiceCode_Safety || voice.voiceCode == KNVoiceCode_Alert || voice.voiceCode == KNVoiceCode_SchoolZone || voice.voiceCode == KNVoiceCode_Alram;
    if (self.guidance != guidance || YLGuidanceOwner != self || (safety ? !self.safetyVoiceEnabled : !self.voiceEnabled)) return NO;
    if (![self shouldSpeak:voice safety:safety]) return NO;
    // SDK supplies timing and guide objects only. All speech uses the app's selected voice.
    KNVoiceCode code = voice.voiceCode;
    id object = voice.guideObj;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    self.lastSpokenAnyTime = now;
    if (code == KNVoiceCode_Turn) self.lastSpokenTurnTime = now;
    if (safety) {
        self.lastSpokenSafetyTime = now;
        if ([object isKindOfClass:KNSafety.class]) {
            KNSafety *s = (KNSafety *)object;
            self.lastSpokenSafetyCode = s.code;
            if ([s isKindOfClass:KNSafety_Camera.class] && ((KNSafety_Camera *)s).speedLimit > 0) {
                self.lastSpokenSpeedLimit = (NSInteger)((KNSafety_Camera *)s).speedLimit;
                self.lastSpokenSpeedLimitTime = now;
            }
        }
    }
    YL_FORWARD(NSString *text = [self spokenTextForCode:code object:object];
               if (text.length) [self emit:safety ? @"spokenSafety" : @"spokenGuide" message:text]);
    return NO;
}
/// Verbosity filter & collision prevention.
/// Suppresses rapid-fire collisions, redundant straight announcements before turns, and double speed limit alerts.
- (BOOL)shouldSpeak:(KNGuide_Voice *)voice safety:(BOOL)safety {
    NSInteger level = self.voiceDetail;
    if (level >= 2) return YES;
    KNVoiceCode code = voice.voiceCode;
    KNVoiceDist dist = voice.voiceDist;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    // Global throttle: do not emit another guidance if ANY guidance was emitted within 2.5s
    if (now - self.lastSpokenAnyTime < 2.5 && code != KNVoiceCode_Alert) return NO;

    switch (code) {
        case KNVoiceCode_LinkSound:
        case KNVoiceCode_Alram:
        case KNVoiceCode_GPSConnected:
        case KNVoiceCode_RouteUnchanged:
        case KNVoiceCode_CheckingRouteChange:
        case KNVoiceCode_StrateToNext:
        case KNVoiceCode_BusLaneGuide:
        case KNVoiceCode_Hipass:
            return NO;                                  // chatter in both brief and normal
        case KNVoiceCode_DetalDir:
        case KNVoiceCode_MultiRoute:
            return NO;                                  // chatter: detail direction often collides immediately with Turn direction
        case KNVoiceCode_Turn: {
            // Check if this is a straight maneuver
            if ([voice.guideObj isKindOfClass:KNDirection.class]) {
                KNDirection *dir = (KNDirection *)voice.guideObj;
                if (dir.rgCode == KNRGCode_Straight) {
                    KNDirection *next = self.routeGuide.nextDirection;
                    // If an upcoming real maneuver exists within 400m, suppress straight!
                    if (next && next.rgCode != KNRGCode_Straight) {
                        return NO; // suppress straight, let upcoming real turn guide
                    }
                    // For pure straight, don't repeat more often than once every 45s
                    if (now - self.lastSpokenTurnTime < 45.0) return NO;
                }
            }
            if (now - self.lastSpokenTurnTime < 3.5) return NO;
            // Brief: only the last two calls before the junction. Normal: from mid distance.
            if (dist == KNVoiceDist_None) return YES;
            return level >= 1 ? dist >= KNVoiceDist_Middle : dist >= KNVoiceDist_Near;
        }
        case KNVoiceCode_Safety: {
            if ([voice.guideObj isKindOfClass:KNSafety.class]) {
                KNSafety *point = (KNSafety *)voice.guideObj;
                if ([point isKindOfClass:KNSafety_Camera.class]) {
                    NSInteger limit = (NSInteger)((KNSafety_Camera *)point).speedLimit;
                    if (limit > 0) {
                        // If same speed limit was spoken within 25 seconds, suppress
                        if (limit == self.lastSpokenSpeedLimit && (now - self.lastSpokenSpeedLimitTime < 25.0)) return NO;
                        // If different speed limit was spoken within 8 seconds, suppress
                        if (now - self.lastSpokenSpeedLimitTime < 8.0) return NO;
                    }
                }
                if (point.code == self.lastSpokenSafetyCode && (now - self.lastSpokenSafetyTime < 15.0)) return NO;
            }
            if (now - self.lastSpokenSafetyTime < 5.0) return NO;
            if (dist == KNVoiceDist_None) return YES;
            return level >= 1 ? dist >= KNVoiceDist_Near : dist >= KNVoiceDist_AtPos;
        }
        case KNVoiceCode_SchoolZone:
            if (now - self.lastSpokenSafetyTime < 15.0) return NO;
            return YES;
        case KNVoiceCode_Alert:
            return YES;
        default:
            return YES;                                 // start/end, deviation, re-route
    }
}

/// Spoken distance buckets. Recording every metre value is impossible, and a navigation call of
/// "삼백 미터 앞" for 290 m is what drivers already hear from every Korean navigation app.
static NSString *YLSpokenDistance(SInt32 metres) {
    static const SInt32 steps[] = {50, 100, 200, 300, 400, 500, 700, 1000, 2000, 3000};
    static NSString *const names[] = {@"오십 미터 앞", @"백 미터 앞", @"이백 미터 앞", @"삼백 미터 앞", @"사백 미터 앞",
                                      @"오백 미터 앞", @"칠백 미터 앞", @"일 킬로미터 앞", @"이 킬로미터 앞", @"삼 킬로미터 앞"};
    const int count = (int)(sizeof(steps) / sizeof(steps[0]));
    int best = 0;
    double bestError = INFINITY;
    for (int i = 0; i < count; i++) {
        // Relative error, so 300 vs 400 is judged the same way as 2 km vs 3 km.
        double error = fabs(log((double)metres / (double)steps[i]));
        if (error < bestError) { bestError = error; best = i; }
    }
    return names[best];
}

- (NSString *)spokenTextForCode:(KNVoiceCode)code object:(id)object {
    NSString *prefix = @"";
    KNLocation *target = nil;
    if ([object isKindOfClass:KNDirection.class]) target = ((KNDirection *)object).location;
    if ([object isKindOfClass:KNSafety.class]) target = ((KNSafety *)object).location;
    if (target && [self locationIsFresh]) {
        SInt32 metres = [self.locationGuide.location distToLocation:target];
        // v42: the spoken distance is snapped to the set the recorded voice can actually say, the way a
        // car navigation system calls turns at fixed distances. The exact metres still drive the display.
        if (metres >= 30) prefix = [YLSpokenDistance(metres) stringByAppendingString:@", "];
        else if (metres >= 0) prefix = @"잠시 후, ";
    }
    if ([object isKindOfClass:KNDirection.class]) {
        KNDirection *dir = (KNDirection *)object;
        if (dir.rgCode == KNRGCode_Goal) return [prefix.length ? prefix : @"" stringByAppendingString:@"목적지에 도착했습니다."];
        if (dir.rgCode == KNRGCode_Via) return [prefix.length ? prefix : @"" stringByAppendingString:@"경유지에 도착했습니다."];
        return [prefix stringByAppendingString:[self directionInfo:object][@"spoken"]];
    }
    if ([object isKindOfClass:KNSafety.class]) {
        KNSafety *point = object;
        NSDictionary *labels = @{@0:@"사고 구간", @1:@"급커브 구간", @2:@"낙석 주의 구간", @3:@"안개 주의 구간", @4:@"추락 주의", @5:@"미끄러운 도로", @6:@"과속 방지턱", @10:@"철도 건널목", @11:@"어린이 보호 구역", @12:@"도로 폭 좁아짐", @13:@"급경사 내리막", @14:@"야생동물 출몰 지역", @15:@"졸음 쉼터", @16:@"사고 구간", @17:@"오르막 구간", @18:@"신호등 주의", @20:@"요금소", @21:@"사고 구간", @22:@"사고 구간", @23:@"사고 구간", @24:@"상습 결빙 구간", @26:@"사고 구간", @28:@"높이 제한", @29:@"중량 제한", @31:@"안개 주의 구간", @32:@"상습 결빙 구간", @40:@"지하차도 침수 주의", @81:@"이동식 단속 구간", @82:@"과속 단속", @83:@"교통 정보 수집 카메라", @84:@"버스 전용 차로 단속 구간", @85:@"과적 단속", @86:@"신호 과속 단속 구간", @87:@"주정차 단속 구간", @88:@"적재 불량 단속", @89:@"버스 전용 차로 단속 구간", @90:@"고정식 단속 구간", @91:@"과속 단속", @92:@"구간 단속 시작", @93:@"구간 단속 종료", @94:@"갓길 단속", @95:@"끼어들기 단속", @96:@"구간 단속", @97:@"지정차로 단속", @98:@"구간 단속 시작", @99:@"구간 단속 종료", @100:@"과속 단속", @101:@"안전띠 단속", @102:@"과속 단속", @103:@"신호 과속 단속 구간", @104:@"노후 경유차 운행 제한 단속", @105:@"구간 단속 시작", @106:@"후면 구간 단속 종료", @692:@"구간 단속 시작", @693:@"구간 단속 종료", @696:@"구간 단속", @705:@"구간 단속 시작", @706:@"후면 구간 단속 종료"};
        // v42: a few calls are a whole sentence rather than "<label>입니다", so they can be said by the
        // recorded voice instead of dropping the whole announcement back to the synthesiser.
        NSDictionary *sentences = @{@93:@"구간 단속이 끝났습니다.", @99:@"구간 단속이 끝났습니다.", @106:@"구간 단속이 끝났습니다.",
                                    @693:@"구간 단속이 끝났습니다.", @706:@"구간 단속이 끝났습니다.",
                                    @12:@"도로 폭이 좁아집니다.", @15:@"졸음쉼터로 진입합니다."};
        // v43: the speed limit is its own sentence. Inside the label it produced one long comma clause
        // that the recorded voice could never say, so the whole warning fell back to the synthesiser.
        NSString *limitSentence = @"";
        if ([point isKindOfClass:KNSafety_Camera.class] && ((KNSafety_Camera *)point).speedLimit > 0)
            limitSentence = [NSString stringWithFormat:@" 제한 속도는 시속 %d킬로미터입니다.", (int)((KNSafety_Camera *)point).speedLimit];
        NSString *whole = sentences[@(point.code)];
        if (whole) return [[prefix stringByAppendingString:whole] stringByAppendingString:limitSentence];
        NSString *label = labels[@(point.code)] ?: @"안전 운행 주의 지점";
        if ([point isKindOfClass:KNSafety_Caution.class]) {
            SInt32 limit = ((KNSafety_Caution *)point).limit;
            if (limit > 0 && point.code == KNSafetyCode_HeightLimitPos) label = [label stringByAppendingFormat:@", %.1f미터", limit/100.0];
            if (limit > 0 && point.code == KNSafetyCode_WeightLimitPos) label = [label stringByAppendingFormat:@", %.1f톤", limit/10.0];
        }
        return [[[prefix stringByAppendingString:label] stringByAppendingString:@"입니다."] stringByAppendingString:limitSentence];
    }
    switch (code) {
        case KNVoiceCode_StartGuide: return @"안내를 시작합니다.";
        case KNVoiceCode_EndGuide: return @"목적지에 도착했습니다.";
        case KNVoiceCode_DetalDir:
        case KNVoiceCode_MultiRoute:
            return self.routeGuide.curDirection ? [self directionInfo:self.routeGuide.curDirection][@"spoken"] : @"분기 경로를 확인해 주세요.";
        case KNVoiceCode_SchoolZone: return @"어린이 보호 구역입니다. 안전 운전하세요.";
        case KNVoiceCode_Alert: return @"속도를 줄여 주세요.";
        case KNVoiceCode_Hipass: return @"하이패스 차로를 이용하세요.";
        case KNVoiceCode_StrateToNext: return @"계속 직진하세요.";
        case KNVoiceCode_CheckingRouteChange: return @"경로를 재탐색합니다.";
        case KNVoiceCode_RouteChanged: return @"새로운 경로로 안내합니다.";
        case KNVoiceCode_RouteUnchanged: return @"현재 경로를 유지합니다.";
        case KNVoiceCode_OutOfRoute: return @"경로를 이탈했습니다. 새 경로를 찾고 있습니다.";
        case KNVoiceCode_GPSConnected: return @"위치 신호가 연결되었습니다.";
        case KNVoiceCode_BusLaneGuide: return @"버스 전용 차로 단속 구간입니다.";
        case KNVoiceCode_Alram: return @"안전 운행에 유의해 주세요.";
        case KNVoiceCode_LinkSound: return @"도로 안내를 확인해 주세요.";
        case KNVoiceCode_Safety: return @"안전 운행 주의 지점을 확인해 주세요.";
        case KNVoiceCode_Turn: return self.routeGuide.curDirection ? [self directionInfo:self.routeGuide.curDirection][@"spoken"] : @"진행 경로를 확인해 주세요.";
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
    if (self.guiding && self.locationGuide.location) return YES;
    KNGPSData *gps = self.locationGuide.gpsMatched;
    NSTimeInterval age = gps.timestamp ? -gps.timestamp.timeIntervalSinceNow : INFINITY;
    // Keep the last matched position for 90 s instead of hiding the car and blanking guidance.
    return gps && gps.valid && age >= -3 && age <= 90 && isfinite(gps.pos.x) && isfinite(gps.pos.y);
}
- (void)updateMap {
    // Route properties may not exist until the SDK asynchronously installs a route.
    if (self.routeStyle && self.map.routeProperties && self.map.routeProperties.theme != self.routeStyle) {
        self.map.routeProperties.theme = self.routeStyle;
    }
    KNLocation *loc = self.locationGuide.location;
    KNGPSData *gps = self.locationGuide.gpsMatched;
    BOOL fresh = [self locationIsFresh];
    if (!fresh && !loc) { self.map.userLocation.isVisible = NO; return; }
    FloatPoint pos;
    float angle = 0;
    if (loc && isfinite(loc.pos.x) && isfinite(loc.pos.y)) {
        pos = FloatPointMake(loc.pos.x, loc.pos.y);
        angle = (gps && gps.angleTrust) ? gps.angle : 0;
    } else if (gps && isfinite(gps.pos.x) && isfinite(gps.pos.y)) {
        pos = FloatPointMake(gps.pos.x, gps.pos.y);
        angle = gps.angleTrust ? gps.angle : 0;
    } else {
        self.map.userLocation.isVisible = NO;
        return;
    }
    self.map.userLocation.coordinate = pos;
    self.map.userLocation.isVisible = YES;
    self.map.userLocation.angle = angle;
    if (!self.cameraReady && self.map.bounds.size.width > 100) {
        KNMapCoordinateRegion *region = [KNMapCoordinateRegion regionWithMin:FloatPointMake(pos.x-250, pos.y-250) max:FloatPointMake(pos.x+250, pos.y+250)];
        [self.map moveCamera:[KNMapCameraUpdate fitToRegion:region] withUserLocation:NO];
        self.cameraReady = YES;
    }
    if (loc) [self.map cullPassedRouteWithLocation:loc isAnimate:NO];
    if (!self.following || self.userZooming) return; // manual map browsing: keep the user's view
    KNMapCameraUpdate *update = [[[[KNMapCameraUpdate targetTo:pos] anchorTo:self.mapAnchor] bearingTo:angle] tiltTo:0];
    // Fit a real coordinate region once; retain subsequent pinch zoom rather than web-map zoom constants.
    [self.map moveCamera:update withUserLocation:YES];
}
- (void)updateStandbyLocationWithLatitude:(double)latitude longitude:(double)longitude bearing:(double)bearing speed:(double)speed {
    if (self.guiding || !self.map) return;
    if (!isfinite(latitude) || !isfinite(longitude) || fabs(latitude) > 90 || fabs(longitude) > 180) return;
    KNSDK *sdk = [KNSDK sharedInstance];
    if (!sdk) return;
    IntPoint pt = [sdk convertWGS84ToKATECWithLongitude:longitude latitude:latitude];
    FloatPoint pos = FloatPointMake(pt.x, pt.y);
    float angle = isfinite(bearing) ? (float)bearing : 0;
    self.map.userLocation.coordinate = pos;
    self.map.userLocation.isVisible = YES;
    self.map.userLocation.angle = angle;
    if (!self.cameraReady && self.map.bounds.size.width > 100) {
        KNMapCoordinateRegion *region = [KNMapCoordinateRegion regionWithMin:FloatPointMake(pos.x-300, pos.y-300) max:FloatPointMake(pos.x+300, pos.y+300)];
        [self.map moveCamera:[KNMapCameraUpdate fitToRegion:region] withUserLocation:NO];
        self.cameraReady = YES;
    }
    if (!self.following || self.userZooming) return;
    KNMapCameraUpdate *update = [[[[KNMapCameraUpdate targetTo:pos] anchorTo:self.mapAnchor] bearingTo:angle] tiltTo:0];
    [self.map moveCamera:update withUserLocation:YES];
}
- (void)recenter {
    [self.followTimer invalidate]; self.followTimer = nil;
    self.following = YES; self.userZooming = NO;
    [self emit:@"follow" message:@"1"];
    if (self.guiding) {
        [self updateMap];
    } else if (self.map && self.map.userLocation.isVisible) {
        FloatPoint pos = self.map.userLocation.coordinate;
        float angle = self.map.userLocation.angle;
        KNMapCameraUpdate *update = [[[[KNMapCameraUpdate targetTo:pos] anchorTo:self.mapAnchor] bearingTo:angle] tiltTo:0];
        [self.map moveCamera:update withUserLocation:YES];
    }
}
- (void)pauseFollowing {
    [self.followTimer invalidate]; self.followTimer = nil;
    if (self.following) { self.following = NO; [self emit:@"follow" message:@"0"]; }
}
- (void)scheduleFollowResume {
    [self.followTimer invalidate];
    __weak typeof(self) weakSelf = self;
    // Kakao-style: after browsing, snap back to the car when the map is left alone.
    self.followTimer = [NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer *timer) { [weakSelf recenter]; }];
}
#pragma mark KNMapViewEventListener
- (void)mapView:(KNMapView *)aMapView singleTappedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView doubleTappedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView longPressedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView panningStartedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { [self pauseFollowing]; }
- (void)mapView:(KNMapView *)aMapView panningChangingWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { }
- (void)mapView:(KNMapView *)aMapView panningEndedWithScreenPoint:(CGPoint)aScreenPoint coordinate:(FloatPoint)aCoordinate { [self scheduleFollowResume]; }
- (void)mapView:(KNMapView *)aMapView zoomingStartedWithScreenPoint:(CGPoint)aScreenPoint zoom:(float)aZoom { self.userZooming = YES; }
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
        case KNRGCode_LeftTurn: case KNRGCode_UnprotectedLeftTurn: symbol = @"arrow.turn.up.left"; action = @"좌회전"; break;
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
    NSString *spokenAction;
    if (direction.rgCode == KNRGCode_Goal) {
        spokenAction = @"목적지에 도착했습니다.";
    } else if (direction.rgCode == KNRGCode_Via) {
        spokenAction = @"경유지에 도착했습니다.";
    } else if (exitClock >= 1 && exitClock <= 4) {
        static NSString *const kRoundaboutExits[] = {
            @"",
            @"회전 교차로에서 첫 번째 출구로 나가세요.",
            @"회전 교차로에서 두 번째 출구로 나가세요.",
            @"회전 교차로에서 세 번째 출구로 나가세요.",
            @"회전 교차로에서 네 번째 출구로 나가세요."
        };
        spokenAction = kRoundaboutExits[exitClock];
    } else if (exitClock > 0) {
        spokenAction = [NSString stringWithFormat:@"회전교차로 %ld시 방향 출구입니다.", (long)exitClock];
    } else {
        spokenAction = [action stringByAppendingString:@"입니다."];
    }
    NSString *toward = [direction.directionNames componentsJoinedByString:@" · "] ?: @"";
    NSString *text = [@[name, toward, action] componentsJoinedByString:@" "];
    return @{@"text": [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], @"symbol":symbol, @"highway":highway, @"exitClock":@(exitClock), @"spoken":spokenAction};
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
    if (!s[@"routeBend"] && gpsFresh && location && gps.angleTrust && isfinite(gps.angle)) {
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
    // Lane count for the drawn road: last guidance count on this road, else a road-type default.
    NSString *roadName = location.roadName ?: @"";
    NSTimeInterval laneAge = [NSDate timeIntervalSinceReferenceDate] - self.lastLaneAt;
    if (self.lastLaneCount > 0 && [self.lastLaneRoad isEqualToString:roadName] && laneAge < 1800) {
        s[@"roadLanes"] = @(self.lastLaneCount);
        s[@"roadLaneSource"] = @"guide";
    } else if (location) {
        // No lane guidance for this road: smart estimate from road class, name, and posted limit.
        SInt32 limit = 0;
        for (KNSafety *safety in self.safetyGuide.safetiesOnGuide) {
            if ([safety isKindOfClass:KNSafety_Camera.class] && ((KNSafety_Camera *)safety).speedLimit > 0) {
                limit = ((KNSafety_Camera *)safety).speedLimit;
                break;
            }
        }
        NSInteger lanes = 2;
        if (location.roadType == KNRoadType_Highway) {
            // Check if on a highway ramp/connector (1 or 2 lanes) vs highway mainline (3 or 4 lanes)
            if ([s[@"highway"] isEqualToString:@"진입"] || [s[@"highway"] isEqualToString:@"진출"] || [roadName containsString:@"램프"] || [roadName containsString:@"IC"] || [roadName containsString:@"JC"]) {
                lanes = 1;
            } else {
                lanes = limit >= 100 ? 4 : 3;
            }
        } else if (location.roadType == KNRoadType_NarrowRoad || [roadName containsString:@"골목"] || [roadName containsString:@"길"]) {
            lanes = 1;
        } else {
            // Urban / General roads:
            // Major avenues in Korea ("~대로" like 강남대로, 테헤란로) typically have 4 lanes per direction
            // Regular arterial roads ("~로") typically have 3 lanes per direction
            // Secondary roads ("~길") typically have 1 or 2 lanes
            if ([roadName hasSuffix:@"대로"] || limit >= 70) {
                lanes = 4;
            } else if ([roadName hasSuffix:@"로"] || limit >= 60) {
                lanes = 3;
            } else if (limit <= 30) {
                lanes = 1;
            } else {
                lanes = 2;
            }
        }
        s[@"roadLanes"] = @(lanes);
        s[@"roadLaneSource"] = @"estimate";
    }
    // Korean lane painting: the left edge is the centre line (yellow) unless the road is one lane.
    if (location) s[@"roadClass"] = location.roadType == KNRoadType_Highway ? @"highway" : location.roadType == KNRoadType_NarrowRoad ? @"narrow" : @"urban";
    s[@"following"] = @(self.following);
    for (KNSafety *safety in self.safetyGuide.safetiesOnGuide) {
        if ([safety isKindOfClass:KNSafety_Camera.class] && ((KNSafety_Camera *)safety).speedLimit > 0) {
            s[@"speedLimit"] = @(((KNSafety_Camera *)safety).speedLimit);
            if (location) { SInt32 d = [location distToLocation:safety.location]; if (d >= 0) s[@"speedLimitMetres"] = @(d); }
            break;
        }
    }
    self.telemetryHandler(s);
}
@end
