#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, FSCSessionPhase) {
    FSCSessionIdle, FSCSessionWaitingBluetooth, FSCSessionScanning, FSCSessionFindingHost,
    FSCSessionConnecting, FSCSessionConnectedUnverified, FSCSessionReady,
    FSCSessionCommandPending, FSCSessionClosed
};
@interface FSCSessionState : NSObject
@property (nonatomic) FSCSessionPhase phase;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL connectionAttempted;
@property (nonatomic, readonly) BOOL restartRequired;
@property (nonatomic, readonly) NSUInteger sessionID;
@property (nonatomic) NSUInteger scanID;
@property (nonatomic, readonly) NSUInteger operationID;
- (BOOL)acceptsSession:(NSUInteger)sessionID;
- (BOOL)beginCommand;
- (BOOL)finishCommand:(NSUInteger)operationID;
- (void)invalidateConfirmation;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
