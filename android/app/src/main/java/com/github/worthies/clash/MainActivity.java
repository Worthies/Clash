package com.github.worthies.clash;

import android.net.VpnService;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.content.Intent;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import android.content.Context;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import org.json.JSONObject;

/**
 * Flutter main activity for Clash VPN application.
 * Provides native VPN service methods to Flutter.
 * Note: Uses startActivityForResult/onActivityResult for FlutterActivity
 * compatibility.
 */
public class MainActivity extends FlutterActivity {
    private static final String TAG = "ClashVPN";
    private static final String CHANNEL = "com.github.worthies.clash/vpn";
    private static final int VPN_PERMISSION_REQUEST = 1;
    private MethodChannel.Result pendingVpnResult = null;
    private java.util.HashMap<String, Object> pendingVpnArgs = null;
    private MethodChannel methodChannel = null; // Store channel reference for error callbacks
    // Relay removed — proxy socket protection is handled via VPN routing and
    // shouldProtectTarget logic.
    private BroadcastReceiver vpnStoppedReceiver = null;
    // Legacy permission flow using startActivityForResult for maximum compatibility

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Using the legacy startActivityForResult/ onActivityResult flow
        // Register a receiver to react to VPN stopped and error events
        vpnStoppedReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                String action = intent.getAction();
                if ("com.github.worthies.clash.ACTION_VPN_STOPPED".equals(action)) {
                    Log.d(TAG, "VPN stopped broadcast received");
                    notifyFlutter("vpn_stopped", null);
                } else if ("com.github.worthies.clash.ACTION_VPN_START_FAILED".equals(action)) {
                    String error = intent.getStringExtra("error");
                    Log.e(TAG, "VPN start failed: " + error);
                    notifyFlutter("vpn_error", error != null ? error : "Unknown VPN startup error");
                }
            }
        };
        try {
            IntentFilter filter = new IntentFilter();
            filter.addAction("com.github.worthies.clash.ACTION_VPN_STOPPED");
            filter.addAction("com.github.worthies.clash.ACTION_VPN_START_FAILED");
            registerReceiver(vpnStoppedReceiver, filter);
        } catch (Exception e) {
            Log.w(TAG, "registerReceiver failed: " + e.getMessage());
        }
    }

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        methodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        methodChannel.setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "startVpn":
                            startVpn(call.arguments, result);
                            break;
                        case "stopVpn":
                            stopVpn(result);
                            break;
                        case "updateProxyNode":
                            updateVpnNode(call.arguments, result);
                            break;
                        case "isVpnRunning":
                            result.success(isVpnServiceRunning());
                            break;
                        case "setRules":
                            setVpnRules(call.arguments, result);
                            break;
                        default:
                            result.notImplemented();
                    }
                });

        // Relay channel removed: no-op, we use VPN routing rules & native protections
        // instead.
    }

    private void setVpnRules(Object argsObj, MethodChannel.Result result) {
        try {
            if (!(argsObj instanceof java.util.List)) {
                Log.e(TAG, "setRules: invalid args, expected list");
                result.error("INVALID_ARGS", "Expected list of rules", null);
                return;
            }
            @SuppressWarnings("unchecked")
            java.util.List<java.util.Map<String, Object>> list = (java.util.List<java.util.Map<String, Object>>) argsObj;
            ClashVpnService svc = ClashVpnService.getRunningInstance();
            if (svc == null) {
                java.util.HashMap<String, Object> map = new java.util.HashMap<>();
                map.put("ok", false);
                map.put("status", "failed");
                map.put("message", "VPN service not running");
                result.success(map);
                return;
            }

            // Forward rules to service and log a short summary for diagnostics
            Log.d(TAG, "setRules received: total rules=" + (list == null ? 0 : list.size()));
            int skippedDirectCount = 0, parsedRuleCount = 0;
            for (java.util.Map<String, Object> ritem : list) {
                try {
                    String t = ritem.get("type") != null ? ritem.get("type").toString() : "";
                    String p = ritem.get("payload") != null ? ritem.get("payload").toString() : "";
                    String pr = ritem.get("proxy") != null ? ritem.get("proxy").toString() : "";
                    if (pr != null && pr.equalsIgnoreCase("DIRECT")) skippedDirectCount++; else parsedRuleCount++;
                } catch (Exception ignored) {}



            }

            Log.d(TAG, "setRules payload=" + list);
            Log.d(TAG, "setRules: parsed=" + parsedRuleCount + " skipped_direct=" + skippedDirectCount);
            // Log up to the first 12 rules for debugging
            int toLog = Math.min(list.size(), 12);
            for (int i = 0; i < toLog; i++) {
                try { Log.d(TAG, "rule[" + i + "]=" + list.get(i)); } catch (Exception ignored) {}
            }

            // Routing rules feature removed - VPN now captures all traffic via default routes
            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
            map.put("ok", true);
            map.put("status", "deprecated");
            map.put("message", "Routing rules feature removed - VPN uses default routes");
            result.success(map);
        } catch (Exception e) {
            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
            map.put("ok", false);
            map.put("status", "failed");
            map.put("message", e.getMessage());
            result.success(map);
        }
    }

    /**
     * Start VPN service (called from Flutter).
     */
    private void startVpn(Object argsObj, MethodChannel.Result result) {
        try {
            // Save args so we can use them after the permission flow
            if (argsObj instanceof java.util.Map) {
                try {
                    //noinspection unchecked
                    pendingVpnArgs = new java.util.HashMap<>((java.util.Map<String, Object>) argsObj);
                } catch (Exception ignored) { pendingVpnArgs = null; }
            } else {
                pendingVpnArgs = null;
            }
            Intent intent = VpnService.prepare(this);
            if (intent != null) {
                // Permission required. Store the result to reply after user action.
                pendingVpnResult = result;
                // Legacy flow: use startActivityForResult which is available across Flutter embeddings
                startActivityForResult(intent, VPN_PERMISSION_REQUEST);
            } else {
                //
                startVpnService(pendingVpnArgs);
                java.util.HashMap<String, Object> map = new java.util.HashMap<>();
                map.put("ok", true);
                map.put("status", "started");
                map.put("message", null);
                result.success(map);
            }
        } catch (Exception e) {
            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
            map.put("ok", false);
            map.put("status", "failed");
            map.put("message", e.getMessage());
            result.success(map);
        }
    }

    private void updateVpnNode(Object argsObj, MethodChannel.Result result) {
        try {
            if (argsObj instanceof java.util.Map) {
                java.util.Map m = (java.util.Map) argsObj;
                if (m.containsKey("proxyNode")) {
                    Object pn = m.get("proxyNode");
                    if (pn instanceof java.util.Map) {
                        org.json.JSONObject jo = new org.json.JSONObject((java.util.Map) pn);
                        ClashVpnService svc = ClashVpnService.getRunningInstance();
                        if (svc != null) {
                            svc.updateProxyNodeJson(jo.toString());
                            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
                            map.put("ok", true);
                            map.put("status", "updated");
                            map.put("message", null);
                            result.success(map);
                            return;
                        }
                    }
                }
            }
            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
            map.put("ok", false);
            map.put("status", "failed");
            map.put("message", "invalid args or service not running");
            result.success(map);
        } catch (Exception e) {
            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
            map.put("ok", false);
            map.put("status", "failed");
            map.put("message", e.getMessage());
            result.success(map);
        }
    }

    /**
     * Start the VPN service.
     */
    private void startVpnService() {
        startVpnService(null);
    }

    private void startVpnService(java.util.Map<String, Object> args) {
        Intent serviceIntent = new Intent(this, ClashVpnService.class);

        if (args != null) {
            try {
                if (args.containsKey("proxyNode")) {
                    Object pn = args.get("proxyNode");
                    if (pn instanceof java.util.Map) {
                        JSONObject jo = new JSONObject((java.util.Map) pn);
                        serviceIntent.putExtra("proxyNodeJson", jo.toString());
                    }
                }
                if (args.containsKey("proxyAddress")) {
                    Object pa = args.get("proxyAddress");
                    if (pa != null) serviceIntent.putExtra("proxyAddress", pa.toString());
                }
                if (args.containsKey("proxyPort")) {
                    Object pp = args.get("proxyPort");
                    if (pp instanceof Integer) serviceIntent.putExtra("proxyPort", (Integer) pp);
                    else if (pp != null) serviceIntent.putExtra("proxyPort", Integer.parseInt(pp.toString()));
                }

                // Allow passing routing rules to the VPN service on startup so
                // the service can program routes immediately and avoid an
                // extra round-trip from the app to set rules separately.
                if (args.containsKey("rules")) {
                    try {
                        Object r = args.get("rules");
                        if (r instanceof java.util.List) {
                            java.util.List list = (java.util.List) r;
                            org.json.JSONArray ja = new org.json.JSONArray();
                            for (Object item : list) {
                                try { ja.put(new org.json.JSONObject((java.util.Map) item)); } catch (Exception ignored) {}
                            }
                            serviceIntent.putExtra("rulesJson", ja.toString());

                            Log.d(TAG, "startVpnService: attaching rulesJson with entries: " + ja.toString());
                        } else if (r instanceof String) {
                            serviceIntent.putExtra("rulesJson", r.toString());
                            Log.d(TAG, "startVpnService: attaching rulesJson (raw string) rules=" + r.toString());
                        }
                    } catch (Exception ignored) {}
                }
            } catch (Exception ignored) {}
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent);
        } else {
            startService(serviceIntent);
        }

        Log.d(TAG, "VPN service started");
    }

    /**
     * Stop VPN service (called from Flutter).
     */
    private void stopVpn(MethodChannel.Result result) {
        try {
            boolean stopped = false;

            // If the service instance is running, request an immediate stop to ensure
            // notification and TUN cleanup happen right away.
            ClashVpnService service = ClashVpnService.getRunningInstance();
            if (service != null) {
                try {
                    stopped = service.requestStopService();
                } catch (Exception e) {
                    Log.w(TAG, "stopVpnServiceNow failed, falling back to stopService: " + e.getMessage());
                    Intent serviceIntent = new Intent(this, ClashVpnService.class);
                    stopped = stopService(serviceIntent);
                }
            } else {
                Intent serviceIntent = new Intent(this, ClashVpnService.class);
                stopped = stopService(serviceIntent);
            }
            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
            map.put("ok", stopped);
            map.put("status", stopped ? "stopped" : "failed");
            map.put("message", null);
            result.success(map);
            Log.d(TAG, "VPN service stopped: " + stopped);
        } catch (Exception e) {
            java.util.HashMap<String, Object> map = new java.util.HashMap<>();
            map.put("ok", false);
            map.put("status", "failed");
            map.put("message", e.getMessage());
            result.success(map);
        }
    }

    /**
     * Check if VPN service is running.
     */
    private boolean isVpnServiceRunning() {
        // Prefer the runningInstance marker rather than deprecated ActivityManager.getRunningServices
        return ClashVpnService.getRunningInstance() != null;
    }

    // Handle VPN permission result (legacy startActivityForResult flow)
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == VPN_PERMISSION_REQUEST && resultCode == RESULT_OK) {
            startVpnService(pendingVpnArgs);
            if (pendingVpnResult != null) {
                java.util.HashMap<String, Object> map = new java.util.HashMap<>();
                map.put("ok", true);
                map.put("status", "started");
                map.put("message", null);
                pendingVpnResult.success(map);
                pendingVpnResult = null;
            }
        } else if (requestCode == VPN_PERMISSION_REQUEST) {
            if (pendingVpnResult != null) {
                java.util.HashMap<String, Object> map = new java.util.HashMap<>();
                map.put("ok", false);
                map.put("status", "permission_denied");
                map.put("message", "VPN permission denied by user");
                pendingVpnResult.success(map);
                pendingVpnResult = null;
            }
        }
    }

    /**
     * Helper method to send events from native to Flutter
     */
    private void notifyFlutter(final String event, final String message) {
        if (methodChannel != null) {
            runOnUiThread(() -> {
                try {
                    java.util.HashMap<String, Object> data = new java.util.HashMap<>();
                    data.put("event", event);
                    data.put("message", message);
                    methodChannel.invokeMethod("onVpnEvent", data);
                } catch (Exception e) {
                    Log.w(TAG, "Failed to notify Flutter: " + e.getMessage());
                }
            });
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        try {
            if (vpnStoppedReceiver != null) {
                unregisterReceiver(vpnStoppedReceiver);
                vpnStoppedReceiver = null;
            }
        } catch (IllegalArgumentException ignored) {}
        methodChannel = null;
    }
}

