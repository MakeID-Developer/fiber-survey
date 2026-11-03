#import "FSCSessionState.h"
@interface FSCSessionState ()
@property (nonatomic, readwrite) BOOL restartRequired;
@property (nonatomic, readwrite) NSUInteger sessionID;
@property (nonatomic, readwrite) NSUInteger operationID;
@end
@implementation FSCSessionState
- (instancetype)init { if ((self = [super init])) { _sessionID = 1; _scanID = 1; _operationID = 1; } return self; }
- (BOOL)acceptsSession:(NSUInteger)sessionID { return self.sessionID == sessionID && self.phase != FSCSessionClosed; }
- (BOOL)beginCommand {
    if (!self.active || self.phase != FSCSessionReady || self.restartRequired) return NO;
    self.operationID++; self.phase = FSCSessionCommandPending; return YES;
}
- (BOOL)finishCommand:(NSUInteger)operationID {
    if (self.phase != FSCSessionCommandPending || self.operationID != operationID) return NO;
    self.phase = FSCSessionClosed; return YES;
}
- (void)invalidateConfirmation { if (self.phase != FSCSessionCommandPending) self.operationID++; }
- (void)invalidate {
    self.sessionID++; self.scanID++; self.operationID++;
    self.restartRequired = self.restartRequired || self.connectionAttempted;
    self.phase = self.restartRequired ? FSCSessionClosed : FSCSessionIdle;
}
@end
