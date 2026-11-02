package com.makeid.fibersurveydemo.core;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class DetectorFilterParser {
    private DetectorFilterParser() { }
    public static List<String> parse(String raw) {
        List<String> out = new ArrayList<>();
        if (raw == null || raw.trim().isEmpty()) return out;
        for (String part : raw.split("[,，;；\\s]+")) {
            String id=part.trim();
            if (id.isEmpty()) continue;
            if (id.length()>128) throw new IllegalArgumentException("探测器ID过长（上限128字符）");
            boolean duplicate=false;
            for (String old : out) if (old.equalsIgnoreCase(id)) { duplicate=true; break; }
            if (!duplicate) out.add(id);
            if (out.size()>200) throw new IllegalArgumentException("示例白名单最多200个ID");
        }
        return out;
    }
    public static String hostId(String raw) {
        String value=raw==null ? "" : raw.trim();
        if (value.toUpperCase(Locale.ROOT).startsWith("TR-FID-")) value=value.substring(7).trim();
        if (value.isEmpty()) throw new IllegalArgumentException("请输入主机编号，例如000002，不是探测器ID");
        if (value.length()>64 || value.matches(".*\\s+.*")) throw new IllegalArgumentException("主机编号格式不正确");
        return value;
    }
}
