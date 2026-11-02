package com.makeid.fibersurveydemo.ui;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.widget.Toast;

/** The same runtime/hardware gate protects scan and connect-by-host-ID. No third-party permission SDK. */
public final class BlePermissionHelper {
    public static final int REQUEST=8801;
    private final Activity activity;
    private Runnable pending;
    private boolean resumed, awaitingResult;
    public BlePermissionHelper(Activity activity) { this.activity=activity; }
    private String[] permissions() {
        return Build.VERSION.SDK_INT>=31
                ? new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT}
                : new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION};
    }
    public void run(Runnable action) {
        if (pending!=null) { toast("权限请求尚未结束"); return; }
        pending=action;
        if (Build.VERSION.SDK_INT>=23) for (String permission:permissions()) {
            if (activity.checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED) {
                awaitingResult=true;
                activity.requestPermissions(permissions(),REQUEST); return;
            }
        }
        proceed();
    }
    public void result(int code,int[] results) {
        if (code!=REQUEST || pending==null) return;
        awaitingResult=false;
        if (results.length!=permissions().length) { pending=null; toast("权限请求已取消"); return; }
        for (int value:results) if (value!=PackageManager.PERMISSION_GRANTED) {
            pending=null; toast("权限未授予，请到系统设置处理后重试"); return;
        }
        proceed();
    }
    public boolean granted() {
        if (Build.VERSION.SDK_INT>=23) for (String permission:permissions())
            if (activity.checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED) return false;
        return true;
    }
    public void onResume() { resumed=true; proceed(); }
    public void onPause() { resumed=false; }
    private void proceed() {
        if (!resumed || awaitingResult || pending==null) return;
        Runnable action=pending; pending=null;
        try {
            if (!ready()) return;
            if (action!=null) action.run();
        } catch (RuntimeException error) { toast("无法执行蓝牙操作："+error.getClass().getSimpleName()); }
    }
    public boolean ready() {
        if (!granted()) { toast("请先授予蓝牙/定位权限"); return false; }
        if (!activity.getPackageManager().hasSystemFeature("android.hardware.bluetooth_le")) { toast("此设备不支持BLE"); return false; }
        BluetoothAdapter adapter=BluetoothAdapter.getDefaultAdapter();
        if (adapter==null || !adapter.isEnabled()) { toast("请先在系统设置打开蓝牙，再手动重试"); return false; }
        if (Build.VERSION.SDK_INT>=23 && Build.VERSION.SDK_INT<31) {
            LocationManager location=(LocationManager)activity.getSystemService(Activity.LOCATION_SERVICE);
            if (location==null || (!location.isProviderEnabled(LocationManager.GPS_PROVIDER)
                    && !location.isProviderEnabled(LocationManager.NETWORK_PROVIDER))) {
                toast("Android 6～11扫描还需打开系统定位服务"); return false;
            }
        }
        return true;
    }
    public void cancel() { pending=null; awaitingResult=false; }
    private void toast(String value) { Toast.makeText(activity,value,Toast.LENGTH_LONG).show(); }
}
