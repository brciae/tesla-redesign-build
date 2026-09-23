#import <Foundation/Foundation.h>
#import "../TeslaLocal.swiftpm/Sources/KakaoNavigationBridge/include/YLNavigationSpeech.h"

static void check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(void) { @autoreleasepool {
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
