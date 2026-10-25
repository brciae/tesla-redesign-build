#import <Foundation/Foundation.h>
#import <math.h>

// Estimate only until the cached clip is opened; playback uses its actual duration.
static inline double YLNavigationSpeechSeconds(NSString *text) {
    return fmax(1, text.length / 5.0);
}
static inline double YLNavigationLeadDistance(double speed, double speechSeconds) {
    return fmax(25, fmax(0, speed) * (speechSeconds + 1.5 + fmax(0, speed) / 20.0));
}
static inline BOOL YLNavigationCanFinish(double distance, double speed, double age, double duration) {
    if (!isfinite(distance) || distance <= 0 || !isfinite(speed) || !isfinite(duration) || !isfinite(age) || age < 0 || age > 3) return NO;
    return distance - fmax(0, speed) * (age + fmax(0, duration) + 0.8) > 0;
}
// Unknown/stale position is not proof that an already playing cue has passed.
static inline BOOL YLNavigationTargetPassed(double issuedDistance, double issuedRemaining, double remaining, double gpsAge, double callbackAge) {
    return isfinite(issuedDistance) && issuedDistance > 0 && isfinite(issuedRemaining) && issuedRemaining > 0 &&
        isfinite(remaining) && remaining >= 0 && isfinite(gpsAge) && gpsAge >= -3 && gpsAge <= 2.5 &&
        isfinite(callbackAge) && callbackAge >= 0 && callbackAge <= 3 &&
        issuedRemaining - remaining > issuedDistance + 15;
}

static inline BOOL YLNavigationPositionUsable(BOOL valid, double gpsAge, double callbackAge, BOOL routePosition) {
    if (!valid) return NO;
    if (isfinite(gpsAge) && gpsAge >= -3 && gpsAge <= 15) return YES;
    // The SDK's current, valid matched-route result may advance while raw GPS is unavailable.
    return routePosition && isfinite(callbackAge) && callbackAge >= 0 && callbackAge <= 3;
}

// Route distances, not straight-line proximity: nearby parallel roads must not form a cluster.
static inline NSArray<NSNumber *> *YLHumpClusterDistances(NSInteger first, NSArray<NSNumber *> *distances) {
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithObject:@(first)];
    NSInteger last = first;
    for (NSNumber *value in [distances sortedArrayUsingSelector:@selector(compare:)]) {
        NSInteger distance = value.integerValue;
        if (distance <= last) continue;
        if (distance > first + 1200 || distance - last > 250) break;
        [result addObject:value]; last = distance;
    }
    return result;
}

// Voice uses approximate distance bands; the map retains the SDK's exact distance.
// Negative means no fresh distance. Never turn it into an imminent maneuver.
static inline NSString *YLNavigationDistancePrefix(NSInteger metres) {
    if (metres < 0) return @"";
    // Conventional wording: "잠시 후" when close, otherwise whole 100 m steps (never "35미터").
    if (metres < 80) return @"잠시 후, ";
    if (metres < 950) {
        NSInteger band = MAX(100, ((metres + 50) / 100) * 100);
        return [NSString stringWithFormat:@"%ld미터 앞, ", (long)band];
    }
    return [NSString stringWithFormat:@"%ld킬로미터 앞, ", (long)((metres + 500) / 1000)];
}

static inline NSString *YLNavigationCompactNumber(double value) {
    // Keep meaningful precision for clearance/weight restrictions, not trailing .0.
    NSString *text = [NSString stringWithFormat:@"%.2f", value];
    while ([text hasSuffix:@"0"]) text = [text substringToIndex:text.length - 1];
    if ([text hasSuffix:@"."]) text = [text substringToIndex:text.length - 1];
    return text;
}

// Speech is independent of dashboard labels. Numeric IDs are the pinned
// KNSDK 1.12.19 KNRGCode contract; the build audit checks every named SDK value.
static inline NSString *YLNavigationAction(NSInteger code) {
    switch (code) {
        case 0: return @"직진하세요.";
        case 1: return @"좌회전하세요.";
        case 2: return @"우회전하세요.";
        case 3: return @"유턴하세요.";
        case 5: return @"왼쪽 방향으로 가세요.";
        case 6: return @"오른쪽 방향으로 가세요.";
        case 7: case 42: return @"출구로 나가세요.";
        case 8: case 43: return @"왼쪽 출구로 나가세요.";
        case 9: case 44: return @"오른쪽 출구로 나가세요.";
        case 10: return @"고속도로로 진입하세요.";
        case 11: return @"왼쪽 고속도로 입구로 진입하세요.";
        case 12: return @"오른쪽 고속도로 입구로 진입하세요.";
        case 14: return @"고가도로로 진입하세요.";
        case 15: return @"지하차도로 진입하세요.";
        case 16: return @"고가도로 옆길로 가세요.";
        case 17: return @"지하차도 옆길로 가세요.";
        case 45: return @"도시고속도로로 진입하세요.";
        case 46: return @"왼쪽 도시고속도로 입구로 진입하세요.";
        case 47: return @"오른쪽 도시고속도로 입구로 진입하세요.";
        case 48: return @"분기점에서 왼쪽으로 가세요.";
        case 49: return @"분기점에서 오른쪽으로 가세요.";
        case 61: return @"페리 승선 지점입니다.";
        case 62: return @"페리 하선 지점입니다.";
        case 63: return @"비보호 좌회전하세요. 반대편 차량과 신호에 주의하세요.";
        case 64: return @"터널로 진입하세요.";
        case 65: return @"터널 옆길로 가세요.";
        case 66: return @"왼쪽 터널로 진입하세요.";
        case 67: return @"터널 왼쪽 옆길로 가세요.";
        case 68: return @"오른쪽 터널로 진입하세요.";
        case 69: return @"터널 오른쪽 옆길로 가세요.";
        case 82: return @"왼쪽 도로로 직진하세요.";
        case 83: return @"오른쪽 도로로 직진하세요.";
        case 84: return @"요금소입니다.";
        case 85: return @"무정차 요금소입니다.";
        case 86: return @"분기 후 합류하는 도로입니다.";
        case 87: return @"왼쪽 고가도로로 진입하세요.";
        case 88: return @"고가도로 왼쪽 옆길로 가세요.";
        case 89: return @"오른쪽 고가도로로 진입하세요.";
        case 90: return @"고가도로 오른쪽 옆길로 가세요.";
        case 91: return @"왼쪽 지하차도로 진입하세요.";
        case 92: return @"지하차도 왼쪽 옆길로 가세요.";
        case 93: return @"오른쪽 지하차도로 진입하세요.";
        case 94: return @"지하차도 오른쪽 옆길로 가세요.";
        case 101: return @"목적지입니다.";
        case 1000: return @"경유지입니다.";
        case 900: return @"주차장으로 진입하세요.";
        case 901: return @"주차장 출구로 나가세요.";
        case 902: return @"위층으로 이동하세요.";
        case 903: return @"아래층으로 이동하세요.";
        case 904: return @"연결된 주차장으로 나가세요.";
        case 905: return @"연결된 주차장에서 진입하는 지점입니다.";
        case 906: return @"회차 지점입니다.";
        case 100: return @""; // StartGuide owns the start announcement.
        default:
            if (code >= 18 && code <= 29)
                return [NSString stringWithFormat:@"%ld시 방향으로 가세요.", (long)(code - 17)];
            if ((code >= 30 && code <= 41) || (code >= 70 && code <= 81)) {
                NSInteger clock = code >= 70 ? code - 69 : code - 29;
                // Clock direction is not the ordinal number of an exit.
                return [NSString stringWithFormat:@"회전교차로에서 %ld시 방향 출구로 나가세요.", (long)clock];
            }
            return @""; // Never invent a maneuver for an unknown SDK code.
    }
}

// v1.35: the SDK sometimes puts maneuver words ("분기후 합류", "분기점", "진출") in the direction
// names. Those are not places, so "분기후 합류 방면, …" must never be spoken.
static inline BOOL YLNavigationIsPlaceName(NSString *name) {
    NSString *flat = [[name stringByReplacingOccurrencesOfString:@" " withString:@""] stringByReplacingOccurrencesOfString:@"·" withString:@""];
    if (flat.length < 2) return NO;
    NSArray<NSString *> *generic = @[@"분기", @"합류", @"분기점", @"진입", @"진출", @"출구", @"입구", @"방향", @"방면", @"직진", @"좌회전", @"우회전",
                                     @"유턴", @"후", @"고속도로", @"도시고속도로", @"고가도로", @"지하차도", @"터널", @"요금소", @"옆길", @"왼쪽", @"오른쪽", @"회전교차로", @"로터리", @"교차로", @"사거리", @"삼거리"];
    NSString *rest = flat;
    for (NSString *w in [generic sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return a.length > b.length ? NSOrderedAscending : NSOrderedDescending; }])
        rest = [rest stringByReplacingOccurrencesOfString:w withString:@""];
    return rest.length >= 2; // something besides maneuver vocabulary remains → a real road/place name
}

static inline NSString *YLNavigationSignName(NSString *raw) {
    if (![raw isKindOfClass:NSString.class]) return @"";
    NSString *name = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Sign metadata may already contain this suffix; say it exactly once.
    for (NSString *suffix in @[@"방면", @"방향"]) {
        if ([name hasSuffix:suffix]) name = [[name substringToIndex:name.length-suffix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return YLNavigationIsPlaceName(name) ? name : @"";
}

static inline NSString *YLNavigationCameraSpeech(NSString *prefix, NSString *kind, NSInteger limit) {
    NSString *type = [[kind stringByReplacingOccurrencesOfString:@" 카메라" withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *speed = limit > 0 ? [NSString stringWithFormat:@" 제한 속도는 시속 %ld킬로미터입니다.", (long)limit] : @"";
    return [NSString stringWithFormat:@"%@%@ 지점입니다.%@", prefix, type, speed];
}

static inline NSString *YLNavigationSpeech(NSInteger code, NSString *node, NSArray<NSString *> *towards, NSInteger metres) {
    if (metres == 0 && code == 101) return @"목적지에 도착했습니다.";
    if (metres == 0 && code == 1000) return @"경유지에 도착했습니다.";
    NSString *action = YLNavigationAction(code);
    if (!action.length) return @"";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *raw in towards) {
        if (![raw isKindOfClass:NSString.class]) continue;
        NSString *name = YLNavigationSignName(raw);
        if (name.length && ![names containsObject:name]) [names addObject:name];
        if (names.count == 2) break; // One road sign pair is enough; do not read a destination list.
    }
    NSString *context = @"";
    // Destinations/facilities already identify the point. Road signs help at forks.
    if (code != 101 && code != 1000 && code != 84 && code != 85 && code != 86) {
        if (names.count) context = [NSString stringWithFormat:@"%@ 방면, ", [names componentsJoinedByString:@", "]];
        else if (node.length && YLNavigationIsPlaceName(node)) context = [NSString stringWithFormat:@"%@, ", node];
    }
    NSString *prefix = YLNavigationDistancePrefix(metres);
    return [NSString stringWithFormat:@"%@%@%@", prefix, context, action];
}
static inline NSString *YLNavigationSpeechForDetail(NSInteger code, NSString *node, NSArray<NSString *> *towards, NSInteger metres, NSInteger detail) {
    if (detail == 0) return YLNavigationSpeech(code, @"", @[], metres);
    NSArray *signs = detail == 1 && towards.count > 1 ? [towards subarrayWithRange:NSMakeRange(0, 1)] : towards;
    return YLNavigationSpeech(code, node, signs, metres);
}
