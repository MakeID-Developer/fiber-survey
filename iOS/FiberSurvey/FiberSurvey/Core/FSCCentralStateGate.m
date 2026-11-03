#import "FSCCentralStateGate.h"
@implementation FSCCentralStateGate
+ (BOOL)canProceed:(CBManagerState)state authorization:(CBManagerAuthorization)authorization active:(BOOL)active {
    return active && state == CBManagerStatePoweredOn && authorization == CBManagerAuthorizationAllowedAlways;
}
+ (NSString *)stateText:(CBManagerState)state {
    switch (state) {
        case CBManagerStateUnknown: return @"等待蓝牙状态";
        case CBManagerStateResetting: return @"蓝牙重置中";
        case CBManagerStateUnsupported: return @"设备不支持BLE";
        case CBManagerStateUnauthorized: return @"蓝牙未授权";
        case CBManagerStatePoweredOff: return @"蓝牙关闭，请在系统设置开启";
        case CBManagerStatePoweredOn: return @"蓝牙已开启";
    }
    return @"未知蓝牙状态";
}
+ (NSString *)authorizationText {
    switch (CBManager.authorization) {
        case CBManagerAuthorizationNotDetermined: return @"授权尚未确定";
        case CBManagerAuthorizationRestricted: return @"蓝牙授权受限";
        case CBManagerAuthorizationDenied: return @"蓝牙授权被拒，请到设置允许";
        case CBManagerAuthorizationAllowedAlways: return @"蓝牙授权允许";
    }
    return @"未知授权状态";
}
@end
