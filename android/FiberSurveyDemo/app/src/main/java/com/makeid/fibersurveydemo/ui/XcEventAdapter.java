package com.makeid.fibersurveydemo.ui;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.makeid.fibersurveydemo.FiberSurveyController;
import com.makeid.fibersurveydemo.R;
import java.util.List;

public final class XcEventAdapter extends RecyclerView.Adapter<XcEventAdapter.Holder> {
    private List<FiberSurveyController.Row> rows=java.util.Collections.emptyList();
    public void submit(List<FiberSurveyController.Row> rows) { this.rows=rows; notifyDataSetChanged(); }
    @NonNull @Override public Holder onCreateViewHolder(@NonNull ViewGroup parent,int type) {
        return new Holder(LayoutInflater.from(parent.getContext()).inflate(R.layout.item_xcfiber_event,parent,false));
    }
    @Override public void onBindViewHolder(@NonNull Holder holder,int index) {
        FiberSurveyController.Row row=rows.get(index);
        holder.time.setText(row.time); holder.kind.setText(row.kind); holder.text.setText(row.text);
        int color="power_up".equals(row.kind)?0xff2e7d32:"Power_On".equals(row.kind)?0xff1565c0:"Power_Off".equals(row.kind)?0xff546e7a:0xffb85e00;
        holder.kind.setTextColor(color);
    }
    @Override public int getItemCount() { return rows.size(); }
    static final class Holder extends RecyclerView.ViewHolder {
        final TextView time,kind,text;
        Holder(View view) { super(view); time=view.findViewById(R.id.tv_time); kind=view.findViewById(R.id.tv_kind); text=view.findViewById(R.id.tv_text); }
    }
}
