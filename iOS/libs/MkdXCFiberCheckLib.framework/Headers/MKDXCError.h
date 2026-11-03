//
//  MKDXCError.h
//  MkdXCFiberCheckLib
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const MKDXCErrorDomain;

/// 信测对纤仪 SDK 错误码。
typedef NS_ENUM(NSInteger, MKDXCErrorCode) {
    /// 蓝牙不可用。
    MKDXCErrorBluetoothUnavailable = 1000,
    /// 蓝牙权限未授权（iOS 上表现为"扫描完全无回调"，必须明确抛给业务层）。
    MKDXCErrorBluetoothUnauthorized,
    /// 扫描失败。
    MKDXCErrorScanFailed,
    /// 连接失败或连接断开。
    MKDXCErrorConnectFailed,
    /// 当前未连接设备。
    MKDXCErrorNotConnected,
    /// 入参不合法。
    MKDXCErrorInvalidParameter,
    /// 数据写入失败。
    MKDXCErrorWriteFailed,
    /// 请求超时。
    MKDXCErrorTimeout,
    /// 协议格式错误。
    MKDXCErrorProtocolError,
    /// 设备返回错误（ACK 的 status 非 ok）。
    MKDXCErrorDeviceError,
};

/// 信测对纤仪 SDK 错误辅助类。
@interface MKDXCError : NSObject

/// 创建 SDK 标准错误对象。
/// @param code SDK 错误码。
/// @param message 错误描述。
+ (NSError *)errorWithCode:(MKDXCErrorCode)code message:(NSString *_Nullable)message;

/// 创建设备返回错误对象。
/// @param status 设备 ACK 返回的原始 status 取值。
+ (NSError *)deviceErrorWithStatus:(NSString *_Nullable)status;

@end

NS_ASSUME_NONNULL_END
