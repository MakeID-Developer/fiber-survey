# FiberSurvey iOS Demo Implementation Plan

**Goal:** 按已确认的开发文档实现Objective-C/UIKit离线真机Demo，不改/重编SDK，不执行App编译。

**Architecture:** Scene持有唯一FSCFiberSurveyController，SDK在用户发起扫描/连接后才初始化。UI不占用BLE代理；独立扫描页通过token交接扫描快照。主线程状态机管理用户意图、截止时间、过滤与有界日志/事件。

**Tech Stack:** UIKit、CoreBluetooth、Vendor两份arm64动态Framework；保留project.xcproj格式。

## 安全决策

现有SDK尚无可靠取消/就绪/写队列保证；本轮不修改SDK。连接仅标为“SDK已回调/未安全验收”，提供扫描、连接和被动事件接收；实际关机发送保持源码级关闭，UI显示阻断原因，不提供用户强制绕过。任何连接尝试终结后禁止本进程再次连接，要求用户重启，不使用固定延时冒充取消完成。关机确认、冻结目标/会话、单事务和结果收尾调用路径仍实现，待供应方完成SDK修复、更新配套包并验收后开放。

## Tasks

- [x] 1. 先编写不触发编译的静态契约检查与XCTest规则用例；运行静态检查确认缺少实现而失败。XCTest因用户默认禁编译而只提供源码，不执行。
- [x] 2. 实现Core/FSCDeviceFilterParser、FSCBoundedStore、FSCSessionState、FSCCentralStateGate及Models/FSCScanItem。规则覆盖编号前导零/标点、分隔符、finite 1～60秒、300日志/200事件、代次/单次终结。
- [x] 3. 实现Controllers/FSCFiberSurveyController：懒初始化、系统授权gate、15秒等待、扫描/按编号查找、22秒连接截止、迟到回调忽略、后台取消、过滤读回、SDK风险写阻断；实现保守单次连接生命周期。
- [x] 4. 实现ViewController与FSCScanViewController：上方40%有界日志表、下方60%滚动操作和事件，设置入口、独立清空、日志跟随/原文开关、主机详情与风险确认。
- [x] 5. Scene单根导航入口，移除Main双入口，添加蓝牙用途键；两库相对链接和签名嵌入，限制真机平台，清空全局Team并保留Xcode写回的target本地签名选择，不更改27.2兼容基线。
- [x] 6. 更新README、使用说明、开发文档和验证记录，静态核对selector、工程格式、SDK哈希与无网络依赖；不运行xcodebuild build/test/archive或clang编译，不提交Git。

## 验证命令

```sh
python3 scripts/check_demo.py
(cd Vendor && shasum -a 256 -c SHA256SUMS)
sh -n scripts/embed-frameworks.sh
xcrun xcprojformatter --input FiberSurvey.xcodeproj --output /tmp/FiberSurvey-project-checked.xcproj
```

静态检查不证明编译/链接或设备可运行；真机验收仍需按开发文档I01～I26执行。SDK风险未修复的场景必须标为阻断，不标通过。
