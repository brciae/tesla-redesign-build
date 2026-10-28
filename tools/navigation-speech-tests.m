#import <Foundation/Foundation.h>
#import "../TeslaLocal.swiftpm/Sources/KakaoNavigationBridge/include/YLNavigationSpeech.h"

static void check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(void) { @autoreleasepool {
    check([YLNavigationSpeech(2, @"교차로", @[@"서울 방면", @"서울", @"수원 방향", @"용인"], 300) isEqual:@"300미터 앞, 서울, 수원 방면, 우회전하세요."], @"Normalize direction suffixes, dedupe and keep at most two sign names");
    check([YLNavigationSpeech(78, @"회전교차로", @[], 100) isEqual:@"100미터 앞, 회전교차로에서 9시 방향 출구로 나가세요."], @"Do not repeat a generic roundabout node before the maneuver");
    check([YLNavigationCameraSpeech(@"300미터 앞, ", @"신호 과속 단속 카메라", 60) isEqual:@"300미터 앞, 신호 과속 단속 지점입니다. 제한 속도는 시속 60킬로미터입니다."], @"Camera wording keeps enforcement type and limit without a filler warning");
    check([YLNavigationCameraSpeech(@"잠시 후, ", @"이동식 과속 단속 카메라", 0) isEqual:@"잠시 후, 이동식 과속 단속 지점입니다."], @"Unknown speed limit must not be invented");
    check(YLNavigationPositionUsable(YES, 1, 1, YES), @"Fresh matched GPS usable");
    check(YLNavigationPositionUsable(YES, 90, 1, YES), @"Current valid SDK route estimate survives raw GPS loss");
    check(!YLNavigationPositionUsable(YES, 90, 9, YES), @"Stale callback is not dead reckoning");
    check(!YLNavigationPositionUsable(NO, 1, 1, YES), @"Invalid matched result rejected");
    check(!YLNavigationPositionUsable(YES, 90, 1, NO), @"Old standalone GPS not revived by callback");
    check([YLHumpClusterDistances(80, @[@500, @210, @350]) isEqual:@[@80, @210, @350, @500]], @"Consecutive humps are sorted and grouped along route");
    check([YLHumpClusterDistances(80, @[@400, @500]) isEqual:@[@80]], @"Separate hump sections remain separate");
    check([YLHumpClusterDistances(80, @[@-1, @50, @80, @200, @200]) isEqual:@[@80, @200]], @"Passed and duplicate points excluded");
    check(YLHumpClusterDistances(80, @[@300, @550, @800, @1050, @1300]).count == 5, @"Long cluster has bounded lookahead");
    check([YLNavigationSpeech(14, nil, nil, 200) isEqual:@"200미터 앞, 고가도로로 진입하세요."], @"Overpass must not say generic proceed");
    check([YLNavigationSpeech(17, nil, nil, 200) containsString:@"지하차도 옆길"], @"Underpass side road differs from entering underpass");
    check([YLNavigationSpeech(2, @"교차로", @[@"서울", @"서울", @"  "], 200) isEqual:@"200미터 앞, 서울 방면, 우회전하세요."], @"Use direction signs once without reading screen labels");
    check([YLNavigationAction(63) containsString:@"비보호"], @"Unprotected left turn must retain restriction");
    for (NSInteger clock=1; clock<=12; clock++) {
        NSString *expected=[NSString stringWithFormat:@"%ld시 방향 출구", (long)clock];
        check([YLNavigationAction(clock+29) containsString:expected], @"Rotary code means clock, not ordinal exit");
        check([YLNavigationAction(clock+69) containsString:expected], @"Roundabout code means clock, not ordinal exit");
    }
    check([YLNavigationSpeech(101,nil,nil,200) isEqual:@"200미터 앞, 목적지입니다."], @"Approaching destination is not arrival");
    check([YLNavigationSpeech(101,nil,nil,0) isEqual:@"목적지에 도착했습니다."], @"Destination arrival must not say ahead");
    check([YLNavigationSpeech(1000,nil,nil,0) isEqual:@"경유지에 도착했습니다."], @"Waypoint arrival is distinct from approach");
    check([YLNavigationDistancePrefix(112) isEqual:@"100미터 앞, "], @"Do not read raw meter precision");
    check(YLNavigationLeadDistance(30, 5) > YLNavigationLeadDistance(10, 5), @"Faster driving requires an earlier cue");
    check(YLNavigationLeadDistance(20, 8) > YLNavigationLeadDistance(20, 3), @"Longer audio requires more route distance");
    check(YLNavigationCanFinish(100, 10, 0, 5), @"Cached clip fits before point at low speed");
    check(!YLNavigationCanFinish(100, 30, 0, 5), @"Same cached clip is late at higher speed");
    check(!YLNavigationCanFinish(50, 20, 2, 1), @"Distance advances while callback ages");
    check(!YLNavigationCanFinish(0, 10, 0, 0), @"Passed point never plays");
    check(!YLNavigationCanFinish(-10, 10, 0, 0), @"Negative route distance never plays");
    check(!YLNavigationCanFinish(500, 10, 4, 1), @"Stale location cannot validate queued speech");
    check(!YLNavigationTargetPassed(100, 1000, 700, 4, 0), @"Stale GPS is unknown, not passed");
    check(!YLNavigationTargetPassed(100, 1000, 700, 0, 4), @"Old callback cannot stop a playing sentence");
    check(!YLNavigationTargetPassed(100, 1000, 890, 0, 0), @"Point crossing tolerance prevents jitter cancellation");
    check(YLNavigationTargetPassed(100, 1000, 880, 0, 0), @"Fresh matched-route progress proves passage");
    check(!YLNavigationTargetPassed(100, 0, 0, 0, 0), @"Missing route anchor cannot prove passage");
    check([YLNavigationAction(86) isEqualToString:@"분기 후 합류하는 도로입니다."], @"Exact user-approved branch/rejoin description");
    check([YLNavigationSafetyKind(90) isEqual:@"camera"] && [YLNavigationSafetyKind(98) isEqual:@"camera"] && [YLNavigationSafetyKind(692) isEqual:@"camera"], @"Signal and section cameras share the approved camera priority");
    check([YLNavigationSafetyKind(26) isEqual:@"safety"], @"Actual accident caution remains enabled in brief mode");
    check([YLNavigationSafetyKind(83) isEqual:@"information"] && [YLNavigationSafetyKind(6) isEqual:@"hump"], @"Traffic collection camera is not a speed warning; humps stay distinct");
    NSString *brief = YLNavigationSpeechForDetail(2, @"삼거리", @[@"서울",@"수원"], 200, 0);
    NSString *normal = YLNavigationSpeechForDetail(2, @"삼거리", @[@"서울",@"수원"], 200, 1);
    NSString *detail = YLNavigationSpeechForDetail(2, @"삼거리", @[@"서울",@"수원"], 200, 2);
    check(![brief containsString:@"서울"] && ![brief containsString:@"수원"], @"Brief omits sign list");
    check([normal containsString:@"서울"] && ![normal containsString:@"수원"], @"Normal reads one sign");
    check([YLNavigationSpeechForDetail(2, @"삼거리", @[@"분기점", @" ", @"서울 방면", @"수원"], 300, 1) isEqual:@"300미터 앞, 서울 방면, 우회전하세요."], @"Filter invalid labels before selecting one sign");
    check([YLNavigationSpeechForDetail(2, @"삼거리", @[@"서울", @"수원"], 40, 2) isEqual:@"잠시 후, 우회전하세요."], @"Imminent simple turn prioritizes the action");
    check([YLNavigationSpeechForDetail(63, nil, @[@"서울"], 40, 2) containsString:@"반대편 차량과 신호"], @"Short imminent cue retains unprotected-turn warning");
    check([YLNavigationSpeechForDetail(9, nil, @[@"서울", @"수원"], 40, 2) isEqual:@"잠시 후, 서울 방면, 오른쪽 출구로 나가세요."], @"Imminent exit retains one identifying sign and side");
    check([YLNavigationSpeechForDetail(2, nil, @[@"서울 방면 방향", @"서울"], 300, 2) isEqual:@"300미터 앞, 서울 방면, 우회전하세요."], @"Repeated suffixes collapse before deduplication");
    check([detail containsString:@"서울"] && [detail containsString:@"수원"], @"Detailed reads at most two signs");
    check(![YLNavigationSpeechForDetail(86, @"분기후 합류", @[@"서울"], 200, 2) containsString:@"서울"], @"Road shape description does not invent a direction command");
    check(YLNavigationCanFinish(20, 0, 0, 10), @"Stopped vehicle does not consume route distance");
    check([YLNavigationDistancePrefix(1381) isEqual:@"1킬로미터 앞, "], @"Long distance uses approximate kilometers");
    check([YLNavigationDistancePrefix(40) isEqual:@"잠시 후, "], @"Nearby event is imminent");
    check([YLNavigationDistancePrefix(0) isEqual:@"잠시 후, "], @"Zero is not zero meters ahead");
    check([YLNavigationDistancePrefix(-1) isEqual:@""], @"Missing distance is not imminent");
    check([YLNavigationDistancePrefix(80) isEqual:@"100미터 앞, "], @"Near distance boundary");
    check([YLNavigationDistancePrefix(75) isEqual:@"잠시 후, "], @"Close is imminent, not meters");
    check([YLNavigationDistancePrefix(460) isEqual:@"500미터 앞, "], @"Whole 100 m steps");
    check([YLNavigationDistancePrefix(950) isEqual:@"1킬로미터 앞, "], @"Kilometer boundary");
    check([YLNavigationCompactNumber(3.0) isEqual:@"3"], @"No meaningless decimal zero");
    check([YLNavigationCompactNumber(3.5) isEqual:@"3.5"], @"Retain real clearance fraction");
    check([YLNavigationCompactNumber(3.25) isEqual:@"3.25"], @"Do not round legal clearance up");
    check([YLNavigationSpeech(777,@"무시",@[@"무시"],200) length]==0, @"Unknown code must not invent movement");
    check([YLNavigationSpeech(100,nil,nil,200) length]==0, @"Start marker must not generate proceed");
    check(![YLNavigationSpeech(2,nil,nil,-1) containsString:@"미터"], @"Invalid distance must not be voiced");
    NSInteger groups[][2]={{0,3},{5,12},{14,49},{61,69},{70,94},{101,101},{900,906},{1000,1000}};
    NSInteger covered=0;
    for (NSUInteger i=0;i<sizeof(groups)/sizeof(groups[0]);i++) {
        for (NSInteger code=groups[i][0];code<=groups[i][1];code++) {
            NSString *text=YLNavigationSpeech(code,nil,nil,200);
            check(text.length>0,[NSString stringWithFormat:@"Missing code %ld",(long)code]);
            check(![text containsString:@"진행입니다"],@"No generic dashboard fallback"); covered++;
        }
    }
    printf("PASS: navigation speech semantics, %ld maneuver codes, all 24 clock exits\n",(long)covered);
} return 0; }
