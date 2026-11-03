#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
NS_ASSUME_NONNULL_BEGIN
@interface FSCCentralStateGate : NSObject
+ (BOOL)canProceed:(CBManagerState)state authorization:(CBManagerAuthorization)authorization active:(BOOL)active;
+ (NSString *)stateText:(CBManagerState)state;
+ (NSString *)authorizationText;
@end
NS_ASSUME_NONNULL_END
