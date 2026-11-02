package com.makeid.fibersurveydemo;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

/** App-visible lifecycle owner shared by the operation page and its scan child. No automatic SDK init. */
public final class SurveyApplication extends Application {
    private int started;
    private final Handler main=new Handler(Looper.getMainLooper());
    private FiberSurveyController controller;
    public FiberSurveyController controller() { return controller; }
    public boolean visible() { return started>0; }
    private final Runnable background=()->{ if (started==0 && controller!=null) controller.onBackground(); };
    @Override public void onCreate() {
        super.onCreate();
        controller=new FiberSurveyController(this);
        registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
            @Override public void onActivityStarted(Activity activity) {
                started++; main.removeCallbacks(background);
            }
            @Override public void onActivityStopped(Activity activity) {
                started=Math.max(0,started-1);
                if (started==0 && !activity.isChangingConfigurations()) main.post(background);
            }
            @Override public void onActivityCreated(Activity activity,Bundle saved) { }
            @Override public void onActivityResumed(Activity activity) { }
            @Override public void onActivityPaused(Activity activity) { }
            @Override public void onActivitySaveInstanceState(Activity activity,Bundle out) { }
            @Override public void onActivityDestroyed(Activity activity) { }
        });
    }
}
