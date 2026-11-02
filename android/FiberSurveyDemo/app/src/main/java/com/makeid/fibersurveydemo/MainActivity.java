package com.makeid.fibersurveydemo;

import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.Toast;
import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import com.makeid.blelibrary.bean.Device;
import com.makeid.fibersurveydemo.core.SessionState.Phase;
import com.makeid.fibersurveydemo.databinding.ActivityMainBinding;
import com.makeid.fibersurveydemo.ui.*;
import java.util.List;

public final class MainActivity extends AppCompatActivity implements FiberSurveyController.Screen {
    private static final int SCAN_PAGE=5501;
    private ActivityMainBinding binding;
    private FiberSurveyController controller;
    private BlePermissionHelper permission;
    private XcLogAdapter logAdapter;
    private XcEventAdapter eventAdapter;
    private LinearLayoutManager logLayout;
    private List<FiberSurveyController.Row> shownLogs=java.util.Collections.emptyList();
    private List<FiberSurveyController.Row> shownEvents=java.util.Collections.emptyList();
    private long scanRequest;
    private Device returnedDevice;
    private long returnedRequest;
    private boolean resumed;
    private AlertDialog confirmation;

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        EdgeToEdge.enable(this);
        binding=ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());
        ViewCompat.setOnApplyWindowInsetsListener(binding.getRoot(),(view,insets)->{
            Insets safe=insets.getInsets(WindowInsetsCompat.Type.systemBars()|WindowInsetsCompat.Type.ime());
            view.setPadding(safe.left,safe.top,safe.right,safe.bottom); return insets;
        });
        controller=((SurveyApplication)getApplication()).controller();
        permission=new BlePermissionHelper(this);
        if (savedInstanceState!=null) {
            scanRequest=savedInstanceState.getLong("scanRequest",0);
            returnedDevice=savedInstanceState.getParcelable("pendingDevice");
            returnedRequest=savedInstanceState.getLong("pendingRequest",0);
        }
        logAdapter=new XcLogAdapter(); eventAdapter=new XcEventAdapter();
        logLayout=new LinearLayoutManager(this);
        binding.logList.setLayoutManager(logLayout); binding.logList.setAdapter(logAdapter);
        binding.eventList.setLayoutManager(new LinearLayoutManager(this)); binding.eventList.setAdapter(eventAdapter);
        binding.rawLog.setChecked(controller.rawLogging());
        binding.rawLog.setOnCheckedChangeListener((button,checked)->controller.setRawLogging(checked));
        binding.clearLog.setOnClickListener(v->controller.clearLogs());
        binding.clearEvents.setOnClickListener(v->controller.clearEvents());
        binding.filterInput.setText(android.text.TextUtils.join(",",controller.filter()));
        binding.scan.setOnClickListener(v->permission.run(()->safe(this::openScanner)));
        binding.connectId.setOnClickListener(v->permission.run(()->safe(()->{
            if (resumed && !isFinishing()) controller.connectByHostId(binding.hostId.getText().toString());
        })));
        binding.applyFilter.setOnClickListener(v->safe(()->controller.applyFilter(binding.filterInput.getText().toString())));
        binding.clearFilter.setOnClickListener(v->safe(()->{ binding.filterInput.setText(""); controller.applyFilter(""); }));
        binding.shutdown.setOnClickListener(v->safe(this::confirmShutdown));
        binding.disconnect.setOnClickListener(v->safe(()->controller.release("用户断开连接")));
        binding.release.setOnClickListener(v->safe(()->controller.release("用户释放/取消等待")));
        binding.about.setOnClickListener(v->new AlertDialog.Builder(this).setTitle("FiberSurveyDemo 1.0")
                .setMessage("本地BLE参考Demo，无网络请求与SDK鉴权。\nSDK：XCFiberCheck 1.0 / BLE 1.1\n包名："+getPackageName()
                        +"\n主机编号不是探测器ID。白名单不限制关机范围。\n\n已做源码静态检查，未编译、打包或真机验证。请在受控环境确认权限、设备固件、关机和SDK兼容性，不能把ACK当作全部设备已断电。")
                .setPositiveButton("知道了",null).show());
    }
    private void openScanner() {
        if (!resumed || isFinishing()) return;
        scanRequest=controller.beginScanSelection();
        Intent intent=new Intent(this,FiberScanActivity.class);
        intent.putExtra("scanRequest",scanRequest); // Non-secret nonce; no SDK owner or connection is passed.
        try { startActivityForResult(intent,SCAN_PAGE); }
        catch (RuntimeException error) { controller.cancelSelection(scanRequest); scanRequest=0; throw error; }
    }
    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data) {
        super.onActivityResult(requestCode,resultCode,data);
        if (requestCode!=SCAN_PAGE) return;
        if (resultCode!=RESULT_OK || data==null) {
            controller.cancelSelection(scanRequest); scanRequest=0; return;
        }
        returnedRequest=data.getLongExtra("scanRequest",0);
        returnedDevice=data.getParcelableExtra("device");
        if (resumed) consumeScanResult();
    }
    private void consumeScanResult() {
        if (returnedDevice==null) return;
        final Device device=returnedDevice; final long request=returnedRequest;
        returnedDevice=null; returnedRequest=0;
        safe(()->{
            if (request==0 || request!=scanRequest) throw new IllegalStateException("扫描返回已过期，请重新选择主机");
            if (!permission.ready()) { controller.cancelSelection(request); return; }
            controller.acceptSelection(request,device);
        });
        scanRequest=0;
    }
    private void confirmShutdown() {
        if (!controller.ready()) throw new IllegalStateException("尚未通知就绪或已有命令在途");
        final long session=controller.session();
        confirmation=new AlertDialog.Builder(this).setTitle("确认一键关机")
                .setMessage("当前主机：\n"+controller.deviceLabel()+"\n\n此命令按设备协议影响全部范围，探测器白名单不会限制关机。请确认现场设备和实际授权。超时/断线可能结果未知，不自动补发。")
                .setNegativeButton("取消",null)
                .setPositiveButton("确认关机",(dialog,which)->safe(()->{
                    if (!resumed || !permission.ready()) return;
                    controller.shutdownAll(session);
                })).create();
        confirmation.setOnDismissListener(dialog->confirmation=null); confirmation.show();
    }
    @Override public void render() {
        if (binding==null || isDestroyed()) return;
        boolean idle=controller.idle();
        Phase phase=controller.phase();
        binding.status.setText(controller.message());
        binding.status.setTextColor(phase==Phase.READY?0xff2e7d32:phase==Phase.RESULT_UNKNOWN?0xffb3261e:0xff53676b);
        binding.device.setText(controller.deviceLabel());
        binding.mtu.setText("MTU / 载荷："+controller.mtuLabel());
        binding.mtuWarning.setVisibility(controller.fragmentedCommand()?View.VISIBLE:View.GONE);
        binding.scan.setEnabled(idle); binding.connectId.setEnabled(idle); binding.hostId.setEnabled(idle);
        binding.shutdown.setEnabled(controller.ready());
        binding.disconnect.setEnabled(phase!=Phase.IDLE && phase!=Phase.CLOSING);
        binding.release.setEnabled(phase!=Phase.CLOSING);
        boolean editable=phase!=Phase.CLOSING && phase!=Phase.COMMAND_PENDING;
        binding.filterInput.setEnabled(editable); binding.applyFilter.setEnabled(editable); binding.clearFilter.setEnabled(editable);
        binding.filterState.setText(controller.filterLabel()); binding.result.setText(controller.result());
        if (confirmation!=null && !controller.ready()) confirmation.dismiss();
        updateLogs(controller.logs());
        List<FiberSurveyController.Row> events=controller.events();
        if (!sameRows(shownEvents,events)) {
            shownEvents=events; eventAdapter.submit(events);
            if (!events.isEmpty()) binding.eventList.scrollToPosition(0);
        }
    }
    private void updateLogs(List<FiberSurveyController.Row> rows) {
        if (sameRows(shownLogs,rows)) return;
        int first=logLayout.findFirstVisibleItemPosition();
        View firstView=first<0?null:logLayout.findViewByPosition(first);
        int offset=firstView==null?0:firstView.getTop()-binding.logList.getPaddingTop();
        FiberSurveyController.Row anchor=first>=0 && first<shownLogs.size()?shownLogs.get(first):null;
        boolean follow=binding.followLog.isChecked() && first<=0;
        shownLogs=rows; logAdapter.submit(rows);
        if (rows.isEmpty()) return;
        if (follow) logLayout.scrollToPositionWithOffset(0,0);
        else if (anchor!=null) {
            int target=rows.indexOf(anchor);
            if (target>=0) logLayout.scrollToPositionWithOffset(target,offset);
        }
    }
    private static boolean sameRows(List<?> left,List<?> right) {
        return left.size()==right.size() && (left.isEmpty() || left.get(0)==right.get(0));
    }
    private void safe(Runnable action) {
        try { action.run(); }
        catch (RuntimeException | LinkageError error) { Toast.makeText(this,error.getMessage()==null?error.getClass().getSimpleName():error.getMessage(),Toast.LENGTH_LONG).show(); }
    }
    @Override protected void onStart() { super.onStart(); controller.attach(this); }
    @Override protected void onResume() {
        super.onResume(); resumed=true; permission.onResume();
        if (!permission.granted() && !controller.idle()) controller.release("权限已变化，请重新确认");
        consumeScanResult(); render();
    }
    @Override protected void onPause() {
        resumed=false; permission.onPause();
        if (confirmation!=null) confirmation.dismiss();
        super.onPause();
    }
    @Override protected void onStop() { controller.detach(this); super.onStop(); }
    @Override protected void onSaveInstanceState(Bundle out) {
        out.putLong("scanRequest",scanRequest);
        if (returnedDevice!=null && returnedRequest==scanRequest) {
            out.putParcelable("pendingDevice",returnedDevice); out.putLong("pendingRequest",returnedRequest);
        }
        super.onSaveInstanceState(out);
    }
    @Override protected void onDestroy() {
        permission.cancel();
        if (isFinishing()) controller.release("退出对纤仪页面");
        controller.detach(this); binding=null; super.onDestroy();
    }
    @Override public void onRequestPermissionsResult(int code,String[] permissions,int[] results) {
        super.onRequestPermissionsResult(code,permissions,results); permission.result(code,results);
    }
}
