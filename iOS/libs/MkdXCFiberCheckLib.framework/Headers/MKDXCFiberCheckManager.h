//
//  MKDXCFiberCheckManager.h
//  MkdXCFiberCheckLib
//
//  信测对纤仪（160#）SDK 统一入口。
//
//  设备自动组网：手机连上的那台是网关，自己的数据和组网内其它设备的数据都会从同一条 notify 涌进来，
//  靠 content.device_id 区分归属。手机侧只有一条 GATT 连接，本 SDK 不做多设备管理。
//
//  deviceId 是同一个编号体系：每台设备的编号 = 其蓝牙名去掉 TR-FID- 前缀，
//  所以连接入参与白名单可以直接复用同一个变量。
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <MkdXCFiberCheckLib/MKDXCModels.h>

NS_ASSUME_NONNULL_BEGIN

/// 扫描到设备的回调，与其余 5 个库签名一致。
typedef void (^MKDXCDeviceCallback)(CBPeripheral *peripheral, NSNumber *RSSI);
/// 通用回调，与 MkdBLEConnectLib 返回保持一致。
typedef void (^MKDXCNormalCallback)(id response);
typedef void (^MKDXCSuccessCallback)(void);
typedef void (^MKDXCFailureCallback)(NSError *error);

/// 对纤仪 SDK 主动上报代理，均在主线程回调。
@protocol MKDXCFiberCheckDelegate <NSObject>
@optional

/// 连接状态变化，主线程回调。包含设备主动断开、一键关机后离线、被系统回收等情况。
///
/// ⚠️ 业务**不要**自行设置 `MkdBLEConnect.connectionStateChangedBlock` ——
/// 那是单例上的单写属性，SDK 内部已占用，外部再设一次会把 SDK 的状态维护顶掉。
/// 需要感知断连就用本方法。
- (void)xcfiberDidUpdateConnectionState:(BOOL)connected;

/// 光纤匹配结果主动上报（已过白名单）。
/// @param deviceId 所属设备编号。
/// @param powerUp YES = power_up（插好），NO = power_down（断开）。
- (void)xcfiberDidReceivePowerChange:(NSString *)deviceId powerUp:(BOOL)powerUp;

/// 设备开机上报（已过白名单）。
- (void)xcfiberDidReceiveDevicePowerOn:(NSString *)deviceId;

/// 设备关机上报（已过白名单）。
- (void)xcfiberDidReceiveDevicePowerOff:(NSString *)deviceId;

/// 收发原文，过滤前的全部 JSON —— 联调与"数据为什么没了"的唯一依据，务必保留。
/// @param json 原始 JSON 文本。
/// @param isSend YES = 下发，NO = 上报。
- (void)xcfiberDidReceiveRawJson:(NSString *)json isSend:(BOOL)isSend;

@end

@interface MKDXCFiberCheckManager : NSObject

/// 主动上报代理。
@property (nonatomic, weak, nullable) id<MKDXCFiberCheckDelegate> delegate;
/// 通知已开启，可下发命令。
@property (nonatomic, assign, readonly) BOOL connected;

/// SDK 单例。
+ (instancetype)shared;

/// SDK 版本号。
- (NSString *)sdkVersion;

#pragma mark - 扫描 / 连接

/// 开始扫描对纤仪设备。只按蓝牙名前缀 TR-FID- 缩小范围，不按 deviceId 裁剪。
///
/// 前缀**不在**底座（MkdBLEConnect.filterArray）里过滤，而是在扫描结果中由本 SDK 自行匹配，
/// 因此大小写不敏感、且按回写后的广播名（Local Name）比对 —— 底座过滤做不到这两点，
/// 会表现为"设备就在旁边但有时候扫不到"。匹配规则见 MKDXCDeviceMatcher.h。
/// @param timeout 扫描超时时间，单位秒。
/// @param success 每发现一个设备回调一次，已在同一次扫描内按 identifier 去重。
/// @param complete 扫描结束回调。
/// @param fail 扫描失败回调。
- (void)searchDevicesForTimeout:(NSTimeInterval)timeout
                        success:(MKDXCDeviceCallback)success
                       complete:(MKDXCNormalCallback)complete
                           fail:(MKDXCNormalCallback)fail;

/// 停止扫描。
- (void)stopScan;

/// 监听系统蓝牙状态变化，response 为 CBManagerState 的 NSNumber 包装值。
/// iOS 没有运行时权限弹窗，一旦被拒只能去系统设置开；不监听会表现为"扫描完全无回调"。
- (void)observeCentralManagerState:(MKDXCNormalCallback)callback;

/// 连接指定设备。
- (void)connectPeripheral:(CBPeripheral *)peripheral
                  success:(MKDXCNormalCallback)success
                     fail:(MKDXCNormalCallback)fail;

/// 按设备编号连接：内部去掉 TR-FID- 前缀后与蓝牙名比对。
/// 入参同时接受 "000002" 与 "TR-FID-000002"（大小写不敏感）。
/// 扫描阶段仍会列出所有 TR-FID- 设备，本方法只决定最终连哪一台。
/// @param timeout 扫描超时时间，单位秒；自身兜底超时在此基础上再加底座连接超时与余量。
- (void)connectDeviceId:(NSString *)deviceId
                timeout:(NSTimeInterval)timeout
                success:(MKDXCNormalCallback)success
                   fail:(MKDXCNormalCallback)fail;

/// 主动断开连接并清空未完成请求。关机后不要自动重连。
- (void)disconnect;

#pragma mark - 命令

/// 一键关机。success = 收到 ACK 且 status == ok。
/// 设备先回 ACK 再关机，所以 ACK 收得到；仍保留超时兜底（丢包、提前断电）。
- (void)shutdownAllWithSuccess:(nullable MKDXCSuccessCallback)success
                       failure:(nullable MKDXCFailureCallback)failure;

#pragma mark - 设备编号白名单（对齐 Android DeviceIdFilter）

/// 只作用于上报分发，不参与蓝牙扫描。
/// 传 nil / 空数组 / 全空白串 = 不拦截。
/// 这里的 deviceId 与 connectDeviceId: 的入参属于同一个编号体系，可直接复用同一个变量。
/// 注意：连上网关后若只设网关自己的编号，就只收得到网关自己这台的数据，
/// 组网内其它设备要另行加进白名单。SDK 不自动设置。
- (void)setDeviceIdFilter:(nullable NSArray<NSString *> *)deviceIds;

/// 恢复全放行。
- (void)clearDeviceIdFilter;

/// 当前白名单快照（已归一化）；未启用时为空集合。
@property (nonatomic, copy, readonly) NSSet<NSString *> *deviceIdFilter;

@end

NS_ASSUME_NONNULL_END
