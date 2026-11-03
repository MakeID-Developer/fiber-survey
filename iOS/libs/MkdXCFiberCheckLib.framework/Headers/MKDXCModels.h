//
//  MKDXCModels.h
//  MkdXCFiberCheckLib
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 对纤仪上报类型。
typedef NS_ENUM(NSInteger, MKDXCReportType) {
    /// 光纤匹配结果（detected_powerchange）。
    MKDXCReportTypePowerChange = 0,
    /// 设备开机（Power_On）。
    MKDXCReportTypeDevicePowerOn,
    /// 设备关机（Power_Off）。
    MKDXCReportTypeDevicePowerOff,
    /// 一键关机命令 ACK（allshutdown）。
    MKDXCReportTypeShutdownAck,
    /// 未知 cmd，只走 RawJson 与日志。
    MKDXCReportTypeUnknown,
};

/// 一条对纤仪上报的解析结果。
///
/// 设备自动组网，手机连上的那台是网关，会上报自己的数据，也代发组网内其它设备的数据，
/// 因此 `deviceId` 不一定是网关自己的编号 —— 它标识的是这条数据属于哪台设备。
@interface MKDXCReport : NSObject

/// 上报类型。
@property (nonatomic, assign, readonly) MKDXCReportType type;
/// 原始 cmd 字符串（未归一化，用于日志与定位固件真实拼法）。
@property (nonatomic, copy, readonly) NSString *rawCommand;
/// 归一化后的 cmd，用于内部比较。
@property (nonatomic, copy, readonly) NSString *command;
/// 设备编号，取不到时为 nil。
@property (nonatomic, copy, readonly, nullable) NSString *deviceId;
/// 光纤匹配结果，YES = power_up，NO = power_down。仅 PowerChange 有效。
@property (nonatomic, assign, readonly) BOOL powerUp;
/// power_change 取值是否被识别。未被识别时不要当成 power_down 静默降级使用。
@property (nonatomic, assign, readonly) BOOL powerChangeRecognized;
/// ACK 原始 status 取值，仅 ShutdownAck 有效；ACK 的 status 在顶层，不在 content 里。
@property (nonatomic, copy, readonly, nullable) NSString *status;
/// ACK 是否成功，唯一成功取值 status == "ok"。仅 ShutdownAck 有效。
@property (nonatomic, assign, readonly) BOOL ackOK;
/// 原始 JSON 文本。
@property (nonatomic, copy, readonly) NSString *rawJSON;

@end

NS_ASSUME_NONNULL_END
