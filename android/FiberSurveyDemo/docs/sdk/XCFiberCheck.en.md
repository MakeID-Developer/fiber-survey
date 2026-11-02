> SDK接口资料快照（2026-11-02）。Demo实际实现/验收状态以根README和验证记录为准，不表示所有SDK能力均已运行验证。

# MkdXCFiberCheckLib Android SDK User Guide

[English](XCFiberCheck.en.md) | [Chinese](XCFiberCheck.zh.md)

## 1. Overview and Scope

`MkdXCFiberCheckLib` connects an Android phone to a **TR-FID-series fiber identification host** over BLE. It receives detector power-change and power-on/off events and sends a shutdown-all command.

| Item | Current Source Configuration |
| --- | --- |
| Version | `1.0`; the matching AAR delivery manifest takes precedence |
| Documentation reviewed | `2026-10-30` |
| Package | `com.makeid.mkdxcfiberchecklib` |
| Entry point | `XCFiberCheckManager.getInstance()` |
| Android / Java | `minSdk 21`, `compileSdk 34`, Java 8 |
| Required module | `MkdBLEConnectLib` |
| Target device names | Start with `TR-FID-`, e.g. `TR-FID-000002` |
| Features | Host scanning/connection, detector event listeners and ID allowlist, shutdown-all, raw JSON debugging |

This is not `MkdFiberClearLib`: it does not provide C42 instrument OPM configuration, ONU/OTDR tests, or SOR downloads. Detectors report through the host and are not independent BLE peripherals that the phone can connect to separately.

**Verification status: this guide was statically checked against the current source. No compilation, build, packaging, or physical-device verification has been performed.**

## 2. Third-Party AAR Setup

### 2.1 Delivery Files and Dependencies

The current `build.gradle` uses ordinary `implementation project(':MkdBLEConnectLib')` dependency linkage; it does not embed the BLE library in this AAR. Third parties need both matching files from the same delivery:

```text
app/libs/
├── MakeID_XCFiberCheckLib_1.0.aar
└── makeid_bleconnectlib_1.1.aar
```

Include `google()` and `mavenCentral()` in the host's existing `settings.gradle` repository configuration. App module example:

```groovy
android {
    compileSdk 34
    defaultConfig { minSdk 21 }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}
dependencies {
    implementation files('libs/MakeID_XCFiberCheckLib_1.0.aar')
    implementation files('libs/makeid_bleconnectlib_1.1.aar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    // The BLE module also depends on Material. Local AARs have no Maven POM, so declare it explicitly.
    implementation 'com.google.android.material:material:1.10.0'
}
```

Use the actual delivered filenames. The AppCompat version matches the business module; Material uses a compatible example version. These are not claims about the latest releases. Align compatible versions in the host, and do not include duplicate AARs, JARs, or equivalent source modules. Use `implementation project(':MkdXCFiberCheckLib')` plus the BLE project dependency only inside the source project.

`org.json:json:20180813`, JUnit, and AndroidX test dependencies are for the library's tests, not host runtime dependencies. Android supplies `org.json`. The SDK itself does not require XXPermissions or RxJava.

### 2.2 Native Libraries, ABI, and Obfuscation

- `libmkdxcfiberchecklib.so` uses cJSON to identify JSON frame boundaries. No `abiFilters` are configured in the current Gradle file; this does not mean every ABI is included in the delivery. Check `jni/<abi>/` in the actual AAR against the host process architecture.
- AAR consumers do not need to copy CMake/NDK configuration. The source currently uses NDK `28.2.13676358`; verify 16 KB page compatibility of the actual SO files and application package separately.
- AAR consumer rules preserve `com.makeid.mkdxcfiberchecklib.utils.XcJsonNative` and native method names. Ensure the host applies them. Verify reflective BLE dispatch in an obfuscated release; if necessary, initially keep `com.makeid.blelibrary.**` conservatively and narrow the rules later.
- **When SO loading fails**, `XcJsonNative.isAvailable()` is false and `CJsonFrameProbe` automatically uses `JavaFrameProbe`, logging the load failure. This is not a guarantee that all native failures trigger fallback.
- If the SO loads but a native call fails, `frameLengthSafe(...)` catches the exception and returns `-1`; that path does not switch to Java automatically and may keep waiting for more bytes. Check native-call logs when RX_HEX appears without RX_JSON.

## 3. Manifest and Permissions

This example assumes `targetSdk >= 31` and no derivation of physical location from BLE scans. Merge it into the host Manifest for the actual use case and inspect the Merged Manifest:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.BLUETOOTH"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
</manifest>
```

- Android 12/API 31 and later: request `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` at runtime. Android 6-11/API 23-30: request location permissions and enable location services. API 21-22 has no runtime permission dialog.
- `neverForLocation` must reflect actual use and can filter some advertisements. Verify it with target TR-FID devices. If location is needed, adjust the configuration instead of copying a no-location declaration.
- The SDK does not request permissions or enable Bluetooth. The host handles denial, disabled Bluetooth, and permission revocation. These operations do not require camera, file, NFC, or all-files-access permissions.
- This module's Manifest is empty, but the matching BLE AAR merges Bluetooth/location permissions. A single module Manifest does not describe the final host permissions.

## 4. Integration Sequence and Device Identity

1. Call `init` with an `Application` and register unsolicited-report listeners. No lock-library AppID/secret authentication is required.
2. Obtain permissions and enable Bluetooth. Older Android versions also require location services.
3. Select a host: choose a scanned `Device`, connect using a valid MAC address, or call `connectByDeviceId` to scan for a host serial number. Choose one method; do not run them concurrently.
4. Wait for `onReady`, not just `onConnected` / `isConnected()`. The internal sequence is service discovery → request MTU 512 → enable FFE4 notifications. MTU failure can continue using defaults; actual MTU 512 is not guaranteed.
5. Receive detector events. Configure an allowlist using detector label identifiers if needed. Send shutdown-all only after explicit user confirmation, never automatically upon readiness.
6. On page exit, invalidate the session, stop scanning, remove data listeners, and release an exclusively owned session. Shared use must release only when the last consumer exits.

| Name | Example | Purpose |
| --- | --- | --- |
| Host BLE name | `TR-FID-000002` | Name of the BLE peripheral actually connected to the phone |
| Host ID / serialNo | `000002` | Target for `connectByDeviceId`; the full host name is also accepted. Preserve leading zeros |
| Host BLE MAC | `AA:BB:CC:DD:EE:FF` | Address for `connect(String, ...)`, not a detector ID |
| Detector ID | `000011`, `A-1` | Report `content.device_id`, used to identify reports and apply the allowlist |

Matching a host name is not business identity authentication. Advertised names can be duplicated or spoofed; sensitive operations require binding information and on-site confirmation. `setDeviceIdFilter` is only a local report filter, not access control, and does not restrict shutdown-all scope.

## 5. API Reference

Class: `com.makeid.mkdxcfiberchecklib.XCFiberCheckManager`. Return type is `void` unless otherwise noted. Business callbacks are in `.listener`; scan types come from `com.makeid.blelibrary`.

| API | Description |
| --- | --- |
| `static XCFiberCheckManager getInstance()` | Process-wide singleton |
| `init(Application application)` | Initialize BLE configuration and register observation before use |
| `release()` | Post asynchronous cleanup: terminate pending shutdown requests, clear assembly state, release connections, and unregister observation; call init before reuse |
| `startScan(long timeoutMillis, ScanListener listener)` | Refresh the `TR-FID-` prefix filter and scan; 0 or less uses 15000ms, very large values are capped at the maximum int; replaces the previous scan |
| `stopScan()` | Asynchronously stop scanning and remove this API's listener |
| `boolean isScanning()` | Current scan state |
| `connect(Device device, XCConnectListener listener)` | Connect a scanned device, disconnect existing connections, and terminate pending shutdown requests |
| `connect(String address, XCConnectListener listener)` | Connect a valid MAC address; invalid addresses may throw synchronously, so validate first |
| `connectByDeviceId(String deviceId, XCConnectListener listener)` | Scan/connect by host serial number, with a default 15-second scan |
| `connectByDeviceId(String deviceId, long scanTimeoutMillis, XCConnectListener listener)` | Specify the scan duration; trim, remove the prefix, and compare case-insensitively without numeric conversion |
| `disconnect()` | Asynchronously disconnect all BLE connections; auto-reconnect is disabled |
| `boolean isConnected()` | Whether the recorded device is connected; not equivalent to readiness |
| `boolean isReady()` | Whether notifications are enabled; only then are commands allowed |
| `int getMtuSize()` | Recorded MTU, initially 23; not proof of session readiness |
| `int getPackageSize()` | Recorded `max(20, mtu-3)`, initially 20; for display only. Actual fragmentation uses the underlying MTU |
| `shutdownAll(XCCommandCallback callback)` | Send shutdown-all and await protocol ACK; prevent repeated taps |
| `setOnPowerChangeListener(OnPowerChangeListener listener)` | Power-change events; null removes |
| `setOnDevicePowerListener(OnDevicePowerListener listener)` | Detector power-on/off events; null removes |
| `setRawJsonListener(RawJsonListener listener)` | Debug JSON send/receive; null removes |
| `setDeviceIdFilter(String... deviceIds)` | Set the detector allowlist |
| `setDeviceIdFilter(Collection<String> deviceIds)` | Collection overload; avoid an untyped null because overload resolution would be ambiguous |
| `clearDeviceIdFilter()` | Clear the allowlist and allow all reports |
| `Set<String> getDeviceIdFilter()` | Immutable snapshot; members retain their original identifiers with surrounding whitespace trimmed |
| `boolean isDeviceIdFilterEnabled()` | Whether the allowlist is active |

### 5.1 Connection and Scan Callbacks

```java
public interface XCConnectListener {
    void onConnected(Device device); // Service discovery completed; not ready yet.
    void onReady(Device device, int mtu, int packageSize);
    void onDisconnected();
    void onFailed(String message);
}
```

Use `com.makeid.blelibrary.ble_callback.ScanListener`, which provides `onScanStart()`, `onScanStop()`, `onScanResult(Device, boolean)`, and `onScanError(ScannerExceptionType, String)`. Do not use MkdLockLib's custom scan interface.

**Threading:** normal connection events, business events parsed from notifications, and shutdown command callbacks are dispatched through the main-thread Handler. Ordinary scan listeners directly forward underlying callbacks; early failures in `connect(String, ...)`, such as an unavailable Bluetooth adapter, may synchronously call back on the caller's thread. Do not assume every callback is on main. Dispatch UI work to main and perform state/session operations on main.

Most actions are asynchronous `mainHandler.post` tasks. A getter read immediately after `connect/release/stopScan` may still reflect old state; a snapshot is not an action-completion notification.

### 5.2 Shutdown-All Results

```java
manager.shutdownAll(new XCCommandCallback() {
    @Override public void onSuccess() {
        // A shutdown ACK with status=ok was received; this does not prove every detector physically powered off.
    }
    @Override public void onFailed(String message) {
        android.util.Log.e("XCDemo", "shutdownAll: " + message);
    }
});
```

- The 5000ms timeout starts when the SDK registers the request and includes writing and waiting for ACK. It does not promise that a normal ACK always arrives within tens of milliseconds.
- ACK, timeout, disconnection, release, and replacement all remove registered requests through `finishPending`, preventing duplicate callbacks for one request. Repeated sending is not recommended: the protocol has no request sequence number, so late ACKs cannot reliably distinguish old and new operations.
- Only `status` equal to `ok` (case-insensitive) is success. A GATT write alone is not business success. Timeout/disconnection does not prove non-execution; do not resend automatically.

| Example Failure Message | Meaning |
| --- | --- |
| `not ready` | Notifications not ready or connection object absent |
| `timeout waiting for ACK` | ACK not completed within 5 seconds; inspect notifications and raw logs |
| `disconnected before ACK` | Disconnected before ACK; execution result may be unknown |
| `rejected: status=...` | ACK received but status was not ok |
| `superseded by a new request` | Replaced by the next identical command |
| `new connection` / `sdk released` | Pending request ended by a new connection or release |

Connection failures use `XCConnectListener.onFailed(String)` without a unified numeric error code. Common messages include `empty device id`, `device not found: ...`, `connect failed: ...`, and `connect timeout: ...`. Record the full message; do not treat text as a stable business enum.

## 6. Unsolicited Reports and Detector Filtering

```java
manager.setOnPowerChangeListener((deviceId, powerUp) -> {
    // deviceId identifies a detector; true=power_up, false=power_down or an unrecognized value.
});
manager.setOnDevicePowerListener(new OnDevicePowerListener() {
    @Override public void onDevicePowerOn(String deviceId) { }
    @Override public void onDevicePowerOff(String deviceId) { }
});
manager.setRawJsonListener(new RawJsonListener() {
    @Override public void onSend(String json) { /* About to submit a write, not device confirmation. */ }
    @Override public void onReceive(String json) { /* Complete, assembled JSON. */ }
});
```

`OnPowerChangeListener` returns `(String deviceId, boolean powerUp)`, not a numerical power-meter reading. `PowerChangeEvent` and `DevicePowerEvent` are optional models; the Manager does not directly return these entities through its current callbacks.

```java
manager.setDeviceIdFilter("000011", "A-1");
boolean enabled = manager.isDeviceIdFilterEnabled();
java.util.Set<String> allowed = manager.getDeviceIdFilter();
manager.clearDeviceIdFilter(); // Explicitly clear when the allowlist is no longer needed.
```

- Null, an empty collection, or all-whitespace entries disable filtering. A nonempty allowlist accepts matching IDs only; reports with missing IDs are rejected.
- Match after trimming, case-insensitively, without removing punctuation: `A-1` differs from `A1`, and `000011` differs from `11`.
- Filtering affects only business dispatch for `detected_powerchange`, `Power_On`, and `Power_Off`. Shutdown ACKs and raw JSON are unaffected; the device still transmits all reports.
- `disconnect/release/init` do not reset the allowlist or application data listeners. Explicitly configure or clear them for each session rather than relying on a previous page's state.
- Parsing tolerates some spelling differences by ignoring case/separators in command/field comparisons and accepting aliases such as power_change / pow_change. This does not extend or change the device protocol.
- If `power_change` is missing or unknown, `isPowerUp()` is false and the callback may look like power_down. False alone is not proof of a real decrease; verify fields using raw JSON and warning logs.

### 6.1 Host Information Wrapper

```java
XcDevice xc = new XcDevice(device); // com.makeid.mkdxcfiberchecklib.entity.XcDevice
String name = xc.getName();
String address = xc.getAddress();
String hostId = xc.serialNo();
Device original = xc.getDevice();
```

`serialNo()` strips the exact `TR-FID-` prefix and returns an empty string for a nonmatching name. Its matching details differ from the case-insensitive `connectByDeviceId`. Preserve leading zeros and do not use the host serial number as a detector ID.

## 7. Complete Java Integration Example

This example exclusively owns the SDK on one page and connects using the **user-selected host serial number**; it never shuts down automatically. Register `com.example.xcdemo.XCDemoActivity` in the host Manifest (`android:exported="false"`) and launch internally with a string extra `hostId`, e.g. `000002`. If initialization already belongs to an application-level component, integrate session ownership there instead of having multiple pages init/release the same BLE singleton.

```java
package com.example.xcdemo;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.makeid.blelibrary.bean.Device;
import com.makeid.mkdxcfiberchecklib.XCFiberCheckManager;
import com.makeid.mkdxcfiberchecklib.listener.OnDevicePowerListener;
import com.makeid.mkdxcfiberchecklib.listener.XCCommandCallback;
import com.makeid.mkdxcfiberchecklib.listener.XCConnectListener;

public final class XCDemoActivity extends Activity {
    private static final int REQUEST_BLE = 1001;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final XCFiberCheckManager manager = XCFiberCheckManager.getInstance();
    private String hostId;
    private boolean ownsSession;
    private boolean closed;
    private boolean connecting;
    private boolean ready;
    private boolean commandPending;
    private final Runnable readyDeadline = () -> {
        if (closed || ready || !connecting) return;
        connecting = false;
        manager.stopScan();
        manager.disconnect();
        Log.e("XCDemo", "Connection not ready; reopen the page and reconnect. Do not resend automatically");
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        hostId = getIntent().getStringExtra("hostId");
        if (hostId == null || hostId.trim().isEmpty()) {
            Log.e("XCDemo", "Pass the user-selected host serial number as hostId");
            finish();
            return;
        }
        manager.init(getApplication());
        ownsSession = true;
        manager.clearDeviceIdFilter(); // Replace with business-confirmed detector IDs if report filtering is needed.
        manager.setOnPowerChangeListener((id, powerUp) -> main.post(() -> {
            if (!closed) Log.i("XCDemo", "detector=" + id + ", powerUp=" + powerUp);
        }));
        manager.setOnDevicePowerListener(new OnDevicePowerListener() {
            @Override public void onDevicePowerOn(String id) { reportPower(id, true); }
            @Override public void onDevicePowerOff(String id) { reportPower(id, false); }
        });
        requestBlePermissions();
    }

    private void reportPower(String id, boolean on) {
        main.post(() -> {
            if (!closed) Log.i("XCDemo", "detector=" + id + ", on=" + on);
        });
    }

    private String[] requiredPermissions() {
        if (Build.VERSION.SDK_INT >= 31) {
            return new String[]{Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT};
        }
        return new String[]{Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION};
    }

    private void requestBlePermissions() {
        if (Build.VERSION.SDK_INT < 23) { connectHost(); return; }
        for (String permission : requiredPermissions()) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(requiredPermissions(), REQUEST_BLE);
                return;
            }
        }
        connectHost();
    }

    @Override public void onRequestPermissionsResult(int code, String[] names, int[] results) {
        super.onRequestPermissionsResult(code, names, results);
        if (code != REQUEST_BLE || closed || results.length == 0) return;
        for (int result : results) {
            if (result != PackageManager.PERMISSION_GRANTED) {
                Log.e("XCDemo", "Bluetooth permission denied; resolve it in Settings");
                return;
            }
        }
        connectHost();
    }

    private void connectHost() {
        if (closed || connecting || ready) return;
        // Prompt the user to enable Bluetooth first; Android 6-11 also requires location services.
        connecting = true;
        // 40 seconds is an application deadline for scanning, connection, and readiness, not a protocol guarantee.
        main.postDelayed(readyDeadline, 40000);
        manager.connectByDeviceId(hostId, 15000L, new XCConnectListener() {
            @Override public void onConnected(Device device) {
                Log.i("XCDemo", "Services discovered; waiting for notification readiness");
            }
            @Override public void onReady(Device device, int mtu, int size) {
                main.post(() -> {
                    if (closed || !connecting) return;
                    main.removeCallbacks(readyDeadline);
                    connecting = false;
                    ready = true;
                    Log.i("XCDemo", "ready, mtu=" + mtu + ", package=" + size);
                    // Display readiness only; never call shutdownAll automatically here.
                });
            }
            @Override public void onDisconnected() { connectionEnded("disconnected"); }
            @Override public void onFailed(String message) { connectionEnded(message); }
        });
    }

    private void connectionEnded(String message) {
        main.post(() -> {
            if (closed) return;
            main.removeCallbacks(readyDeadline);
            connecting = false;
            ready = false;
            commandPending = false;
            Log.e("XCDemo", message);
            // The user reopens the page after disconnection; no automatic connection or shutdown in callbacks.
        });
    }

    // Call on main only after a user action explicitly confirms the shutdown-all scope.
    public void shutdownAfterUserConfirmation() {
        if (closed || !ready || !manager.isReady() || commandPending) return;
        commandPending = true;
        manager.shutdownAll(new XCCommandCallback() {
            @Override public void onSuccess() {
                main.post(() -> {
                    if (closed) return;
                    commandPending = false;
                    Log.i("XCDemo", "Device acknowledged shutdown; disconnection may follow");
                });
            }
            @Override public void onFailed(String message) {
                main.post(() -> {
                    if (closed) return;
                    commandPending = false;
                    Log.e("XCDemo", "shutdownAll: " + message);
                    // Timeout/disconnection may leave the result unknown. Never resend automatically.
                });
            }
        });
    }

    @Override protected void onDestroy() {
        closed = true;
        ready = false;
        main.removeCallbacksAndMessages(null);
        if (ownsSession) {
            manager.stopScan();
            manager.setOnPowerChangeListener(null);
            manager.setOnDevicePowerListener(null);
            manager.setRawJsonListener(null);
            manager.clearDeviceIdFilter();
            manager.release();
        }
        super.onDestroy();
    }
}
```

This example does not implement a UI layout, silent background scanning, or automatic reconnection. Production applications must handle permission revocation, foreground/background transitions, device binding, and old-session callback isolation. Matching a host serial number does not establish authorization.

## 8. Scan Lists and Other Connection Methods

Use the following instead of Section 7's connect-by-ID method, not concurrently. Let the user choose a scan result; do not send shutdown to the first discovered device:

```java
manager.startScan(15000L, new com.makeid.blelibrary.ble_callback.ScanListener() {
    @Override public void onScanStart() { }
    @Override public void onScanStop() { }
    @Override public void onScanResult(Device device, boolean connectedBySystem) {
        // Save Device and display name, MAC, and RSSI. Stop scanning and connect only after user selection.
    }
    @Override public void onScanError(
            com.makeid.blelibrary.bean.ScannerExceptionType type, String message) { }
});
// These calls belong to a later user-selection event, not immediately after startScan:
manager.stopScan();
manager.connect(selectedDevice, connectListener);
// Alternatively, validate a known MAC with BluetoothAdapter.checkBluetoothAddress(address) first:
manager.connect(address, connectListener);
```

For `connectByDeviceId`, a scan duration of 0 or less defaults to 15 seconds. Failure is reported if the host is not found, with a fallback deadline 3 seconds beyond the scan period. This covers only scan matching, not subsequent connection and notification readiness. Do not start another scan or connect-by-ID attempt during this operation.

The current connect-by-ID fallback task is a local variable and is not centrally cancelled by `release()`. A failure callback can arrive after scanning stops or the page exits. Mark the page/session closed and ignore late callbacks. `release` also does not clear the three application data listeners or ID allowlist; clear them as in the complete example.

## 9. Protocol, Logging, and Troubleshooting

### 9.1 BLE and JSON

| Parameter | Value |
| --- | --- |
| Service | `0000ffe0-0000-1000-8000-00805f9b34fb` |
| Write | `0000ffe1-0000-1000-8000-00805f9b34fb` |
| Notify | `0000ffe4-0000-1000-8000-00805f9b34fb` |
| Write type | `WRITE_TYPE_DEFAULT`, with GATT write acknowledgment |
| Requested MTU | `512`; use the actual value from readiness callbacks |
| Connection configuration timeout / command timeout | `15000ms` / `5000ms` |
| Receive buffer limit | `256 * 1024` bytes; cleared on overflow |

```json
{"cmd":"allshutdown"}
```

```json
{"cmd":"allshutdown","status":"ok"}
```

```json
{"cmd":"detected_powerchange","content":{"power_change":"power_down","device_id":"000011"}}
```

```json
{"cmd":"Power_On","content":{"device_id":"000011"}}
```

```json
{"cmd":"Power_Off","content":{"device_id":"000011"}}
```

Transmission is fragmented using the underlying actual MTU. Reception assembles bytes by JSON syntax, handling concatenated/fragmented frames and UTF-8 characters split across packets. `RawJsonListener.onReceive` supplies assembled JSON, not each BLE notification's bytes. Damaged or incomplete underlying data is not guaranteed to produce a business event.

### 9.2 Logs and Fault Isolation

```java
com.makeid.mkdxcfiberchecklib.log.MkdLog.DEBUG = false;
```

This switch controls this module's `MkdXCFiberCheckLog` output. It does not unregister `RawJsonListener` or disable every underlying BLE log. Production code must not log full sensitive identifiers, binding information, or unredacted raw messages.

```bash
adb logcat -s MkdXCFiberCheckLog
```

| Symptom | Diagnostic Order |
| --- | --- |
| Cannot import `Device` / `ScanListener` | Verify the matching BLE AAR and avoid similarly named callbacks from other modules |
| Host not found | Check permissions, Bluetooth, older-system location, name prefix, leading zeros/host serial number, and an advertised device name |
| onConnected received but shutdown rejected | Wait for onReady. Capture MTU/notification failures and impose an overall readiness deadline |
| Never becomes ready | Verify FFE0/FFE1/FFE4 and record notification errors; not every notification failure is guaranteed to immediately call onFailed |
| Command timeout or disconnection | Inspect TX_JSON, WRITE_FAILED, FFE4 RX, and ACK. The result may be unknown; do not retry automatically |
| RX_HEX without RX_JSON | Check missing fragments, buffer overflow, and native-call errors. Loading failure and invocation failure behave differently |
| RX_JSON without business callback | Check command spelling, allowlist, missing device_id, and listener registration. Raw JSON may arrive while business events are filtered |
| powerUp=false contradicts the scene | Inspect raw power_change. Missing/unknown values also produce false; not necessarily a valid decrease |
| Callbacks after page destruction | State changes are asynchronous and connect-by-ID can fail late. Mark the session closed, clear listeners, and stop scanning |
| JNI error or fallback log | Check final ABI, SO, consumer rules, and full stack trace. Fallback is not evidence that delivery validation passed |

## 10. Delivery and Verification Checklist

- Supply both matching AARs, versions and SHA-256 hashes, external dependencies, ABI list, supported host/detector firmware range, and both language editions of this guide.
- Capture phone model, Android/App versions, process ABI, host name/serial number, detector allowlist, connection/MTU/notification timing, TX/RX, and complete failures. Redact before sharing.
- Supplier and integrator should verify permissions, host selection, connect-by-ID, readiness recovery, detector reports, allowlist, shutdown ACK/disconnect/timeout, obfuscated release, JNI loading, and 16 KB page compatibility on applicable devices.
- Shutdown-all affects on-site equipment. Verify only in a controlled environment after explicit user confirmation; an ACK is not a substitute for checking physical power-off.

**This work is documentation and static checking only. No compilation, build, packaging, or physical-device verification was performed; this is not a compatibility validation report for the actual AARs.**

## 11. Related Documents

- Existing README and Development Notes（SDK补充附录未随本Demo提供，可向供应方索取 / supplementary source appendix） (Chinese)
- Development Documentation（SDK补充附录未随本Demo提供，可向供应方索取 / supplementary source appendix） (Chinese)
- Original Fiber Identification Protocol（SDK补充附录未随本Demo提供，可向供应方索取 / supplementary source appendix） (Chinese)
- Detector ID Filtering and Host-ID Connection（SDK补充附录未随本Demo提供，可向供应方索取 / supplementary source appendix） (Chinese)
- iOS Porting Notes（SDK补充附录未随本Demo提供，可向供应方索取 / supplementary source appendix） (Chinese)
