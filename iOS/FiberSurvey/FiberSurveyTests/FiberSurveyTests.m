#import <XCTest/XCTest.h>
#import "../FiberSurvey/Core/FSCDeviceFilterParser.h"
#import "../FiberSurvey/Core/FSCBoundedStore.h"
#import "../FiberSurvey/Core/FSCSessionState.h"
#import "../FiberSurvey/Core/FSCCentralStateGate.h"

@interface FiberSurveyTests : XCTestCase
@end
@implementation FiberSurveyTests
- (void)testFilterKeepsPunctuationAndLeadingZeroes {
    NSError *error = nil;
    NSArray *ids = [FSCDeviceFilterParser parse:@"000011，A-1;A1\n11 a-1" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(ids, (@[@"000011", @"A-1", @"A1", @"11"]));
    XCTAssertEqualObjects([FSCDeviceFilterParser parse:@" ,；\n" error:NULL], @[]);
}
- (void)testFilterRejectsOversizedIdentifier {
    NSString *longID = [@"x" stringByPaddingToLength:65 withString:@"x" startingAtIndex:0];
    NSError *error = nil;
    XCTAssertNil([FSCDeviceFilterParser parse:longID error:&error]);
    XCTAssertNotNil(error);
}
- (void)testDurationMustBeFiniteAndConsumeWholeInput {
    NSTimeInterval seconds = 0;
    XCTAssertTrue([FSCDeviceFilterParser duration:@"15" seconds:&seconds]);
    XCTAssertEqual(seconds, 15);
    for (NSString *s in @[@"nan", @"inf", @"0", @"61", @"-1", @"15abc", @""]) {
        XCTAssertFalse([FSCDeviceFilterParser duration:s seconds:&seconds], @"%@", s);
    }
}
- (void)testBoundedStoreKeepsNewestFirst {
    FSCBoundedStore *store = [[FSCBoundedStore alloc] initWithCapacity:2];
    [store prepend:@"one"]; [store prepend:@"two"]; [store prepend:@"three"];
    XCTAssertEqualObjects(store.items, (@[@"three", @"two"]));
    [store clear]; XCTAssertEqual(store.items.count, 0u);
}
- (void)testSessionInvalidatesLateResultsAndLocksReentry {
    FSCSessionState *s = [FSCSessionState new];
    NSUInteger generation = s.sessionID;
    s.connectionAttempted = YES;
    [s invalidate];
    XCTAssertNotEqual(s.sessionID, generation);
    XCTAssertTrue(s.restartRequired);
    XCTAssertFalse([s acceptsSession:generation]);
}
- (void)testCommandEndsAtMostOnceAndCannotStartUnverified {
    FSCSessionState *s = [FSCSessionState new];
    s.active = YES;
    s.phase = FSCSessionConnectedUnverified;
    XCTAssertFalse([s beginCommand]);
    s.phase = FSCSessionReady;
    XCTAssertTrue([s beginCommand]);
    NSUInteger operation = s.operationID;
    XCTAssertFalse([s beginCommand]);
    XCTAssertTrue([s finishCommand:operation]);
    XCTAssertFalse([s finishCommand:operation]);
}
- (void)testInactiveInvalidatesConfirmationButNotPendingCommand {
    FSCSessionState *s = [FSCSessionState new]; s.active = YES; s.phase = FSCSessionReady;
    NSUInteger before = s.operationID; [s invalidateConfirmation];
    XCTAssertNotEqual(s.operationID, before);
    XCTAssertTrue([s beginCommand]); before = s.operationID;
    [s invalidateConfirmation]; XCTAssertEqual(s.operationID, before);
    XCTAssertTrue([s finishCommand:before]);
}
- (void)testFilterAllowsOneHundredUniqueIDsAndRejectsNext {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSUInteger i = 0; i < 100; i++) [ids addObject:[NSString stringWithFormat:@"%03lu", (unsigned long)i]];
    NSString *text = [[ids componentsJoinedByString:@","] stringByAppendingString:@",000"];
    XCTAssertEqual([FSCDeviceFilterParser parse:text error:NULL].count, 100u);
    XCTAssertNil([FSCDeviceFilterParser parse:[text stringByAppendingString:@",extra"] error:NULL]);
}
- (void)testBluetoothGateRequiresActiveAuthorizedPoweredOn {
    XCTAssertTrue([FSCCentralStateGate canProceed:CBManagerStatePoweredOn authorization:CBManagerAuthorizationAllowedAlways active:YES]);
    XCTAssertFalse([FSCCentralStateGate canProceed:CBManagerStatePoweredOn authorization:CBManagerAuthorizationDenied active:YES]);
    XCTAssertFalse([FSCCentralStateGate canProceed:CBManagerStatePoweredOn authorization:CBManagerAuthorizationAllowedAlways active:NO]);
    XCTAssertFalse([FSCCentralStateGate canProceed:CBManagerStateResetting authorization:CBManagerAuthorizationAllowedAlways active:YES]);
}
@end
