# MkdXCFiberCheckLib Android SDK 使用说明

[简体中文](SDK接口说明文档.md) | [English](SDK-API-Guide.en.md)

## 1. 概述与适用范围

`MkdXCFiberCheckLib` 用于手机通过 BLE 连接 **TR-FID- 系列对纤仪主机**，接收探测器功率变化、开关机事件，并下发一键关机指令。

| 项目 | 当前源码配置 |
| --- | --- |
| 版本 | `1.0`；实际交付以配套 AAR 清单为准 |
| 文档核对日期 | `2026-10-30` |
| 包名 | `com.makeid.mkdxcfiberchecklib` |
| 入口 | `XCFiberCheckManager.getInstance()` |
| Android / Java | `minSdk 21`、`compileSdk 34`、Java 8 |
| 依赖模块 | `MkdBLEConnectLib` |
| 目标设备名 | `TR-FID-` 开头，例如 `TR-FID-000002` |
| 业务能力 | 主机扫描/连接、探测器事件监听与 ID 白名单、一键关机、原始 JSON 调试 |

本库不是 `MkdFiberClearLib`，不提供 C42 清洗仪的 OPM 配置、ONU、OTDR 测试或 SOR 文件下载。探测器通过主机统一上报，不是手机能单独连接的 BLE 外设。

**验证状态：本文对照当前源码做静态核对，未执行编译、构建、打包或真机验证。**

## 2. 第三方 AAR 引入

### 2.1 交付文件与依赖

当前 `build.gradle` 使用普通 `implementation project(':MkdBLEConnectLib')`，不会把 BLE 库自动嵌入本库 AAR。第三方需要同一批次的两个文件：

```text
app/libs/
├── MakeID_XCFiberCheckLib_1.0.aar
└── makeid_bleconnectlib_1.1.aar
```

宿主 `settings.gradle` 的已有仓库配置需包含 `google()`、`mavenCentral()`；App 模块示例：

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
    // BLE 模块还依赖 Material；本地 AAR 不带 Maven POM，宿主需显式声明。
    implementation 'com.google.android.material:material:1.10.0'
}
```

文件名与实际交付一致。上述 AppCompat 与业务模块配置一致，Material 示例使用兼容版本；均不表示最新发布版本，宿主已有依赖时统一兼容版本。不要同时添加重复 AAR、JAR 或相同源码模块。源码工程内部才使用 `implementation project(':MkdXCFiberCheckLib')` 与 BLE 模块依赖。

`org.json:json:20180813`、JUnit、AndroidX 测试依赖只用于库自身测试，不应照抄为宿主运行依赖；Android 运行环境提供 `org.json`。SDK 本身不要求 XXPermissions 或 RxJava。

### 2.2 native、ABI 与混淆

- native 库名为 `libmkdxcfiberchecklib.so`，用于 cJSON 帧边界判定。当前 Gradle 未设 `abiFilters`，不代表最终交付支持所有 ABI；应核对 AAR 的 `jni/<abi>/` 与宿主进程架构。
- 宿主消费 AAR 无需复制 CMake/NDK 配置。当前源码使用 NDK `28.2.13676358`；实际 SO 与安装包的 16 KB 页兼容性仍需单独验证。
- AAR 的 consumer rules 已保留 `com.makeid.mkdxcfiberchecklib.utils.XcJsonNative` 和 native 方法。确保最终宿主保留规则生效；BLE 反射分发在混淆后的 release 仍需验证，必要时先保守保留 `com.makeid.blelibrary.**` 再收窄。
- **加载 SO 失败时**，`XcJsonNative.isAvailable()` 为 false，`CJsonFrameProbe` 自动使用 `JavaFrameProbe`，并记录加载失败日志；这不是“所有 native 错误都会自动降级”的保证。
- SO 已加载但 native 调用异常时，`frameLengthSafe(...)` 捕获异常并返回 `-1`，不会在该路径自动切换 Java；结果可能是一直等待后续字节。遇到“有 RX_HEX 无 RX_JSON”时也要检查 native 调用日志。

## 3. Manifest 与权限

以下示例面向 `targetSdk >= 31` 且不从 BLE 扫描推导物理位置的应用，合并到宿主 Manifest 并检查 Merged Manifest：

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

- Android 12/API 31 及以上动态申请 `BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT`；Android 6～11/API 23～30 动态申请定位权限并打开定位服务；API 21～22 无运行时权限框。
- `neverForLocation` 必须符合实际用途，可能过滤部分广播，需用目标 TR-FID 设备验证。确需定位时应调整配置，不能照抄不定位声明。
- SDK 不代申请权限或打开蓝牙；拒绝授权、蓝牙关闭、权限撤销由宿主处理。本业务不需要相机、文件、NFC 或“所有文件访问”权限。
- 当前模块 Manifest 为空，但配套 BLE AAR 会合并蓝牙/定位权限，不能仅依据单个 Manifest 判断最终声明。

## 4. 接入顺序与身份区分

1. 使用 `Application` 调用 `init`，注册主动上报监听；无需锁库的 AppID/密钥鉴权。
2. 取得权限、打开蓝牙；旧 Android 还需打开定位服务。
3. 选主机：扫描列表选取 `Device`、按合法 MAC 地址连接，或使用 `connectByDeviceId` 扫描匹配主机编号。三种方式选择一种，不要并发执行。
4. 等待 `onReady`，而不是仅等 `onConnected` / `isConnected()`。内部流程为服务发现 → 请求 MTU 512 → 开启 FFE4 通知；MTU 失败可按默认值继续，不保证实际 MTU 为 512。
5. 接收探测器事件；如需白名单，按探测器标签编码设置。用户确认后才调用一键关机，严禁连接就绪即自动关机。
6. 页面退出时标记会话无效、停止扫描、移除数据监听并释放独占会话；共享场景仅最后一个使用方释放。

| 名称 | 示例 | 用途 |
| --- | --- | --- |
| 主机蓝牙名 | `TR-FID-000002` | 手机实际连接的 BLE 外设名称 |
| 主机编号 / serialNo | `000002` | `connectByDeviceId` 的目标；也接受完整主机名，保留前导零 |
| 主机 BLE MAC | `AA:BB:CC:DD:EE:FF` | `connect(String, ...)` 的设备地址；不是探测器 ID |
| 探测器 ID | `000011`、`A-1` | 报文 `content.device_id`，用于主动上报区分和白名单 |

SDK 按设备名匹配主机，不执行业务身份鉴权。广播名可能重复或伪造，敏感业务需结合绑定信息与现场确认。`setDeviceIdFilter` 只是本地上报筛选，不是权限控制，也不限制一键关机范围。

## 5. 接口速查

类：`com.makeid.mkdxcfiberchecklib.XCFiberCheckManager`。除特别说明外返回 `void`；业务回调在 `.listener` 包，扫描类型来自 `com.makeid.blelibrary`。

| 接口 | 说明 |
| --- | --- |
| `static XCFiberCheckManager getInstance()` | 进程内单例 |
| `init(Application application)` | 初始化 BLE 配置并注册观察者，使用前调用 |
| `release()` | 异步投递清理：终结挂起关机命令、清空组包、释放连接并注销观察者；之后需重新 init |
| `startScan(long timeoutMillis, ScanListener listener)` | 刷新 `TR-FID-` 前缀过滤并扫描；≤0 默认 15000ms，超大值限制到 int 最大值；替换上次扫描 |
| `stopScan()` | 异步停止扫描、移除本接口的监听 |
| `boolean isScanning()` | 当前扫描状态 |
| `connect(Device device, XCConnectListener listener)` | 连接扫描所得设备，断开已有连接并终结挂起关机请求 |
| `connect(String address, XCConnectListener listener)` | 通过合法 MAC 地址连接；非法地址可能同步抛异常，宿主先校验 |
| `connectByDeviceId(String deviceId, XCConnectListener listener)` | 主机编号扫描连接，默认扫描 15 秒 |
| `connectByDeviceId(String deviceId, long scanTimeoutMillis, XCConnectListener listener)` | 指定扫描时长；trim、去前缀后忽略大小写比较，不做数字转换 |
| `disconnect()` | 异步断开全部 BLE 连接，不开启自动重连 |
| `boolean isConnected()` | 记录设备是否连接，不等于业务就绪 |
| `boolean isReady()` | 通知是否已开启；只有此时允许下发命令 |
| `int getMtuSize()` | 当前记录 MTU，初始 23；不作为会话就绪凭据 |
| `int getPackageSize()` | 当前记录 `max(20, mtu-3)`，初始 20，仅展示；真实分包由底层 MTU 处理 |
| `shutdownAll(XCCommandCallback callback)` | 一键关机，等待协议 ACK，应用禁止重复点击 |
| `setOnPowerChangeListener(OnPowerChangeListener listener)` | 功率变化事件；null 移除 |
| `setOnDevicePowerListener(OnDevicePowerListener listener)` | 探测器开关机事件；null 移除 |
| `setRawJsonListener(RawJsonListener listener)` | 调试 JSON 收发；null 移除 |
| `setDeviceIdFilter(String... deviceIds)` | 设置探测器白名单 |
| `setDeviceIdFilter(Collection<String> deviceIds)` | 集合重载；不要直接传无类型的 null，以免重载歧义 |
| `clearDeviceIdFilter()` | 清空白名单，恢复全部放行 |
| `Set<String> getDeviceIdFilter()` | 不可变快照；成员为去首尾空白后的原标识 |
| `boolean isDeviceIdFilterEnabled()` | 当前是否启用白名单 |

### 5.1 连接与扫描回调

```java
public interface XCConnectListener {
    void onConnected(Device device); // 服务发现完成，尚未就绪
    void onReady(Device device, int mtu, int packageSize);
    void onDisconnected();
    void onFailed(String message);
}
```

`ScanListener` 是 `com.makeid.blelibrary.ble_callback.ScanListener`，提供 `onScanStart()`、`onScanStop()`、`onScanResult(Device, boolean)`、`onScanError(ScannerExceptionType, String)`；不要使用 MkdLockLib 的自定义扫描接口。

**线程约定：**正常连接事件、通知解析后的业务事件和关机命令回调经主线程 Handler 派发；但普通扫描监听直接转发底层回调，`connect(String, ...)` 在无蓝牙适配器等早期失败路径也可能同步回调调用线程。不要承诺全部回调都在主线程；UI 更新统一投递主线程，并在主线程调用状态设置和会话操作。

多数动作通过 `mainHandler.post` 异步执行；刚调用 `connect/release/stopScan` 后立即读取状态可能仍是旧值。不要把 getter 的瞬时值当作动作完成通知。

### 5.2 一键关机结果

```java
manager.shutdownAll(new XCCommandCallback() {
    @Override public void onSuccess() {
        // 收到 status=ok 的关机 ACK；不等于所有探测器实际断电的证明。
    }
    @Override public void onFailed(String message) {
        android.util.Log.e("XCDemo", "shutdownAll: " + message);
    }
});
```

- 超时为 5000ms，从 SDK 登记请求时开始，包含等待写入和 ACK 的时间；不是“正常 ACK 必须几十毫秒返回”的承诺。
- 对每次登记的请求，ACK、超时、断线、release、被新请求替换统一经 `finishPending` 移除，避免同一请求重复回调。重复发送不建议作为正常操作，协议无请求序号，迟到 ACK 无法可靠区分新旧业务。
- 只有 `status` 等于 `ok`（忽略大小写）算成功；GATT 写成功不算业务成功；超时/断线不证明设备未执行，不自动重发。

| 失败信息示例 | 含义 |
| --- | --- |
| `not ready` | 通知未就绪或连接对象不存在 |
| `timeout waiting for ACK` | 5秒内未完成 ACK；先查通知与原始日志 |
| `disconnected before ACK` | 收到 ACK 前断开，执行结果可能未知 |
| `rejected: status=...` | 收到 ACK，但 status 不是 ok |
| `superseded by a new request` | 被下一次相同命令替换 |
| `new connection` / `sdk released` | 新连接或释放时结束挂起请求 |

连接失败使用 `XCConnectListener.onFailed(String)`，没有统一数字错误码。常见文本还包括 `empty device id`、`device not found: ...`、`connect failed: ...`、`connect timeout: ...`。记录完整信息，不把错误文本当作稳定业务枚举。

## 6. 主动上报与探测器过滤

```java
manager.setOnPowerChangeListener((deviceId, powerUp) -> {
    // deviceId 是探测器编码；true=power_up，false=power_down或无法识别的值。
});
manager.setOnDevicePowerListener(new OnDevicePowerListener() {
    @Override public void onDevicePowerOn(String deviceId) { }
    @Override public void onDevicePowerOff(String deviceId) { }
});
manager.setRawJsonListener(new RawJsonListener() {
    @Override public void onSend(String json) { /* 即将提交写入，并非设备确认 */ }
    @Override public void onReceive(String json) { /* 已组装的完整 JSON */ }
});
```

`OnPowerChangeListener` 返回 `(String deviceId, boolean powerUp)`，不是数值功率计读数。`PowerChangeEvent`、`DevicePowerEvent` 是可选模型，当前 Manager 回调并不直接返回这些实体。

```java
manager.setDeviceIdFilter("000011", "A-1");
boolean enabled = manager.isDeviceIdFilterEnabled();
java.util.Set<String> allowed = manager.getDeviceIdFilter();
manager.clearDeviceIdFilter(); // 不再需要白名单时显式清理
```

- null、空集合、全空白表示不过滤，非空白名单只放行匹配 ID；缺失 ID 的上报被拦截。
- 匹配 trim 后忽略大小写，但不去除标点，`A-1` 与 `A1` 不同；`000011` 与 `11` 不同。
- 仅过滤 `detected_powerchange`、`Power_On`、`Power_Off` 的业务分发。关机 ACK 和原始 JSON 不受影响，设备端仍发送完整上报。
- 白名单及应用数据监听不因 `disconnect/release/init` 自动重置；新会话按业务需要显式设置或清空，不依赖上次页面留下的状态。
- 当前解析兼容部分拼写差异：命令与字段比较会忽略大小写/分隔符，支持 power_change / pow_change 等别名；不应据此扩展或改变设备协议。
- `power_change` 缺失或未知时，`isPowerUp()` 为 false，业务回调可能表现为 power_down。不能只凭 false 断言设备真实功率下降；用原始 JSON 和告警日志核对字段。

### 6.1 主机信息包装

```java
XcDevice xc = new XcDevice(device); // com.makeid.mkdxcfiberchecklib.entity.XcDevice
String name = xc.getName();
String address = xc.getAddress();
String hostId = xc.serialNo();
Device original = xc.getDevice();
```

`serialNo()` 按精确的 `TR-FID-` 前缀截取，名称不匹配时返回空字符串；它和忽略大小写的 `connectByDeviceId` 匹配细节不同。保留主机编号的前导零，不作为探测器 ID 使用。

## 7. 完整 Java 接入示例

示例由单页面独占 SDK，按**用户选定的主机编号**连接；没有自动关机。宿主在 Manifest 中注册 `com.example.xcdemo.XCDemoActivity`（`android:exported="false"`），由内部页面传入字符串 extra `hostId`，如 `000002`。已有应用级初始化时应合并会话管理，不要多个页面分别 init/release 同一 BLE 单例。

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
        Log.e("XCDemo", "连接未就绪；退出页面后重新连接，勿自动重发命令");
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        hostId = getIntent().getStringExtra("hostId");
        if (hostId == null || hostId.trim().isEmpty()) {
            Log.e("XCDemo", "请传入用户选择的主机编号hostId");
            finish();
            return;
        }
        manager.init(getApplication());
        ownsSession = true;
        manager.clearDeviceIdFilter(); // 如需限制上报，改为业务确认的探测器白名单。
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
                Log.e("XCDemo", "蓝牙权限未授予，请到设置中处理");
                return;
            }
        }
        connectHost();
    }

    private void connectHost() {
        if (closed || connecting || ready) return;
        // 先引导用户开启蓝牙；Android 6～11 还需开启定位服务。
        connecting = true;
        // 40秒为应用级整体等待上限，涵盖扫描、连接及通知就绪，不是协议承诺。
        main.postDelayed(readyDeadline, 40000);
        manager.connectByDeviceId(hostId, 15000L, new XCConnectListener() {
            @Override public void onConnected(Device device) {
                Log.i("XCDemo", "服务发现完成，等待通知就绪");
            }
            @Override public void onReady(Device device, int mtu, int size) {
                main.post(() -> {
                    if (closed || !connecting) return;
                    main.removeCallbacks(readyDeadline);
                    connecting = false;
                    ready = true;
                    Log.i("XCDemo", "ready, mtu=" + mtu + ", package=" + size);
                    // 这里只显示可操作状态，不能自动调用 shutdownAll。
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
            // 断开后由用户重新进入页面，不在回调中自动连接或关机。
        });
    }

    // 仅在用户点击且明确确认一键关机范围后，于主线程调用。
    public void shutdownAfterUserConfirmation() {
        if (closed || !ready || !manager.isReady() || commandPending) return;
        commandPending = true;
        manager.shutdownAll(new XCCommandCallback() {
            @Override public void onSuccess() {
                main.post(() -> {
                    if (closed) return;
                    commandPending = false;
                    Log.i("XCDemo", "设备确认关机指令，后续可能断开");
                });
            }
            @Override public void onFailed(String message) {
                main.post(() -> {
                    if (closed) return;
                    commandPending = false;
                    Log.e("XCDemo", "shutdownAll: " + message);
                    // 超时/断线时结果可能未知，不能自动重发。
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

本示例不实现 UI 布局，也不提供静默后台扫描或自动重连。正式应用补充权限撤销、后台/前台切换、设备绑定校验及旧会话回调隔离；主机匹配编号不代表授权成功。

## 8. 扫描列表与其他连接方式

以下与第 7 节的按编号连接二选一，扫描结果先交给用户选择，不要扫描到首个设备就发关机指令：

```java
manager.startScan(15000L, new com.makeid.blelibrary.ble_callback.ScanListener() {
    @Override public void onScanStart() { }
    @Override public void onScanStop() { }
    @Override public void onScanResult(Device device, boolean connectedBySystem) {
        // 保存 Device，展示名称、MAC、RSSI；用户选中后再停止扫描和连接。
    }
    @Override public void onScanError(
            com.makeid.blelibrary.bean.ScannerExceptionType type, String message) { }
});
// 以下是后续用户选择事件中的调用点，不要在 startScan 后立即连发：
manager.stopScan();
manager.connect(selectedDevice, connectListener);
// 或已知合法 MAC 时，先用 BluetoothAdapter.checkBluetoothAddress(address) 校验：
manager.connect(address, connectListener);
```

`connectByDeviceId` 的扫描≤0默认15秒，找不到设备会失败，并有扫描周期额外3秒的兜底；这只是扫描匹配阶段，不含后续连接和通知就绪耗时。调用期间不要再次 `startScan` 或开启另一轮按编号连接。

当前按编号扫描的兜底任务是局部变量，`release()` 不会统一取消它；停止扫描/退出后仍可能收到失败回调。宿主必须标记页面/会话已关闭并忽略迟到回调。`release` 也不会自动清空三类应用数据监听和 ID 白名单，按完整示例主动清理。

## 9. 协议、日志与排查

### 9.1 BLE 与 JSON

| 参数 | 值 |
| --- | --- |
| Service | `0000ffe0-0000-1000-8000-00805f9b34fb` |
| Write | `0000ffe1-0000-1000-8000-00805f9b34fb` |
| Notify | `0000ffe4-0000-1000-8000-00805f9b34fb` |
| 写类型 | `WRITE_TYPE_DEFAULT`，等待 GATT 写回执 |
| 请求 MTU | `512`，实际值以就绪回调为准 |
| 连接配置超时 / 命令超时 | `15000ms` / `5000ms` |
| 接收缓冲上限 | `256 * 1024` 字节，超限清空 |

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

发送端按底层实际 MTU 分包；接收端按 JSON 语法做 byte 级组包，支持粘包、分包及跨包 UTF-8 字符。`RawJsonListener.onReceive` 是已组装的 JSON，不是每个 BLE 通知的字节；底层损坏或不完整的数据不保证一定有业务事件。

### 9.2 日志与故障定位

```java
com.makeid.mkdxcfiberchecklib.log.MkdLog.DEBUG = false;
```

该开关控制本模块 `MkdXCFiberCheckLog` 输出，不会注销 `RawJsonListener`，也不等于关闭底层 BLE 库的所有日志。生产业务不要输出完整敏感标识、绑定信息或未经脱敏的原始报文。

```bash
adb logcat -s MkdXCFiberCheckLog
```

| 现象 | 排查顺序 |
| --- | --- |
| 无法导入 `Device` / `ScanListener` | 配套 BLE AAR 是否齐全，是否混入其他模块的同名回调 |
| 扫描不到主机 | 权限、蓝牙、旧系统定位、名称前缀；前导零和主机编号是否匹配，广播是否带名称 |
| 收到 onConnected 却不能关机 | 等 onReady；MTU 协商或通知阶段异常时捕获日志，宿主对整体就绪流程设截止时间 |
| 一直未就绪 | 设备是否提供 FFE0/FFE1/FFE4，记录通知错误；不能保证任意通知失败都立即触发 onFailed |
| 命令超时或断线 | 查 TX_JSON、WRITE_FAILED、FFE4 RX 与 ACK；结果可能未知，勿自动重试 |
| 有 RX_HEX 无 RX_JSON | 后续分片是否缺失、缓冲超限、native 调用是否报错；加载失败与调用失败的行为不同 |
| 有 RX_JSON 无业务回调 | 查命令拼法、白名单、缺失 device_id、监听是否注册；原文可被收到但业务被过滤 |
| powerUp=false 与现场不一致 | 查原文 power_change 字段；缺失/未知也会得到 false，不一定是有效下降事件 |
| 页面销毁后仍有回调 | 状态设置异步，按编号扫描可能有迟到失败；标记会话关闭，清监听并停止扫描 |
| JNI 异常或降级日志 | 核对最终 ABI、SO、consumer rules、完整异常栈；不能把降级当作产物验证通过 |

## 10. 交付与验证清单

- 提供两份配套 AAR、各自版本与 SHA-256、外部依赖、ABI 清单、支持的主机/探测器固件范围，以及本中英文文档。
- 现场日志记录手机型号、Android/App版本、进程ABI、主机名与编号、探测器白名单、连接/MTU/通知时序、TX/RX 和完整失败信息；分享前脱敏。
- 由供应方和接入方验证权限、扫描选主机、按编号连接、就绪失败恢复、探测器上报、白名单、一键关机 ACK/断线/超时、混淆 release、JNI加载与适用设备上的16 KB页兼容性。
- 一键关机属于会影响现场设备的操作，验证需在受控环境经用户明确确认后进行，不以收到 ACK 代替物理断电核验。

**本次仅整理文档和静态检查，未执行编译、构建、打包或真机验证；不构成实际 AAR 的兼容性验证报告。**

## 11. 相关资料

- [现有 README 与开发说明](README.md)
- [开发文档](docs/开发文档.md)
- [原始对纤仪协议](docs/160%23对纤仪协议.md)
- [设备 ID 过滤与按 ID 连接](docs/设备ID过滤与按ID连接.md)
- [iOS 移植说明](docs/iOS开发文档.md)
