#import <Foundation/Foundation.h>

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
        case 63: return @"비보호 좌회전입니다.";
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
        case 86: return @"분기 후 합류 구간입니다.";
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

static inline NSString *YLNavigationSpeech(NSInteger code, NSString *node, NSArray<NSString *> *towards, NSInteger metres) {
    NSString *action = YLNavigationAction(code);
    if (!action.length) return @"";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *raw in towards) {
        if (![raw isKindOfClass:NSString.class]) continue;
        NSString *name = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length && ![names containsObject:name]) [names addObject:name];
    }
    NSString *context = @"";
    // Destinations/facilities already identify the point. Road signs help at forks.
    if (code != 101 && code != 1000 && code != 84 && code != 85) {
        if (names.count) context = [NSString stringWithFormat:@"%@ 방면, ", [names componentsJoinedByString:@", "]];
        else if (node.length) context = [NSString stringWithFormat:@"%@, ", node];
    }
    NSString *prefix = metres > 0 ? [NSString stringWithFormat:@"%ld미터 앞, ", (long)metres] : @"";
    return [NSString stringWithFormat:@"%@%@%@", prefix, context, action];
}
