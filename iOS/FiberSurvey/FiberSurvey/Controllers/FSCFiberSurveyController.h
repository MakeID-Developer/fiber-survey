#import <Foundation/Foundation.h>
#import <MkdXCFiberCheckLib/MkdXCFiberCheckLib.h>
#import "../Core/FSCSessionState.h"
#import "../Models/FSCScanItem.h"
NS_ASSUME_NONNULL_BEGIN
@interface FSCFiberSurveyController : NSObject <MKDXCFiberCheckDelegate>
@property (nonatomic, copy, nullable) void (^changed)(void);
@property (nonatomic, copy, nullable) void (^scanChanged)(void);
@property (nonatomic, strong, readonly) FSCSessionState *session;
@property (nonatomic, copy, readonly) NSArray<NSString *> *logs;
@property (nonatomic, copy, readonly) NSArray<NSString *> *events;
@property (nonatomic, copy, readonly) NSArray<FSCScanItem *> *scanItems;
@property (nonatomic, strong, readonly, nullable) FSCScanItem *host;
@property (nonatomic, copy, readonly) NSString *statusText;
@property (nonatomic, copy, readonly) NSString *bluetoothText;
@property (nonatomic, copy, readonly) NSString *filterText;
@property (nonatomic, copy, readonly) NSString *lastResult;
@property (nonatomic, readonly) BOOL canStart;
@property (nonatomic, readonly) BOOL canShutdown;
@property (nonatomic, readonly) BOOL canChangeFilter;
@property (nonatomic, readonly) BOOL hasConnection;
@property (nonatomic) BOOL rawLogging;
- (BOOL)startScanWithDuration:(NSString *)duration;
- (void)cancelScan:(NSUInteger)scanID;
- (void)selectItem:(FSCScanItem *)item scanID:(NSUInteger)scanID;
- (void)connectHostID:(NSString *)hostID duration:(NSString *)duration;
- (void)applyFilter:(NSString *)input;
- (void)clearFilter;
- (NSDictionary<NSString *, id> *)shutdownConfirmation;
- (void)confirmShutdown:(NSDictionary<NSString *, id> *)confirmation;
- (void)cancelAndDisconnect;
- (void)sceneBecameActive;
- (void)sceneResignedActive;
- (void)sceneEnteredBackground;
- (void)tearDown;
- (void)clearLogs;
- (void)clearEvents;
@end
NS_ASSUME_NONNULL_END
