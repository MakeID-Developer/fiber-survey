# FiberSurveyDemo SDK AAR交付清单与静态核对记录

- 核对日期：2026-11-02。
- 文件位置：独立工程 `app/libs/`。
- 来源：用户已放入的现有文件；本次未生成、重签、替换或打包AAR。
- 验证层级：只读文件、ZIP/内嵌JAR CRC、Manifest、class常量/方法描述符、ELF程序头；未运行编译器、Gradle、Java字节码、JNI或设备测试。
- 相关方案：[开发文档](开发文档.md)。

## 1. 实际文件与SHA-256

| 文件 | 大小（字节） | 标称版本来源 | ZIP与classes.jar CRC |
| --- | --- | --- | --- |
| `MakeID_XCFiberCheckLib_1.0.aar` | 88893 | 文件名标称1.0，待供应方确认发布来源 | 通过 |
| `makeid_bleconnectlib_1.1.aar` | 113121 | 文件名标称1.1，待供应方确认发布来源 | 通过 |

SHA-256为当前文件的完整指纹；后续替换应重新核对，不能仅比较文件名：

```text
MakeID_XCFiberCheckLib_1.0.aar
ea6d67ecfa2cd405b36ab78b284851711feaec412abd4ea7262a98dc8800c57b
```

```text
makeid_bleconnectlib_1.1.aar
dc5ff88fbf0fa342fdf9dd635e2ea53a8842bc28cc1578e471dff4cb1162d146
```

## 2. Manifest与class内容

| 项目 | 对纤仪AAR | BLE AAR |
| --- | --- | --- |
| Manifest package | com.makeid.mkdxcfiberchecklib | com.makeid.blelibrary |
| minSdk | 21 | 21 |
| AAR自身Manifest targetSdk | 21 | 34 |
| BuildConfig.BUILD_TYPE | release | release |
| BuildConfig.DEBUG | false | false |
| Java class数量 | 26 | 83 |
| class major | 52（Java8） | 52（Java8） |
| 独立native库 | 四种ABI的libmkdxcfiberchecklib.so | 无jni/so |
| R.txt | 空 | 空 |
| AAR元数据minCompileSdk | 1 | 1 |
| AAR元数据minAndroidGradlePluginVersion | 1.0.0 | 1.0.0 |

两个BuildConfig未包含库版本号字段，不能独立从其证实1.0/1.1或与当前源码完全一致。包名/BuildType/方法存在也不证明设备行为已回归。

AAR自身targetSdk声明不等于宿主targetSdk，也不表示宿主必须降级。新App仍是targetSdk36模板，最终合并与系统兼容需要实际接入验证。BuildConfig.DEBUG=false也不代表MkdLog.DEBUG或底层日志一定关闭。

### 2.1 权限

对纤仪AAR未声明uses-permission；BLE AAR实际声明：

```text
android.permission.BLUETOOTH
android.permission.BLUETOOTH_ADMIN
android.permission.ACCESS_COARSE_LOCATION
android.permission.ACCESS_FINE_LOCATION
android.permission.BLUETOOTH_SCAN
android.permission.BLUETOOTH_CONNECT
```

这6项没有maxSdkVersion限定。两个AAR均无INTERNET声明。宿主后续按系统/真实用途调整蓝牙与定位权限、处理运行时申请并审查Merged Manifest；本次未修改宿主Manifest。

### 2.2 配套关系与混淆

- 对纤仪AAR有Manager、XcDevice、过滤器、协议解析和listener；未内嵌 `com.makeid.blelibrary.bean.Device`，因此仍须显式同时引入BLE AAR。
- BLE AAR包含Device、ScanListener、连接请求与事件基础类型，不应仅复制对纤仪一个AAR。
- 对纤仪AAR的proguard.txt包含以下规则；BLE AAR的proguard.txt为空：

```proguard
# JNI 静态绑定依赖完整的类名与方法签名，混淆后会抛 UnsatisfiedLinkError：
# 找不到 Java_com_makeid_mkdxcfiberchecklib_utils_XcJsonNative_frameLength
-keep class com.makeid.mkdxcfiberchecklib.utils.XcJsonNative { *; }

-keepclasseswithmembernames class * {
    native <methods>;
}
```

上述规则存在不表示宿主最终已合并/应用，也不证明BLE反射路径在混淆后正常。需要后续release验收。

## 3. 实际native ABI与ELF加载段对齐

仅检查PT_LOAD的p_align字段。以下不是APK/AAB zip对齐或运行加载测试，也未证明依赖库、RELRO等全部兼容。

| ABI | 文件 | SO大小（字节） | PT_LOAD p_align（所有加载段） |
| --- | --- | --- | --- |
| arm64-v8a | libmkdxcfiberchecklib.so | 31792 | 16384 / 16384 / 16384 |
| armeabi-v7a | libmkdxcfiberchecklib.so | 22112 | 4096 / 4096 / 4096 |
| x86 | libmkdxcfiberchecklib.so | 32164 | 4096 / 4096 / 4096 |
| x86_64 | libmkdxcfiberchecklib.so | 32336 | 16384 / 16384 / 16384 |

- arm64-v8a、x86_64的静态p_align为16384（16KB）；armeabi-v7a、x86为4096（4KB）。
- 四种ABI确实存在于这份业务AAR；不能套用另一电子钥匙项目仅arm64的限制。但“包内有库”不等于该设备/模拟器已验证。
- 不因32位条目为4KB便笼统宣布本包全部不兼容，也不能仅凭64位16KB字段宣布最终App已适配；按目标系统/ABI及最终安装包验证。
- 生产路径的native加载失败与调用失败处理仍需按SDK文档区分；本次没有执行这些路径。

## 4. class二进制接口核对

只读解析了class常量池及public方法描述符，未执行javap/java或编译。Manager包含21个不同业务方法名，共24个签名（计入重载，不计SDK内部观察者回调）。已核对以下功能对应签名存在：

| 功能 | 存在的公开方法/重载 |
| --- | --- |
| 生命周期 | getInstance、init(Application)、release |
| 扫描 | startScan(long, ScanListener)、stopScan、isScanning |
| 连接 | connect(Device, XCConnectListener)、connect(String, XCConnectListener) |
| 编号连接 | connectByDeviceId(String, XCConnectListener)、connectByDeviceId(String, long, XCConnectListener) |
| 状态/MTU | disconnect、isConnected、isReady、getMtuSize、getPackageSize |
| 上报/调试 | setOnPowerChangeListener、setOnDevicePowerListener、setRawJsonListener |
| 白名单 | setDeviceIdFilter(Collection)、setDeviceIdFilter(String[])、clearDeviceIdFilter、getDeviceIdFilter、isDeviceIdFilterEnabled |
| 关机 | shutdownAll(XCCommandCallback) |

以下6类listener的回调名与参数描述符已核对：

| listener | 回调 |
| --- | --- |
| XCConnectListener | onConnected(Device)、onReady(Device,int,int)、onDisconnected、onFailed(String) |
| XCCommandCallback | onSuccess、onFailed(String) |
| OnPowerChangeListener | onPowerChange(String,boolean) |
| OnDevicePowerListener | onDevicePowerOn(String)、onDevicePowerOff(String) |
| RawJsonListener | onSend(String)、onReceive(String) |
| BLE ScanListener | onScanStart、onScanStop、onScanResult(Device,boolean)、onScanError(ScannerExceptionType,String) |

这确认迁移方案所需接口在当前二进制中存在；不证明返回数据、线程、超时、清理或固件兼容行为与源码逐项一致。

## 5. 接入状态与剩余任务

- [x] 两个完整AAR已放入app/libs，文件名与计划路径一致。
- [x] ZIP/内嵌JAR CRC、大小、SHA-256、Manifest、BuildType、class接口、混淆规则与native ABI/加载段对齐静态核对。
- [ ] 供应方确认真实发布版本、来源及适用主机/探测器固件范围。
- [x] 后续实施已在app/build.gradle显式引入两份AAR、开启ViewBinding/声明RecyclerView；仅配置和源码静态核对，未编译验证。
- [x] 后续已编写页面、资源、Controller、权限/状态与安全流程；验证层级见实施记录，不表示设备运行通过。
- [ ] 根据用户要求进行编译、安装及受控设备验收，核查Merged Manifest、target36、混淆、JNI与16KB页兼容。

**AAR实物与哈希未改动。独立App功能源码与Gradle接入后续已编写，但未运行编译/构建/打包、尚未进行真机验证。归档静态检查和源码实现不代表可直接外发release。**
