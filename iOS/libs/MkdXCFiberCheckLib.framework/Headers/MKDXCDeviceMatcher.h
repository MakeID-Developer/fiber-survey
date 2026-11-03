//
//  MKDXCDeviceMatcher.h
//  MkdXCFiberCheckLib
//
//  扫描结果的设备匹配：蓝牙名 → 设备编号。
//
//  为什么不把前缀设进 MkdBLEConnect.filterArray 让底座过滤？
//  底座 didDiscoverPeripheral 里的过滤有三个坑，会让设备"有时候扫不到"：
//    1. 先判 `peripheral.name.length > 0`，name 为 nil 的设备直接 return，
//       连后面的 Local Name 回写都走不到；
//    2. 过滤用 `hasPrefix:`，大小写敏感 —— 广播名 tr-fid-000002 匹配不上 TR-FID-；
//    3. 过滤发生在 Local Name 回写**之前**，比的是 GAP 名而不是广播名。
//
//  所以本 SDK 把 filterArray 置 nil，让底座回调全部设备（此时 name 已完成 Local Name 回写），
//  再由这里自行匹配。匹配规则：去首尾空白 → 大小写不敏感判前缀 → 取后缀。
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

/// 从蓝牙名提取设备编号；不是对纤仪（不含 TR-FID- 前缀）返回 nil。
/// @param name 蓝牙名，允许 nil / 空串。
/// @return 去掉前缀后的设备编号（如 "000002"）；不匹配返回 nil。
FOUNDATION_EXPORT NSString *_Nullable MKDXCDeviceIdFromName(NSString *_Nullable name);

/// 从扫描结果提取设备编号；不是对纤仪返回 nil。
///
/// 只依赖 `peripheral.name`：底座在回调前已把 `kCBAdvDataLocalName`
/// 回写进 name（见 MkdBLEConnect didDiscoverPeripheral），这里无需再取广播包。
///
/// @return 设备编号；name 为空或前缀不匹配返回 nil。
FOUNDATION_EXPORT NSString *_Nullable MKDXCDeviceIdFromPeripheral(CBPeripheral *_Nullable peripheral);

/// 宽松提取：归一化后取 `trfid` 之后的部分，取不到返回 nil。
///
/// 仅用于**兜底** —— 严格匹配失败、但名字里确实含 `TR-FID` 时（例如前缀不在开头、
/// 或名字里混了严格规则没覆盖到的字符）。扫描列表漏掉真设备的代价远大于多显示一台，
/// 所以这时候宁可放行；调用方应打 Warn 告警，方便事后追溯固件名的真实形态。
///
/// 注意：归一化会把大写转小写、去掉非字母数字，所以这里返回的编号**大小写可能与固件不一致**。
FOUNDATION_EXPORT NSString *_Nullable MKDXCDeviceIdFromNameLenient(NSString *_Nullable name);

NS_ASSUME_NONNULL_END
