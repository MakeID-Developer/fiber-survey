package com.makeid.fibersurveydemo.ui;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.makeid.blelibrary.bean.Device;
import com.makeid.fibersurveydemo.R;
import com.makeid.fibersurveydemo.core.DetectorFilterParser;
import java.util.List;

/** Controller's MAC-keyed inventory supplies unique devices and latest RSSI. */
public final class XcScanListAdapter extends RecyclerView.Adapter<XcScanListAdapter.Holder> {
    public interface Select { void select(Device device); }
    private List<Device> devices=java.util.Collections.emptyList();
    private final Select select;
    public XcScanListAdapter(Select select) { this.select=select; }
    public void submit(List<Device> devices) { this.devices=devices; notifyDataSetChanged(); }
    @NonNull @Override public Holder onCreateViewHolder(@NonNull ViewGroup parent,int type) {
        return new Holder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_xcfiber_scan,parent,false));
    }
    @Override public void onBindViewHolder(@NonNull Holder holder,int position) {
        Device device=devices.get(position);
        String name=device.getName();
        holder.name.setText(name==null ? "未命名" : name);
        String host="未识别";
        try { host=DetectorFilterParser.hostId(name); } catch (IllegalArgumentException ignored) { }
        holder.address.setText(device.getAddress()+"\n主机编号="+host);
        int rssi=device.getRssi(); holder.rssi.setText("RSSI "+rssi+" dBm");
        holder.rssi.setTextColor(rssi>=-60?0xff2e7d32:rssi>=-80?0xffb85e00:0xffc62828);
        holder.itemView.setOnClickListener(v->select.select(device));
    }
    @Override public int getItemCount() { return devices.size(); }
    static final class Holder extends RecyclerView.ViewHolder {
        final TextView name,address,rssi;
        Holder(View view) { super(view); name=view.findViewById(R.id.tv_name); address=view.findViewById(R.id.tv_address); rssi=view.findViewById(R.id.tv_rssi); }
    }
}
