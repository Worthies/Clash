package com.github.worthies.clash;

import android.app.Application;
import android.util.Log;

public class ClashApplication extends Application {
    private static final String TAG = "ClashApplication";

    @Override
    public void onCreate() {
        super.onCreate();

        // No native tun2socks engine is used any more; the VPN service runs
        // an in-process TUN processor. No native cleanup required at startup.
        Log.d(TAG, "Startup: native tun2socks engine not used (in-process TUN processor enabled)");

        // Install a default uncaught exception handler to perform cleanup before crash
        final Thread.UncaughtExceptionHandler defaultHandler = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            Log.e(TAG, "Uncaught exception in thread " + thread.getName() + ", attempting graceful cleanup", throwable);
            try {
                // Ask the running service instance to stop (if present)
                try {
                    ClashVpnService svc = ClashVpnService.getRunningInstance();
                    if (svc != null) {
                        svc.requestStopService();
                    }
                } catch (Throwable ignore) {}

                // No native engine used anymore; rely on the running service
                // instance to perform appropriate cleanup.
            } catch (Throwable ignore) {
            } finally {
                // delegate to previous handler to preserve platform behavior
                if (defaultHandler != null) {
                    defaultHandler.uncaughtException(thread, throwable);
                } else {
                    // If no default handler, kill process
                    android.os.Process.killProcess(android.os.Process.myPid());
                    System.exit(10);
                }
            }
        });
    }
}
