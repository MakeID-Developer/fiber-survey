#import "FSCFiberSurveyController.h"
#import "../Core/FSCBoundedStore.h"
#import "../Core/FSCDeviceFilterParser.h"
#import "../Core/FSCCentralStateGate.h"

// Fail closed for the delivered 1.0 frameworks. This is NOT a user preference.
// Change only after vendor fixes, paired artifacts/hash update and device safety acceptance.
static const BOOL FSCSDKWriteSafetyValidated = NO;

@interface FSCFiberSurveyController ()
@property (nonatomic, strong, readwrite) FSCSessionState *session;
@property (nonatomic, strong) MKDXCFiberCheckManager *sdk;
@property (nonatomic, strong) FSCBoundedStore *logStore;
@property (nonatomic, strong) FSCBoundedStore *eventStore;
@property (nonatomic, strong) NSMutableArray<FSCScanItem *> *discovered;
@property (nonatomic, strong, readwrite) FSCScanItem *host;
@property (nonatomic, copy, readwrite) NSString *filterText;
@property (nonatomic, copy, readwrite) NSString *lastResult;
@property (nonatomic, copy) NSArray<NSString *> *filterIDs;
@property (nonatomic) CBManagerState centralState;
@property (nonatomic, copy) dispatch_block_t deadline;
@property (nonatomic, copy) dispatch_block_t pendingIntent;
@property (nonatomic, strong) NSDateFormatter *timestampFormatter;
@property (nonatomic) NSUInteger logSequence;
@property (nonatomic) BOOL updateQueued;
@property (nonatomic) BOOL scanInFlight;
@property (nonatomic) NSTimeInterval deadlineUptime;
@end

@implementation FSCFiberSurveyController
- (instancetype)init {
    if ((self = [super init])) {
        _session = [FSCSessionState new];
        _logStore = [[FSCBoundedStore alloc] initWithCapacity:300];
        _eventStore = [[FSCBoundedStore alloc] initWithCapacity:200];
        _discovered = [NSMutableArray array]; _filterIDs = @[];
        _filterText = @"全部放行（空白名单）";
        _lastResult = @"未发送指令；当前SDK未通过安全写入验收";
        _centralState = CBManagerStateUnknown; _rawLogging = YES;
        _timestampFormatter = [NSDateFormatter new]; _timestampFormatter.dateFormat = @"HH:mm:ss.SSS";
        [self log:@"说明" text:@"离线真机Demo。点击扫描/连接后才初始化蓝牙；无网络与锁库鉴权。"];
        [self log:@"安全" text:@"SDK 1.0存在就绪/取消/旧写风险：仅被动联调，实际关机发送已禁用。连接结束后须重启App。"];
    }
    return self;
}
- (NSArray<NSString *> *)logs { return self.logStore.items; }
- (NSArray<NSString *> *)events { return self.eventStore.items; }
- (NSArray<FSCScanItem *> *)scanItems { return self.discovered.copy; }
- (BOOL)canStart {
    return self.session.active && !self.session.restartRequired && !self.pendingIntent &&
           (self.session.phase == FSCSessionIdle || self.session.phase == FSCSessionScanning);
}
- (BOOL)hasConnection { return self.session.phase == FSCSessionConnectedUnverified || self.session.phase == FSCSessionReady; }
- (BOOL)canChangeFilter { return self.session.active && self.session.phase != FSCSessionCommandPending; }
- (BOOL)canShutdown {
    return FSCSDKWriteSafetyValidated && self.session.active && self.host && self.sdk.connected &&
           self.session.phase == FSCSessionReady && !self.session.restartRequired &&
           [FSCCentralStateGate canProceed:self.centralState authorization:CBManager.authorization active:self.session.active];
}
- (NSString *)bluetoothText {
    if (!self.sdk) return @"蓝牙尚未初始化 · 点击扫描或连接后申请授权";
    return [NSString stringWithFormat:@"%@ · %@", [FSCCentralStateGate stateText:self.centralState], [FSCCentralStateGate authorizationText]];
}
- (NSString *)statusText {
    if (self.session.restartRequired) return @"会话已结束 · 请从任务列表关闭并重新打开App";
    switch (self.session.phase) {
        case FSCSessionIdle: return @"待操作";
        case FSCSessionWaitingBluetooth: return @"等待蓝牙/授权 · 最多15秒";
        case FSCSessionScanning: return @"扫描中 · 请手动选择主机";
        case FSCSessionFindingHost: return @"按编号寻找主机中";
        case FSCSessionConnecting: return @"连接中 · 等待SDK回调（未安全验收）";
        case FSCSessionConnectedUnverified: return @"SDK已回调连接 · 未安全验收 · 仅被动接收";
        case FSCSessionReady: return @"已就绪";
        case FSCSessionCommandPending: return @"等待业务ACK · 不可重复发送或换目标";
        case FSCSessionClosed: return @"会话已关闭";
    }
    return @"未知状态";
}
- (void)notifyUI {
    if (self.updateQueued) return;
    self.updateQueued = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf; if (!self) return;
        self.updateQueued = NO;
        if (self.changed) self.changed();
        if (self.scanChanged) self.scanChanged();
    });
}
- (void)log:(NSString *)kind text:(NSString *)text {
    NSDateFormatter *f = self.timestampFormatter;
    [self.logStore prepend:[NSString stringWithFormat:@"%@ [%@ #%lu] %@", [f stringFromDate:NSDate.date], kind, (unsigned long)++self.logSequence, [FSCDeviceFilterParser boundedText:text ?: @""]]];
    [self notifyUI];
}
- (void)event:(NSString *)text device:(NSString *)deviceID {
    if (!self.hasConnection || !self.host) return;
    NSDateFormatter *f = self.timestampFormatter;
    [self.eventStore prepend:[NSString stringWithFormat:@"%@ · %@\n来源：%@ · 主机：%@ · session:%lu", [f stringFromDate:NSDate.date], text, [FSCDeviceFilterParser boundedText:deviceID.length ? deviceID : @"缺失ID"], self.host.deviceID, (unsigned long)self.session.sessionID]];
    [self notifyUI];
}
- (void)clearLogs { [self.logStore clear]; [self notifyUI]; }
- (void)clearEvents { [self.eventStore clear]; [self notifyUI]; }
- (void)cancelDeadline {
    if (self.deadline) dispatch_block_cancel(self.deadline);
    self.deadline = nil;
}
- (void)setDeadline:(NSTimeInterval)seconds action:(dispatch_block_t)action {
    [self cancelDeadline];
    self.deadlineUptime = NSProcessInfo.processInfo.systemUptime + seconds;
    NSUInteger sessionID = self.session.sessionID;
    __weak typeof(self) weakSelf = self;
    self.deadline = dispatch_block_create(0, ^{
        typeof(self) self = weakSelf;
        if (!self || ![self.session acceptsSession:sessionID]) return;
        self.deadline = nil;
        action();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), self.deadline);
}
- (void)prepareSDK {
    if (self.sdk) { self.sdk.delegate = self; return; }
    self.sdk = MKDXCFiberCheckManager.shared;
    self.sdk.delegate = self;
    [self.sdk clearDeviceIdFilter];
    [self log:@"SDK" text:[NSString stringWithFormat:@"MkdXCFiberCheckLib %@ · BLE 1.0 · arm64真机", self.sdk.sdkVersion]];
    __weak typeof(self) weakSelf = self;
    [self.sdk observeCentralManagerState:^(id response) {
        // Manager normally delivers on main, but normalize synchronous failure paths too.
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            if ([response isKindOfClass:NSNumber.class]) self.centralState = [response integerValue];
            [self log:@"蓝牙" text:self.bluetoothText];
            if (self.centralState == CBManagerStatePoweredOn) [self consumeIntent];
            else if (self.centralState == CBManagerStatePoweredOff || self.centralState == CBManagerStateUnauthorized || self.centralState == CBManagerStateUnsupported) {
                [self closeWithReason:self.bluetoothText];
            } else if (self.scanInFlight || self.session.connectionAttempted) {
                [self closeWithReason:@"蓝牙状态不稳定，结束当前任务；不自动恢复连接"];
            }
        });
    }];
}
- (void)withBluetooth:(dispatch_block_t)action {
    if (!self.canStart || self.session.phase == FSCSessionScanning) {
        [self log:@"拒绝" text:@"请先结束当前任务；关闭的连接会话需重启App后重试"];
        return;
    }
    self.pendingIntent = action;
    self.session.phase = FSCSessionWaitingBluetooth;
    [self prepareSDK];
    __weak typeof(self) weakSelf = self;
    [self setDeadline:15 action:^{ [weakSelf closeWithReason:@"等待蓝牙/授权超过15秒，请检查系统设置后主动重试"]; }];
    [self consumeIntent]; [self notifyUI];
}
- (void)consumeIntent {
    if (!self.pendingIntent || ![FSCCentralStateGate canProceed:self.centralState authorization:CBManager.authorization active:self.session.active]) return;
    dispatch_block_t intent = self.pendingIntent; self.pendingIntent = nil;
    [self cancelDeadline]; intent();
}
- (BOOL)startScanWithDuration:(NSString *)duration {
    NSTimeInterval seconds = 0;
    if (![FSCDeviceFilterParser duration:duration seconds:&seconds]) { [self log:@"输入" text:@"扫描时长必须为1～60秒的有限数值"]; return NO; }
    if (!self.canStart || self.session.phase == FSCSessionScanning) { [self log:@"拒绝" text:self.statusText]; return NO; }
    self.session.scanID++;
    [self.discovered removeAllObjects];
    __weak typeof(self) weakSelf = self;
    [self withBluetooth:^{ [weakSelf runScan:seconds target:nil]; }];
    return YES;
}
- (void)connectHostID:(NSString *)hostID duration:(NSString *)duration {
    NSString *target = [hostID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (target.length >= 7 && [[target substringToIndex:7] caseInsensitiveCompare:@"TR-FID-"] == NSOrderedSame) target = [[target substringFromIndex:7] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!target.length || target.length > 64 || [target rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        [self log:@"输入" text:@"主机编号不能为空、不能含空白，最长64字符；可输入TR-FID-完整名称"]; return;
    }
    NSTimeInterval seconds = 0;
    if (![FSCDeviceFilterParser duration:duration seconds:&seconds]) { [self log:@"输入" text:@"扫描时长必须为1～60秒"]; return; }
    if (!self.canStart || self.session.phase == FSCSessionScanning) { [self log:@"拒绝" text:self.statusText]; return; }
    self.session.scanID++; [self.discovered removeAllObjects];
    __weak typeof(self) weakSelf = self;
    // Use public search + connectPeripheral rather than connectDeviceId's uncancellable local fallback.
    // This also keeps the selected peripheral/name/identifier visible for confirmation.
    [self withBluetooth:^{ [weakSelf runScan:seconds target:target]; }];
}
- (void)runScan:(NSTimeInterval)seconds target:(NSString *)target {
    NSUInteger sessionID = self.session.sessionID, scanID = self.session.scanID;
    self.session.phase = target ? FSCSessionFindingHost : FSCSessionScanning;
    self.scanInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [self log:@"扫描" text:[NSString stringWithFormat:@"%.1f秒%@；不自动连接首个发现设备", seconds, target ? [@"，目标编号：" stringByAppendingString:target] : @""]];
    [self setDeadline:seconds + 2 action:^{ [weakSelf closeWithReason:@"扫描超过App总截止时间，结果作废；旧任务未确认取消，重启后再试"]; }];
    [self.sdk searchDevicesForTimeout:seconds success:^(CBPeripheral *peripheral, NSNumber *RSSI) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || ![self.session acceptsSession:sessionID] || self.session.scanID != scanID || !self.scanInFlight || !self.session.active) return;
            FSCScanItem *item = nil;
            for (FSCScanItem *existing in self.discovered) if ([existing.identifier isEqualToString:peripheral.identifier.UUIDString]) { item = existing; break; }
            if (item) [item updatePeripheral:peripheral RSSI:RSSI];
            else if (self.discovered.count < 200) { item = [[FSCScanItem alloc] initWithPeripheral:peripheral RSSI:RSSI scanID:scanID]; [self.discovered addObject:item]; }
            if (!item) return;
            [self notifyUI];
            if (target && [item.deviceID caseInsensitiveCompare:target] == NSOrderedSame) [self connectItem:item];
        });
    } complete:^(id response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || ![self.session acceptsSession:sessionID] || self.session.scanID != scanID || !self.scanInFlight) return;
            self.scanInFlight = NO; [self cancelDeadline]; self.session.phase = FSCSessionIdle;
            [self log:@"扫描" text:target ? @"未发现匹配主机，请核对编号、设备电源与广播名称" : @"扫描结束，可选择本轮结果或重新扫描；RSSI为最后发现值"];
        });
    } fail:^(id response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || ![self.session acceptsSession:sessionID] || self.session.scanID != scanID || !self.scanInFlight) return;
            [self closeWithReason:[@"扫描失败：" stringByAppendingString:[self describeError:response]]];
        });
    }];
    [self notifyUI];
}
- (void)cancelScan:(NSUInteger)scanID {
    if (self.session.scanID != scanID || self.session.connectionAttempted) return;
    if (self.scanInFlight || self.pendingIntent) [self closeWithReason:@"用户取消扫描/等待；无连接交接"];
    else { self.session.scanID++; [self.discovered removeAllObjects]; [self notifyUI]; }
}
- (void)selectItem:(FSCScanItem *)item scanID:(NSUInteger)scanID {
    if (!self.canStart || scanID != self.session.scanID || item.scanID != scanID || ![self.discovered containsObject:item]) {
        [self log:@"拒绝" text:@"扫描结果已失效，请重新扫描"]; return;
    }
    [self connectItem:item];
}
- (void)connectItem:(FSCScanItem *)item {
    if (![FSCCentralStateGate canProceed:self.centralState authorization:CBManager.authorization active:self.session.active] || self.session.connectionAttempted) return;
    self.scanInFlight = NO; self.session.scanID++;
    [self.sdk stopScan]; [self cancelDeadline];
    self.session.connectionAttempted = YES; self.session.phase = FSCSessionConnecting;
    self.host = item; [self.eventStore clear]; self.lastResult = @"未发送指令；当前SDK仅允许被动接收";
    [self.sdk clearDeviceIdFilter];
    if (self.filterIDs.count) [self.sdk setDeviceIdFilter:self.filterIDs];
    [self updateFilterText];
    NSUInteger sessionID = self.session.sessionID;
    __weak typeof(self) weakSelf = self;
    [self setDeadline:22 action:^{ [weakSelf closeWithReason:@"连接/通知超过App总截止22秒；未证明就绪，请重启App后再试"]; }];
    [self log:@"连接" text:item.summary];
    [self.sdk connectPeripheral:item.peripheral success:^(id response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || ![self.session acceptsSession:sessionID] || self.session.phase != FSCSessionConnecting) return;
            [self cancelDeadline];
            self.session.phase = FSCSDKWriteSafetyValidated ? FSCSessionReady : FSCSessionConnectedUnverified;
            [self log:@"连接" text:@"SDK返回成功；现有库未修复就绪误报风险，不视作已安全READY，不允许写入"];
        });
    } fail:^(id response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || ![self.session acceptsSession:sessionID]) return;
            [self closeWithReason:[@"连接失败/断开：" stringByAppendingString:[self describeError:response]]];
        });
    }];
    [self notifyUI];
}
- (NSString *)describeError:(id)value {
    if ([value isKindOfClass:NSError.class]) {
        NSError *error = value;
        return [NSString stringWithFormat:@"%@ / %ld / %@", error.domain, (long)error.code, error.localizedDescription];
    }
    return [NSString stringWithFormat:@"底层未提供NSError：%@", value ?: @"无详细信息"];
}
- (void)updateFilterText {
    if (!self.filterIDs.count) self.filterText = @"全部放行（空白名单）";
    else self.filterText = [NSString stringWithFormat:@"已确认：%@\nSDK匹配键：%@", [self.filterIDs componentsJoinedByString:@", "], self.sdk ? [[self.sdk.deviceIdFilter.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "] : @"SDK尚未初始化，连接前应用"];
}
- (void)applyFilter:(NSString *)input {
    if (!self.canChangeFilter) return;
    NSError *error = nil;
    NSArray *ids = [FSCDeviceFilterParser parse:input error:&error];
    if (!ids) { [self log:@"输入" text:[self describeError:error]]; return; }
    self.filterIDs = ids;
    if (self.sdk) { if (ids.count) [self.sdk setDeviceIdFilter:ids]; else [self.sdk clearDeviceIdFilter]; }
    [self updateFilterText]; [self log:@"过滤" text:self.filterText];
}
- (void)clearFilter { [self applyFilter:@""]; }
- (NSDictionary<NSString *, id> *)shutdownConfirmation {
    return @{@"session": @(self.session.sessionID), @"operation": @(self.session.operationID), @"identifier": self.host.identifier ?: @"", @"summary": self.host.summary ?: @"尚未选择主机"};
}
- (void)confirmShutdown:(NSDictionary<NSString *, id> *)confirmation {
    if (!self.canShutdown || [confirmation[@"session"] unsignedIntegerValue] != self.session.sessionID ||
        [confirmation[@"operation"] unsignedIntegerValue] != self.session.operationID ||
        ![confirmation[@"identifier"] isEqual:self.host.identifier] || ![self.session beginCommand]) {
        [self log:@"安全阻断" text:@"当前SDK未通过就绪/取消/写入验收，或确认已过期；没有发送关机指令"];
        return;
    }
    NSUInteger sessionID = self.session.sessionID, operationID = self.session.operationID;
    __weak typeof(self) weakSelf = self;
    self.lastResult = @"等待SDK业务ACK（5秒），App最终兜底8秒";
    [self setDeadline:8 action:^{ [weakSelf finishShutdown:operationID sessionID:sessionID error:@"App8秒兜底超时；物理结果未知，不自动补发"]; }];
    [self.sdk shutdownAllWithSuccess:^{
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finishShutdown:operationID sessionID:sessionID error:nil]; });
    } failure:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finishShutdown:operationID sessionID:sessionID error:[weakSelf describeError:error]]; });
    }];
    [self notifyUI];
}
- (void)finishShutdown:(NSUInteger)operationID sessionID:(NSUInteger)sessionID error:(NSString *)error {
    if (![self.session acceptsSession:sessionID] || ![self.session finishCommand:operationID]) return;
    self.lastResult = error ? [@"关机未确认，物理结果未知：" stringByAppendingString:error] : @"收到status=ok业务ACK；不代表全部组网设备已实际断电";
    [self log:@"关机结果" text:self.lastResult]; [self closeWithReason:@"命令已终结，结束会话；不重试、不自动重连"];
}
- (void)closeWithReason:(NSString *)reason {
    BOOL commandPending = self.session.phase == FSCSessionCommandPending;
    // A cancelled SDK scan may still be scheduled asynchronously: also quarantine it.
    if (self.scanInFlight) self.session.connectionAttempted = YES;
    [self.session invalidate]; self.pendingIntent = nil; self.scanInFlight = NO;
    [self cancelDeadline];
    [self.sdk stopScan]; [self.sdk disconnect]; [self.sdk clearDeviceIdFilter];
    self.sdk.delegate = nil;
    self.filterIDs = @[]; [self updateFilterText];
    [self.discovered removeAllObjects];
    if (commandPending) self.lastResult = @"关机等待中被取消/断开，物理结果未知；不得自动重发";
    [self log:@"结束" text:reason];
}
- (void)cancelAndDisconnect { [self closeWithReason:@"用户取消/断开；不承诺SDK内部任务已可靠取消"]; }
- (void)sceneBecameActive {
    self.session.active = YES;
    // No reconnect or command replay. Only consume the existing bounded scan/connect intent.
    if (self.pendingIntent && NSProcessInfo.processInfo.systemUptime >= self.deadlineUptime) [self closeWithReason:@"蓝牙等待已过截止时间，请主动重试"];
    else [self consumeIntent];
    [self notifyUI];
}
- (void)sceneResignedActive { self.session.active = NO; [self.session invalidateConfirmation]; [self notifyUI]; }
- (void)sceneEnteredBackground { self.session.active = NO; [self closeWithReason:@"进入后台：取消本次意图与会话，不保留危险操作"]; }
- (void)tearDown { self.session.active = NO; [self closeWithReason:@"Scene退出"]; self.changed = nil; self.scanChanged = nil; }
- (void)xcfiberDidUpdateConnectionState:(BOOL)connected {
    if (!connected && (self.session.phase == FSCSessionConnecting || self.hasConnection || self.session.phase == FSCSessionCommandPending)) [self closeWithReason:@"SDK通知连接断开；不推断所有来源设备已关机"];
    // connected=YES alone is not proof of notification/service readiness.
}
- (void)xcfiberDidReceivePowerChange:(NSString *)deviceId powerUp:(BOOL)powerUp { [self event:powerUp ? @"power_up · 光纤匹配" : @"power_down · 光纤断开" device:deviceId]; }
- (void)xcfiberDidReceiveDevicePowerOn:(NSString *)deviceId { [self event:@"Power_On · 来源设备开机" device:deviceId]; }
- (void)xcfiberDidReceiveDevicePowerOff:(NSString *)deviceId { [self event:@"Power_Off · 来源设备关机（不等同主机断连）" device:deviceId]; }
- (void)xcfiberDidReceiveRawJson:(NSString *)json isSend:(BOOL)isSend {
    if (self.rawLogging && (self.hasConnection || self.session.phase == FSCSessionConnecting || self.session.phase == FSCSessionCommandPending)) [self log:isSend ? @"TX" : @"RX" text:json];
}
@end
