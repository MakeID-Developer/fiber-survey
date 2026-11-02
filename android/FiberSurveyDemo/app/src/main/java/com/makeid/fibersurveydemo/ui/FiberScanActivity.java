package com.makeid.fibersurveydemo.ui;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Toast;
import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import com.makeid.blelibrary.bean.Device;
import com.makeid.fibersurveydemo.FiberSurveyController;
import com.makeid.fibersurveydemo.SurveyApplication;
import com.makeid.fibersurveydemo.databinding.ActivityFiberScanBinding;

/** Borrows one scan request. It must never initialize or release the shared SDK. */
public final class FiberScanActivity extends AppCompatActivity implements FiberSurveyController.ScanScreen {
    private ActivityFiberScanBinding binding;
    private FiberSurveyController controller;
    private BlePermissionHelper permission;
    private XcScanListAdapter adapter;
    private long scanRequest;
    private boolean selected, startedOnce;
    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved); EdgeToEdge.enable(this);
        binding=ActivityFiberScanBinding.inflate(getLayoutInflater()); setContentView(binding.getRoot());
        ViewCompat.setOnApplyWindowInsetsListener(binding.getRoot(),(view,insets)->{
            Insets safe=insets.getInsets(WindowInsetsCompat.Type.systemBars());
            int pad=(int)(16*getResources().getDisplayMetrics().density);
            view.setPadding(safe.left+pad,safe.top+pad,safe.right+pad,safe.bottom+pad); return insets;
        });
        controller=((SurveyApplication)getApplication()).controller(); permission=new BlePermissionHelper(this);
        scanRequest=getIntent().getLongExtra("scanRequest",0);
        adapter=new XcScanListAdapter(this::select);
        binding.devices.setLayoutManager(new LinearLayoutManager(this)); binding.devices.setAdapter(adapter);
        binding.rescan.setOnClickListener(v->scan());
        binding.stop.setOnClickListener(v->controller.stopScan(scanRequest));
        binding.back.setOnClickListener(v->finish());
    }
    private void scan() {
        permission.run(()->{
            try { controller.startScan(scanRequest); }
            catch (RuntimeException | LinkageError error) { toast("无法扫描："+error.getMessage()); finish(); }
        });
    }
    private void select(Device device) {
        if (selected) return;
        try {
            if (!permission.ready()) return;
            Device verified=controller.commitSelection(scanRequest,device.getAddress());
            selected=true;
            Intent result=new Intent(); result.putExtra("scanRequest",scanRequest); result.putExtra("device",verified);
            setResult(RESULT_OK,result); finish();
        } catch (RuntimeException error) { toast("选择已过期，请返回重试"); finish(); }
    }
    @Override public void renderScan() {
        if (binding==null || isDestroyed()) return;
        boolean valid=controller.scanValid(scanRequest);
        binding.status.setText(valid?controller.scanMessage()+"\n"+controller.devices().size()+"台唯一主机，点击后连接":"扫描会话已失效，请返回重新选择");
        binding.rescan.setEnabled(valid && !controller.scanRunning()); binding.stop.setEnabled(valid && controller.scanRunning());
        adapter.submit(valid?controller.devices():java.util.Collections.emptyList());
    }
    @Override protected void onStart() { super.onStart(); controller.attachScan(this); }
    @Override protected void onResume() {
        super.onResume(); permission.onResume();
        if (!controller.scanValid(scanRequest)) { toast("会话已关闭，请从首页重新扫描"); finish(); return; }
        if (!startedOnce) { startedOnce=true; scan(); }
    }
    @Override protected void onPause() { permission.onPause(); super.onPause(); }
    @Override protected void onStop() {
        if (!selected) controller.stopScan(scanRequest);
        controller.detachScan(this); super.onStop();
    }
    @Override protected void onDestroy() {
        permission.cancel();
        if (isFinishing() && !selected) controller.cancelSelection(scanRequest);
        controller.detachScan(this); binding=null; super.onDestroy();
    }
    @Override public void onRequestPermissionsResult(int code,String[] permissions,int[] results) {
        super.onRequestPermissionsResult(code,permissions,results); permission.result(code,results);
    }
    private void toast(String text) { Toast.makeText(this,text,Toast.LENGTH_LONG).show(); }
}
