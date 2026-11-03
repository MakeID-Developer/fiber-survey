#import <XCTest/XCTest.h>
@interface FiberSurveyUITests : XCTestCase
@end
@implementation FiberSurveyUITests
- (void)setUp { self.continueAfterFailure = NO; }
- (void)testLaunchDoesNotRequireNetworkOrEnableUnsafeShutdown {
    XCUIApplication *app = [XCUIApplication new]; [app launch];
    XCTAssertTrue(app.buttons[@"扫描并选择主机"].exists);
    XCTAssertTrue(app.tables[@"本地日志，可独立滚动"].exists);
    XCUIElement *shutdown = app.buttons[@"一键关机（当前SDK安全阻断）"];
    for (NSUInteger i = 0; i < 6 && !shutdown.hittable; i++) [app.scrollViews[@"操作及事件区域，可独立滚动"] swipeUp];
    XCTAssertTrue(shutdown.exists);
    XCTAssertFalse(shutdown.enabled);
}
@end
