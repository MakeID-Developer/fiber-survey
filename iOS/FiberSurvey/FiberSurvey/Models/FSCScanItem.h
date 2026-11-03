#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
NS_ASSUME_NONNULL_BEGIN
@interface FSCScanItem : NSObject
@property (nonatomic, strong, readonly) CBPeripheral *peripheral;
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *firstName;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *deviceID;
@property (nonatomic, strong, readonly) NSNumber *RSSI;
@property (nonatomic, strong, readonly) NSDate *discoveredAt;
@property (nonatomic, readonly) BOOL lenient;
@property (nonatomic, readonly) BOOL nameChanged;
@property (nonatomic) NSUInteger scanID;
- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral RSSI:(NSNumber *)RSSI scanID:(NSUInteger)scanID;
- (void)updatePeripheral:(CBPeripheral *)peripheral RSSI:(NSNumber *)RSSI;
- (NSString *)summary;
@end
NS_ASSUME_NONNULL_END
