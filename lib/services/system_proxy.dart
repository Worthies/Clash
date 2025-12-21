import 'dart:io';
import 'dart:developer';
import 'package:flutter/services.dart';

/// Service to manage system-wide proxy settings
class SystemProxyService {
  static const platform = MethodChannel('com.github.worthies.clash/vpn');
  static Function(String event, String? message)? onVpnEvent;

  /// Initialize the method channel callback handler
  static void initialize() {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onVpnEvent') {
        try {
          final Map<dynamic, dynamic> data = call.arguments as Map<dynamic, dynamic>;
          final String event = data['event'] as String;
          final String? message = data['message'] as String?;
          if (onVpnEvent != null) {
            onVpnEvent!(event, message);
          }
        } catch (e) {
          log('Failed to handle VPN event: $e');
        }
      }
    });
  }

  /// Set system proxy to the specified address and port
  /// Returns true if successful, false otherwise
  /// Returns a structured result map with keys:
  ///  - ok: bool success flag
  ///  - status: string status ('started', 'permission_required', 'failed', ...)
  ///  - message: optional human-readable message
  static Future<Map<String, dynamic>> setSystemProxy(
    String address,
    int port, {
    Map<String, dynamic>? node,
    List<Map<String, dynamic>>? rules,
  }) async {
    try {
      if (Platform.isAndroid) {
        return await _setAndroidVPN(address, port, node: node, rules: rules);
      } else if (Platform.isLinux) {
        final ok = await _setLinuxProxy(address, port);
        return {'ok': ok, 'status': ok ? 'started' : 'failed', 'message': null};
      } else if (Platform.isWindows) {
        final ok = await _setWindowsProxy(address, port);
        return {'ok': ok, 'status': ok ? 'started' : 'failed', 'message': null};
      } else if (Platform.isMacOS) {
        final ok = await _setMacOSProxy(address, port);
        return {'ok': ok, 'status': ok ? 'started' : 'failed', 'message': null};
      }
      return {'ok': false, 'status': 'unsupported', 'message': 'Platform not supported'};
    } catch (e) {
      return {'ok': false, 'status': 'failed', 'message': e.toString()};
    }
  }

  /// Clear system proxy settings
  static Future<Map<String, dynamic>> clearSystemProxy() async {
    try {
      if (Platform.isAndroid) {
        return await _clearAndroidVPN();
      } else if (Platform.isLinux) {
        final ok = await _clearLinuxProxy();
        return {'ok': ok, 'status': ok ? 'stopped' : 'failed', 'message': null};
      } else if (Platform.isWindows) {
        final ok = await _clearWindowsProxy();
        return {'ok': ok, 'status': ok ? 'stopped' : 'failed', 'message': null};
      } else if (Platform.isMacOS) {
        final ok = await _clearMacOSProxy();
        return {'ok': ok, 'status': ok ? 'stopped' : 'failed', 'message': null};
      }
      return {'ok': false, 'status': 'unsupported', 'message': 'Platform not supported'};
    } catch (e) {
      return {'ok': false, 'status': 'failed', 'message': e.toString()};
    }
  }

  /// Android VPN implementation using platform channel
  /// NOTE: On Android, the VPN service creates a TUN interface that captures
  /// all device traffic. The proxy server (SOCKS5) running on port 1080
  /// receives the address and port but traffic routing is handled at the VPN level.
  /// This is different from desktop where proxy is set in system settings.
  ///
  /// To properly route traffic through the proxy:
  /// 1. User grants VPN permission
  /// 2. VPN service establishes TUN interface
  /// 3. All apps' traffic flows through the VPN
  /// 4. The proxy server (Clash) processes the traffic
  static Future<Map<String, dynamic>> _setAndroidVPN(
    String address,
    int port, {
    Map<String, dynamic>? node,
    List<Map<String, dynamic>>? rules,
  }) async {
    try {
      // Native Android method is implemented as 'startVpn' in MainActivity.
      // VPN captures all traffic via default route (0.0.0.0/0) and uses addDisallowedApplication
      // to exclude Clash app itself. No need to resolve DNS or add per-IP routes anymore.
      final Map<String, Object?> args = {'proxyAddress': address, 'proxyPort': port};
      if (node != null) args['proxyNode'] = node;
      // Pass rules to VPN service for logging/debugging, but no DNS resolution needed
      if (rules != null) {
        args['rules'] = rules;
      }
      final result = await platform.invokeMethod('startVpn', args);
      // Native may return a Map with {status, message, ok} or boolean/null for legacy.
      if (result == null) return {'ok': true, 'status': 'permission_required', 'message': null};
      if (result is bool) return {'ok': result, 'status': result ? 'started' : 'failed', 'message': null};
      if (result is Map) return Map<String, dynamic>.from(result);
      return {'ok': true, 'status': 'unknown', 'message': result.toString()};
    } on PlatformException catch (e) {
      return {'ok': false, 'status': 'failed', 'message': e.message ?? e.toString()};
    }
  }

  /// Clear Android VPN
  static Future<Map<String, dynamic>> _clearAndroidVPN() async {
    try {
      // Match Android method name 'stopVpn' and treat null as success.
      final result = await platform.invokeMethod('stopVpn');
      if (result == null) return {'ok': true, 'status': 'stopped', 'message': null};
      if (result is bool) return {'ok': result, 'status': result ? 'stopped' : 'failed', 'message': null};
      if (result is Map) return Map<String, dynamic>.from(result);
      return {'ok': true, 'status': 'unknown', 'message': result.toString()};
    } on PlatformException catch (e) {
      return {'ok': false, 'status': 'failed', 'message': e.message ?? e.toString()};
    }
  }

  /// Update the currently configured proxy node on the Android VPN service
  /// This will pass the proxyNode map (JSON-like) to the running service so
  /// it can adjust socket protection heuristics dynamically.
  static Future<Map<String, dynamic>> updateProxyNode(Map<String, dynamic> node) async {
    try {
      if (!Platform.isAndroid) return {'ok': false, 'status': 'unsupported', 'message': 'Platform not supported'};
      final result = await platform.invokeMethod('updateProxyNode', {'proxyNode': node});
      if (result == null) return {'ok': true, 'status': 'updated', 'message': null};
      if (result is bool) return {'ok': result, 'status': result ? 'updated' : 'failed', 'message': null};
      if (result is Map) return Map<String, dynamic>.from(result);
      return {'ok': true, 'status': 'unknown', 'message': result.toString()};
    } on PlatformException catch (e) {
      return {'ok': false, 'status': 'failed', 'message': e.message ?? e.toString()};
    }
  }

  // Linux implementation using gsettings (GNOME) and environment variables
  static Future<bool> _setLinuxProxy(String address, int port) async {
    final proxyUrl = 'http://$address:$port';

    // Try GNOME gsettings first
    try {
      final gsettingsCheck = await Process.run('which', ['gsettings']);
      if (gsettingsCheck.exitCode == 0) {
        // Set HTTP proxy
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.http', 'host', address]);
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.http', 'port', port.toString()]);

        // Set HTTPS proxy
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.https', 'host', address]);
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.https', 'port', port.toString()]);

        // Set SOCKS proxy
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.socks', 'host', address]);
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.socks', 'port', port.toString()]);

        // Enable manual proxy mode
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'manual']);
      }
    } catch (_) {}

    // Try KDE settings (try kwriteconfig6 first, then kwriteconfig5)
    try {
      String? kwriteconfig;

      // Check for kwriteconfig6 (KDE 6)
      var check = await Process.run('which', ['kwriteconfig6']);
      if (check.exitCode == 0) {
        kwriteconfig = 'kwriteconfig6';
      } else {
        // Check for kwriteconfig5 (KDE 5)
        check = await Process.run('which', ['kwriteconfig5']);
        if (check.exitCode == 0) {
          kwriteconfig = 'kwriteconfig5';
        }
      }

      if (kwriteconfig != null) {
        // Set proxy type to manual (1)
        await Process.run(kwriteconfig, ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'ProxyType', '1']);

        // Set HTTP proxy
        await Process.run(kwriteconfig, ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'httpProxy', proxyUrl]);

        // Set HTTPS proxy
        await Process.run(kwriteconfig, ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'httpsProxy', proxyUrl]);

        // Set FTP proxy
        await Process.run(kwriteconfig, ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', 'ftpProxy', proxyUrl]);

        // Set SOCKS proxy
        await Process.run(kwriteconfig, [
          '--file',
          'kioslaverc',
          '--group',
          'Proxy Settings',
          '--key',
          'socksProxy',
          'socks://$address:$port',
        ]);

        // Notify KDE to reload proxy settings
        await _notifyKDE();
      }
    } catch (_) {}

    return true;
  }

  static Future<bool> _clearLinuxProxy() async {
    // Try GNOME gsettings first
    try {
      final gsettingsCheck = await Process.run('which', ['gsettings']);
      if (gsettingsCheck.exitCode == 0) {
        // Disable proxy
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'none']);
      }
    } catch (_) {}

    // Try KDE settings
    try {
      String? kwriteconfig;

      // Check for kwriteconfig6 (KDE 6)
      var check = await Process.run('which', ['kwriteconfig6']);
      if (check.exitCode == 0) {
        kwriteconfig = 'kwriteconfig6';
      } else {
        // Check for kwriteconfig5 (KDE 5)
        check = await Process.run('which', ['kwriteconfig5']);
        if (check.exitCode == 0) {
          kwriteconfig = 'kwriteconfig5';
        }
      }

      if (kwriteconfig != null) {
        // Set proxy type to none (0)
        final result = await Process.run(kwriteconfig, [
          '--file',
          'kioslaverc',
          '--group',
          'Proxy Settings',
          '--key',
          'ProxyType',
          '0',
        ]);

        if (result.exitCode != 0) {
        } else {}

        // Notify KDE to reload proxy settings
        await _notifyKDE();
      } else {}
    } catch (_) {}

    return true;
  }

  /// Notify KDE to reload proxy configuration
  /// Uses multiple methods to ensure the System Settings UI updates
  static Future<void> _notifyKDE() async {
    // Method 1: Use dbus-send to emit signal
    try {
      await Process.run('dbus-send', [
        '--type=signal',
        '/KIO/Scheduler',
        'org.kde.KIO.Scheduler.reparseSlaveConfiguration',
        'string:',
      ]);
    } catch (_) {}

    // Method 2: Use qdbus method call (more reliable for UI refresh)
    try {
      final qdbusCheck = await Process.run('which', ['qdbus']);
      if (qdbusCheck.exitCode == 0) {
        // Call the method instead of sending signal
        await Process.run('qdbus', ['org.kde.klauncher5', '/KLauncher', 'org.kde.KLauncher.reparseConfiguration']);
      }
    } catch (_) {}

    // Method 3: Use qdbus6 for KDE 6
    try {
      final qdbus6Check = await Process.run('which', ['qdbus6']);
      if (qdbus6Check.exitCode == 0) {
        await Process.run('qdbus6', ['org.kde.klauncher6', '/KLauncher', 'org.kde.KLauncher.reparseConfiguration']);
      }
    } catch (_) {}

    // Method 4: Restart KDE proxy-related services
    try {
      final pkillCheck = await Process.run('which', ['pkill']);
      if (pkillCheck.exitCode == 0) {
        // Send SIGHUP to reload config without killing processes
        await Process.run('pkill', ['-HUP', 'kded5']);
        await Process.run('pkill', ['-HUP', 'kded6']);
      }
    } catch (_) {}

    // Method 5: Close System Settings to force refresh on next open
    // This is the most reliable way to ensure the UI shows updated settings
    try {
      final kquitappCheck = await Process.run('which', ['kquitapp5']);
      if (kquitappCheck.exitCode == 0) {
        // Close System Settings gracefully
        await Process.run('kquitapp5', ['systemsettings']);
      } else {
        // Fallback: use pkill if kquitapp5 not available
        await Process.run('pkill', ['systemsettings']);
      }
    } catch (_) {}
  }

  // Windows implementation using registry
  static Future<bool> _setWindowsProxy(String address, int port) async {
    final proxyServer = '$address:$port';

    try {
      // Enable proxy
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '1',
        '/f',
      ]);

      // Set proxy server
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings',
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        proxyServer,
        '/f',
      ]);

      // Refresh settings
      await Process.run('netsh', ['winhttp', 'import', 'proxy', 'source=ie']);

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _clearWindowsProxy() async {
    try {
      // Disable proxy
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '0',
        '/f',
      ]);

      // Clear proxy server
      await Process.run('reg', [
        'delete',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings',
        '/v',
        'ProxyServer',
        '/f',
      ]);

      // Refresh settings
      await Process.run('netsh', ['winhttp', 'reset', 'proxy']);

      return true;
    } catch (_) {
      return false;
    }
  }

  // macOS implementation using networksetup
  static Future<bool> _setMacOSProxy(String address, int port) async {
    try {
      // Get list of network services
      final result = await Process.run('networksetup', ['-listallnetworkservices']);
      if (result.exitCode != 0) return false;

      final services = result.stdout.toString().split('\n').where((line) => line.isNotEmpty && !line.startsWith('*')).toList();

      // Set proxy for each network service
      for (final service in services) {
        if (service.trim().isEmpty) continue;

        // Set web proxy (HTTP)
        await Process.run('networksetup', ['-setwebproxy', service.trim(), address, port.toString()]);

        // Set secure web proxy (HTTPS)
        await Process.run('networksetup', ['-setsecurewebproxy', service.trim(), address, port.toString()]);

        // Set SOCKS proxy
        await Process.run('networksetup', ['-setsocksfirewallproxy', service.trim(), address, port.toString()]);

        // Enable proxies
        await Process.run('networksetup', ['-setwebproxystate', service.trim(), 'on']);
        await Process.run('networksetup', ['-setsecurewebproxystate', service.trim(), 'on']);
        await Process.run('networksetup', ['-setsocksfirewallproxystate', service.trim(), 'on']);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _clearMacOSProxy() async {
    try {
      // Get list of network services
      final result = await Process.run('networksetup', ['-listallnetworkservices']);
      if (result.exitCode != 0) return false;

      final services = result.stdout.toString().split('\n').where((line) => line.isNotEmpty && !line.startsWith('*')).toList();

      // Disable proxy for each network service
      for (final service in services) {
        if (service.trim().isEmpty) continue;

        await Process.run('networksetup', ['-setwebproxystate', service.trim(), 'off']);
        await Process.run('networksetup', ['-setsecurewebproxystate', service.trim(), 'off']);
        await Process.run('networksetup', ['-setsocksfirewallproxystate', service.trim(), 'off']);
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
