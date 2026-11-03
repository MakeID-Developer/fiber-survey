# MkdXCFiberCheckLib — Xince Fiber Identification Instrument iOS SDK

`MkdXCFiberCheckLib` connects to Xince fiber identification instruments (160#, TR-FID series) over BLE, receives fiber matching results and device power events, and provides an all-device shutdown API.

This guide is based on the current public headers and implementation. Last updated: **November 2, 2026**. The Objective-C examples are intended for standalone apps and third-party integrations. This document is not a device compatibility or safety acceptance report. **The example code has not been compiled or validated on physical devices.**

> **Important limitations in the current version:** The BLE transport may report connection success even when notification setup fails. Other risks include incomplete cancellation of asynchronous tasks after disconnection and delayed writes. See Section 10. Neither `connected == YES` nor a connection success callback is sufficient to establish that a device is safely ready. The companion Demo currently allows passive reception for integration testing only; actual shutdown transmission remains disabled. Documenting these APIs does not mean the underlying risks have been fixed.

## Contents

1. Features and Communication Model
2. Integrating the Frameworks
3. Bluetooth Authorization and Lifecycle
4. Public API Reference
5. Scanning, Connection, and Event Examples
6. Device ID Allowlist
7. All-Device Shutdown Example
8. Report Model and Example Messages
9. Error Handling
10. Known Limitations and Integration Constraints
11. Troubleshooting and Delivery Checklist

## 1. Features and Communication Model

### 1.1 Supported Features

- Scan for instrument hosts and receive a `CBPeripheral` and its discovery-time RSSI.
- Connect to a discovered peripheral, or find and connect by device ID/full Bluetooth name.
- Observe system Bluetooth state and connection state.
- Receive `power_up` / `power_down` and `Power_On` / `Power_Off` events.
- Receive raw transmitted/received JSON before filtering, for integration diagnostics.
- Configure an event allowlist using the source `device_id`.
- Send `allshutdown` and receive a device-level ACK callback.

The SDK does not implement login, HTTP requests, tokens, cloud binding, or lock SDK authentication. No AppID/AppSecret is required. Bluetooth communication is not IP networking; integrating this SDK does not require adding network services to the app.

### 1.2 Host, Gateway, and Source Device IDs

The instruments can form a network independently. The phone connects to one host, which acts as a gateway and may forward reports from itself and other networked devices:

```text
Phone app ── Single BLE/GATT link ── Current host/gateway
                                      ├─ Its own events
                                      └─ Events from other networked devices
                                         (distinguished by device_id)
```

- **Connection target:** The host `CBPeripheral` selected by the phone.
- **Source `device_id`:** The device to which a report belongs; not necessarily the connected host.
- Both use the same device numbering scheme. A typical device ID is its Bluetooth name with `TR-FID-` removed. However, the connection target and the source of the current report are separate contexts.
- The SDK singleton manages one BLE link; it does not support simultaneous connections to multiple hosts.
- On iOS, `peripheral.identifier.UUIDString` is a local CoreBluetooth identifier, not a hardware MAC address. Do not use it as a permanent cross-platform identity or proof of authorization.

## 2. Integrating the Frameworks

### 2.1 Required Files

Include both libraries from a matching release, not just the instrument SDK:

```text
YourApp/
├── YourApp.xcodeproj
└── Vendor/
    ├── MkdXCFiberCheckLib.framework
    └── MkdBLEConnectLib.framework
```

The instrument SDK depends on the BLE transport library. System frameworks such as Foundation, CoreBluetooth, and UIKit are linked by Xcode; do not copy system frameworks into the app.

The current delivery uses **dynamic arm64 frameworks for physical iOS devices**, with no Simulator slices. An Apple Silicon Simulator cannot use an iOS device binary even though both use arm64. Do not attempt to bypass platform restrictions with `EXCLUDED_ARCHS`, renamed extensions, or lipo merging.

**Use the actual delivered artifacts as the authority for minimum OS and version.** The previously built pair was version `1.0` / build `1`, with minOS `15.0`. This is not a guarantee for every source build: the instrument framework target currently uses `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)`, and the BLE project has its own settings. A `12.0` value elsewhere in a project does not establish iOS 12 support. The app's deployment target must not be lower than its actual dependencies; API availability and runtime compatibility must also be verified.

### 2.2 Xcode Configuration

1. Copy both complete `.framework` directories into the app project's `Vendor` directory. Use project-relative references, not a developer's temporary `DerivedData` location.
2. Add both frameworks under the app target's **General → Frameworks, Libraries, and Embedded Content**, selecting **Embed & Sign** for each.
3. Check **Build Phases**:
   - **Link Binary With Libraries:** Each library appears once.
   - **Embed Frameworks:** Each library appears once, with **Code Sign On Copy** enabled.
4. If necessary, configure **Framework Search Paths**:

   ```text
   $(inherited)
   $(PROJECT_DIR)/Vendor
   ```

5. Retain `$(inherited)` and `@executable_path/Frameworks` in **Runpath Search Paths**.
6. Sign with your own Team/Profile and select a physical iPhone/iPad. Building an SDK without signing does not mean that installing the app requires no signing.

> **Keep only one embedding mechanism.** If native `Embed Frameworks` is used, do not also copy the same libraries into `App.app/Frameworks` with a Run Script or another Copy Files phase. Two producers declaring the same output cause `Multiple commands produce .../MkdBLEConnectLib.framework` or `.../MkdXCFiberCheckLib.framework`. Prefer native Embed & Sign and remove the duplicate script. Do not hide duplicate writes by merely removing the script's output-paths.
>
> Once native framework link references exist, there is no need to add duplicate `OTHER_LDFLAGS = -framework ...` entries for these libraries. Static and dynamic libraries have different integration requirements. If a future delivery changes library type, reassess the configuration rather than applying these dynamic framework instructions unchanged.

### 2.3 Importing the SDK

```objc
#import <MkdXCFiberCheckLib/MkdXCFiberCheckLib.h>
```

The umbrella header exports `MKDXCFiberCheckManager`, the functions declared in `MKDXCDeviceMatcher`, `MKDXCError`, and `MKDXCModels`. Apps generally do not need to manipulate `MkdBLEConnect` directly.

`MKDXCLog`, the JSON assembler/parser, the write queue, and internal report construction interfaces are not integration entry points exposed by the current public umbrella header. Do not bypass the SDK by importing private source paths.

## 3. Bluetooth Authorization and Lifecycle

### 3.1 Info.plist

Add an accurate usage description to the app's `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Used to discover and connect to fiber identification instruments, receive device events, and send commands after your confirmation.</string>
```

- Initial CoreBluetooth access may trigger a system authorization prompt. Do not rely on the header comment claiming that iOS has no runtime authorization prompt.
- Prefer calling `[MKDXCFiberCheckManager shared]` only after the user requests scanning/connection. Initializing the singleton obtains the BLE transport; initializing it at app launch is not deferred authorization.
- When authorization is denied/restricted, direct the user to system settings as appropriate. Do not repeatedly create central managers or use private APIs to enable Bluetooth.
- Ordinary BLE central functionality does not require adding location access, unrestricted ATS exceptions, or background BLE capabilities. Check legacy usage-description keys against the OS versions actually supported.

### 3.2 State, Threading, and Ownership

- On iOS 13.1 and later, use `CBManager.authorization` to distinguish not determined, restricted, denied, and allowed states. Add availability checks if the app supports older systems.
- The `response` passed to `observeCentralManagerState:` is an `NSNumber` wrapping `CBManagerState`.
- Start scanning/connection only when authorization allows it, Bluetooth is `CBManagerStatePoweredOn`, the app is active, and the current user intent remains valid.
- Unknown/Resetting must not be treated as PoweredOn. The app should impose its own overall waiting deadline, such as 15 seconds, and consume the current user intent only once after prerequisites are satisfied.
- The Manager dispatches public delegate callbacks to the main thread. Scan/connection blocks are generally forwarded to the main thread in the current implementation, but some parameter/not-connected failures can return synchronously on the calling thread. Initiate public operations on the main thread and normalize UI callback handling to the main thread.
- `delegate` is `weak`. The app must strongly retain one business owner; multiple screens must not compete to replace the delegate.
- Pushing/presenting a screen is not the same as entering the background. Do not unconditionally disconnect in the main screen's `viewDidDisappear`, which would disconnect when opening a scanner screen.
- When a Scene is temporarily inactive, disable dangerous operations while retaining unexpired ordinary authorization/scan intent. On actual background entry, business exit, or user cancellation, invalidate app tokens first, then call `stopScan` / `disconnect`, clear filtering, and detach the owner.
- The SDK has no `release`, `init(appId...)`, `requestMtu`, `getMtuSize`, or MAC-based connection API. Do not copy Android API calls into the iOS integration.

## 4. Public API Reference

### 4.1 Manager API

These selectors match the current `Public/MKDXCFiberCheckManager.h`:

| API | Parameters / Return | Behavior and Notes |
| --- | --- | --- |
| `+shared` | Singleton `MKDXCFiberCheckManager *` | First access initializes the transport; business modules share the underlying connection |
| `-sdkVersion` | `NSString *` | Reads the framework's CFBundleShortVersionString first, falling back to 1.0.0 if absent; not every package is therefore version 1.0.0 |
| `-observeCentralManagerState:` | `MKDXCNormalCallback` | State is NSNumber; observes the singleton rather than creating a second BLE owner |
| `-searchDevicesForTimeout:success:complete:fail:` | Seconds, discovery/completion/failure blocks | Returns SDK-matched devices; build the list from success callbacks, not by treating the complete payload as the filtered instrument list |
| `-stopScan` | No return value | Stops scanning; does not guarantee a complete callback or reliable cancellation of connection/other tasks |
| `-connectPeripheral:success:fail:` | `CBPeripheral *`, general callbacks | Use the current scan's result and retain the peripheral; success does not establish safely READY status in the current version |
| `-connectDeviceId:timeout:success:fail:` | ID/full name, scan seconds, general callbacks | Accepts 000002 or TR-FID-000002, case-insensitively; not a connection by identifier or MAC |
| `-disconnect` | No return value | Disconnects and clears pending commands/assembler/write queue; does not guarantee cancellation of all old asynchronous work; see Section 10 |
| `-shutdownAllWithSuccess:failure:` | No-argument success block, NSError failure block | Succeeds only on an allshutdown ACK with status ok (case-insensitive); no automatic retry |
| `-setDeviceIdFilter:` | Nullable `NSArray<NSString *> *` | Replaces the entire event allowlist, without changing scanning or shutdown scope |
| `-clearDeviceIdFilter` | No return value | Restores unrestricted event delivery |

| Property | Type | Meaning |
| --- | --- | --- |
| `delegate` | `weak id<MKDXCFiberCheckDelegate>` | Recipient of unsolicited events; the app must strongly retain the owner |
| `connected` | Read-only `BOOL` | SDK connection state; subject to false-readiness reporting in the current implementation, not a safe-write guarantee |
| `deviceIdFilter` | Read-only `NSSet<NSString *> *` | Allowlist matching keys after trimming and lowercasing; an empty set means filtering is disabled |

Callback types:

```objc
typedef void (^MKDXCDeviceCallback)(CBPeripheral *peripheral, NSNumber *RSSI);
typedef void (^MKDXCNormalCallback)(id response);
typedef void (^MKDXCSuccessCallback)(void);
typedef void (^MKDXCFailureCallback)(NSError *error);
```

Scan duration is in **seconds**. The SDK currently does not uniformly validate finiteness/range. Reject NaN, infinity, zero/negative values, and other invalid inputs in the app; a recommended app-defined range is 1–60 seconds. The transport connection timer is 5 seconds. The ID-based connection's local fallback is `timeout + 5 + 2` seconds (22 seconds when passed 15), but it claims completion as soon as a matching device is found. **It is not a reliable overall timeout covering notification readiness.** The app still needs an overall deadline and task generations.

### 4.2 Unsolicited Event Delegate

| Selector | Purpose |
| --- | --- |
| `xcfiberDidUpdateConnectionState:` | Link-state notification; YES alone must not enable dangerous writes with the current library |
| `xcfiberDidReceivePowerChange:powerUp:` | Source ID + YES(power_up)/NO(power_down), after allowlist filtering; unrecognized values are not silently reported as NO |
| `xcfiberDidReceiveDevicePowerOn:` | Source device powered on; allowlist-filtered |
| `xcfiberDidReceiveDevicePowerOff:` | Source device powered off; allowlist-filtered; not equivalent to disconnection between the phone and host |
| `xcfiberDidReceiveRawJson:isSend:` | JSON before filtering; YES means TX, NO means RX; not proof of GATT write success or command execution |

All delegate methods are optional. Unknown commands, unrecognized power values, and reports excluded by the allowlist may still appear in raw logs. The difference between raw-message and business-callback counts cannot all be attributed to allowlist filtering. Invalid data or data that cannot be assembled into a complete message is not guaranteed to arrive as a complete JSON callback.

### 4.3 Name-Matching Functions

```objc
NSString * _Nullable MKDXCDeviceIdFromName(NSString * _Nullable name);
NSString * _Nullable MKDXCDeviceIdFromPeripheral(CBPeripheral * _Nullable peripheral);
NSString * _Nullable MKDXCDeviceIdFromNameLenient(NSString * _Nullable name);
```

- Strict matching is based on the `TR-FID-` prefix, is case-insensitive, and handles some invisible characters.
- Lenient fallback normalizes, lowercases, and removes non-alphanumeric characters; the derived ID may not retain the firmware's original punctuation. Preserve the original name and ask the user to verify it.
- SDK scanning uses strict matching plus lenient fallback. Do not discard accepted results by applying an additional case-sensitive hasPrefix check in the app.

## 5. Scanning, Connection, and Event Examples

### 5.1 Basic Call Sequence

```text
User requests scanning/connection
  → Obtain shared, bind the single delegate, observe Bluetooth
  → Authorization allowed + PoweredOn + app active
  → Scan and maintain a list keyed by identifier
  → User confirms host → stopScan → connectPeripheral
  → Display SDK connection callbacks/events, without claiming safely READY status
  → Exit/background → invalidate tokens → stopScan/disconnect/clearDeviceIdFilter
```

### 5.2 Passive Reception Example for a Dedicated Owner

This class demonstrates SDK calls and delegate ownership, **without all-device shutdown**. It permits only one business lifecycle; do not reuse it after `close`. Until SDK cancellation guarantees are fixed, do not rapidly switch hosts in the same process simply by creating another owner. A real app still needs list UI, input validation, overall deadlines, Scene active/pending intent management, and late-callback handling. This teaching example is not a complete production state machine.

```objc
#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <MkdXCFiberCheckLib/MkdXCFiberCheckLib.h>

@interface XCFiberSession : NSObject <MKDXCFiberCheckDelegate>
@property (nonatomic, strong) MKDXCFiberCheckManager *sdk;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *devices;
@property (nonatomic) CBManagerState bluetoothState;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSUInteger scanGeneration;
@property (nonatomic) BOOL scanning;
@property (nonatomic) BOOL connectionAttempted;
@property (nonatomic) BOOL closed;
- (void)prepareAfterUserAction;
- (void)scanWhenBluetoothAllowedAndAppActive;
- (void)connectSelectedIdentifier:(NSString *)identifier;
- (void)close;
@end

@implementation XCFiberSession
- (instancetype)init {
    if ((self = [super init])) {
        _devices = [NSMutableDictionary dictionary];
        _generation = 1;
    }
    return self;
}

// Enter from a user action. The Scene/business container strongly retains this owner.
// Do not call this preemptively at app launch.
- (void)prepareAfterUserAction {
    NSAssert(NSThread.isMainThread, @"Initiate public calls on the main thread");
    if (self.closed || self.sdk) return;
    self.sdk = [MKDXCFiberCheckManager shared];
    self.sdk.delegate = self;
    [self.sdk clearDeviceIdFilter];
    NSLog(@"SDK version: %@", [self.sdk sdkVersion]);
    __weak typeof(self) weakSelf = self;
    [self.sdk observeCentralManagerState:^(id response) {
        typeof(self) self = weakSelf;
        if (!self || self.closed || ![response isKindOfClass:NSNumber.class]) return;
        self.bluetoothState = [response integerValue];
        NSLog(@"System Bluetooth state: %@", response);
        // Once authorization and app-active prerequisites are satisfied,
        // consume the current user scan intent once.
        // Do not automatically scan, reconnect, or send commands here.
    }];
}

- (void)scanWhenBluetoothAllowedAndAppActive {
    NSAssert(NSThread.isMainThread, @"Initiate public calls on the main thread");
    if (!self.sdk || self.closed || self.scanning || self.connectionAttempted) return;
    if (self.bluetoothState != CBManagerStatePoweredOn) return;
    if (@available(iOS 13.1, *)) {
        if (CBManager.authorization != CBManagerAuthorizationAllowedAlways) return;
    }
    [self.devices removeAllObjects];
    self.scanning = YES;
    NSUInteger generation = self.generation;
    NSUInteger scan = ++self.scanGeneration;
    __weak typeof(self) weakSelf = self;
    [self.sdk searchDevicesForTimeout:15.0 success:^(CBPeripheral *p, NSNumber *RSSI) {
        typeof(self) self = weakSelf;
        if (!self || self.closed || !self.scanning || self.generation != generation || self.scanGeneration != scan) return;
        self.devices[p.identifier.UUIDString] = p; // Retain; merge by identifier, not name.
        NSString *deviceId = MKDXCDeviceIdFromPeripheral(p);
        if (!deviceId) deviceId = MKDXCDeviceIdFromNameLenient(p.name);
        NSLog(@"name=%@ deviceId=%@ identifier=%@ lastRSSI=%@",
              p.name, deviceId, p.identifier.UUIDString, RSSI);
        // Update the list, preserving name/ID snapshots; do not auto-connect to the first device.
    } complete:^(id response) {
        typeof(self) self = weakSelf;
        if (!self || self.closed || self.generation != generation || self.scanGeneration != scan) return;
        self.scanning = NO;
        NSLog(@"Scan finished; matched devices: %lu", (unsigned long)self.devices.count);
    } fail:^(id response) {
        typeof(self) self = weakSelf;
        if (!self || self.closed || self.generation != generation || self.scanGeneration != scan) return;
        NSLog(@"Scan failed (response may not be NSError): %@", response);
        [self close];
    }];
}

// Identifier must come from this scan's list. Call after user selection/confirmation.
// The caller must recheck app-active state and authorization.
- (void)connectSelectedIdentifier:(NSString *)identifier {
    NSAssert(NSThread.isMainThread, @"Initiate public calls on the main thread");
    if (self.closed || self.connectionAttempted || self.bluetoothState != CBManagerStatePoweredOn) return;
    CBPeripheral *peripheral = self.devices[identifier];
    if (!peripheral) return;
    self.connectionAttempted = YES;
    self.scanning = NO;
    self.scanGeneration++; // Invalidate scan callbacks first; stopScan does not guarantee complete.
    [self.sdk stopScan];
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    [self.sdk connectPeripheral:peripheral success:^(id response) {
        typeof(self) self = weakSelf;
        if (!self || self.closed || self.generation != generation) return;
        NSLog(@"SDK connection success: %@; current library is not safety-validated; do not enable shutdown", response);
    } fail:^(id response) {
        typeof(self) self = weakSelf;
        if (!self || self.closed || self.generation != generation) return;
        NSLog(@"Connection failed/disconnected: %@", response);
        [self close];
    }];
}

- (void)xcfiberDidUpdateConnectionState:(BOOL)connected {
    if (self.closed) return;
    NSLog(@"SDK connection state=%d", connected);
    if (!connected && self.connectionAttempted) [self close];
}
- (void)xcfiberDidReceivePowerChange:(NSString *)deviceId powerUp:(BOOL)powerUp {
    if (!self.closed) NSLog(@"Source %@: %@", deviceId, powerUp ? @"power_up" : @"power_down");
}
- (void)xcfiberDidReceiveDevicePowerOn:(NSString *)deviceId {
    if (!self.closed) NSLog(@"Source %@: Power_On", deviceId);
}
- (void)xcfiberDidReceiveDevicePowerOff:(NSString *)deviceId {
    if (!self.closed) NSLog(@"Source %@: Power_Off (not proof of host link disconnection)", deviceId);
}
- (void)xcfiberDidReceiveRawJson:(NSString *)json isSend:(BOOL)isSend {
    if (!self.closed) NSLog(@"[%@] %@", isSend ? @"TX" : @"RX", json);
    // Real apps need a raw-log switch, length/count limits, and a privacy policy; no default uploads.
}
- (void)close {
    NSAssert(NSThread.isMainThread, @"Initiate public calls on the main thread");
    if (self.closed) return;
    self.closed = YES;
    self.generation++;
    self.scanGeneration++;
    self.scanning = NO;
    [self.sdk stopScan];
    [self.sdk disconnect];
    [self.sdk clearDeviceIdFilter];
    if (self.sdk.delegate == self) self.sdk.delegate = nil;
    [self.devices removeAllObjects];
    // Cancellation is incomplete in the current library: invalidating tokens does not
    // prove transport cancellation. Do not rapidly create another owner and reconnect.
}
@end
```

### 5.3 Convenience API: Connect by Device ID

If the vendor confirms that cancellation and timeout behavior in the relevant version meets your requirements, use:

```objc
// Call within an existing authorization gate and single owner,
// with no other scan/connection in flight.
MKDXCFiberCheckManager *manager = [MKDXCFiberCheckManager shared];
[manager connectDeviceId:@"000002" // Also accepts @"TR-FID-000002".
                 timeout:15.0
                 success:^(id response) {
    NSLog(@"SDK connection callback: %@ (the version's readiness constraints still apply)", response);
} fail:^(id response) {
    NSLog(@"Connection by ID failed: %@", response);
}];
```

Do not run this concurrently with the scan in Section 5.2, as it would overwrite singleton requests. The current standalone Demo instead uses “public scan → ID matching → `connectPeripheral`” to preserve host snapshots and avoid this convenience method's local fallback cancellation risk. That does not fix the underlying transport cancellation issues.

## 6. Device ID Allowlist

```objc
MKDXCFiberCheckManager *manager = [MKDXCFiberCheckManager shared];
[manager setDeviceIdFilter:@[@"000002", @"000011", @"A-1"]];
NSLog(@"SDK matching keys: %@", manager.deviceIdFilter);

[manager clearDeviceIdFilter];      // Restore unrestricted event delivery.
// [manager setDeviceIdFilter:nil]; // Also disables filtering.
// [manager setDeviceIdFilter:@[]]; // Also disables filtering.
```

- Array entries are **source device IDs**, not full Bluetooth names. Matching only trims whitespace and ignores case. It does not remove `TR-FID-`, strip punctuation, or convert IDs to numbers.
- `A-1` differs from `A1`, and `000011` differs from `11`. Duplicate matching keys are deduplicated.
- nil, an empty array, or whitespace-only entries disable filtering. When a nonempty allowlist is enabled, reports without a source ID do not reach business callbacks.
- **Only business events are filtered. Scanning, raw messages, and shutdown ACKs are not filtered, and the allowlist does not limit allshutdown scope.**
- Allowlisting only the host ID hides other networked devices' business events; it does not mean those devices did not report.
- The SDK does not accept comma-separated text as an input format. Apps with input fields must split the text, validate count/length, and display which filter has actually been applied.
- Explicitly apply/clear filtering when entering a session, and clear it on exit. Do not rely on leftover singleton settings.

## 7. All-Device Shutdown Example

> **Dangerous operation: Do not enable actual transmission until the risks in Section 10 have been fixed and validated on devices.** Do not use automatic shutdown as a connection probe. The following only shows the API call location. `NO` is a source-level safety gate; do not change it to YES merely to try a button.

```objc
// Called by the app's single command owner; not an additional SDK API.
static void SendShutdownAfterAppConfirmation(BOOL userConfirmed,
                                            BOOL appSessionReady,
                                            BOOL commandPending) {
    static const BOOL SDKWriteSafetyValidated = NO;
    MKDXCFiberCheckManager *manager = [MKDXCFiberCheckManager shared];
    if (!SDKWriteSafetyValidated || !userConfirmed || !appSessionReady ||
        commandPending || !manager.connected) {
        NSLog(@"Shutdown not sent: SDK unvalidated/unconfirmed/invalid session/command pending/disconnected");
        return;
    }
    // After fixes and acceptance, the app must also synchronously mark pending here
    // and freeze sessionId/operationId/target.
    [manager shutdownAllWithSuccess:^{
        NSLog(@"Received allshutdown business ACK with status=ok; not proof that all networked devices powered off");
        // Complete the operation once and close this session; do not resend/auto-reconnect.
    } failure:^(NSError *error) {
        NSLog(@"Shutdown unconfirmed: %@ / %ld / %@",
              error.domain, (long)error.code, error.localizedDescription);
        // Physical outcome may be unknown after timeout/disconnection/write failure.
        // Verify first; do not automatically resend.
    }];
}
```

Integration requirements:

1. The confirmation dialog must show the host name, ID, identifier, and “all devices” scope, explaining that the allowlist does not restrict shutdown.
2. After confirmation, recheck app-active state, authorization/Bluetooth, target, and session/operation. An old dialog must not send to a new target.
3. While a shutdown is in flight, prevent duplicate sends, scanning, connection attempts, and target switching. A new same-command request may replace a pending SDK request; that is not app-level duplicate prevention.
4. The SDK ACK deadline is **5 seconds**. The app may add its own final fallback, such as 8 seconds, but must complete the operation only once and preserve the meaning of SDK errors.
5. The protocol has no app transaction sequence number for reliably correlating late ACKs. Do not repeatedly send shutdown in the same session. Conservatively close the session after completion, without automatic retry or reconnection.
6. A TX raw-message callback means the SDK is preparing transmission, not that a GATT write succeeded. A successful GATT write is not a device-level ACK, and neither proves that all devices have powered off.

## 8. Report Model and Example Messages

### 8.1 `MKDXCReport`

The public model fields are listed below, but the Manager's public delegate **does not directly return MKDXCReport instances**. It exposes interpreted results through separate callbacks and delivers raw JSON separately. Do not assume there is a public parse method or treat the internal `MKDXCResponseParser` as a host-app API.

| Field | Meaning |
| --- | --- |
| `type` | MKDXCReportType: PowerChange, DevicePowerOn, DevicePowerOff, ShutdownAck, Unknown |
| `rawCommand` / `command` | Original cmd / normalized comparison key |
| `deviceId` | Source ID; may be nil |
| `powerUp` / `powerChangeRecognized` | Matching value and recognition flag; meaningful only for a recognized PowerChange report |
| `status` / `ackOK` | Top-level ACK status and success flag; meaningful only for ShutdownAck |
| `rawJSON` | Original JSON text |

### 8.2 Example Messages

These examples illustrate fields only. The device firmware and actual raw messages determine real spelling and network behavior. Apps do not need to construct/parse these messages themselves in place of the SDK.

```json
{"cmd":"detected_powerchange","content":{"device_id":"000011","power_change":"power_up"}}
```

```json
{"cmd":"Power_On","content":{"device_id":"000011"}}
```

```json
{"cmd":"Power_Off","content":{"device_id":"000011"}}
```

All-device shutdown request and ACK:

```json
{"cmd":"allshutdown"}
```

```json
{"cmd":"allshutdown","status":"ok"}
```

The SDK UTF-8 encodes the request, currently 21 bytes, without trailing CR/LF. The ACK status is at the **top level**. Missing, empty, or non-ok status is not success; the current parser compares ok case-insensitively. Unknown commands/unrecognized power values only produce raw messages/logs, not fabricated power_down events.

## 9. Error Handling

Error domain: `MKDXCErrorDomain`, whose string value is `com.makeid.MkdXCFiberCheckLib.error`.

| Enum | Value | Meaning |
| --- | --- | --- |
| `MKDXCErrorBluetoothUnavailable` | 1000 | Bluetooth unavailable |
| `MKDXCErrorBluetoothUnauthorized` | 1001 | Bluetooth authorization unavailable |
| `MKDXCErrorScanFailed` | 1002 | Scan failed |
| `MKDXCErrorConnectFailed` | 1003 | Connection failed/disconnected, including some device-ID-not-found cases |
| `MKDXCErrorNotConnected` | 1004 | Not currently connected |
| `MKDXCErrorInvalidParameter` | 1005 | Invalid parameter |
| `MKDXCErrorWriteFailed` | 1006 | Write failed |
| `MKDXCErrorTimeout` | 1007 | Request timed out/replaced by a new same-command request |
| `MKDXCErrorProtocolError` | 1008 | Protocol format/construction error |
| `MKDXCErrorDeviceError` | 1009 | ACK status is non-ok or missing |

`MKDXCError` provides the helper constructors `+errorWithCode:message:` and `+deviceErrorWithStatus:`. The latter preserves the original status under the userInfo `status` key (an empty string if absent).

**An enum's existence does not mean every underlying failure is converted into that NSError.** Scan/connection failure callbacks use `MKDXCNormalCallback(id)` and may receive a string or another response type. Check the type first:

```objc
static NSString *DescribeXCFiberFailure(id response) {
    if ([response isKindOfClass:NSError.class]) {
        NSError *error = (NSError *)response;
        return [NSString stringWithFormat:@"%@ / %ld / %@",
                error.domain, (long)error.code, error.localizedDescription];
    }
    return [NSString stringWithFormat:@"Transport did not provide NSError: %@", response ?: @"No details"];
}
```

The UI should show the operation, target, error domain/code/description, and whether the result is unknown. Keep bounded logs. Absence of a fail callback is not success; do not assume that every underlying stage always delivers a callback.

## 10. Known Limitations and Integration Constraints

These observations concern the current source and must be reassessed after vendor upgrades. This document does not modify or fix the implementation.

| Risk | Current Behavior | Integration Constraint |
| --- | --- | --- |
| False readiness reporting | The BLE notification callback may invoke connectSuccess even with an error; Manager success then directly sets connected | Success blocks/connected/a raw message do not establish safely READY status. Do not probe with shutdown. Block actual writes until fixes and acceptance |
| Incomplete asynchronous cancellation | disconnect does not uniformly cancel all transport timers/callbacks; connectDeviceId's local fallback has no public cancellation handle | App tokens isolate app-level stale results, not transport actions. Avoid rapid reentry/target switching; the current Demo requires restarting the app after closing a session |
| Stale delayed writes | WriteQueue.reset clears the queue, but a delayed block that already captured data has no generation check | Subsequent connections may be affected. Sleeping is not proof of safe cleanup; vendor generation/cancellation fixes are needed |
| Assembler cleanup race | assembler reset and protocolQueue receive parsing may execute outside a shared serial context | Calling all app APIs on main does not prove that SDK internals are race-free; cleanup must be serialized by the vendor |
| Empty/cached scan names | The transport checks peripheral.name before processing advertisement LocalName and uses KVC to overwrite name | A device with only an advertisement name and an empty cached name may be missed. The app's list cannot recover it; do not copy the KVC approach |
| Write capability/error propagation | writeData submits a whole packet without public length/fragmentation/backpressure guarantees; didWrite errors do not guarantee complete business-failure propagation | Even the 21-byte JSON requires device validation. Do not claim MTU512/automatic fragmentation or bypass the SDK to split data |
| Singleton configuration conflicts | Multiple device SDKs share MkdBLEConnect and can overwrite UUIDs/notification/state listeners | Keep one business owner at a time; do not let unrelated SDKs use the transport concurrently |

In particular, do not set `MkdBLEConnect.connectionStateChangedBlock`, `recvDataCallback`, UUIDs, or rawNotifyPassthrough yourself. The instrument SDK configures these; replacing them breaks its state and parsing chain. An app raw-message display switch does not disable SDK/transport console logging. Review logging privacy separately before release.

## 11. Troubleshooting and Delivery Checklist

| Symptom | What to Check |
| --- | --- |
| Multiple commands produce the same Framework | Native Embed plus a custom copy script/duplicate Copy Files phase; keep one embed entry per library |
| dyld Library not loaded | Both dynamic libraries must be Embed & Sign; check signing/runpaths/@rpath and whether only the instrument library was embedded |
| Building for iOS Simulator while linking an iOS library | The package has device slices only. Select a physical device; Simulator support requires a separate vendor delivery for the correct platform |
| Module/header/symbol not found | Complete Framework directories, search paths, matching BLE version, Headers/modulemap, and link references |
| No scan results | Usage description, authorization, PoweredOn, device power, advertisement name, and the empty-name transport risk; header comments do not rule out authorization prompts |
| Callbacks suddenly disappear | Owner released (weak delegate), another screen/SDK replaced the singleton delegate or transport callbacks |
| Raw messages but no business events | Allowlist keys, source ID, unknown cmd, unrecognized power values; not all missing callbacks are allowlist rejections |
| Shutdown success but devices remain powered | Success only means a business ACK. Verify network scope/firmware/physical power; do not automatically send again |
| Old results after disconnect/impact on a new host | Apply Section 10's cancellation/delayed-write constraints. Ignoring callbacks in the UI does not fix the SDK |

Before delivery to a third party, check:

- Both frameworks' versions, source, platform/architecture, actual minOS, dynamic dependencies, public headers/modulemaps, and paired hashes. Do not compare re-signed app binaries directly with original Vendor hashes.
- A single set of link/embed entries for each library; your own Team/Profile; no personal private keys or provisioning profiles; no dependency on the original comprehensive app or developer-specific absolute paths.
- Actual test records for authorization, host/source separation, cancellation/background/timeout/late callbacks, filtering, and log limits.
- Explicit fixes and validation evidence for Section 10's risks. Restrict functionality when unresolved; “build succeeded” does not mean “safe to transmit.”
- The standalone example at `fiber-survey/iOS/FiberSurvey` has usage instructions and validation records for reference. It is not a runtime dependency of this SDK and must not become a mandatory developer-specific absolute path for third parties.

**This documentation work only adds a README and performs static documentation/API checks. It does not modify SDK code or project settings, compile, build, package, or test devices. Physical-device validation has not been performed.**
