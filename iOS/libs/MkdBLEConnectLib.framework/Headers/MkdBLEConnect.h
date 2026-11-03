//
//  MkdBLEConnect.h
//  MkdBLEConnectLib
//
//  Created by 凉皮 on 2023/8/29.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^DataCallback)(NSData *data);
typedef void(^SearchDeviceCallback)(CBPeripheral *peripheral, NSNumber *RSSI);
typedef void(^NormalCallback)(id response);

@interface MkdBLEConnect : NSObject

///过滤器，需要过滤的蓝牙前缀，例如P50、CS1000、RR01，不设置则不过滤
@property (nonatomic, strong, nullable) NSArray <NSString *> *filterArray;
///数据包头，不同机型的前缀不一样，例如0x66、0x67、0x68
@property (nonatomic, assign) int dataPrefix;
/// 写特征UUID，保留给特殊协议覆盖；不设置时按特征属性自动匹配。
@property (nonatomic, copy, nullable) NSString *writeUUID;
/// notify特征UUID，保留给特殊协议覆盖；不设置时按特征属性自动匹配。
@property (nonatomic, copy, nullable) NSString *notifyUUID;
///是否直接透传notify原始数据，适用于清虚仪这类不带包头/长度字段的JSON协议
@property (nonatomic, assign) BOOL rawNotifyPassthrough;
///当前蓝牙是否已完成连接并可用
@property (nonatomic, assign, readonly) BOOL connected;
///蓝牙连接状态变化回调，仅在状态实际变化时触发
@property (nonatomic, copy, nullable) void (^connectionStateChangedBlock)(BOOL connected);

///接收数据的回调
@property (nonatomic, copy) DataCallback recvDataCallback;

/**
 * 单例，global_queue线程实例化方法
 */
+ (instancetype)sharedInstance;

/**
 * 监听蓝牙状态
 * @param callback 回调
 */
- (void)observeCentralManagerState:(NormalCallback)callback;

/**
 * 搜索蓝牙设备
 * @param timeout 搜索超时时间
 */
- (void)searchDevicesForTimeout:(NSTimeInterval)timeout
                        success:(SearchDeviceCallback)successCallback
                       complete:(NormalCallback)completeCallback
                           fail:(NormalCallback)failCallback;

/**
 * 连接蓝牙
 * @param peripheral 需要连接的peripheral
 */
- (void)connectPeripheral:(CBPeripheral *)peripheral success:(NormalCallback)successCallback fail:(NormalCallback)failCallback;

/**
 * 停止蓝牙扫描
 */
- (void)stopScan;

/**
 * 蓝牙自动重连
 */
- (void)reconnectPeripheralWithIdentifier:(NSString *)identifier success:(NormalCallback)successCallback fail:(NormalCallback)failCallback;

/**
 断开连接
 */
- (void)disconnect;

/**
 * 写入数据
 * @param data 写入的数据
 */
- (void)writeData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
