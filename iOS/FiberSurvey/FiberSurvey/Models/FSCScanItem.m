#import "FSCScanItem.h"
#import <MkdXCFiberCheckLib/MkdXCFiberCheckLib.h>
@interface FSCScanItem ()
@property (nonatomic, strong, readwrite) CBPeripheral *peripheral;
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *firstName;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *deviceID;
@property (nonatomic, strong, readwrite) NSNumber *RSSI;
@property (nonatomic, strong, readwrite) NSDate *discoveredAt;
@property (nonatomic, readwrite) BOOL lenient;
@property (nonatomic, readwrite) BOOL nameChanged;
@end
@implementation FSCScanItem
- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral RSSI:(NSNumber *)RSSI scanID:(NSUInteger)scanID {
    if ((self = [super init])) {
        _firstName = peripheral.name.copy ?: @""; _scanID = scanID;
        [self updatePeripheral:peripheral RSSI:RSSI];
    }
    return self;
}
- (void)updatePeripheral:(CBPeripheral *)peripheral RSSI:(NSNumber *)RSSI {
    self.peripheral = peripheral;
    self.identifier = peripheral.identifier.UUIDString;
    NSString *latest = peripheral.name ?: @"";
    NSString *strict = MKDXCDeviceIdFromName(latest);
    NSString *derived = strict ?: MKDXCDeviceIdFromNameLenient(latest);
    if (derived.length) { self.name = latest; self.deviceID = derived; self.lenient = !strict; }
    if (!self.name) self.name = latest;
    if (!self.deviceID) self.deviceID = @"";
    self.nameChanged = ![self.firstName isEqualToString:latest];
    self.RSSI = RSSI; self.discoveredAt = NSDate.date;
}
- (NSString *)summary {
    return [NSString stringWithFormat:@"%@\n编号：%@%@\nidentifier：%@\n最后发现RSSI：%@ dBm%@", self.name, self.deviceID,
            self.lenient ? @"（SDK宽松推导，请核对）" : @"", self.identifier, self.RSSI,
            self.nameChanged ? [NSString stringWithFormat:@"\n名称变化；首次：%@", self.firstName] : @""];
}
@end
