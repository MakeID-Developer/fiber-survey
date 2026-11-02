# FiberSurveyDemo

信测对纤仪（TR-FID-）独立Android Java示例。只依赖 `app/libs` 中两份配套AAR，不依赖原综合App，不包含锁/钥匙/清虚仪入口、SDK鉴权、登录或运行时IP网络请求。

## 当前状态（2026-11-02）

已编写本地AAR配置、ViewBinding界面、扫描页、主机编号连接、探测器事件/白名单、确认一键关机和应用会话清理。已运行不编译的静态检查及Python源码约束测试。

**没有执行Gradle、Java编译、Android测试、构建或打包，也没有真机验证。** 当前源码不等于可直接外发的已验收版本；target36与实际AAR、JNI、设备固件和系统权限/生命周期必须由用户自行编译并在受控设备验证。

## 打开工程与依赖

使用Android Studio打开本目录，包名为`com.makeid.fibersurveydemo`。沿用新建工程AGP9.0.1 / Gradle9.2.1 / Java11源码 / JVM toolchain21 / compileSdk36.1 / targetSdk36 / minSdk21。为保留minSdk21，UI依赖固定为AppCompat1.6.1、Material1.10.0、Activity1.8.0，ConstraintLayout2.2.2保持模板值，显式引入RecyclerView1.3.2。已只读核对本机缓存AAR最低API与EdgeToEdge入口；完整传递依赖/编译兼容性仍未验证。模板原AppCompat1.8.0、Material1.14.0、Activity1.13.0均要求API23，不能在minSdk21不变时直接照用。

App已显式引入：

- `app/libs/MakeID_XCFiberCheckLib_1.0.aar`
- `app/libs/makeid_bleconnectlib_1.1.aar`

文件大小、SHA-256、ABI和二进制接口见[SDK交付清单](docs/SDK交付清单.md)。本次未修改或重新打包AAR。消费AAR不需原SDK源码、CMake、NDK个人路径；首次Gradle获取外部依赖仍可能联网，运行时不联网不代表完全离线构建。

## 使用

1. 启动即为操作首页，上方日志、下方操作，分别滚动。SDK不在Application启动时初始化，更不会自动关机。
2. 打开蓝牙，授予对应权限；Android6～11还需定位权限/系统定位服务。设备必须广播TR-FID-名称。Manifest中的neverForLocation仅用于不推导位置的业务，需在实际设备验证。
3. 选“扫描列表选择主机”，看到名称/MAC/主机编号/RSSI后点击设备连接；列表按MAC更新，不重复计数。扫描页不是第二个SDK所有者。
4. 或填写`000002` / `TR-FID-000002`后点“按主机编号连接”。这个编号不是探测器的device_id，不丢弃前导零。
5. 等待`onReady`。仅服务发现/onConnected不允许关机；界面展示实际MTU/载荷及小包风险，不强制假定MTU512。
6. 事件显示功率up/非up及探测器Power_On/Power_Off。`false`可能来自未知/缺失字段，不必然是有效下降，结合原文查看。
7. 白名单手工输入，例如`000011,A-1`，支持半/全角逗号、分号、空白分隔。trim后忽略大小写，但保留`-`和前导零；空为全放行。
8. 一键关机前必须确认当前主机与全部影响范围。白名单仅过滤本地事件，**不会限制关机范围**。关机等待时禁止重复发送/换目标。
9. ACK status=ok只是设备确认，不代替现场断电核验。超时/断线结果可能未知，不自动重发。为避免无请求序号协议中的旧ACK混入，本Demo在关机返回后结束本会话，再次操作必须由用户重新选择设备。
10. “断开”结束设备会话；“释放/取消等待”关闭在途流程。清理中不能开始新流程。SDK的编号查找/连接没有公开取消完成回调，提前取消可能需等其本轮截止（最长约40秒）再放开，期间不自动连接。
11. 主页面与扫描页在本App内切换不会误释放；整个App退后台停止扫描并结束会话。旋转不自动重放关机。返回前台重新选择设备，不恢复旧就绪状态。
12. JSON开关只控制本App显示，不关闭SDK/底层BLE内部logcat。日志最多300条，事件200条，默认内存保存、无导出/上传/备份。用户看历史时不强拉到最新，勾选“跟随最新”且位于顶部时跟随。

## 源码导航

- `SurveyApplication`：两页可见性计数，真正退后台关闭controller；不初始化SDK。
- `FiberSurveyController`：唯一SDK生命周期所有者、扫描/连接/关机状态、deadline、session/scan/command标识，listener分发。
- `MainActivity`：上日志/下操作ViewBinding、用户确认、扫描返回校验与权限入口。
- `ui/FiberScanActivity`：借用本轮scanRequest，只扫描/返回选中设备，不init或release SDK。
- `ui/BlePermissionHelper`：原生系统权限及硬件检查，无XXPermissions。
- `ui/Xc*Adapter`：MAC去重数据/事件/日志展示；`core/`为纯Java过滤、会话token与有界列表。

未加入后台服务、自动重连、云平台、固件更新或协议重写。App不尝试通过反射或内部Helper修复SDK。

## 检查与未验证项

```bash
python3 tools/aar_inventory.py
python3 tools/check_project.py
python3 -m unittest discover -s tools/tests -v
```

`check_project.py`可选使用`tools/requirements-static.txt`中的纯Python Java语法解析器；安装该开发工具可联网，不是App运行请求。解析检查不是Java编译/类型校验。`app/src/test`中的真实Java JUnit用例仅编写，未经用户明确要求不执行会触发编译的Gradle测试。

请查阅[使用说明](docs/使用说明.md)、[实施记录](docs/实施记录.md)、[验证记录](docs/验证记录.md)及[开发文档](docs/开发文档.md)。原SDK中文/英文接口资料快照位于`docs/sdk/`。

外发前必须完成依赖/toolchain、Manifest合并、权限、跨页面/后台、ACK/设备真实效果、混淆release、ABI/JNI/16KB页等验收。不要仅凭AAR内存在4种ABI或native降级日志宣布兼容。打包源码时排除`.idea`、`.gradle`、`build`、`local.properties`及个人签名/keystore，不携带内部账号或原仓库路径。
