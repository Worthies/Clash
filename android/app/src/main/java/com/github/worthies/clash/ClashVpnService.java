package com.github.worthies.clash;

import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.os.IBinder;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.io.BufferedReader;
import android.app.Notification;
import android.app.Service;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import androidx.core.app.NotificationCompat;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.ServerSocket;
import java.net.DatagramSocket;
import java.net.DatagramPacket;
import java.net.InetAddress;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.util.concurrent.ConcurrentHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.lang.reflect.Field;
import java.io.FileDescriptor;

/**
 * Android VPN service — establishes a TUN device and runs an in-process
 * TUN processor to selectively capture TCP flows (HTTP/TLS) and forward
 * matched payloads to an upstream proxy. The old native tun2socks engine
 * and JNI startup path was removed in favor of a simplified Java-based
 * capture + SOCKS5 relay plumbing.
 */
public class ClashVpnService extends VpnService {
    private static final String TAG = "ClashVpnService";
    private static final int NOTIFICATION_ID = 1;
    private static final String NOTIFICATION_CHANNEL = "clash_vpn";

    private static volatile ClashVpnService runningInstance = null;

    private ParcelFileDescriptor tunDevice;
    // No external executable fallback — we use an in-process TUN processor.
    // TUN processing thread (replaces tun2socks native runner)
    private Thread tunProcessorThread = null;
    private volatile boolean tunProcessorRunning = false;
    // Writer thread & queue for injecting packets into the tun device.
    private Thread tunWriterThread = null;
    // Increased from 1024 to 4096 to handle burst traffic from multiple browser tabs
    private final java.util.concurrent.BlockingQueue<byte[]> tunWriteQueue = new java.util.concurrent.LinkedBlockingQueue<>(4096);
    private volatile boolean tunWriterRunning = false;
    private final java.util.concurrent.atomic.AtomicInteger tunPacketsWritten = new java.util.concurrent.atomic.AtomicInteger(0);
    private final java.util.concurrent.atomic.AtomicInteger tunPacketsDropped = new java.util.concurrent.atomic.AtomicInteger(0);
    private final java.util.concurrent.atomic.AtomicInteger tunWriteQueueMax = new java.util.concurrent.atomic.AtomicInteger(0);
    private final java.util.concurrent.atomic.AtomicInteger tunPacketsRead = new java.util.concurrent.atomic.AtomicInteger(0);
    private final java.util.concurrent.atomic.AtomicInteger tunPacketsForwarded = new java.util.concurrent.atomic.AtomicInteger(0);
    @SuppressWarnings("deprecation")
    private String abi = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && Build.SUPPORTED_ABIS.length > 0) ? Build.SUPPORTED_ABIS[0] : Build.CPU_ABI;;
    // proxy node info passed from Flutter (optional) so the service can decide
    // which outbound connections should be created as protected sockets.
    private String proxyNodeJson = null;
    private String proxyNodeHost = null;
    private Integer proxyNodePort = null;
    private String proxyNodeSni = null;
    private String proxyNodeType = null;
    // Resolved proxy node IP addresses cached for quick matching
    private String[] proxyNodeAddrs = null;
    // No DNS retry — routes must already be resolved by Dart/Flutter
    // Executor used to manage captured connection tasks (cleanup, async work)
    // Increased from 2 to 32 threads to handle browser with multiple tabs
    private final java.util.concurrent.ScheduledExecutorService connectionExecutor = java.util.concurrent.Executors.newScheduledThreadPool(32);
    // Executor for egress socket readers to avoid unbounded thread creation
    private final java.util.concurrent.ExecutorService egressReaderExecutor = java.util.concurrent.Executors.newCachedThreadPool(new java.util.concurrent.ThreadFactory() {
        private final java.util.concurrent.atomic.AtomicInteger counter = new java.util.concurrent.atomic.AtomicInteger(0);
        @Override
        public Thread newThread(Runnable r) {
            Thread t = new Thread(r, "clash-egress-reader-" + counter.incrementAndGet());
            t.setDaemon(true);
            return t;
        }
    });
    // Maximum concurrent connections to prevent resource exhaustion
    private static final int MAX_CONCURRENT_CONNECTIONS = 512;
    // Buffer pool to reduce allocations for transient read/write operations
    private final BufferPool bufferPool = new BufferPool(8192, 128);
    private static final int RETRANSMIT_MS = 2000; // ms
    private static final int MAX_RETRANSMIT_ATTEMPTS = 5;
    // Persist the last startup Intent extras so if the service restarts
    // internally it can reuse the same configuration
    // without requiring the app to re-send the startup intent.
    private String savedProxyNodeJson = null;
    private String savedProxyAddress = null;
    private Integer savedProxyPort = null;
    // SharedPreferences keys for durable storage across process restarts
    private static final String PREFS_NAME = "clash_vpn_prefs";
    private static final String KEY_PROXY_NODE_JSON = "proxyNodeJson";
    private static final String KEY_PROXY_ADDRESS = "proxyAddress";
    private static final String KEY_PROXY_PORT = "proxyPort";
    // Active TCP connections observed on the TUN device (simple 4-tuple key)
    private final java.util.concurrent.ConcurrentHashMap<ConnectionKey, ConnectionState> connectionMap = new java.util.concurrent.ConcurrentHashMap<>();
    // Active UDP 'flows' observed on the TUN device -- we keep a small mapping to
    // forward datagrams out via protected DatagramSocket and reinject responses.
    private final java.util.concurrent.ConcurrentHashMap<ConnectionKey, UdpFlowState> udpMap = new java.util.concurrent.ConcurrentHashMap<>();
    // NOTE: native tun2socks support removed — we operate with an in-process
    // TUN processor and service-owned TCP sockets (transparent capture).

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "VPN service starting (SDK " + Build.VERSION.SDK_INT + ")");

        try {
            runningInstance = this;

            createNotificationChannel();
            startForeground(NOTIFICATION_ID, createNotification());

            startVpn(intent);
            Log.d(TAG, "VPN service started successfully");

        } catch (Exception e) {
            Log.e(TAG, "Failed to start VPN: " + e.getClass().getSimpleName() + " - " + e.getMessage(), e);
            e.printStackTrace();

            // Broadcast failure back to the app so Flutter can show the error in Logs
            try {
                Intent failIntent = new Intent("com.github.worthies.clash.ACTION_VPN_START_FAILED");
                failIntent.putExtra("error", e.getMessage() != null ? e.getMessage() : e.toString());
                sendBroadcast(failIntent);
            } catch (Throwable ignored) {}

            stopSelf();
            return START_NOT_STICKY;
        }

        return START_STICKY;
    }

    // Note: executable extraction/exec fallback removed. We rely solely on the
    // embedded native libraries (`libtun2socks.so` + `libclashjni.so`) and JNI.

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        // App/task removed (swiped away) — ensure VPN and native bits are stopped
        Log.d(TAG, "onTaskRemoved: stopping VPN service");
        try {
            requestStopService();
        } catch (Throwable t) {
            Log.w(TAG, "onTaskRemoved: requestStopService failed: " + t.getMessage());
        }
        super.onTaskRemoved(rootIntent);
    }

    @Override
    public void onDestroy() {
        Log.d(TAG, "VPN service is being destroyed");
        stopVpn();
        runningInstance = null;
    }

    public static ClashVpnService getRunningInstance() {
        return runningInstance;
    }

    /**
     * Public API used by callers (e.g. MainActivity) to request the running VPN
     * service stop immediately. This ensures TUN and the foreground notification
     * are removed right away.
     *
     * @return true when the request was accepted
     */
    public boolean requestStopService() {
        Log.d(TAG, "requestStopService called");
        try {
            stopVpn();
            runningInstance = null;

            try { stopForeground(Service.STOP_FOREGROUND_REMOVE); } catch (Throwable t) { Log.w(TAG, "stopForeground failed: " + t.getMessage()); }
            try { stopSelf(); } catch (Throwable t) { Log.w(TAG, "stopSelf failed: " + t.getMessage()); }

            return true;
        } catch (Exception e) {
            Log.e(TAG, "requestStopService failed", e);
            return false;
        }
    }

    /**
    * Setup VPN interface.
    * Routes configured traffic through VPN and hands packets to the in-process
    * TUN processor for selective capture and forwarding.
     */
    private void startVpn(Intent incomingIntent) throws Exception {
        // If proxy node info was provided via the startup Intent, read it now
        // so protection decisions are in place before we configure the VPN interface.
        try {
            if (incomingIntent != null && incomingIntent.hasExtra("proxyNodeJson")) {
                String json = incomingIntent.getStringExtra("proxyNodeJson");
                if (json != null) updateProxyNodeJson(json);
            }
        } catch (Throwable t) { Log.w(TAG, "Failed to read proxyNodeJson intent early: " + t.getMessage()); }

        Builder builder = new Builder();
        builder.setSession("Clash VPN");
        builder.addAddress("192.168.1.1", 32);

        // Add default routes to capture all traffic
        builder.addRoute("0.0.0.0", 0);
        builder.addRoute("::", 0);

        // CRITICAL: Exclude our own app from VPN routing to avoid loops
        // This allows the Dart ProxyService to connect to the remote proxy without being captured
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                builder.addDisallowedApplication(getPackageName());
                Log.d(TAG, "Successfully excluded own app from VPN routing: " + getPackageName());
            } catch (Exception e) {
                Log.e(TAG, "CRITICAL: Failed to exclude own app from VPN - routing loop will occur!", e);
                Log.e(TAG, "Error details: " + e.getClass().getSimpleName() + ": " + e.getMessage());
                // On some systems (HarmonyOS), this might fail - throw exception to prevent routing loop
                throw new RuntimeException("Failed to configure VPN exclusion: " + e.getMessage(), e);
            }
        } else {
            Log.w(TAG, "API < 21: Cannot use addDisallowedApplication - routing loops may occur");
        }

        // CRITICAL: Exclude proxy server IPs from VPN routes so they bypass VPN
        // Without this, the local Clash proxy's connections to the remote proxy will loop through VPN
        if (proxyNodeAddrs != null && proxyNodeAddrs.length > 0) {
            for (String proxyIp : proxyNodeAddrs) {
                if (proxyIp != null && !proxyIp.isEmpty()) {
                    try {
                        // We need to exclude specific IPs from the default 0.0.0.0/0 route
                        // Unfortunately VPN API doesn't support exclusions directly, but we can
                        // use allowedApplications/disallowedApplications or let Clash proxy protect its own sockets
                        if (proxyIp.contains(":")) {
                            // IPv6 - can't easily exclude, rely on protect()
                            Log.d(TAG, "Proxy uses IPv6 - Clash proxy must protect its own sockets: " + proxyIp);
                        } else {
                            // IPv4 - Clash proxy must call VpnService.protect() on its sockets to remote proxy
                            Log.d(TAG, "Remote proxy IP: " + proxyIp + " - Clash must protect sockets to this IP");
                        }
                    } catch (Exception e) {
                        Log.w(TAG, "Error processing proxy IP: " + proxyIp + " - " + e.getMessage());
                    }
                }
            }
        } else {
            Log.w(TAG, "No proxy IPs resolved yet - proxy connections may fail!");
        }

        builder.addDnsServer("114.114.114.114");
        builder.setMtu(1500);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false);
            builder.setUnderlyingNetworks(null);
        }

        tunDevice = builder.establish();
        if (tunDevice == null) throw new IOException("Failed to establish VPN interface");

        // Start the in-process TUN processor (transparent capture / TCP inspection)
        try {
            startTunProcessor();
        } catch (Throwable t) {
            Log.w(TAG, "Failed to start in-process TUN processor: " + t.getMessage());
        }

        // Merge incoming intent extras with saved values. If incomingIntent
        // is null (e.g. on internal restart) fall back to previously-saved
        // startup values so we keep behavior consistent across restarts.
        try {
            // Update saved startup values when an explicit intent is provided
            if (incomingIntent != null) {
                if (incomingIntent.hasExtra("proxyNodeJson")) {
                    savedProxyNodeJson = incomingIntent.getStringExtra("proxyNodeJson");
                    try { getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString(KEY_PROXY_NODE_JSON, savedProxyNodeJson).apply(); } catch (Exception ignored) {}
                }
                if (incomingIntent.hasExtra("proxyAddress")) {
                    savedProxyAddress = incomingIntent.getStringExtra("proxyAddress");
                    try { getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString(KEY_PROXY_ADDRESS, savedProxyAddress).apply(); } catch (Exception ignored) {}
                }
                if (incomingIntent.hasExtra("proxyPort")) {
                    int pp = incomingIntent.getIntExtra("proxyPort", -1);
                    savedProxyPort = pp >= 0 ? Integer.valueOf(pp) : null;
                    try { getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putInt(KEY_PROXY_PORT, savedProxyPort == null ? -1 : savedProxyPort.intValue()).apply(); } catch (Exception ignored) {}
                }
            } else {
                // If no intent provided, try to load previously saved startup extras
                try {
                    android.content.SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
                    if (savedProxyNodeJson == null) savedProxyNodeJson = prefs.getString(KEY_PROXY_NODE_JSON, null);
                    if (savedProxyAddress == null) savedProxyAddress = prefs.getString(KEY_PROXY_ADDRESS, null);
                    if (savedProxyPort == null) {
                        int pp = prefs.getInt(KEY_PROXY_PORT, -1);
                        savedProxyPort = pp >= 0 ? Integer.valueOf(pp) : null;
                    }
                } catch (Exception ignored) {}
            }

            // Use saved values when incomingIntent doesn't provide them
            String proxyJson = (incomingIntent != null && incomingIntent.hasExtra("proxyNodeJson")) ? incomingIntent.getStringExtra("proxyNodeJson") : savedProxyNodeJson;
            String proxyAddress = (incomingIntent != null && incomingIntent.hasExtra("proxyAddress")) ? incomingIntent.getStringExtra("proxyAddress") : savedProxyAddress;
            Integer proxyPort = null;
            if (incomingIntent != null && incomingIntent.hasExtra("proxyPort")) proxyPort = incomingIntent.getIntExtra("proxyPort", -1) >= 0 ? Integer.valueOf(incomingIntent.getIntExtra("proxyPort", -1)) : null; else proxyPort = savedProxyPort;

            // Apply proxy node info (if present either on the incoming intent
            // or previously saved startup values)
            if (proxyJson != null) {
                updateProxyNodeJson(proxyJson);
            }

            // Use saved proxyAddress/Port (not currently required for startup)
            if (proxyAddress != null) {
                // keep proxyAddress around for diagnostics but nothing else here
                Log.d(TAG, "Using startup proxy address=" + proxyAddress + " port=" + proxyPort);
            }
        } catch (Throwable t) { Log.w(TAG, "Failed to read persisted startup extras: " + t.getMessage()); }

        Log.d(TAG, "VPN interface established and in-process TUN processor started");
    }

    /**
     * Whether the destination host/port should be protected (bypass VPN) —
     * this is used by bridge/native helpers when deciding to create sockets
     * outside the TUN. We conservatively protect DNS (53/853) and any
     * socket matching the configured proxy node info.
     * NOTE: When using local proxy (127.0.0.1), protection is not needed since localhost traffic
     * naturally bypasses the VPN. This avoids issues in environments where protect() doesn't work
     * properly (e.g., Android emulator).
     */
    private boolean shouldProtectTarget(String destHost, int destPort) {
        if (destPort == 53 || destPort == 853) return true;

        // Since we're using local proxy (proxyAddress:proxyPort = 127.0.0.1:1080),
        // we don't need to protect those connections - they naturally bypass VPN
        if (destHost != null && (destHost.equals("127.0.0.1") || destHost.equals("localhost") || destHost.equals("::1"))) {
            return false;
        }

        if (proxyNodeHost != null && proxyNodePort != null) {
            if (proxyNodePort == destPort) {
                // If the destination host matches the configured proxy node
                // host (or a previously-resolved address) we consider it a
                // candidate for protection — avoid doing DNS resolves on the
                // caller thread here.
                try {
                    if (destHost.equalsIgnoreCase(proxyNodeHost)) return true;
                    if (proxyNodeAddrs != null) {
                        for (String a : proxyNodeAddrs) {
                            if (a != null && a.equals(destHost)) return true;
                        }
                    }
                } catch (Exception ignored) {}
            }
        }

        if (proxyNodeType != null) {
            final String t = proxyNodeType.toLowerCase();
            if (t.contains("trojan") || t.contains("ss") || t.contains("shadowsocks") || t.contains("vmess")) {
                if (destPort == 443 || destPort >= 1024) return true;
            }
        }

        return false;
    }

    /** Public API — update proxy node info dynamically (JSON string) */
    public void updateProxyNodeJson(String json) {
        if (json == null) return;
        try {
            org.json.JSONObject jo = new org.json.JSONObject(json);
            this.proxyNodeJson = json;
            this.proxyNodeHost = jo.optString("host", null);
            int p = jo.optInt("port", -1);
            this.proxyNodePort = p >= 0 ? Integer.valueOf(p) : null;
            this.proxyNodeSni = jo.optString("sni", null);
            this.proxyNodeType = jo.optString("type", null);
            Log.d(TAG, "updateProxyNodeJson: host=" + this.proxyNodeHost + " port=" + this.proxyNodePort + " sni=" + this.proxyNodeSni);
            // Persist the startup proxy node JSON so restarts keep the same
            // configuration without requiring the app to resend the Intent.
            try { savedProxyNodeJson = json; getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString(KEY_PROXY_NODE_JSON, savedProxyNodeJson).apply(); } catch (Exception ignored) {}
            // Resolve proxy node host to addresses asynchronously to avoid blocking
            // the main/UI thread while still capturing resolved addresses for protection.
            try {
                if (this.proxyNodeHost != null && !this.proxyNodeHost.isEmpty()) {
                    connectionExecutor.submit(() -> {
                        try {
                            InetAddress[] ips = InetAddress.getAllByName(this.proxyNodeHost);
                            if (ips != null && ips.length > 0) {
                                this.proxyNodeAddrs = new String[ips.length];
                                for (int i = 0; i < ips.length; i++) this.proxyNodeAddrs[i] = ips[i].getHostAddress();
                                Log.d(TAG, "Async resolved proxy node " + this.proxyNodeHost + " to IPs for protection: " + java.util.Arrays.toString(this.proxyNodeAddrs));
                            }
                        } catch (Exception e) {
                            Log.d(TAG, "Async resolve proxy node host failed: " + e.getClass().getSimpleName() + " -> " + (e.getMessage() == null ? "(no message)" : e.getMessage()));
                        }
                    });
                }
            } catch (Exception ignored) {}
        } catch (Exception e) {
            Log.w(TAG, "updateProxyNodeJson failed: " + e.getMessage());
        }
    }

    /**
     * Stop VPN service and cleanup resources.
     */
    private void stopVpn() {
        // Stop VPN and native components. Close Java TUN device early so Java
        // does not claim ownership when native closes its duplicate.
        try {
            // Stop our in-process TUN processor first so it no longer holds the
            // device FD or threads.
            try { stopTunProcessor(); } catch (Throwable t) { Log.w(TAG, "stopTunProcessor failed: " + t.getMessage()); }

            if (tunDevice != null) {
                try {
                    int origFd = tunDevice.getFd();
                    Log.d(TAG, "Closing Java TUN device early (fd=" + origFd + ")");
                    tunDevice.close();
                } catch (IOException ioe) {
                    Log.w(TAG, "Error closing tunDevice early: " + ioe.getMessage());
                }
                tunDevice = null;
            }

            try { connectionExecutor.shutdownNow(); } catch (Exception ignored) {}
            try { egressReaderExecutor.shutdownNow(); } catch (Exception ignored) {}

            // Close all active connections
            for (ConnectionState state : connectionMap.values()) {
                try {
                    if (state.egress != null) state.egress.close();
                } catch (Exception ignored) {}
            }
            connectionMap.clear();

            // Close all UDP flows
            for (UdpFlowState flow : udpMap.values()) {
                try {
                    if (flow.socket != null) flow.socket.close();
                } catch (Exception ignored) {}
            }
            udpMap.clear();
        } catch (Exception e) {
            Log.e(TAG, "Error stopping TUN processor / cleanup", e);
        }

        Log.d(TAG, "VPN stopped and resources cleaned up");
        // Notify the app that VPN has stopped so other components (e.g. relay) can cleanup
        try {
            Intent i = new Intent("com.github.worthies.clash.ACTION_VPN_STOPPED");
            sendBroadcast(i);
        } catch (Throwable t) {
            Log.w(TAG, "Failed to broadcast VPN stopped: " + t.getMessage());
        }
        try { stopForeground(Service.STOP_FOREGROUND_REMOVE); } catch (Throwable t) { Log.w(TAG, "stopForeground failed: " + t.getMessage()); }
        try { stopSelf(); } catch (Throwable t) { Log.w(TAG, "stopSelf failed: " + t.getMessage()); }
    }

    /** Start a basic in-process TUN processor thread. This is a small skeleton
     *  for reading packets from the TUN device and performing lightweight
     *  inspection. The real forwarding/connection tracking is implemented next;
     *  for now we read and log incoming TCP packets and otherwise drop them.
     */
    private synchronized void startTunProcessor() {
        if (tunDevice == null) {
            Log.w(TAG, "startTunProcessor: tunDevice is null");
            return;
        }
        if (tunProcessorRunning) return;
        tunProcessorRunning = true;
        // Schedule periodic pruning of stale captured connections
        connectionExecutor.scheduleAtFixedRate(() -> pruneStaleConnections(), 30, 30, java.util.concurrent.TimeUnit.SECONDS);

        // Start writers used to inject packets into TUN (single shared FileOutputStream)
        startTunWriter();
        // Schedule retransmit checks for server->client injected segments
        connectionExecutor.scheduleAtFixedRate(() -> retransmitPendingSegments(), 1000, 1000, java.util.concurrent.TimeUnit.MILLISECONDS);
        tunProcessorThread = new Thread(() -> {
            Log.d(TAG, "TUN processor thread started");
            byte[] buf = null;
            try (java.io.FileInputStream in = new java.io.FileInputStream(tunDevice.getFileDescriptor())) {
                buf = bufferPool.acquireAtLeast(1536);
                while (tunProcessorRunning) {
                    int n = -1;
                    try {
                        n = in.read(buf);
                    } catch (java.io.InterruptedIOException ie) {
                        break;
                    } catch (Exception e) {
                        Log.w(TAG, "TUN read error: " + e.getMessage());
                        break;
                    }
                    if (n <= 0) {
                        try { Thread.sleep(10); } catch (InterruptedException ignored) {}
                        continue;
                    }

                    // Basic IPv4/TCP detection and logging
                    try {
                        int version = (buf[0] >> 4) & 0xF;
                        if (version == 4 && n >= 20) {
                            int ihl = (buf[0] & 0x0F) * 4;
                            if (ihl >= 20 && n >= ihl + 20) {
                                int protocol = buf[9] & 0xFF;
                                if (protocol == 6) { // TCP
                                    int srcPort = ((buf[ihl] & 0xFF) << 8) | (buf[ihl + 1] & 0xFF);
                                    int dstPort = ((buf[ihl + 2] & 0xFF) << 8) | (buf[ihl + 3] & 0xFF);
                                    tunPacketsRead.incrementAndGet();
                                    // Avoid logging every packet (noisy) — only sample 1/100
                                    if ((tunPacketsRead.get() % 100) == 0)
                                        Log.d(TAG, "TUN packet (sample): IPv4 TCP srcPort=" + srcPort + " dstPort=" + dstPort + " len=" + n);

                                    // Capture payload bytes for detection (after IP+TCP headers)
                                    int tcpDataOffsetWords = ((buf[ihl + 12] & 0xF0) >> 4);
                                    int dataOffset = ihl + (tcpDataOffsetWords * 4);

                                    // Extract TCP header (first 20 bytes cover seq/ack/flags)
                                    int tcpHdrLenBytes = tcpDataOffsetWords * 4;

                                    // If we have application payload, copy it
                                    byte[] payload = null;
                                    if (dataOffset < n) {
                                        int payloadLen = n - dataOffset;
                                        payload = new byte[payloadLen];
                                        System.arraycopy(buf, dataOffset, payload, 0, payloadLen);
                                    }

                                    // Track connection and attempt detection
                                    String srcIp = (buf[12] & 0xFF) + "." + (buf[13] & 0xFF) + "." + (buf[14] & 0xFF) + "." + (buf[15] & 0xFF);
                                    String dstIp = (buf[16] & 0xFF) + "." + (buf[17] & 0xFF) + "." + (buf[18] & 0xFF) + "." + (buf[19] & 0xFF);
                                    ConnectionKey key = new ConnectionKey(srcIp, srcPort, dstIp, dstPort);
                                    ConnectionState state = connectionMap.get(key);
                                    if (state == null) {
                                        // Check connection limit to prevent resource exhaustion
                                        if (connectionMap.size() >= MAX_CONCURRENT_CONNECTIONS) {
                                            // Prune stale connections immediately
                                            pruneStaleConnections();
                                            // If still at limit, skip this connection
                                            if (connectionMap.size() >= MAX_CONCURRENT_CONNECTIONS) {
                                                Log.w(TAG, "Max connections reached (" + MAX_CONCURRENT_CONNECTIONS + "), dropping new connection: " + key);
                                                continue;
                                            }
                                        }
                                        state = new ConnectionState(key);
                                        connectionMap.put(key, state);
                                    }
                                    if (payload != null) state.appendClientPayload(payload);

                                    if (!state.detectionDone && payload != null) {
                                        // Attempt to detect HTTP or TLS ClientHello
                                        if (looksLikeHttp(payload)) {
                                            state.detectionDone = true;
                                            state.captured = true;
                                            state.detectedType = "HTTP";
                                            Log.d(TAG, "Captured connection " + key + " -> HTTP detected");
                                            handleCapturedConnection(state);
                                        } else {
                                            String sni = extractTlsSni(payload);
                                            if (sni != null) {
                                                state.detectionDone = true;
                                                state.captured = true;
                                                state.detectedType = "TLS:SNI(" + sni + ")";
                                                Log.d(TAG, "Captured connection " + key + " -> TLS ClientHello / SNI=" + sni);
                                                handleCapturedConnection(state);
                                            }
                                        }
                                    }

                                    // Parse TCP header (seq/ack/flags) from tcpHdr
                                    int seq = ((buf[ihl + 4] & 0xFF) << 24) | ((buf[ihl + 5] & 0xFF) << 16) | ((buf[ihl + 6] & 0xFF) << 8) | (buf[ihl + 7] & 0xFF);
                                    int ack = ((buf[ihl + 8] & 0xFF) << 24) | ((buf[ihl + 9] & 0xFF) << 16) | ((buf[ihl + 10] & 0xFF) << 8) | (buf[ihl + 11] & 0xFF);
                                    int flags = buf[ihl + 13] & 0xFF; // TCP flags byte

                                    // If SYN-only (handshake start), record ISN and try to establish egress
                                    boolean syn = (flags & 0x02) != 0;
                                    boolean ackFlag = (flags & 0x10) != 0;
                                    boolean fin = (flags & 0x01) != 0;
                                    boolean rst = (flags & 0x04) != 0;

                                    if (syn && !ackFlag && !state.detectionDone) {
                                        // initial client SYN - record client ISN
                                        state.clientIsn = Integer.toUnsignedLong(seq);
                                        state.clientNextSeq = state.clientIsn + 1;
                                        // attempt connection via proxy (async)
                                        Log.d(TAG, "Observed SYN from client for " + key + " clientIsn=" + state.clientIsn);
                                        // If proxy connect hasn't been started yet, start it
                                        if (state.egress == null) {
                                            state.detectionDone = true;
                                            state.captured = true;
                                            state.detectedType = "SYN";
                                            state.stage = ConnectionStage.SYN_RECEIVED;
                                            // attempt async connect
                                            handleCapturedConnection(state);
                                        }

                                        // RST handling: remove connection and close egress
                                        if (rst) {
                                            Log.d(TAG, "Observed RST from client for " + key + "; tearing down captured flow");
                                            try { if (state.egress != null) state.egress.close(); } catch (Exception ignored) {}
                                            connectionMap.remove(key);
                                            continue;
                                        }

                                        // FIN handling: if client closed and we have egress, shutdown output to send FIN
                                        if (fin) {
                                            Log.d(TAG, "Observed FIN from client for " + key);
                                            if (state.egress != null) {
                                                try { state.egress.shutdownOutput(); } catch (Exception ignored) {}
                                                state.stage = ConnectionStage.FIN_WAIT;
                                                state.clientNextSeq = Integer.toUnsignedLong(seq) + 1;
                                            }
                                        }
                                        // We will wait for egress to be established; when it is, we'll inject SYN-ACK
                                    } else if (ackFlag && state.egress != null && state.serverNextSeq > 0) {
                                        // Client ack to our SYN-ACK: check handshake completion
                                        long ackVal = Integer.toUnsignedLong(ack);
                                        if (ackVal == state.serverIsn + 1 && state.stage != ConnectionStage.ESTABLISHED) {
                                            // Handshake completed at client side (log only once)
                                            Log.d(TAG, "TCP handshake established for " + key);
                                            state.stage = ConnectionStage.ESTABLISHED;
                                        }
                                        // Remove any server-sent segments acknowledged by client
                                        try {
                                            synchronized (state.getSentSegments()) {
                                                java.util.Iterator<SentSegment> it = state.getSentSegments().iterator();
                                                while (it.hasNext()) {
                                                    SentSegment s = it.next();
                                                    if ((s.seq + s.payloadLen) <= ackVal) {
                                                        it.remove();
                                                    }
                                                }
                                            }
                                        } catch (Exception ignored) {}
                                    }

                                    // If we have an established egress, and this packet contains payload, forward it
                                    if (state.egress != null && payload != null) {
                                        try {
                                            long clientSeq = Integer.toUnsignedLong(seq);
                                            // Simple duplicate/reorder avoidance: if this packet's seq is behind what we've already
                                            // consumed, skip forwarding the duplicate payload. Otherwise forward and advance state.
                                            if (clientSeq < state.clientNextSeq) {
                                                // Log only first few duplicates per connection to reduce spam
                                                if (state.duplicateCount++ < 2) {
                                                    Log.d(TAG, "Duplicate payload for " + key + " (seq=" + clientSeq + " expected=" + state.clientNextSeq + ")");
                                                }
                                            } else {
                                                java.io.OutputStream os = state.egress.getOutputStream();
                                                os.write(payload);
                                                os.flush();
                                                tunPacketsForwarded.incrementAndGet();
                                                // update client next seq
                                                state.clientNextSeq = clientSeq + payload.length;
                                            }
                                        } catch (Exception e) {
                                            Log.w(TAG, "Failed to forward client payload to egress for " + key + ": " + e.getMessage());
                                        }
                                    }
                                    // Non-TCP (UDP) transparent forwarding
                                    // If this is UDP, forward payload transparently using a protected DatagramSocket
                                } else if (protocol == 17) { // UDP
                                    int srcPortU = ((buf[ihl] & 0xFF) << 8) | (buf[ihl + 1] & 0xFF);
                                    int dstPortU = ((buf[ihl + 2] & 0xFF) << 8) | (buf[ihl + 3] & 0xFF);
                                    int dataOffset = ihl + 8;
                                    byte[] payloadUdp = null;
                                    if (dataOffset < n) {
                                        int pLen = n - dataOffset;
                                        payloadUdp = new byte[pLen];
                                        System.arraycopy(buf, dataOffset, payloadUdp, 0, pLen);
                                    }

                                    String srcIpStr = (buf[12] & 0xFF) + "." + (buf[13] & 0xFF) + "." + (buf[14] & 0xFF) + "." + (buf[15] & 0xFF);
                                    String dstIpStr = (buf[16] & 0xFF) + "." + (buf[17] & 0xFF) + "." + (buf[18] & 0xFF) + "." + (buf[19] & 0xFF);
                                    ConnectionKey keyUdp = new ConnectionKey(srcIpStr, srcPortU, dstIpStr, dstPortU);
                                    UdpFlowState st = udpMap.get(keyUdp);
                                    if (st == null) {
                                        try {
                                            DatagramSocket ds = new DatagramSocket();
                                            try { protect(ds); } catch (Exception ignored) {}
                                            final UdpFlowState fst = new UdpFlowState(keyUdp, ds);
                                            st = fst;
                                            udpMap.put(keyUdp, fst);

                                            // start reader for responses
                                            Thread reader = new Thread(() -> {
                                                final byte[] tmp = bufferPool.acquireAtLeast(4096);
                                                try {
                                                    while (fst.running) {
                                                        DatagramPacket dp = new DatagramPacket(tmp, tmp.length);
                                                        try { fst.socket.receive(dp); } catch (java.net.SocketTimeoutException ste) { continue; }
                                                        if (dp.getLength() <= 0) continue;
                                                        fst.lastActivityMillis = System.currentTimeMillis();
                                                        // build a server->client packet (flip src/dst + ports)
                                                        try {
                                                            byte[] payloadResp = java.util.Arrays.copyOf(dp.getData(), dp.getLength());
                                                            byte[] p = buildIpv4UdpPacket(keyUdp.dstIp, keyUdp.srcIp, keyUdp.dstPort, keyUdp.srcPort, payloadResp);
                                                            try { sendPacketIntoTun(p); } catch (Exception ex) { Log.w(TAG, "Failed to inject UDP response: " + ex.getMessage()); }
                                                        } catch (Exception ex) { Log.w(TAG, "Failed to craft/inject UDP response: " + ex.getMessage()); }
                                                    }
                                                } catch (Exception e) {
                                                    Log.w(TAG, "UDP reader loop failed for " + keyUdp + ": " + e.getMessage());
                                                } finally {
                                                    bufferPool.release(tmp);
                                                    try { fst.socket.close(); } catch (Exception ignored) {}
                                                    udpMap.remove(keyUdp);
                                                }
                                            }, "clash-udp-reader");
                                            reader.start();
                                        } catch (Exception e) {
                                            Log.w(TAG, "Failed to create UDP socket for " + keyUdp + ": " + e.getMessage());
                                            // fallthrough: we can't forward; break
                                            continue;
                                        }
                                    }

                                    // send datagram out
                                    if (st != null && payloadUdp != null) {
                                        try {
                                            DatagramPacket out = new DatagramPacket(payloadUdp, payloadUdp.length, InetAddress.getByName(keyUdp.dstIp), keyUdp.dstPort);
                                            st.socket.send(out);
                                            st.lastActivityMillis = System.currentTimeMillis();
                                        } catch (Exception e) {
                                            Log.w(TAG, "Failed to send UDP datagram for " + keyUdp + ": " + e.getMessage());
                                        }
                                    }
                                    // continue processing next packet
                                }
                            }
                        } else if (version == 6 && n >= 40) {
                            // Minimal IPv6 handling (no extension headers support yet)
                            int nextHeader = buf[6] & 0xFF; // protocol
                            if (nextHeader == 6 && n >= 40 + 20) {
                                int ihl = 40; // IPv6 fixed header size
                                int srcPort = ((buf[ihl] & 0xFF) << 8) | (buf[ihl + 1] & 0xFF);
                                int dstPort = ((buf[ihl + 2] & 0xFF) << 8) | (buf[ihl + 3] & 0xFF);
                                tunPacketsRead.incrementAndGet();
                                if ((tunPacketsRead.get() % 100) == 0) Log.d(TAG, "TUN packet (sample): IPv6 TCP srcPort=" + srcPort + " dstPort=" + dstPort + " len=" + n);

                                int tcpDataOffsetWords = ((buf[ihl + 12] & 0xF0) >> 4);
                                int dataOffset = ihl + (tcpDataOffsetWords * 4);
                                int payloadLen = dataOffset < n ? (n - dataOffset) : 0;
                                byte[] payload = null;
                                if (payloadLen > 0) { payload = new byte[payloadLen]; System.arraycopy(buf, dataOffset, payload, 0, payloadLen); }

                                // src/dst IP textual representation (IPv6)
                                String srcIp = toIpv6String(buf, 8);
                                String dstIp = toIpv6String(buf, 24);
                                ConnectionKey key = new ConnectionKey(srcIp, srcPort, dstIp, dstPort);
                                ConnectionState state = connectionMap.get(key);
                                if (state == null) { state = new ConnectionState(key); connectionMap.put(key, state); }
                                if (payload != null) state.appendClientPayload(payload);

                                if (!state.detectionDone && payload != null) {
                                    if (looksLikeHttp(payload)) {
                                        state.detectionDone = true; state.captured = true; state.detectedType = "HTTP"; Log.d(TAG, "Captured connection " + key + " -> HTTP detected (IPv6)"); handleCapturedConnection(state);
                                    } else {
                                        String sni = extractTlsSni(payload);
                                        if (sni != null) { state.detectionDone = true; state.captured = true; state.detectedType = "TLS:SNI(" + sni + ")"; Log.d(TAG, "Captured connection " + key + " -> TLS ClientHello / SNI=" + sni + " (IPv6)"); handleCapturedConnection(state); }
                                    }
                                }

                                // Parse TCP header
                                int tcpHdrLenBytes = tcpDataOffsetWords * 4;
                                int seq = ((buf[ihl + 4] & 0xFF) << 24) | ((buf[ihl + 5] & 0xFF) << 16) | ((buf[ihl + 6] & 0xFF) << 8) | (buf[ihl + 7] & 0xFF);
                                int ack = ((buf[ihl + 8] & 0xFF) << 24) | ((buf[ihl + 9] & 0xFF) << 16) | ((buf[ihl + 10] & 0xFF) << 8) | (buf[ihl + 11] & 0xFF);
                                int flags = buf[ihl + 13] & 0xFF;
                                boolean syn = (flags & 0x02) != 0;
                                boolean ackFlag = (flags & 0x10) != 0;
                                boolean rst = (flags & 0x04) != 0;

                                if (syn && !ackFlag && !state.detectionDone) {
                                    state.clientIsn = Integer.toUnsignedLong(seq);
                                    state.clientNextSeq = state.clientIsn + 1;
                                    Log.d(TAG, "Observed IPv6 SYN from client for " + key + " clientIsn=" + state.clientIsn);
                                    if (state.egress == null) { state.detectionDone = true; state.captured = true; state.detectedType = "SYN"; state.stage = ConnectionStage.SYN_RECEIVED; handleCapturedConnection(state); }
                                }

                                if (rst) {
                                    Log.d(TAG, "Observed RST from client for " + key + " (IPv6); tearing down captured flow");
                                    try { if (state.egress != null) state.egress.close(); } catch (Exception ignored) {}
                                    connectionMap.remove(key);
                                    continue;
                                }

                                // If client sent ACKs, remove acknowledged sent segments
                                if (ackFlag) {
                                    long ackVal = Integer.toUnsignedLong(ack);
                                    try {
                                        synchronized (state.getSentSegments()) {
                                            java.util.Iterator<SentSegment> it = state.getSentSegments().iterator();
                                            while (it.hasNext()) {
                                                SentSegment s = it.next();
                                                if ((s.seq + s.payloadLen) <= ackVal) it.remove();
                                            }
                                        }
                                    } catch (Exception ignored) {}
                                }

                                if (state.egress != null && payload != null) {
                                    try {
                                        long clientSeq = Integer.toUnsignedLong(seq);
                                        if (clientSeq < state.clientNextSeq) {
                                            Log.d(TAG, "Dropping duplicate IPv6 payload for " + key + " seq=" + clientSeq + " nextExpected=" + state.clientNextSeq);
                                        } else {
                                            java.io.OutputStream os = state.egress.getOutputStream(); os.write(payload); os.flush(); state.clientNextSeq = clientSeq + payload.length;
                                        }
                                    } catch (Exception e) { Log.w(TAG, "Failed to forward IPv6 client payload to egress for " + key + ": " + e.getMessage()); }
                                }
                            } else if (nextHeader == 17 && n >= 40 + 8) {
                                int ihl = 40; // IPv6 base header length for UDP
                                int srcPort = ((buf[ihl] & 0xFF) << 8) | (buf[ihl + 1] & 0xFF);
                                int dstPort = ((buf[ihl + 2] & 0xFF) << 8) | (buf[ihl + 3] & 0xFF);
                                int tcpDataOffsetWords = 0; // not applicable for UDP
                                int dataOffset = ihl + 8;
                                int payloadLen = dataOffset < n ? (n - dataOffset) : 0;
                                byte[] payload = null;
                                if (payloadLen > 0) { payload = new byte[payloadLen]; System.arraycopy(buf, dataOffset, payload, 0, payloadLen); }

                                String srcIp = toIpv6String(buf, 8);
                                String dstIp = toIpv6String(buf, 24);
                                ConnectionKey keyUdp = new ConnectionKey(srcIp, srcPort, dstIp, dstPort);
                                UdpFlowState st = udpMap.get(keyUdp);
                                if (st == null) {
                                    try {
                                        DatagramSocket ds = new DatagramSocket();
                                        try { protect(ds); } catch (Exception ignored) {}
                                        final UdpFlowState fst = new UdpFlowState(keyUdp, ds);
                                        st = fst;
                                        udpMap.put(keyUdp, fst);

                                        Thread reader = new Thread(() -> {
                                            byte[] tmp = bufferPool.acquireAtLeast(4096);
                                            try {
                                                while (fst.running) {
                                                    DatagramPacket dp = new DatagramPacket(tmp, tmp.length);
                                                    try { fst.socket.receive(dp); } catch (java.net.SocketTimeoutException ste) { continue; }
                                                    if (dp.getLength() <= 0) continue;
                                                    fst.lastActivityMillis = System.currentTimeMillis();
                                                    try {
                                                        byte[] payloadResp = java.util.Arrays.copyOf(dp.getData(), dp.getLength());
                                                        byte[] p = buildIpv6UdpPacket(keyUdp.dstIp, keyUdp.srcIp, keyUdp.dstPort, keyUdp.srcPort, payloadResp);
                                                        try { sendPacketIntoTun(p); } catch (Exception ex) { Log.w(TAG, "Failed to inject UDP response (IPv6): " + ex.getMessage()); }
                                                    } catch (Exception ex) {
                                                        Log.w(TAG, "Failed to craft/inject UDP response (IPv6): " + ex.getMessage());
                                                    }
                                                }
                                            } catch (Exception e) {
                                                Log.w(TAG, "UDP reader loop failed (IPv6) for " + keyUdp + ": " + e.getMessage());
                                            } finally {
                                                bufferPool.release(tmp);
                                                try { fst.socket.close(); } catch (Exception ignored) {}
                                                udpMap.remove(keyUdp);
                                            }
                                        }, "clash-udp6-reader");
                                        reader.start();
                                    } catch (Exception e) {
                                        Log.w(TAG, "Failed to create UDP socket for " + keyUdp + " (IPv6): " + e.getMessage());
                                        continue;
                                    }
                                }

                                if (st != null && payload != null) {
                                    try {
                                        DatagramPacket out = new DatagramPacket(payload, payload.length, InetAddress.getByName(keyUdp.dstIp), keyUdp.dstPort);
                                        st.socket.send(out);
                                        st.lastActivityMillis = System.currentTimeMillis();
                                    } catch (Exception e) {
                                        Log.w(TAG, "Failed to send UDP datagram (IPv6) for " + keyUdp + ": " + e.getMessage());
                                    }
                                }
                            }
                        }
                    } catch (Exception e) { Log.w(TAG, "TUN packet parse error: " + e.getMessage()); }


                }
            } catch (Exception e) {
                bufferPool.release(buf);
                Log.e(TAG, "TUN processor main loop failed", e);
            } finally {
                tunProcessorRunning = false;
                Log.d(TAG, "TUN processor thread exiting");
            }
        }, "clash-tun-processor");
        tunProcessorThread.start();
    }

    private synchronized void stopTunProcessor() {
        if (!tunProcessorRunning && tunProcessorThread == null) return;
        tunProcessorRunning = false;
        stopTunWriter();
        try {
            if (tunProcessorThread != null) {
                try { tunProcessorThread.interrupt(); } catch (Exception ignored) {}
                try { tunProcessorThread.join(1000); } catch (Exception ignored) {}
            }
        } finally {
            tunProcessorThread = null;
        }
    }

    private synchronized void startTunWriter() {
        if (tunWriterRunning) return;
        if (tunDevice == null) return;
        tunWriterRunning = true;
        tunWriterThread = new Thread(() -> {
            Log.d(TAG, "TUN writer thread started");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(tunDevice.getFileDescriptor())) {
                while (tunWriterRunning) {
                    byte[] pkt = null;
                    try { pkt = tunWriteQueue.take(); } catch (InterruptedException ie) { break; }
                    if (pkt == null) continue;
                    try { out.write(pkt); out.flush(); tunPacketsWritten.incrementAndGet(); } catch (Exception e) { Log.w(TAG, "TUN writer failed to write packet: " + e.getMessage()); }
                    // Packets are now properly-sized arrays (not pool buffers), no need to release
                }
            } catch (Exception e) {
                Log.e(TAG, "TUN writer main loop failed", e);
            } finally {
                tunWriterRunning = false;
                Log.d(TAG, "TUN writer thread exiting");
            }
        }, "clash-tun-writer");
        tunWriterThread.start();
    }

    private synchronized void stopTunWriter() {
        if (!tunWriterRunning && tunWriterThread == null) return;
        tunWriterRunning = false;
        try {
            if (tunWriterThread != null) {
                try { tunWriterThread.interrupt(); } catch (Exception ignored) {}
                try { tunWriterThread.join(1000); } catch (Exception ignored) {}
            }
        } finally {
            tunWriterThread = null;
            tunWriteQueue.clear();
        }
    }

    /**
     * Create notification channel for foreground service.
     * On Android 12+ and HarmonyOS, use DEFAULT importance to ensure visibility.
     */
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Use DEFAULT importance instead of LOW for Android 12+ / HarmonyOS compatibility
            int importance = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                ? NotificationManager.IMPORTANCE_DEFAULT
                : NotificationManager.IMPORTANCE_LOW;

            NotificationChannel channel = new NotificationChannel(
                NOTIFICATION_CHANNEL,
                "Clash VPN Service",
                importance
            );
            channel.setDescription("Clash VPN is running");
            channel.setShowBadge(false); // Don't show badge on app icon
            channel.enableVibration(false); // No vibration
            channel.enableLights(false); // No LED
            channel.setSound(null, null); // No sound

            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
                Log.d(TAG, "Notification channel created with importance: " + importance);
            }
        }
    }

    /**
     * Create foreground service notification.
     * Enhanced for Android 12+ and HarmonyOS visibility.
     */
    private Notification createNotification() {
        // Create an intent to launch the app when notification is tapped
        android.app.PendingIntent pendingIntent = null;
        try {
            Intent notificationIntent = new Intent(this, com.github.worthies.clash.MainActivity.class);
            notificationIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
            int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                ? android.app.PendingIntent.FLAG_IMMUTABLE
                : 0;
            pendingIntent = android.app.PendingIntent.getActivity(this, 0, notificationIntent, flags);
        } catch (Exception e) {
            Log.w(TAG, "Failed to create pending intent: " + e.getMessage());
        }

        // Use DEFAULT priority for Android 12+ / HarmonyOS to ensure notification shows
        int priority = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            ? NotificationCompat.PRIORITY_DEFAULT
            : NotificationCompat.PRIORITY_LOW;

        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
            .setContentTitle("Clash VPN")
            .setContentText("VPN connection active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(priority)
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC);

        if (pendingIntent != null) {
            builder.setContentIntent(pendingIntent);
        }

        return builder.build();
    }

    // Connection key used for the minimal connection-tracking map
    private static class ConnectionKey {
        final String srcIp;
        final int srcPort;
        final String dstIp;
        final int dstPort;

        ConnectionKey(String s, int sp, String d, int dp) {
            srcIp = s; srcPort = sp; dstIp = d; dstPort = dp;
        }

        @Override public boolean equals(Object o) {
            if (o == null || !(o instanceof ConnectionKey)) return false;
            ConnectionKey k = (ConnectionKey)o;
            return srcIp.equals(k.srcIp) && dstIp.equals(k.dstIp) && srcPort == k.srcPort && dstPort == k.dstPort;
        }

        @Override public int hashCode() { return (srcIp + ":" + srcPort + ":" + dstIp + ":" + dstPort).hashCode(); }

        @Override public String toString() { return srcIp + ":" + srcPort + " -> " + dstIp + ":" + dstPort; }
    }

    // State for an observed connection (buffers, detection info and egress socket)
    private enum ConnectionStage { NEW, SYN_RECEIVED, PROXY_CONNECTING, ESTABLISHED, FIN_WAIT, CLOSED }

    private static class ConnectionState {
        final ConnectionKey key;
        final java.io.ByteArrayOutputStream clientBuffer = new java.io.ByteArrayOutputStream();
        volatile boolean detectionDone = false;
        volatile boolean captured = false;
        volatile String detectedType = null;
        volatile Socket egress = null;
        // Sequence / ack bookkeeping for client <-> service (we mirror)
        volatile long clientIsn = 0; // client's initial sequence
        volatile long clientNextSeq = 0; // next expected seq from client
        volatile int duplicateCount = 0; // track duplicate packets to reduce log spam
        volatile long serverIsn = 0; // server-side seq space we use when injecting
        volatile long serverNextSeq = 0; // next seq to use when sending server->client
        // Sent server->client segments awaiting ACK from client
        private final java.util.LinkedList<SentSegment> sentSegments = new java.util.LinkedList<>();

        volatile long lastActivityMillis = System.currentTimeMillis();
        volatile ConnectionStage stage = ConnectionStage.NEW;
        ConnectionState(ConnectionKey k) { key = k; }

        void appendClientPayload(byte[] data) {
            try { clientBuffer.write(data); } catch (Exception ignored) {}
            lastActivityMillis = System.currentTimeMillis();
        }

        byte[] getBufferedClientData() { return clientBuffer.toByteArray(); }
        void addSentSegment(SentSegment s) { sentSegments.addLast(s); }
        java.util.List<SentSegment> getSentSegments() { return sentSegments; }
    }

    private static class SentSegment {
        final long seq;
        final byte[] packet; // full IPv4/IPv6 packet to reinject
        final int payloadLen;
        long sentAtMillis;
        int attempts;

        SentSegment(long seq, byte[] pkt, int payloadLen) {
            this.seq = seq; this.packet = pkt; this.payloadLen = payloadLen; this.sentAtMillis = System.currentTimeMillis(); this.attempts = 1;
        }
    }

    // Lightweight UDP flow state used to forward datagrams transparently
    private static class UdpFlowState {
        final ConnectionKey key;
        final DatagramSocket socket;
        volatile long lastActivityMillis = System.currentTimeMillis();
        volatile boolean running = true;

        UdpFlowState(ConnectionKey k, DatagramSocket s) {
            this.key = k; this.socket = s;
        }
    }

    private void pruneStaleConnections() {
        long now = System.currentTimeMillis();
        // Reduce timeout from 2 minutes to 30 seconds for faster cleanup
        long timeoutMs = 30 * 1000;

        // Track pruned count for logging
        int prunedTcp = 0;
        int prunedUdp = 0;

        // Prune TCP connections
        java.util.Iterator<Map.Entry<ConnectionKey, ConnectionState>> tcpIter = connectionMap.entrySet().iterator();
        while (tcpIter.hasNext()) {
            Map.Entry<ConnectionKey, ConnectionState> e = tcpIter.next();
            ConnectionState st = e.getValue();
            if (st == null || st.lastActivityMillis + timeoutMs < now) {
                try {
                    if (st != null && st.egress != null) {
                        try { st.egress.close(); } catch (Exception ignored) {}
                    }
                } catch (Exception ignored) {}
                tcpIter.remove();
                prunedTcp++;
            }
        }

        // Prune UDP flows
        java.util.Iterator<Map.Entry<ConnectionKey, UdpFlowState>> udpIter = udpMap.entrySet().iterator();
        while (udpIter.hasNext()) {
            Map.Entry<ConnectionKey, UdpFlowState> e = udpIter.next();
            UdpFlowState st = e.getValue();
            if (st == null || st.lastActivityMillis + timeoutMs < now) {
                try {
                    if (st != null && st.socket != null) st.socket.close();
                } catch (Exception ignored) {}
                udpIter.remove();
                prunedUdp++;
            }
        }

        if (prunedTcp > 0 || prunedUdp > 0) {
            Log.d(TAG, "Pruned " + prunedTcp + " TCP and " + prunedUdp + " UDP stale connections (total: TCP=" + connectionMap.size() + " UDP=" + udpMap.size() + ")");
        }
    }

    /** Very small heuristic to detect HTTP plaintext requests */
    private static boolean looksLikeHttp(byte[] bytes) {
        if (bytes == null || bytes.length < 4) return false;
        String s = null;
        try { s = new String(bytes, 0, Math.min(bytes.length, 16), "US-ASCII"); } catch (Exception e) { return false; }
        s = s.toUpperCase();
        return s.startsWith("GET ") || s.startsWith("POST ") || s.startsWith("PUT ") || s.startsWith("HEAD ") || s.startsWith("PATCH ") || s.startsWith("DELETE ") || s.startsWith("OPTIONS ") || s.startsWith("CONNECT ");
    }

    /** Extract SNI from a TLS ClientHello if present. Returns domain string or null. */
    private static String extractTlsSni(byte[] bytes) {
        try {
            if (bytes == null || bytes.length < 5) return null;
            int pos = 0;
            // TLS record header: type(1)=22 for handshake, ver(2), len(2)
            int contentType = bytes[pos] & 0xFF; pos++;
            if (contentType != 22) return null;
            int ver = ((bytes[pos] & 0xFF) << 8) | (bytes[pos+1] & 0xFF); pos+=2;
            int recLen = ((bytes[pos] & 0xFF) << 8) | (bytes[pos+1] & 0xFF); pos+=2;
            if (recLen + 5 > bytes.length) { /* truncated but may still contain full ClientHello parts, continue */ }

            // Handshake header
            if (pos + 4 >= bytes.length) return null;
            int hsType = bytes[pos] & 0xFF; pos++;
            if (hsType != 1) return null; // not ClientHello
            int hsLen = ((bytes[pos] & 0xFF) << 16) | ((bytes[pos+1] & 0xFF) << 8) | (bytes[pos+2] & 0xFF); pos += 3;
            if (pos + 2 >= bytes.length) return null;
            // skip client version and random
            pos += 2; // client version
            pos += 32; // random
            if (pos >= bytes.length) return null;
            // session id
            int sessionIdLen = bytes[pos] & 0xFF; pos++;
            pos += sessionIdLen;
            if (pos + 2 > bytes.length) return null;
            // cipher suites
            int csLen = ((bytes[pos] & 0xFF) << 8) | (bytes[pos+1] & 0xFF); pos += 2;
            pos += csLen;
            if (pos >= bytes.length) return null;
            // compression methods
            int compLen = bytes[pos] & 0xFF; pos++;
            pos += compLen;
            if (pos + 2 > bytes.length) return null;
            // extensions length
            int extTotalLen = ((bytes[pos] & 0xFF) << 8) | (bytes[pos+1] & 0xFF); pos += 2;
            int extEnd = pos + extTotalLen;
            while (pos + 4 <= extEnd && pos + 4 <= bytes.length) {
                int extType = ((bytes[pos] & 0xFF) << 8) | (bytes[pos+1] & 0xFF); pos += 2;
                int extLen = ((bytes[pos] & 0xFF) << 8) | (bytes[pos+1] & 0xFF); pos += 2;
                if (pos + extLen > bytes.length) break;
                if (extType == 0) { // server_name
                    int listLen = ((bytes[pos] & 0xFF) << 8) | (bytes[pos+1] & 0xFF); pos += 2;
                    int idx = pos;
                    while (idx + 3 <= pos + listLen && idx + 3 <= bytes.length) {
                        int nameType = bytes[idx] & 0xFF; idx++;
                        int nameLen = ((bytes[idx] & 0xFF) << 8) | (bytes[idx+1] & 0xFF); idx += 2;
                        if (idx + nameLen > bytes.length) break;
                        if (nameType == 0) {
                            return new String(bytes, idx, nameLen, "US-ASCII");
                        }
                        idx += nameLen;
                    }
                }
                pos += extLen;
            }
        } catch (Exception e) {
            // Ignore parsing errors
        }
        return null;
    }

    /** Handle a connection that was flagged for capture based on detection.
     *  Try to open a protected egress connection to the configured proxy
     *  and forward buffered client data. This is a best-effort bridge; a
     *  full TCP stack is outside scope — this is a pragmatic streaming
     *  solution for proxying payloads (e.g. HTTP/TLS initial bytes).
     */
    private void handleCapturedConnection(ConnectionState state) {
        if (state == null || state.captured == false) return;
        // Ensure we have a proxy configured
        // Use local proxy (savedProxyAddress:savedProxyPort) instead of remote proxy (proxyNodeHost:proxyNodePort)
        // to avoid VPN routing loops when protect() doesn't work (e.g., Android emulator)
        if (savedProxyAddress == null || savedProxyPort == null) {
            Log.w(TAG, "Captured connection but no proxy configured; skipping: " + state.key);
            return;
        }

        // Connect via SOCKS5 on a protected socket in background
        state.stage = ConnectionStage.PROXY_CONNECTING;
        connectionExecutor.submit(() -> {
            try {
                Log.d(TAG, "Attempting SOCKS5 connect for captured flow " + state.key + " via local proxy " + savedProxyAddress + ":" + savedProxyPort);
                Socket s = connectViaSocks5(savedProxyAddress, savedProxyPort.intValue(), state.key.dstIp, state.key.dstPort, 8000);
                if (s == null) {
                    Log.w(TAG, "SOCKS5 connect failed for flow " + state.key);
                    return;
                }
                state.egress = s;
                state.stage = ConnectionStage.ESTABLISHED;
                // record a server-side ISN (random) for injected packets
                state.serverIsn = (System.currentTimeMillis() & 0x7FFFFFFF) + 1000;
                state.serverNextSeq = state.serverIsn;
                Log.d(TAG, "SOCKS5 connect established for flow " + state.key + "; forwarding buffered client payload (" + state.getBufferedClientData().length + " bytes)");

                // Send buffered client payload to egress (best-effort)
                try { s.getOutputStream().write(state.getBufferedClientData()); } catch (Exception e) { Log.w(TAG, "Failed writing buffered client data to egress: " + e.getMessage()); }

                // Send SYN-ACK back to client to complete the client handshake (best-effort)
                try { sendSynAckToClient(state); } catch (Exception e) { Log.w(TAG, "Failed to send SYN-ACK to client: " + e.getMessage()); }

                // Start a reader thread that consumes responses from the egress and injects them into TUN
                // Use executor instead of creating unbounded threads
                egressReaderExecutor.submit(() -> {
                    byte[] tmp = bufferPool.acquireAtLeast(4096);
                    try (java.io.InputStream is = s.getInputStream()) {
                        int len;
                        while ((len = is.read(tmp)) > 0) {
                            state.lastActivityMillis = System.currentTimeMillis();
                            // Inject server->client payload as TCP packets into the TUN device
                            byte[] payloadBytes = java.util.Arrays.copyOf(tmp, len);
                            try {
                                sendServerPayloadToClient(state, payloadBytes);
                            } catch (Exception e) {
                                Log.w(TAG, "Failed to inject server->client payload for " + state.key + ": " + e.getMessage());
                            }
                        }
                    } catch (Exception e) {
                        Log.w(TAG, "Egress read error for " + state.key + ": " + e.getMessage());
                    } finally {
                        try { s.close(); } catch (Exception ignored) {}
                        bufferPool.release(tmp);
                        // inject a final FIN to client to signal close (best-effort)
                        try {
                            if (state.clientNextSeq > 0 && state.serverNextSeq > 0) {
                                byte[] finPkt;
                                if (state.key.srcIp.contains(":" ) || state.key.dstIp.contains(":")) {
                                    finPkt = buildIpv6TcpPacket(state.key.dstIp, state.key.srcIp, state.key.dstPort, state.key.srcPort, state.serverNextSeq, state.clientNextSeq, (byte)0x11, null);
                                } else {
                                    finPkt = buildIpv4TcpPacket(state.key.dstIp, state.key.srcIp, state.key.dstPort, state.key.srcPort, state.serverNextSeq, state.clientNextSeq, (byte)0x11, null);
                                }
                                try { sendPacketIntoTun(finPkt); } catch (Exception ignored) {}
                                state.serverNextSeq += 1;
                            }
                        } catch (Exception e) { Log.w(TAG, "Error injecting final FIN: " + e.getMessage()); }

                        connectionMap.remove(state.key);
                        Log.d(TAG, "Egress socket closed and connection removed for " + state.key);
                    }
                });

            } catch (Throwable t) {
                Log.w(TAG, "Error handling captured flow " + state.key + ": " + t.getMessage());
            }
        });
    }

    /** Create a protected TCP socket, connect to the proxy and do a SOCKS5 handshake+CONNECT.
     *  Returns the established socket if successful, otherwise null.
     */
    private Socket connectViaSocks5(String proxyHost, int proxyPort, String destHost, int destPort, int timeoutMs) {
        Socket socket = null;
        try {
            socket = new Socket();
            // Protect socket so its traffic does not loop back through the VPN
            // Note: In Android emulator and when using addDisallowedApplication, protect()
            // may return false but traffic still bypasses VPN correctly
            boolean isProtected = protect(socket);
            if (!isProtected && Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                // Only warn on older Android versions where addDisallowedApplication isn't available
                Log.w(TAG, "Socket protection failed - VPN routing loop possible on API < 21");
            }
            Log.d(TAG, "Connecting to SOCKS5 proxy " + proxyHost + ":" + proxyPort);
            socket.connect(new InetSocketAddress(proxyHost, proxyPort), timeoutMs);
            Log.d(TAG, "SOCKS5 socket connected successfully to " + proxyHost + ":" + proxyPort);

            java.io.OutputStream os = socket.getOutputStream();
            java.io.InputStream is = socket.getInputStream();

            // No-auth greeting: VER=5, NMETHODS=1, METHODS=0 (no auth)
            os.write(new byte[] {0x05, 0x01, 0x00}); os.flush();
            byte[] buf = new byte[2];
            int r = is.read(buf);
            if (r != 2 || buf[0] != 0x05 || buf[1] == (byte)0xFF) {
                Log.w(TAG, "SOCKS5 greeting failed or no acceptable auth method");
                try { socket.close(); } catch (Exception ignored) {}
                return null;
            }

            // Build CONNECT request: VER=5, CMD=1, RSV=0, ATYP, DST.ADDR, DST.PORT
            java.io.ByteArrayOutputStream req = new java.io.ByteArrayOutputStream();
            req.write(0x05); req.write(0x01); req.write(0x00);
            // Always use ATYP=3 (domain) for simplicity, even for IPs
            byte[] hostBytes = destHost.getBytes("US-ASCII");
            req.write(0x03); req.write(hostBytes.length); req.write(hostBytes);
            req.write((destPort >> 8) & 0xFF); req.write(destPort & 0xFF);
            os.write(req.toByteArray()); os.flush();

            // Read response header
            byte[] respHdr = new byte[4];
            r = is.read(respHdr);
            if (r < 4 || respHdr[0] != 0x05) {
                Log.w(TAG, "Invalid SOCKS5 response header"); try { socket.close(); } catch (Exception ignored) {} return null;
            }
            int rep = respHdr[1] & 0xFF;
            if (rep != 0x00) {
                Log.w(TAG, "SOCKS5 CONNECT failed rep=" + rep);
                try { socket.close(); } catch (Exception ignored) {}
                return null;
            }
            int atyp = respHdr[3] & 0xFF;

            // consume bound address depending on atyp
            if (atyp == 1) { // IPv4
                byte[] tail = new byte[6]; is.read(tail);
            } else if (atyp == 3) { // domain
                int len = is.read(); if (len > 0) { byte[] tail = new byte[len + 2]; is.read(tail); }
            } else if (atyp == 4) { // IPv6
                byte[] tail = new byte[18]; is.read(tail);
            }

            return socket;
        } catch (Exception e) {
            Log.w(TAG, "connectViaSocks5 failed: " + e.getClass().getSimpleName() + " -> " + e.getMessage());
            try { if (socket != null) socket.close(); } catch (Exception ignored) {}
            return null;
        }
    }

    // Debug / test helpers
    public synchronized int getActiveCapturedConnectionCount() {
        return connectionMap.size();
    }

    public synchronized String dumpCapturedConnections() {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<ConnectionKey, ConnectionState> e : connectionMap.entrySet()) {
            ConnectionState s = e.getValue();
            sb.append(e.getKey().toString()).append(" -> ");
            sb.append("captured=").append(s.captured).append(", type=").append(s.detectedType).append(", egress=").append(s.egress == null ? "null" : "open");
            sb.append("\n");
        }
        return sb.toString();
    }

    public int getTunPacketsWritten() { return tunPacketsWritten.get(); }
    public int getTunPacketsDropped() { return tunPacketsDropped.get(); }
    public int getTunWriteQueueMax() { return tunWriteQueueMax.get(); }
    public int getTunPacketsRead() { return tunPacketsRead.get(); }
    public int getTunPacketsForwarded() { return tunPacketsForwarded.get(); }

    // Utility to inject SYN-ACK into the TUN device to complete client handshake
    private void sendSynAckToClient(ConnectionState state) {
        if (tunDevice == null) return;
        try {
            long seq = state.serverIsn;
            long ack = state.clientIsn + 1;
            byte[] pkt;
            if (state.key.srcIp.contains(":" ) || state.key.dstIp.contains(":")) {
                pkt = buildIpv6TcpPacket(state.key.dstIp, state.key.srcIp, state.key.dstPort, state.key.srcPort, seq, ack, (byte)0x12, null);
            } else {
                pkt = buildIpv4TcpPacket(state.key.dstIp, state.key.srcIp, state.key.dstPort, state.key.srcPort, seq, ack, (byte)0x12, null);
            }
            sendPacketIntoTun(pkt);
            // advance serverNextSeq for SYN (SYN consumes 1 sequence)
            state.serverNextSeq = state.serverIsn + 1;
        } catch (Exception e) {
            Log.w(TAG, "sendSynAckToClient failed: " + e.getMessage());
        }
    }

    // Inject server->client payload as TCP segment(s) into the TUN device
    private void sendServerPayloadToClient(ConnectionState state, byte[] payload) {
        if (payload == null || payload.length == 0) return;
        try {
            // craft a single TCP packet with PSH+ACK
            byte flags = 0x18; // PSH + ACK
            byte[] pkt;
            if (state.key.srcIp.contains(":" ) || state.key.dstIp.contains(":")) {
                pkt = buildIpv6TcpPacket(state.key.dstIp, state.key.srcIp, state.key.dstPort, state.key.srcPort, state.serverNextSeq, state.clientNextSeq, flags, payload);
            } else {
                pkt = buildIpv4TcpPacket(state.key.dstIp, state.key.srcIp, state.key.dstPort, state.key.srcPort, state.serverNextSeq, state.clientNextSeq, flags, payload);
            }
            // Track the injected packet for retransmit and ACK handling
            SentSegment seg = new SentSegment(state.serverNextSeq, pkt, payload.length);
            state.addSentSegment(seg);
            sendPacketIntoTun(pkt);
            state.serverNextSeq += payload.length;
        } catch (Exception e) {
            Log.w(TAG, "sendServerPayloadToClient failed: " + e.getMessage());
        }
    }

    private void retransmitPendingSegments() {
        long now = System.currentTimeMillis();
        for (Map.Entry<ConnectionKey, ConnectionState> e : connectionMap.entrySet()) {
            ConnectionState st = e.getValue();
            if (st == null) continue;
            synchronized (st.getSentSegments()) {
                java.util.Iterator<SentSegment> it = st.getSentSegments().iterator();
                while (it.hasNext()) {
                    SentSegment s = it.next();
                    if (now - s.sentAtMillis >= RETRANSMIT_MS) {
                        if (s.attempts >= MAX_RETRANSMIT_ATTEMPTS) {
                            // Give up on this connection
                            Log.w(TAG, "Retransmit attempts exceeded for " + e.getKey() + " segment seq=" + s.seq + "; closing connection");
                            try { if (st.egress != null) st.egress.close(); } catch (Exception ignored) {}
                            it.remove();
                            connectionMap.remove(e.getKey());
                            break; // connection removed
                        } else {
                            try {
                                sendPacketIntoTun(s.packet);
                                s.sentAtMillis = now;
                                s.attempts += 1;
                                Log.d(TAG, "Retransmitted segment for " + e.getKey() + " seq=" + s.seq + " attempts=" + s.attempts);
                            } catch (Exception ex) {
                                Log.w(TAG, "Failed retransmit for " + e.getKey() + " seq=" + s.seq + ": " + ex.getMessage());
                            }
                        }
                    }
                }
            }
        }
    }

    // Build a minimal IPv4+TCP packet (no options) ready to write to the tun device
    private byte[] buildIpv4TcpPacket(String srcIpStr, String dstIpStr, int srcPort, int dstPort, long seq, long ack, byte flags, byte[] payload) throws Exception {
        byte[] srcIp = ipToBytes(srcIpStr);
        byte[] dstIp = ipToBytes(dstIpStr);
        int tcpHeaderLen = 20;
        int payloadLen = payload == null ? 0 : payload.length;
        int ipTotalLen = 20 + tcpHeaderLen + payloadLen;
        byte[] packet = bufferPool.acquireAtLeast(ipTotalLen);

        // IP header
        packet[0] = 0x45; // ver(4)=4, ihl=5
        packet[1] = 0; // TOS
        packet[2] = (byte)((ipTotalLen >> 8) & 0xFF);
        packet[3] = (byte)(ipTotalLen & 0xFF);
        int id = (int)(System.nanoTime() & 0xFFFF);
        packet[4] = (byte)((id >> 8) & 0xFF);
        packet[5] = (byte)(id & 0xFF);
        packet[6] = 0; packet[7] = 0; // flags+frag
        packet[8] = 64; // TTL
        packet[9] = 6; // TCP
        packet[10] = 0; packet[11] = 0; // checksum placeholder
        System.arraycopy(srcIp, 0, packet, 12, 4);
        System.arraycopy(dstIp, 0, packet, 16, 4);

        // Build TCP header at offset 20
        int off = 20;
        packet[off] = (byte)((srcPort >> 8) & 0xFF);
        packet[off+1] = (byte)(srcPort & 0xFF);
        packet[off+2] = (byte)((dstPort >> 8) & 0xFF);
        packet[off+3] = (byte)(dstPort & 0xFF);
        packet[off+4] = (byte)((seq >> 24) & 0xFF);
        packet[off+5] = (byte)((seq >> 16) & 0xFF);
        packet[off+6] = (byte)((seq >> 8) & 0xFF);
        packet[off+7] = (byte)(seq & 0xFF);
        packet[off+8] = (byte)((ack >> 24) & 0xFF);
        packet[off+9] = (byte)((ack >> 16) & 0xFF);
        packet[off+10] = (byte)((ack >> 8) & 0xFF);
        packet[off+11] = (byte)(ack & 0xFF);
        packet[off+12] = (byte)((5 << 4) & 0xF0); // data offset = 5 (20 bytes)
        packet[off+13] = flags;
        packet[off+14] = (byte)((65535 >> 8) & 0xFF);
        packet[off+15] = (byte)(65535 & 0xFF);
        packet[off+16] = 0; packet[off+17] = 0; // checksum
        packet[off+18] = 0; packet[off+19] = 0; // urgent pointer

        // Payload
        if (payloadLen > 0) System.arraycopy(payload, 0, packet, off + tcpHeaderLen, payloadLen);

        // compute checksums
        int ipChk = ipChecksum(packet, 0, 20);
        packet[10] = (byte)((ipChk >> 8) & 0xFF); packet[11] = (byte)(ipChk & 0xFF);

        int tcpChk = tcpChecksum(srcIp, dstIp, packet, off, tcpHeaderLen + payloadLen);
        packet[off+16] = (byte)((tcpChk >> 8) & 0xFF); packet[off+17] = (byte)(tcpChk & 0xFF);

        // CRITICAL FIX: bufferPool returns 8192-byte buffers, but actual packet is ipTotalLen
        // Copy to properly-sized array to avoid EINVAL errors when writing to TUN
        byte[] result = new byte[ipTotalLen];
        System.arraycopy(packet, 0, result, 0, ipTotalLen);
        bufferPool.release(packet); // Release pool buffer immediately
        return result;
    }

    private byte[] ipToBytes(String ip) throws Exception {
        if (ip.contains(":")) {
            // IPv6
            java.net.InetAddress ia = java.net.InetAddress.getByName(ip);
            byte[] b = ia.getAddress();
            if (b.length != 16) throw new IllegalArgumentException("Invalid IPv6 address");
            return b;
        } else {
            String[] parts = ip.split("\\.");
            if (parts.length != 4) throw new IllegalArgumentException("Invalid IPv4 address");
            byte[] b = new byte[4];
            for (int i = 0; i < 4; i++) b[i] = (byte)(Integer.parseInt(parts[i]) & 0xFF);
            return b;
        }
    }

    private String toIpv6String(byte[] buf, int off) {
        try {
            byte[] addr = new byte[16];
            System.arraycopy(buf, off, addr, 0, 16);
            java.net.InetAddress ia = java.net.InetAddress.getByAddress(addr);
            return ia.getHostAddress();
        } catch (Exception e) { return null; }
    }

    private int ipChecksum(byte[] buf, int off, int len) {
        long sum = 0;
        for (int i = off; i < off + len; i += 2) {
            int hi = buf[i] & 0xFF;
            int lo = (i+1 < off + len) ? (buf[i+1] & 0xFF) : 0;
            sum += ((hi << 8) | lo);
            while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        return (int)(~sum & 0xFFFF);
    }

    private int tcpChecksum(byte[] srcIp, byte[] dstIp, byte[] tcpPacket, int tcpOff, int tcpLen) {
        long sum = 0;
        // pseudo-header
        for (int i = 0; i < 4; i += 2) {
            int v = ((srcIp[i] & 0xFF) << 8) | (srcIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        for (int i = 0; i < 4; i += 2) {
            int v = ((dstIp[i] & 0xFF) << 8) | (dstIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        sum += 6 & 0xFF; // protocol (6) - treat as 0x0006
        sum += tcpLen & 0xFFFF; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);

        // TCP header and payload
        for (int i = 0; i < tcpLen; i += 2) {
            int hi = tcpPacket[tcpOff + i] & 0xFF;
            int lo = (i + 1 < tcpLen) ? (tcpPacket[tcpOff + i + 1] & 0xFF) : 0;
            sum += ((hi << 8) | lo);
            while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }

        return (int)(~sum & 0xFFFF);
    }

    private int udpChecksum(byte[] srcIp, byte[] dstIp, byte[] udpPacket, int udpOff, int udpLen) {
        long sum = 0;
        // pseudo-header for IPv4 (src 4 bytes, dst 4 bytes)
        for (int i = 0; i < 4; i += 2) {
            int v = ((srcIp[i] & 0xFF) << 8) | (srcIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        for (int i = 0; i < 4; i += 2) {
            int v = ((dstIp[i] & 0xFF) << 8) | (dstIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        sum += 17 & 0xFF; // protocol
        sum += udpLen & 0xFFFF; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);

        for (int i = 0; i < udpLen; i += 2) {
            int hi = udpPacket[udpOff + i] & 0xFF;
            int lo = (i + 1 < udpLen) ? (udpPacket[udpOff + i + 1] & 0xFF) : 0;
            sum += ((hi << 8) | lo);
            while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }

        return (int)(~sum & 0xFFFF);
    }

    private int tcpChecksumIPv6(byte[] srcIp, byte[] dstIp, byte[] tcpPacket, int tcpOff, int tcpLen) {
        long sum = 0;
        // pseudo-header: src(16), dst(16), length(4), zeros(3) + next header(1)
        for (int i = 0; i < 16; i += 2) {
            int v = ((srcIp[i] & 0xFF) << 8) | (srcIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        for (int i = 0; i < 16; i += 2) {
            int v = ((dstIp[i] & 0xFF) << 8) | (dstIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        // length (32-bit) contains tcpLen
        sum += (tcpLen >> 16) & 0xFFFF; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        sum += tcpLen & 0xFFFF; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        // next header (protocol) = 6 (TCP)
        sum += 0x0006; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);

        for (int i = 0; i < tcpLen; i += 2) {
            int hi = tcpPacket[tcpOff + i] & 0xFF;
            int lo = (i + 1 < tcpLen) ? (tcpPacket[tcpOff + i + 1] & 0xFF) : 0;
            sum += ((hi << 8) | lo);
            while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }

        return (int)(~sum & 0xFFFF);
    }

    private int udpChecksumIPv6(byte[] srcIp, byte[] dstIp, byte[] udpPacket, int udpOff, int udpLen) {
        long sum = 0;
        for (int i = 0; i < 16; i += 2) {
            int v = ((srcIp[i] & 0xFF) << 8) | (srcIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        for (int i = 0; i < 16; i += 2) {
            int v = ((dstIp[i] & 0xFF) << 8) | (dstIp[i+1] & 0xFF);
            sum += v; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }
        // length (32-bit)
        int lenHigh = (udpLen >> 16) & 0xFFFF;
        int lenLow = udpLen & 0xFFFF;
        sum += lenHigh; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        sum += lenLow; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);

        sum += 0x0011; while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);

        for (int i = 0; i < udpLen; i += 2) {
            int hi = udpPacket[udpOff + i] & 0xFF;
            int lo = (i + 1 < udpLen) ? (udpPacket[udpOff + i + 1] & 0xFF) : 0;
            sum += ((hi << 8) | lo);
            while ((sum >> 16) > 0) sum = (sum & 0xFFFF) + (sum >> 16);
        }

        return (int)(~sum & 0xFFFF);
    }

    private byte[] buildIpv6TcpPacket(String srcIpStr, String dstIpStr, int srcPort, int dstPort, long seq, long ack, byte flags, byte[] payload) throws Exception {
        byte[] srcIp = ipToBytes(srcIpStr);
        byte[] dstIp = ipToBytes(dstIpStr);
        int tcpHeaderLen = 20;
        int payloadLen = payload == null ? 0 : payload.length;
        int ipPayloadLen = tcpHeaderLen + payloadLen;
        byte[] packet = bufferPool.acquireAtLeast(40 + ipPayloadLen);

        // IPv6 header
        packet[0] = (byte)((6 << 4) & 0xF0);
        packet[1] = 0; packet[2] = 0; packet[3] = 0; // traffic class + flowlabel
        packet[4] = (byte)((ipPayloadLen >> 8) & 0xFF);
        packet[5] = (byte)(ipPayloadLen & 0xFF);
        packet[6] = 6; // next header = TCP
        packet[7] = 64; // hop limit
        System.arraycopy(srcIp, 0, packet, 8, 16);
        System.arraycopy(dstIp, 0, packet, 24, 16);

        // TCP header at offset 40
        int off = 40;
        packet[off] = (byte)((srcPort >> 8) & 0xFF);
        packet[off+1] = (byte)(srcPort & 0xFF);
        packet[off+2] = (byte)((dstPort >> 8) & 0xFF);
        packet[off+3] = (byte)(dstPort & 0xFF);
        packet[off+4] = (byte)((seq >> 24) & 0xFF);
        packet[off+5] = (byte)((seq >> 16) & 0xFF);
        packet[off+6] = (byte)((seq >> 8) & 0xFF);
        packet[off+7] = (byte)(seq & 0xFF);
        packet[off+8] = (byte)((ack >> 24) & 0xFF);
        packet[off+9] = (byte)((ack >> 16) & 0xFF);
        packet[off+10] = (byte)((ack >> 8) & 0xFF);
        packet[off+11] = (byte)(ack & 0xFF);
        packet[off+12] = (byte)((5 << 4) & 0xF0);
        packet[off+13] = flags;
        packet[off+14] = (byte)((65535 >> 8) & 0xFF);
        packet[off+15] = (byte)(65535 & 0xFF);
        packet[off+16] = 0; packet[off+17] = 0; // checksum placeholder
        packet[off+18] = 0; packet[off+19] = 0; // urgent pointer

        if (payloadLen > 0) System.arraycopy(payload, 0, packet, off + tcpHeaderLen, payloadLen);

        int tcpChk = tcpChecksumIPv6(srcIp, dstIp, packet, off, tcpHeaderLen + payloadLen);
        packet[off+16] = (byte)((tcpChk >> 8) & 0xFF); packet[off+17] = (byte)(tcpChk & 0xFF);

        // CRITICAL FIX: bufferPool returns 8192-byte buffers, but actual packet is 40 + ipPayloadLen
        // Copy to properly-sized array to avoid EINVAL errors when writing to TUN
        int actualLen = 40 + ipPayloadLen;
        byte[] result = new byte[actualLen];
        System.arraycopy(packet, 0, result, 0, actualLen);
        bufferPool.release(packet); // Release pool buffer immediately
        return result;
    }

    private byte[] buildIpv4UdpPacket(String srcIpStr, String dstIpStr, int srcPort, int dstPort, byte[] payload) throws Exception {
        byte[] srcIp = ipToBytes(srcIpStr);
        byte[] dstIp = ipToBytes(dstIpStr);
        int udpHeaderLen = 8;
        int payloadLen = payload == null ? 0 : payload.length;
        int ipTotalLen = 20 + udpHeaderLen + payloadLen;
        byte[] packet = bufferPool.acquireAtLeast(ipTotalLen);

        // IP header
        packet[0] = 0x45; packet[1] = 0; packet[2] = (byte)((ipTotalLen >> 8) & 0xFF); packet[3] = (byte)(ipTotalLen & 0xFF);
        int id = (int)(System.nanoTime() & 0xFFFF);
        packet[4] = (byte)((id >> 8) & 0xFF); packet[5] = (byte)(id & 0xFF);
        packet[6] = 0; packet[7] = 0; packet[8] = 64; packet[9] = 17; packet[10] = 0; packet[11] = 0;
        System.arraycopy(srcIp, 0, packet, 12, 4);
        System.arraycopy(dstIp, 0, packet, 16, 4);

        int off = 20;
        packet[off] = (byte)((srcPort >> 8) & 0xFF);
        packet[off+1] = (byte)(srcPort & 0xFF);
        packet[off+2] = (byte)((dstPort >> 8) & 0xFF);
        packet[off+3] = (byte)(dstPort & 0xFF);
        int udpLen = udpHeaderLen + payloadLen;
        packet[off+4] = (byte)((udpLen >> 8) & 0xFF);
        packet[off+5] = (byte)(udpLen & 0xFF);
        packet[off+6] = 0; packet[off+7] = 0; // checksum placeholder

        if (payloadLen > 0) System.arraycopy(payload, 0, packet, off + udpHeaderLen, payloadLen);

        int ipChk = ipChecksum(packet, 0, 20);
        packet[10] = (byte)((ipChk >> 8) & 0xFF); packet[11] = (byte)(ipChk & 0xFF);

        int udpChk = udpChecksum(srcIp, dstIp, packet, off, udpLen);
        packet[off+6] = (byte)((udpChk >> 8) & 0xFF); packet[off+7] = (byte)(udpChk & 0xFF);

        // CRITICAL FIX: Return properly-sized array
        byte[] result = new byte[ipTotalLen];
        System.arraycopy(packet, 0, result, 0, ipTotalLen);
        bufferPool.release(packet);
        return result;
    }

    private byte[] buildIpv6UdpPacket(String srcIpStr, String dstIpStr, int srcPort, int dstPort, byte[] payload) throws Exception {
        byte[] srcIp = ipToBytes(srcIpStr);
        byte[] dstIp = ipToBytes(dstIpStr);
        int udpHeaderLen = 8;
        int payloadLen = payload == null ? 0 : payload.length;
        int ipPayloadLen = udpHeaderLen + payloadLen;
        byte[] packet = bufferPool.acquireAtLeast(40 + ipPayloadLen);

        packet[0] = (byte)((6 << 4) & 0xF0);
        packet[1] = 0; packet[2] = 0; packet[3] = 0;
        packet[4] = (byte)((ipPayloadLen >> 8) & 0xFF); packet[5] = (byte)(ipPayloadLen & 0xFF);
        packet[6] = 17; packet[7] = 64;
        System.arraycopy(srcIp, 0, packet, 8, 16);
        System.arraycopy(dstIp, 0, packet, 24, 16);

        int off = 40;
        packet[off] = (byte)((srcPort >> 8) & 0xFF);
        packet[off+1] = (byte)(srcPort & 0xFF);
        packet[off+2] = (byte)((dstPort >> 8) & 0xFF);
        packet[off+3] = (byte)(dstPort & 0xFF);
        int udpLen = udpHeaderLen + payloadLen;
        packet[off+4] = (byte)((udpLen >> 8) & 0xFF); packet[off+5] = (byte)(udpLen & 0xFF);
        packet[off+6] = 0; packet[off+7] = 0; // checksum placeholder

        if (payloadLen > 0) System.arraycopy(payload, 0, packet, off + udpHeaderLen, payloadLen);

        int chk = udpChecksumIPv6(srcIp, dstIp, packet, off, udpLen);
        packet[off+6] = (byte)((chk >> 8) & 0xFF); packet[off+7] = (byte)(chk & 0xFF);

        // CRITICAL FIX: Return properly-sized array
        int actualLen = 40 + ipPayloadLen;
        byte[] result = new byte[actualLen];
        System.arraycopy(packet, 0, result, 0, actualLen);
        bufferPool.release(packet);
        return result;
    }

    private void sendPacketIntoTun(byte[] packet) throws Exception {
        if (tunDevice == null || packet == null) return;

        // Validate packet before writing to prevent EINVAL errors
        if (!validatePacket(packet)) {
            Log.w(TAG, "Invalid packet dropped (length=" + packet.length + ")");
            tunPacketsDropped.incrementAndGet();
            return;
        }

        if (tunWriterRunning && tunWriterThread != null) {
            // enqueue; if queue is full, drop oldest to avoid blocking writer
            int qsz = tunWriteQueue.size();
            tunWriteQueueMax.updateAndGet(old -> Math.max(old, qsz));
            boolean offered = tunWriteQueue.offer(packet);
            if (!offered) {
                try {
                    byte[] old = tunWriteQueue.poll(); // drop oldest (it's a regular array now, not pool buffer)
                    boolean re = tunWriteQueue.offer(packet);
                    if (!re) tunPacketsDropped.incrementAndGet();
                } catch (Exception ignored) { tunPacketsDropped.incrementAndGet(); }
            }
            return;
        }

        // fallback: direct write (best-effort) if writer not running
        try (java.io.FileOutputStream out = new java.io.FileOutputStream(tunDevice.getFileDescriptor())) {
            out.write(packet);
            out.flush();
        }
    }

    /**
     * Validate IP packet structure to prevent EINVAL errors when writing to TUN.
     * Checks basic IPv4/IPv6 header integrity and packet length constraints.
     */
    private boolean validatePacket(byte[] packet) {
        if (packet == null || packet.length < 20) return false;

        int version = (packet[0] >> 4) & 0xF;

        if (version == 4) {
            // IPv4 validation
            if (packet.length < 20) return false;
            int ihl = (packet[0] & 0x0F) * 4;
            if (ihl < 20 || ihl > 60) return false;
            if (packet.length < ihl) return false;

            // Check total length field matches actual packet length
            int totalLen = ((packet[2] & 0xFF) << 8) | (packet[3] & 0xFF);
            if (totalLen != packet.length) {
                Log.w(TAG, "IPv4 packet length mismatch: header says " + totalLen + " but actual is " + packet.length);
                return false;
            }

            // Validate protocol field (common values)
            int protocol = packet[9] & 0xFF;
            if (protocol != 6 && protocol != 17 && protocol != 1) { // TCP, UDP, ICMP
                Log.w(TAG, "IPv4 unknown protocol: " + protocol);
            }

        } else if (version == 6) {
            // IPv6 validation
            if (packet.length < 40) return false;

            // Check payload length field
            int payloadLen = ((packet[4] & 0xFF) << 8) | (packet[5] & 0xFF);
            if (40 + payloadLen != packet.length) {
                Log.w(TAG, "IPv6 packet length mismatch: header says " + (40 + payloadLen) + " but actual is " + packet.length);
                return false;
            }

        } else {
            Log.w(TAG, "Unknown IP version: " + version);
            return false;
        }

        // Additional sanity check: reject unreasonably large packets
        if (packet.length > 65535) {
            Log.w(TAG, "Packet too large: " + packet.length);
            return false;
        }

        return true;
    }
}
