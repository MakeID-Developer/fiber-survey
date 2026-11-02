package com.makeid.fibersurveydemo.core;

import java.util.ArrayList;
import java.util.List;

/** Main-thread owned, newest first, snapshots cannot mutate the store. */
public final class BoundedLogStore<T> {
    private final int capacity;
    private final List<T> items=new ArrayList<>();
    public BoundedLogStore(int capacity) {
        if (capacity<1) throw new IllegalArgumentException("capacity must be positive");
        this.capacity=capacity;
    }
    public void add(T item) {
        items.add(0,item);
        if (items.size()>capacity) items.subList(capacity,items.size()).clear();
    }
    public List<T> snapshot() { return new ArrayList<>(items); }
    public void clear() { items.clear(); }
}
