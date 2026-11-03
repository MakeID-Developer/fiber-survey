#import "FSCScanViewController.h"
#import "FSCFiberSurveyController.h"
@interface FSCScanViewController ()
@property (nonatomic, strong) FSCFiberSurveyController *controller;
@property (nonatomic, copy) NSString *duration;
@property (nonatomic) NSUInteger scanID;
@property (nonatomic) BOOL selected;
@property (nonatomic, copy) NSArray<FSCScanItem *> *displayedItems;
@end
@implementation FSCScanViewController
- (instancetype)initWithController:(FSCFiberSurveyController *)controller duration:(NSString *)duration {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _controller = controller; _duration = duration.copy; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"选择信测对纤仪主机";
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 130;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"重新扫描" style:UIBarButtonItemStylePlain target:self action:@selector(rescan)];
    self.tableView.accessibilityLabel = @"扫描到的主机，点选后确认连接";
    __weak typeof(self) weakSelf = self;
    self.controller.scanChanged = ^{ [weakSelf refresh]; };
    [self rescan];
}
- (void)rescan {
    if ([self.controller startScanWithDuration:self.duration]) self.scanID = self.controller.session.scanID;
    [self refresh];
}
- (void)refresh {
    self.navigationItem.rightBarButtonItem.enabled = self.controller.canStart && self.controller.session.phase != FSCSessionScanning;
    self.displayedItems = self.controller.scanItems;
    [self.tableView reloadData];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%@\n%@\n只列出SDK发现的设备，最多200台。RSSI为最后发现快照，不是实时值。", self.controller.statusText, self.controller.bluetoothText];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.displayedItems.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"host"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"host"];
    FSCScanItem *item = self.displayedItems[indexPath.row];
    cell.textLabel.text = item.name; cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cell.textLabel.numberOfLines = 0; cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = item.summary; cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *items = self.displayedItems;
    if (indexPath.row >= items.count) return;
    FSCScanItem *item = items[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认连接此主机？" message:[item.summary stringByAppendingString:@"\n\n当前SDK只允许被动接收，关机发送被安全阻断。"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    NSUInteger scanID = self.scanID;
    [alert addAction:[UIAlertAction actionWithTitle:@"连接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) self = weakSelf; if (!self || !self.controller.session.active || scanID != self.controller.session.scanID) return;
        [self.controller selectItem:item scanID:scanID];
        if (self.controller.session.connectionAttempted) { self.selected = YES; [self.navigationController popViewControllerAnimated:YES]; }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || !self.navigationController) {
        self.controller.scanChanged = nil;
        if (!self.selected) [self.controller cancelScan:self.scanID];
    }
}
@end
