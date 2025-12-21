# Clash - AI Coding Agent Instructions

## Project Overview

This is a **production-ready Flutter proxy tool** implementing actual proxy protocols (Trojan, Shadowsocks, SOCKS5) with a complete 8-page UI. Unlike typical Flutter demos, this includes working cryptographic implementations and real network tunneling.

**Key Architecture**: Flutter 3.35.4 + Dart 3.9.2 multi-platform app (Android, iOS, Linux, macOS, Windows, Web) with Provider state management, custom protocol implementations, and platform-specific native integrations.

## Critical Architectural Patterns

### State Management: ClashState (Provider Pattern)
- **Single source of truth**: `lib/services/clash_state.dart` extends `ChangeNotifier` and manages ALL app state
- **Persistent storage**: Uses `SharedPreferences` with versioned keys (`clash_profiles_v1`, `clash_proxies_v1`, etc.)
- **Key convention**: All storage keys follow pattern `clash_<feature>_v1` to enable future migrations
- **Initialization flow**:
  1. Constructor sets up `ProxyService` and ensures default data exists
  2. `init()` loads from storage and calls `_autoConnectLastSelectedNode()`
  3. Always call `notifyListeners()` after state mutations

Example state mutation pattern:
```dart
void addRule(Rule rule) {
  _rules.add(rule);
  _saveRules();  // Persist immediately (CRITICAL: must await in async contexts)
  notifyListeners();  // Trigger UI rebuild
}
```

**CRITICAL STATE MANAGEMENT PATTERNS**:
- Always call `await _saveProxies()` after parsing YAML profiles to persist proxies to SharedPreferences
- When state changes are triggered by UI callbacks (e.g., PopupMenuButton.onSelected), defer with `Future.microtask()` to avoid "setState during build" errors
- Example fix for profile deletion:
  ```dart
  onSelected: (action) {
    if (action == 'delete') {
      Future.microtask(() => state.removeProfile(profile));
    }
  }
  ```

### Protocol Implementations (Critical for Proxy Features)

**Trojan Protocol** (`lib/protocols/trojan_protocol.dart`):
- Uses SHA-224 password hashing (NOT SHA-256) per Trojan spec
- TLS connection with SNI support (`node.sni` or `node.host`)
- Request format: `password_hash + CRLF + command + address_type + address + port + CRLF`
- Must handle IPv4/IPv6/domain address types (0x01/0x04/0x03)
- Returns `TrojanConnection` with bidirectional socket for tunneling

**Shadowsocks Protocol** (`lib/protocols/shadowsocks_protocol.dart`):
- AEAD ciphers only: `aes-128-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`
- Salt generation: random 32 bytes for AES-256-GCM, 32 for ChaCha20
- Key derivation: HKDF-SHA1 with info bytes `[115, 115, 45, 115, 117, 98, 107, 101, 121]` ("ss-subkey")
- Payload format: `[target_addr_type][target_addr][target_port][payload][16-byte tag]`

**SOCKS5 Handler** (`lib/protocols/socks5_handler.dart`):
- Implements RFC 1928 server-side with no-auth (0x00) only
- Handles CONNECT (0x01) and UDP ASSOCIATE (0x03) commands
- Auto-detects address type (IPv4/IPv6/domain) in client requests
- Relays traffic through `ProxyService` to configured upstream proxy

### ProxyService Architecture (`lib/services/proxy_service.dart`)

**Connection Flow**:
1. `connect(ProxyNode)` → starts local SOCKS5 server on `_localPort` (default 1080)
2. SOCKS5 clients connect → `_handleClient()` parses requests
3. `_connectThroughProxy()` establishes upstream connection via Trojan/Shadowsocks
4. Bidirectional relay: `_relayTraffic()` pipes data between client ↔ proxy
5. Traffic callbacks trigger `_onTrafficUpdate` → updates `ClashState.trafficStats`

**Critical**: Each protocol returns a connection object with a `socket` field. Always relay both directions simultaneously using `Future.wait([clientToProxy, proxyToClient])`.

### Platform-Specific: System Proxy Integration

**Android VPN Service (FULLY IMPLEMENTED)** (`ClashVpnService.java` + `SystemProxyService._setAndroidVPN`):
- **In-Process TUN Processor**: No external native tun2socks. VPN service runs a Java-based TUN device packet processor (1893 lines).
- **VPN Architecture**:
  1. `ClashVpnService` creates TUN interface via Android VpnService API with default routes (0.0.0.0/0, ::/0)
  2. App exclusion via `addDisallowedApplication(getPackageName())` prevents routing loops
  3. In-process `tunProcessorThread` reads IP packets from TUN device
  4. Packet inspection detects HTTP/TLS ClientHello for protocol identification
  5. TCP payloads relayed to local SOCKS5 server (127.0.0.1:1080)
  6. Server connects upstream via Trojan/Shadowsocks protocol
  7. UDP flows handled via protected DatagramSocket pool for bidirectional relay
- **Key Files**:
  - `android/app/src/main/java/com/github/worthies/clash/ClashVpnService.java` - Main VPN service
  - `android/app/src/main/java/com/github/worthies/clash/BufferPool.java` - Memory pooling for packet buffers
  - `android/app/src/main/AndroidManifest.xml` - Service registration + permissions
- **Traffic Flow**: Device App → TUN → VPN Processor → SOCKS5 Server (1080) → Upstream Proxy
- **Protected Sockets**: Clash app connections must call `VpnService.protect()` to bypass VPN
- **VPN Events**: Handle `onVpnEvent` callbacks for `vpn_error`, `vpn_stopped`
- **Return Spec**: `setSystemProxy()` returns `{ok: bool, status: string, message: string}`

**Linux** (`SystemProxyService._setLinuxProxy`):
- Detects desktop environment: KDE (kwriteconfig5), GNOME (gsettings)
- Sets HTTP/HTTPS/SOCKS proxy via system commands
- Remember to call `clearSystemProxy()` on disconnect

**Windows/macOS**: Similar platform-specific implementations in `system_proxy.dart`

## Development Workflows

### Building and Running

**Quick start**:
```bash
flutter pub get
flutter run -d linux    # or android, windows, macos, ios
```

**Production build with Makefile** (preferred for releases):
```bash
make build platform=linux mode=release   # Builds to build/dist/
make package platform=linux              # Creates .deb package (Linux)
```

Makefile handles:
- Multi-platform builds (Android, Linux, Windows, macOS, iOS, Web)
- Dependency installation (`make install-prerequisites`)
- Packaging (`.deb` for Linux via `tools/package_deb.sh`)

### Testing

**Unit tests** (`test/widget_test.dart`):
```bash
flutter test
```

Tests cover:
- Model serialization (`TrafficStats.formatBytes`, `ProxyNode.toJson/fromJson`)
- State management operations (addProfile, clearLogs, etc.)
- Settings mutations (setProxyMode, setMixedPort)

**Manual testing checklist**:
1. Add Clash subscription URL in Profiles page → activate profile
2. Select proxy node in Proxies page
3. Run speed test in Test page
4. Enable system proxy in Settings → verify native integration
5. Check Connections page for active tunnels
6. Monitor Logs page for protocol errors

### Debugging Protocol Issues

**Enable verbose logging**: Look for commented-out debug statements in protocol files:
```dart
// Debug: log outgoing request bytes (hex preview)
try {
  print('Trojan request: ${request.sublist(0, min(64, request.length))}');
} catch (_) {}
```

Uncomment these to diagnose handshake failures, encryption issues, or address parsing bugs.

**Common pitfalls**:
- Trojan: Wrong password hash (must be SHA-224, lowercase hex)
- Shadowsocks: Salt size mismatch (32 bytes for both AES-256-GCM and ChaCha20)
- SOCKS5: Not sending 0x00 in auth method selection response

## Code Conventions

### Model Patterns
- All models in `lib/models/clash_models.dart` have `toJson()` and `fromJson()` for persistence
- Use `copyWith()` method pattern for immutable updates (see `Profile.copyWith`)
- Normalize user input: trim whitespace, replace tabs/newlines with space (see `activateProfile`)

### Widget Structure
- Pages are stateless where possible (e.g., `HomePage`, `RulesPage`)
- Use `Consumer<ClashState>` for reactive UI updates
- Dialogs are separate `StatefulWidget` classes (e.g., `_RuleDialog` in `rules_page.dart`)

### Async Operations
- Always use `try-catch` for network operations (`http.get`, `Socket.connect`)
- Add log entries on errors: `addLog(LogEntry(level: 'ERROR', message: '...', time: DateTime.now()))`
- Use `Future.wait()` for concurrent operations, never parallel `await`

### File Organization
```
lib/
├── main.dart              # App entry, window setup, system tray
├── models/                # Pure data classes (no business logic)
├── pages/                 # Full-screen UI pages (8 pages)
├── protocols/             # Crypto + network protocol implementations
├── services/              # Business logic (ClashState, ProxyService, SystemProxyService)
└── widgets/               # Reusable components (TrafficMonitor, BandwidthChart, EmojiText)
```

**Never** put business logic in pages or widgets. Always delegate to `ClashState` or `ProxyService`.

## Key Files Reference

- **YAML parsing**: `ClashState.activateProfile()` parses Clash subscription format (proxies, proxy-groups, rules). **MUST** call `await _saveProxies()` after parsing to persist.
- **Speed testing**: `ClashState.runSpeedTest()` measures TCP latency to proxy server
- **Password management**: Trojan nodes extract `password` field from YAML; Shadowsocks uses `cipher` + `password`
- **Private rules**: `ClashState.setPrivateRules()` uses SHA-256 hashing for 4-digit PIN protection; `unlockPrivateRules()` verifies password
- **Auto-reconnect**: `_autoConnectLastSelectedNode()` restores last selected proxy on app launch
- **Profile deletion**: Use `Future.microtask()` wrapper to defer state changes triggered by UI callbacks
- **Rule management**: `addRule()`, `removeRuleAt()`, `updateRuleAt()`, `insertRuleAt()` all persist via `_saveRules()`

## Recent Bug Fixes (CRITICAL - ALWAYS REFERENCE)

**Profile Activation Missing Proxies** (FIXED):
- Root Cause: `activateProfile()` parsed YAML proxies but never called `_saveProxies()`
- Solution: Added `await _saveProxies();` after `_saveRules();` in `activateProfile()`
- **Lesson**: Always persist parsed data immediately to SharedPreferences

**Profile Deletion State Error** (FIXED):
- Root Cause: `PopupMenuButton.onSelected()` fires during widget build phase, causing "setState during build"
- Solution: Wrapped `state.removeProfile()` in `Future.microtask()` to defer state change
- **Pattern**: Any state mutations triggered by UI callbacks should use `Future.microtask()`

**Routing Rules Deprecated and Removed**:
- Removed `setRoutingRules()` from ClashVpnService.java, MainActivity.java, and system_proxy.dart
- Removed `_pushRoutingRulesToVpn()` method and all 6 call sites from clash_state.dart
- VPN now captures all traffic via default routes + app exclusion only

## Adding New Features

**New proxy protocol** (e.g., VMess):
1. Create `lib/protocols/vmess_protocol.dart` with `connect()` method returning connection object
2. Add handler in `ProxyService._connectThroughProxy()` switch statement
3. Update `ProxyNode` model to include VMess-specific fields (alterId, security, etc.)
4. Add YAML parsing logic in `ClashState.activateProfile()`

**New rule type**:
1. Add rule type constant (e.g., `PROCESS-NAME`) in UI rendering logic
2. Update native Android VpnService routing logic to handle new type
3. Persist via `_saveRules()` and sync via `_pushRoutingRulesToVpn()`

**New platform**:
1. Add platform check in `SystemProxyService.setSystemProxy()`
2. Implement platform-specific method (e.g., `_setIOSProxy()`)
3. Test native integration with MethodChannel if needed

## Documentation

- `ARCHITECTURE.md`: High-level UI/UX design
- `IMPLEMENTATION.md`: Component breakdown
- `QUICKSTART.md`: User-facing setup guide
- `TROJAN_AUTH.md`: Trojan protocol authentication details
- `SYSTEM_PROXY_*.md`: Platform proxy setup notes

Always update documentation when changing core protocols or state management patterns.
