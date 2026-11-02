package com.makeid.fibersurveydemo;

import android.app.Application;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import com.makeid.blelibrary.bean.Device;
import com.makeid.blelibrary.bean.ScannerExceptionType;
import com.makeid.blelibrary.ble_callback.ScanListener;
import com.makeid.mkdxcfiberchecklib.XCFiberCheckManager;
import com.makeid.mkdxcfiberchecklib.entity.XcDevice;
import com.makeid.mkdxcfiberchecklib.listener.*;
import com.makeid.fibersurveydemo.core.BoundedLogStore;
import com.makeid.fibersurveydemo.core.DetectorFilterParser;
import com.makeid.fibersurveydemo.core.SessionState;
import com.makeid.fibersurveydemo.core.SessionState.Phase;

import java.text.SimpleDateFormat;
import java.util.*;

/** The only owner of SDK init/release. All app state and callbacks are serialized on main. */
public final class FiberSurveyController {
    public interface Screen { void render(); }
    public interface ScanScreen { void renderScan(); }
    public static final class Row {
        public final String time, kind, text;
        public Row(String time, String kind, String text) { this.time=time; this.kind=kind; this.text=text; }
    }
    private final Application application;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final SessionState state=new SessionState();
    private final BoundedLogStore<Row> logs=new BoundedLogStore<>(300);
    private final BoundedLogStore<Row> events=new BoundedLogStore<>(200);
    private final LinkedHashMap<String,Device> scanned=new LinkedHashMap<>();
    private XCFiberCheckManager sdk;
    private Screen screen;
    private ScanScreen scanScreen;
    private Phase phase=Phase.IDLE;
    private boolean initialized, rawLogging=true;
    private String message="未连接 · 请选择主机，不会自动关机";
    private String deviceName="", address="", host="", result="尚未发送关机命令";
    private List<String> filter=new ArrayList<>();
    private int mtu=0, packageSize=0;
    private long requestSequence, scanRequest, scanSession, scanRound;
    private long connectStarted, commandStarted, finderMayLiveUntil, connectionMayLiveUntil;
    private String targetAddress="", requestedHost="";
    private boolean requiresRestart;
    private Runnable readyDeadline, commandDeadline;
    private boolean scanRunning, selectionCommitted;
    private String scanMessage="准备扫描";

    public FiberSurveyController(Application application) { this.application=application; }
    public void attach(Screen screen) { this.screen=screen; notifyScreen(); }
    public void detach(Screen screen) { if (this.screen==screen) this.screen=null; }
    public void attachScan(ScanScreen screen) { scanScreen=screen; notifyScan(); }
    public void detachScan(ScanScreen screen) { if (scanScreen==screen) scanScreen=null; }
    public Phase phase() { return phase; }
    public long session() { return state.session(); }
    public String message() { return message; }
    public String result() { return result; }
    public String deviceLabel() { return deviceName.isEmpty() ? "—" : deviceName+"\n主机编号="+host+"\nMAC="+address; }
    public String mtuLabel() { return mtu==0 ? "—" : mtu+" / 载荷 "+packageSize+" B"; }
    public boolean fragmentedCommand() { return mtu>0 && packageSize<21; }
    public boolean idle() { return !requiresRestart && ((!initialized && phase!=Phase.CLOSING) || (initialized && phase==Phase.IDLE)); }
    public boolean ready() { return initialized && phase==Phase.READY && sdk!=null && sdk.isReady(); }
    public boolean rawLogging() { return rawLogging; }
    public List<Row> logs() { return logs.snapshot(); }
    public List<Row> events() { return events.snapshot(); }
    public List<Device> devices() { return new ArrayList<>(scanned.values()); }
    public String scanMessage() { return scanMessage; }
    public boolean scanRunning() { return scanRunning; }
    public List<String> filter() { return new ArrayList<>(filter); }
    public String filterLabel() { return filter.isEmpty() ? "放行全部（未启用过滤）" : "只放行："+join(filter)+"\n其余业务上报被过滤，JSON与关机ACK不受影响"; }

    private void initialize() {
        assertMain();
        if (phase==Phase.CLOSING) throw new IllegalStateException("旧会话清理中，请等待提示；不要重复匹配/连接");
        if (initialized) return;
        state.next();
        final long generation=state.session();
        phase=Phase.IDLE;
        sdk=XCFiberCheckManager.getInstance();
        // The shipped module owns native framing; the App never parses/rebuilds BLE packets.
        try {
            sdk.init(application);
            initialized=true;
            sdk.setDeviceIdFilter(filter);
            sdk.setRawJsonListener(new RawJsonListener() {
                @Override public void onSend(String json) { post(generation,()-> { if (rawLogging) log("TX",json); }); }
                @Override public void onReceive(String json) { post(generation,()-> { if (rawLogging) log("RX",json); }); }
            });
            sdk.setOnPowerChangeListener((id,up)->post(generation,()->{
                if (!acceptReports()) return;
                event(up ? "power_up" : "power_down / 非up",id);
            }));
            sdk.setOnDevicePowerListener(new OnDevicePowerListener() {
                @Override public void onDevicePowerOn(String id) { post(generation,()->{ if (acceptReports()) event("Power_On",id); }); }
                @Override public void onDevicePowerOff(String id) { post(generation,()->{ if (acceptReports()) event("Power_Off",id); }); }
            });
            log("状态","SDK初始化，使用本地BLE，无AppID或网络请求");
        } catch (RuntimeException | LinkageError error) {
            // init may have partially registered SDK observers, so schedule cleanup even on failure.
            initialized=true;
            close("SDK初始化失败："+safeError(error),Phase.DISCONNECTED);
            throw new IllegalStateException("SDK初始化失败，请查看日志/检查AAR与系统兼容");
        }
    }
    public long beginScanSelection() {
        requireIdle(); initialize();
        phase=Phase.SCANNING;
        scanRequest=++requestSequence; scanSession=state.session();
        selectionCommitted=false; scanned.clear(); scanRunning=false;
        scanMessage="等待扫描页开始扫描"; message="选择主机中";
        notifyScreen(); return scanRequest;
    }
    public boolean scanValid(long request) {
        return initialized && phase==Phase.SCANNING && request!=0 && request==scanRequest
                && state.isCurrent(scanSession) && !selectionCommitted;
    }
    public void startScan(long request) {
        if (!scanValid(request)) throw new IllegalStateException("扫描子流程已失效，请返回重新选择");
        if (scanRunning) throw new IllegalStateException("扫描尚未结束，请先停止");
        final long generation=state.session(), round=++scanRound;
        scanRunning=true; scanned.clear(); scanMessage="扫描中，仅显示TR-FID-主机"; notifyScan();
        try {
            sdk.startScan(15000L,new ScanListener() {
                @Override public void onScanStart() { post(generation,()->{ if (scanCurrent(request,round)) { scanRunning=true; scanMessage="扫描中（15秒）"; notifyScan(); } }); }
                @Override public void onScanStop() { post(generation,()->{ if (scanCurrent(request,round)) { scanRunning=false; scanMessage="扫描停止，可选择已发现的主机或重新扫描"; notifyScan(); } }); }
                @Override public void onScanResult(Device device,boolean connectedBySystem) {
                    post(generation,()->{
                        if (!scanCurrent(request,round) || !scanRunning || device==null || device.getAddress()==null) return;
                        String name=device.getName();
                        if (name==null || !name.toUpperCase(Locale.ROOT).startsWith("TR-FID-")) return;
                        String key=device.getAddress().toUpperCase(Locale.ROOT);
                        if (scanned.size()>=200 && !scanned.containsKey(key)) return;
                        scanned.put(key,device); notifyScan();
                    });
                }
                @Override public void onScanError(ScannerExceptionType type,String error) {
                    post(generation,()->{
                        if (!scanCurrent(request,round)) return;
                        scanRunning=false; scanMessage="扫描失败："+type+" / "+bounded(error);
                        log("异常",scanMessage); notifyScan();
                    });
                }
            });
        } catch (RuntimeException | LinkageError error) {
            scanRunning=false; scanMessage="扫描异常："+safeError(error); log("异常",scanMessage); notifyScan();
        }
    }
    private boolean scanCurrent(long request,long round) { return scanValid(request) && round==scanRound; }
    public void stopScan(long request) {
        if (!scanValid(request)) return;
        ++scanRound;
        scanRunning=false; sdk.stopScan(); scanMessage="已请求停止扫描"; notifyScan();
    }
    public Device commitSelection(long request,String mac) {
        if (!scanValid(request)) throw new IllegalStateException("旧扫描结果不可用于新会话");
        Device selected=scanned.get(mac.toUpperCase(Locale.ROOT));
        if (selected==null) throw new IllegalArgumentException("请选择本轮发现的主机");
        ++scanRound;
        selectionCommitted=true; scanRunning=false; sdk.stopScan();
        return selected;
    }
    public void acceptSelection(long request,Device selected) {
        if (!initialized || phase!=Phase.SCANNING || request!=scanRequest || !selectionCommitted
                || !state.isCurrent(scanSession) || selected==null) throw new IllegalStateException("扫描返回已过期");
        Device current=scanned.get(selected.getAddress().toUpperCase(Locale.ROOT));
        if (current==null) throw new IllegalStateException("返回的设备不是本轮扫描结果");
        scanRequest=0; scanned.clear(); phase=Phase.IDLE;
        connect(current);
    }
    public void cancelSelection(long request) {
        if (request==scanRequest && phase==Phase.SCANNING) close("取消扫描选择",Phase.IDLE);
    }
    private void connect(Device device) {
        targetAddress=device.getAddress(); requestedHost="";
        beginConnection();
        setDevice(device);
        try { sdk.connect(device,connectionListener(state.session())); }
        catch (RuntimeException | LinkageError error) { close("连接异常："+safeError(error),Phase.DISCONNECTED); }
    }
    public void connectByHostId(String input) {
        String id=DetectorFilterParser.hostId(input);
        requireIdle(); initialize();
        targetAddress=""; requestedHost=id;
        beginConnection();
        phase=Phase.FINDING; message="扫描匹配主机编号 "+id;
        // The SDK's local finder timer may survive release. Do not start another session until it can expire.
        finderMayLiveUntil=SystemClock.elapsedRealtime()+18000L;
        log("状态","按主机编号匹配："+id+"（不是探测器ID）"); notifyScreen();
        try { sdk.connectByDeviceId(id,15000L,connectionListener(state.session())); }
        catch (RuntimeException | LinkageError error) { close("编号连接异常："+safeError(error),Phase.DISCONNECTED); }
    }
    private void beginConnection() {
        phase=Phase.CONNECTING; message="连接中，等待服务发现与通知就绪";
        mtu=0; packageSize=0; events.clear(); result="尚未发送关机命令";
        connectStarted=SystemClock.elapsedRealtime();
        connectionMayLiveUntil=connectStarted+40000L;
        final long generation=state.session();
        readyDeadline=()->{ if (active(generation) && !ready()) close("整体40秒未就绪；已结束等待，请核实设备",Phase.DISCONNECTED); };
        main.postDelayed(readyDeadline,40000); notifyScreen();
    }
    private XCConnectListener connectionListener(long generation) {
        return new XCConnectListener() {
            @Override public void onConnected(Device device) { post(generation,()->{
                if (!connectionPending() || !expectedDevice(device)) return;
                finderMayLiveUntil=0; setDevice(device); phase=Phase.SERVICE_DISCOVERED;
                message="服务已发现，正在协商MTU/开启FFE4通知，暂不能关机"; log("状态",message); notifyScreen();
            }); }
            @Override public void onReady(Device device,int actualMtu,int size) { post(generation,()->{
                if (!connectionPending() || !expectedDevice(device)) return;
                finderMayLiveUntil=0; connectionMayLiveUntil=0;
                cancelReady(); setDevice(device); mtu=actualMtu; packageSize=size;
                phase=Phase.READY; message="已就绪，可以接收探测器事件";
                log("状态","onReady MTU="+mtu+", 载荷="+size+" B，耗时="+(SystemClock.elapsedRealtime()-connectStarted)+"ms"); notifyScreen();
            }); }
            @Override public void onDisconnected() { post(generation,()->{
                boolean unknown=state.pending();
                close(unknown ? "ACK前断线，结果未知，请现场核实" : "主机BLE断开；不自动重连",unknown ? Phase.RESULT_UNKNOWN : Phase.DISCONNECTED);
            }); }
            @Override public void onFailed(String error) { post(generation,()->{
                if (connectionPending()) close("连接失败："+bounded(error),Phase.DISCONNECTED);
                else log("异常","忽略已就绪后的迟到连接失败："+bounded(error));
            }); }
        };
    }
    private boolean connectionPending() {
        return phase==Phase.FINDING || phase==Phase.CONNECTING || phase==Phase.SERVICE_DISCOVERED;
    }
    private boolean expectedDevice(Device device) {
        if (device==null || device.getAddress()==null) return false;
        if (!targetAddress.isEmpty()) return targetAddress.equalsIgnoreCase(device.getAddress());
        if (requestedHost.isEmpty()) return false;
        try {
            if (!requestedHost.equalsIgnoreCase(DetectorFilterParser.hostId(device.getName()))) return false;
            targetAddress=device.getAddress(); return true;
        } catch (IllegalArgumentException invalid) { return false; }
    }
    public void applyFilter(String input) {
        assertMain();
        if (phase==Phase.CLOSING || phase==Phase.COMMAND_PENDING) throw new IllegalStateException("请等待当前操作结束");
        List<String> parsed=DetectorFilterParser.parse(input);
        filter=new ArrayList<>(parsed);
        if (initialized) sdk.setDeviceIdFilter(parsed);
        log("状态",filterLabel()); notifyScreen();
    }
    public void setRawLogging(boolean enabled) { rawLogging=enabled; log("状态",enabled ? "原始JSON显示已开启（仅本地）" : "原始JSON显示已关闭；SDK内部日志单独控制"); }
    public void clearLogs() { logs.clear(); notifyScreen(); }
    public void clearEvents() { events.clear(); notifyScreen(); }
    public void shutdownAll(long confirmedSession) {
        assertMain();
        if (confirmedSession!=state.session() || !ready() || state.pending()) throw new IllegalStateException("目标会话已改变或尚未就绪，请重新核对");
        final long generation=state.session(), token=state.beginCommand();
        commandStarted=SystemClock.elapsedRealtime();
        phase=Phase.COMMAND_PENDING; result="等待设备ACK…不自动重发"; message="一键关机命令执行中";
        log("状态","用户确认对当前主机执行一键关机，白名单不限制关机范围"); notifyScreen();
        // SDK has its own 5s timeout. App deadline is a final guard, not a replacement or retry.
        commandDeadline=()->{ if (active(generation) && state.commandCurrent(token)) close("App等待ACK超时，结果未知，不自动重发",Phase.RESULT_UNKNOWN); };
        main.postDelayed(commandDeadline,8000);
        try {
            sdk.shutdownAll(new XCCommandCallback() {
                @Override public void onSuccess() { post(generation,()->{
                    if (!state.finishCommand(token)) return;
                    cancelCommand(); result="设备ACK status=ok；需另行核实实际断电，设备可能随后断开";
                    log("状态",result+"，耗时="+(SystemClock.elapsedRealtime()-commandStarted)+"ms");
                    // No further shutdown on the same channel: protocol has no request ID.
                    close(result,Phase.DISCONNECTED);
                }); }
                @Override public void onFailed(String error) { post(generation,()->{
                    if (!state.finishCommand(token)) return;
                    cancelCommand(); result="关机未确认："+bounded(error)+"；结果可能未知，不自动重发";
                    close(result,Phase.RESULT_UNKNOWN);
                }); }
            });
        } catch (RuntimeException | LinkageError error) { close("关机异常："+safeError(error)+"，结果未知",Phase.RESULT_UNKNOWN); }
    }
    public void release(String reason) { close(reason,state.pending() ? Phase.RESULT_UNKNOWN : Phase.IDLE); }
    public void onBackground() {
        if (initialized || phase==Phase.SCANNING || phase==Phase.FINDING) close("App退后台，结束设备会话；未确认命令须现场核实",state.pending() ? Phase.RESULT_UNKNOWN : Phase.IDLE);
    }
    private void close(String reason,Phase after) {
        assertMain();
        if (phase==Phase.CLOSING) return;
        final boolean wasInitialized=initialized;
        final long generation=state.next();
        initialized=false; scanRunning=false; selectionCommitted=false; scanRequest=0; ++scanRound;
        scanned.clear(); cancelReady(); cancelCommand();
        if (phase==Phase.COMMAND_PENDING && after==Phase.RESULT_UNKNOWN) result="结果未知："+reason;
        phase=Phase.CLOSING; mtu=0; packageSize=0;
        message=reason; filter=new ArrayList<>();
        log("状态",reason+"；会话已失效，清理中"); notifyScreen(); notifyScan();
        if (wasInitialized && sdk!=null) cleanupSdk();
        long wait=Math.max(0,Math.max(finderMayLiveUntil,connectionMayLiveUntil)-SystemClock.elapsedRealtime());
        if (wait>0) { message=reason+"\n旧扫描/连接可能有迟到任务，等本轮截止后再开放新会话"; notifyScreen(); }
        // Waiting is tied to the SDK finder deadline, not a fixed delay claiming release completion.
        main.postDelayed(()->{
            if (!state.isCurrent(generation)) return;
            if (wasInitialized && sdk!=null && wait>0) cleanupSdk();
            main.post(()->main.post(()->{
                if (!state.isCurrent(generation)) return;
                finderMayLiveUntil=0; connectionMayLiveUntil=0;
                targetAddress=""; requestedHost="";
                phase=after; message=reason+(requiresRestart ? "\n清理出现异常，请关闭并重新启动App后核实设备" : "\nApp清理任务已执行，可手动重新选择；不等于设备资源已通过验证");
                notifyScreen(); notifyScan();
            }));
        },wait);
    }
    private void cleanupSdk() {
        try {
            sdk.stopScan(); sdk.setRawJsonListener(null); sdk.setOnPowerChangeListener(null);
            sdk.setOnDevicePowerListener(null); sdk.clearDeviceIdFilter(); sdk.disconnect(); sdk.release();
        } catch (RuntimeException | LinkageError error) {
            requiresRestart=true;
            log("异常","SDK清理异常："+safeError(error)+"；请关闭App并核实设备");
        }
    }
    private boolean active(long generation) { return initialized && state.isCurrent(generation) && phase!=Phase.CLOSING; }
    private void post(long generation,Runnable action) { main.post(()->{ if (active(generation)) action.run(); }); }
    private boolean acceptReports() { return phase==Phase.READY || phase==Phase.COMMAND_PENDING; }
    private void requireIdle() { assertMain(); if (!idle()) throw new IllegalStateException("已有扫描/连接/操作或清理过程，请先结束当前会话"); }
    private void cancelReady() { if (readyDeadline!=null) main.removeCallbacks(readyDeadline); readyDeadline=null; }
    private void cancelCommand() { if (commandDeadline!=null) main.removeCallbacks(commandDeadline); commandDeadline=null; }
    private void setDevice(Device device) {
        deviceName=device.getName()==null ? "未命名主机" : device.getName(); address=device.getAddress();
        host=new XcDevice(device).serialNo();
        if (host.isEmpty()) { try { host=DetectorFilterParser.hostId(deviceName); } catch (IllegalArgumentException ignored) { host="未识别"; } }
    }
    private void event(String type,String id) { events.add(new Row(now(),type,"主机="+host+" / device_id="+bounded(id))); notifyScreen(); }
    private void log(String kind,String text) { logs.add(new Row(now(),kind,bounded(text))); notifyScreen(); }
    private void notifyScreen() { if (screen!=null) screen.render(); }
    private void notifyScan() { if (scanScreen!=null) scanScreen.renderScan(); }
    private static String now() { return new SimpleDateFormat("HH:mm:ss.SSS",Locale.getDefault()).format(new Date()); }
    private static String bounded(String value) {
        if (value==null) return "未知";
        return value.length()<=4096 ? value : value.substring(0,4096)+"…（已截断）";
    }
    private static String safeError(Throwable error) { return error.getClass().getSimpleName()+": "+bounded(error.getMessage()); }
    private static String join(List<String> items) { StringBuilder s=new StringBuilder(); for (String id:items) { if (s.length()>0)s.append(" / ");s.append(id); }return s.toString(); }
    private static void assertMain() { if (Looper.myLooper()!=Looper.getMainLooper()) throw new IllegalStateException("Controller必须在主线程调用"); }
}
