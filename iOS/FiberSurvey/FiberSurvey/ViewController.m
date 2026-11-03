#import "ViewController.h"
#import <math.h>
#import "Controllers/FSCFiberSurveyController.h"
#import "Controllers/FSCScanViewController.h"

@interface ViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) FSCFiberSurveyController *controller;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *hostLabel;
@property (nonatomic, strong) UILabel *filterLabel;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) UILabel *eventLabel;
@property (nonatomic, strong) UITableView *logTable;
@property (nonatomic, strong) UIScrollView *operations;
@property (nonatomic, strong) UITextField *hostInput;
@property (nonatomic, strong) UITextField *durationInput;
@property (nonatomic, strong) UITextField *filterInput;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, strong) UIButton *clearFilterButton;
@property (nonatomic, strong) UIButton *shutdownButton;
@property (nonatomic, strong) UISwitch *rawSwitch;
@property (nonatomic, strong) UISwitch *followSwitch;
@property (nonatomic, copy) NSArray<NSString *> *displayedLogs;
@property (nonatomic, copy) NSArray<NSString *> *displayedEvents;
@end

@implementation ViewController
- (instancetype)initWithController:(FSCFiberSurveyController *)controller {
    if ((self = [super initWithNibName:nil bundle:nil])) _controller = controller;
    return self;
}
- (UILabel *)label:(NSString *)text style:(UIFontTextStyle)style {
    UILabel *label = [UILabel new]; label.text = text; label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:style]; label.adjustsFontForContentSizeCategory = YES;
    return label;
}
- (UITextField *)field:(NSString *)placeholder {
    UITextField *field = [UITextField new]; field.borderStyle = UITextBorderStyleRoundedRect;
    field.placeholder = placeholder; field.accessibilityLabel = placeholder;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; field.adjustsFontForContentSizeCategory = YES;
    field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.translatesAutoresizingMaskIntoConstraints = NO; [field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    UIToolbar *toolbar = [UIToolbar new]; [toolbar sizeToFit];
    toolbar.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(endEditing)]];
    field.inputAccessoryView = toolbar;
    return field;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = UIButtonConfiguration.tintedButtonConfiguration;
    configuration.title = title; button.configuration = configuration;
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.titleLabel.adjustsFontForContentSizeCategory = YES; button.titleLabel.numberOfLines = 0;
    button.accessibilityLabel = title; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.translatesAutoresizingMaskIntoConstraints = NO; [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}
- (UIStackView *)row:(NSArray<UIView *> *)views {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views]; row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8; row.alignment = UIStackViewAlignmentCenter; row.distribution = UIStackViewDistributionFill;
    return row;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"FiberSurvey · 信测对纤仪"; self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关于" style:UIBarButtonItemStylePlain target:self action:@selector(about)];
    self.rawSwitch = [UISwitch new]; self.rawSwitch.on = self.controller.rawLogging; self.rawSwitch.accessibilityLabel = @"显示TX/RX原文";
    [self.rawSwitch addTarget:self action:@selector(rawChanged) forControlEvents:UIControlEventValueChanged];
    self.followSwitch = [UISwitch new]; self.followSwitch.on = YES; self.followSwitch.accessibilityLabel = @"日志跟随最新";
    [self.followSwitch addTarget:self action:@selector(followChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *rawRow = [self row:@[[self label:@"TX/RX原文" style:UIFontTextStyleCaption1], self.rawSwitch,
                                    [self label:@"跟随" style:UIFontTextStyleCaption1], self.followSwitch]];
    UIStackView *logHeader = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:@"日志 · 最新在上 · 上限300" style:UIFontTextStyleHeadline], rawRow,
                                        [self button:@"清空日志" action:@selector(clearLogs)]]];
    logHeader.axis = UILayoutConstraintAxisVertical; logHeader.spacing = 4; logHeader.translatesAutoresizingMaskIntoConstraints = NO;
    self.logTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.logTable.dataSource = self; self.logTable.delegate = self; self.logTable.rowHeight = UITableViewAutomaticDimension;
    self.logTable.estimatedRowHeight = 70; self.logTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.logTable.accessibilityLabel = @"本地日志，可独立滚动";
    self.logTable.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    UIView *logPanel = [UIView new]; logPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [logPanel addSubview:logHeader]; [logPanel addSubview:self.logTable];
    [NSLayoutConstraint activateConstraints:@[
        [logHeader.topAnchor constraintEqualToAnchor:logPanel.topAnchor], [logHeader.leadingAnchor constraintEqualToAnchor:logPanel.leadingAnchor], [logHeader.trailingAnchor constraintEqualToAnchor:logPanel.trailingAnchor],
        [self.logTable.topAnchor constraintEqualToAnchor:logHeader.bottomAnchor constant:4], [self.logTable.leadingAnchor constraintEqualToAnchor:logPanel.leadingAnchor],
        [self.logTable.trailingAnchor constraintEqualToAnchor:logPanel.trailingAnchor], [self.logTable.bottomAnchor constraintEqualToAnchor:logPanel.bottomAnchor],
    ]];
    self.operations = [UIScrollView new]; self.operations.translatesAutoresizingMaskIntoConstraints = NO;
    self.operations.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.operations.accessibilityLabel = @"操作及事件区域，可独立滚动";
    UIStackView *form = [UIStackView new]; form.axis = UILayoutConstraintAxisVertical; form.spacing = 12;
    form.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel = [self label:@"" style:UIFontTextStyleSubheadline];
    self.hostLabel = [self label:@"尚未选择主机" style:UIFontTextStyleCaption1];
    UILabel *warning = [self label:@"当前SDK仅限被动联调：连接成功回调不代表安全READY。关机发送已禁用；连接结束后需重启App。" style:UIFontTextStyleSubheadline];
    warning.textColor = UIColor.systemOrangeColor;
    self.durationInput = [self field:@"扫描时长（1～60秒）"]; self.durationInput.text = @"15"; self.durationInput.keyboardType = UIKeyboardTypeDecimalPad;
    self.hostInput = [self field:@"主机编号或TR-FID-完整名称"];
    self.scanButton = [self button:@"扫描并选择主机" action:@selector(openScan)];
    self.connectButton = [self button:@"按编号连接主机" action:@selector(connectByID)];
    self.filterInput = [self field:@"白名单：000011,A-1（空为全部放行）"];
    self.filterLabel = [self label:@"" style:UIFontTextStyleCaption1];
    self.filterButton = [self button:@"应用白名单" action:@selector(applyFilter)];
    self.clearFilterButton = [self button:@"清空白名单（全放行）" action:@selector(clearFilter)];
    self.shutdownButton = [self button:@"一键关机（当前SDK安全阻断）" action:@selector(shutdown)];
    self.shutdownButton.tintColor = UIColor.systemRedColor;
    self.resultLabel = [self label:@"" style:UIFontTextStyleCaption1];
    self.eventLabel = [self label:@"暂无业务事件" style:UIFontTextStyleCaption1];
    for (UIView *view in @[[self label:@"操作区域" style:UIFontTextStyleHeadline], self.statusLabel, self.hostLabel, warning,
                          self.durationInput, self.scanButton, self.hostInput, self.connectButton,
                          [self button:@"取消等待 / 停止扫描 / 断开连接" action:@selector(disconnect)],
                          [self label:@"上报白名单（不限制关机范围）" style:UIFontTextStyleHeadline], self.filterInput,
                          self.filterButton, self.clearFilterButton, self.filterLabel,
                          self.shutdownButton, [self button:@"查看关机阻断原因" action:@selector(shutdownBlocked)], self.resultLabel,
                          [self button:@"系统设置（蓝牙授权）" action:@selector(openSettings)],
                          [self label:@"业务事件 · 上限200 · 与日志独立清空" style:UIFontTextStyleHeadline],
                          [self button:@"清空事件" action:@selector(clearEvents)], self.eventLabel]) [form addArrangedSubview:view];
    [self.operations addSubview:form]; [self.view addSubview:logPanel]; [self.view addSubview:self.operations];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    // Prefer a 40/60 split, but let the header and at least one log row fit in landscape/Dynamic Type.
    NSLayoutConstraint *split = [logPanel.heightAnchor constraintEqualToAnchor:safe.heightAnchor multiplier:0.4];
    split.priority = UILayoutPriorityDefaultHigh; split.active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [logPanel.heightAnchor constraintGreaterThanOrEqualToAnchor:logHeader.heightAnchor constant:48],
        [logPanel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8], [logPanel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [logPanel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [self.operations.topAnchor constraintEqualToAnchor:logPanel.bottomAnchor constant:8], [self.operations.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.operations.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12], [self.operations.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [form.topAnchor constraintEqualToAnchor:self.operations.contentLayoutGuide.topAnchor constant:8], [form.bottomAnchor constraintEqualToAnchor:self.operations.contentLayoutGuide.bottomAnchor constant:-16],
        [form.leadingAnchor constraintEqualToAnchor:self.operations.contentLayoutGuide.leadingAnchor], [form.trailingAnchor constraintEqualToAnchor:self.operations.contentLayoutGuide.trailingAnchor],
        [form.widthAnchor constraintEqualToAnchor:self.operations.frameLayoutGuide.widthAnchor],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    __weak typeof(self) weakSelf = self; self.controller.changed = ^{ [weakSelf refresh]; };
    [self refresh];
}
- (void)refresh {
    if (!self.isViewLoaded) return;
    self.statusLabel.text = [NSString stringWithFormat:@"%@\n%@", self.controller.statusText, self.controller.bluetoothText];
    self.hostLabel.text = self.controller.host ? self.controller.host.summary : @"尚未选择主机（主机/网关与来源device_id分别展示）";
    self.filterLabel.text = self.controller.filterText; self.resultLabel.text = self.controller.lastResult;
    self.scanButton.enabled = self.controller.canStart && self.controller.session.phase != FSCSessionScanning;
    self.connectButton.enabled = self.scanButton.enabled; self.hostInput.enabled = self.scanButton.enabled;
    self.durationInput.enabled = self.scanButton.enabled;
    self.filterButton.enabled = self.controller.canChangeFilter; self.clearFilterButton.enabled = self.controller.canChangeFilter;
    self.filterInput.enabled = self.controller.canChangeFilter; self.shutdownButton.enabled = self.controller.canShutdown;
    NSArray *latest = self.controller.logs;
    if (![latest isEqualToArray:self.displayedLogs]) {
        NSArray *old = self.displayedLogs;
        NSIndexPath *visible = self.logTable.indexPathsForVisibleRows.firstObject;
        NSString *anchor = visible && visible.row < old.count ? old[visible.row] : nil;
        CGFloat delta = visible ? self.logTable.contentOffset.y - [self.logTable rectForRowAtIndexPath:visible].origin.y : 0;
        self.displayedLogs = latest; [self.logTable reloadData]; [self.logTable layoutIfNeeded];
        if (self.followSwitch.on && latest.count) [self.logTable setContentOffset:CGPointMake(0, -self.logTable.adjustedContentInset.top) animated:NO];
        else if (anchor) {
            NSUInteger index = [latest indexOfObject:anchor];
            if (index != NSNotFound) {
                CGRect rect = [self.logTable rectForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
                [self.logTable setContentOffset:CGPointMake(0, MAX(-self.logTable.adjustedContentInset.top, rect.origin.y + delta)) animated:NO];
            }
        }
    }
    NSArray *events = self.controller.events;
    if (![events isEqualToArray:self.displayedEvents]) {
        self.displayedEvents = events;
        self.eventLabel.text = events.count ? [events componentsJoinedByString:@"\n\n"] : @"暂无业务事件";
    }
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.displayedLogs.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"log"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"log"];
    cell.textLabel.text = self.displayedLogs[indexPath.row]; cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { if (scrollView == self.logTable) self.followSwitch.on = NO; }
- (void)keyboard:(NSNotification *)note {
    CGRect frame = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat height = CGRectGetHeight(CGRectIntersection(self.operations.frame, frame));
    if (!isfinite(height)) height = 0;
    self.operations.contentInset = UIEdgeInsetsMake(0, 0, height, 0); self.operations.verticalScrollIndicatorInsets = self.operations.contentInset;
    UITextField *field = self.hostInput.isFirstResponder ? self.hostInput : self.filterInput.isFirstResponder ? self.filterInput : self.durationInput.isFirstResponder ? self.durationInput : nil;
    if (field) [self.operations scrollRectToVisible:[field convertRect:field.bounds toView:self.operations] animated:YES];
}
- (void)endEditing { [self.view endEditing:YES]; }
- (void)openScan { [self endEditing]; [self.navigationController pushViewController:[[FSCScanViewController alloc] initWithController:self.controller duration:self.durationInput.text ?: @"15"] animated:YES]; }
- (void)connectByID { [self endEditing]; [self.controller connectHostID:self.hostInput.text ?: @"" duration:self.durationInput.text ?: @"15"]; }
- (void)applyFilter { [self endEditing]; [self.controller applyFilter:self.filterInput.text ?: @""]; }
- (void)clearFilter { self.filterInput.text = @""; [self.controller clearFilter]; }
- (void)clearLogs { [self.controller clearLogs]; }
- (void)clearEvents { [self.controller clearEvents]; }
- (void)rawChanged { self.controller.rawLogging = self.rawSwitch.on; }
- (void)followChanged {
    if (self.followSwitch.on && self.displayedLogs.count) [self.logTable setContentOffset:CGPointMake(0, -self.logTable.adjustedContentInset.top) animated:NO];
}
- (void)disconnect { [self endEditing]; [self.controller cancelAndDisconnect]; }
- (void)message:(NSString *)title text:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)shutdownBlocked { [self message:@"关机发送已禁用" text:@"当前1.0 SDK存在通知失败仍回调成功、取消和延迟写风险。必须先由供应方修复、重新交付配套Framework并真机验收，不能在App中强制绕过。\n\n白名单只过滤上报，不限制allshutdown范围；业务ACK不证明全部组网设备断电。"]; }
- (void)shutdown {
    if (!self.controller.canShutdown) { [self shutdownBlocked]; return; }
    NSDictionary *confirmation = self.controller.shutdownConfirmation;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认向全部范围发送关机？" message:[NSString stringWithFormat:@"%@\n\n白名单不限制关机范围。只发送一次；ACK不等于所有组网设备已经断电。", confirmation[@"summary"]] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认关机" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf.controller confirmShutdown:confirmation]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openSettings { NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString]; [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil]; }
- (void)about { [self message:@"FiberSurvey iOS Demo 1.0" text:@"Objective-C/UIKit · 本地BLE · 无网络请求/鉴权。\nSDK：XCFiberCheck 1.0 / BLE 1.0，arm64真机Framework，minOS15.0；App当前最低27.2。\nSDK写入安全门保持关闭，连接结束后重启App再试。\n\n本轮仅完成源码与静态检查，未编译App、未进行真机验证。请参阅docs中的使用说明、SDK交付清单及验证记录。"]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
