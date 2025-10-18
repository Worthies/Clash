# System Proxy Integration

This document describes how the system proxy feature works in Clash.

## Overview

The "System Proxy" toggle in the Settings page allows users to configure their operating system's network proxy settings to use the Clash proxy server. This enables all system applications to route their traffic through Clash automatically.

## Features

- **Automatic OS Proxy Configuration**: Configures system-wide proxy settings when enabled
- **Platform Support**: Works on Linux (GNOME/KDE), Windows, and macOS
- **Dynamic Updates**: Automatically updates system proxy when port or LAN settings change
- **Admin Privilege Handling**: Gracefully handles permission issues and logs warnings

## How It Works

### When Enabled

1. User toggles "System Proxy" ON in Settings
2. `ClashState.setSystemProxy(true)` is called
3. System proxy is configured to point to:
   - Address: `127.0.0.1` (localhost only) or `0.0.0.0` (all interfaces) depending on "Allow LAN" setting
   - Port: The configured mixed port (default 1080)
4. Success/failure is logged to the application logs

### When Disabled

1. User toggles "System Proxy" OFF in Settings
2. `ClashState.setSystemProxy(false)` is called
3. System proxy settings are cleared/disabled
4. Applications revert to direct connections

### Dynamic Updates

The system proxy is automatically updated when:
- **Allow LAN** toggle changes: Updates the bind address (127.0.0.1 ↔ 0.0.0.0)
- **Mixed Port** changes: Updates the proxy port
- Changes only apply if System Proxy is already enabled

## Platform-Specific Implementations

### Linux

**GNOME (gsettings)**:
- Sets `org.gnome.system.proxy` settings
- Configures HTTP, HTTPS, and SOCKS proxies
- Sets mode to `manual` when enabling

**KDE (kwriteconfig5)**:
- Modifies `kioslaverc` configuration
- Sets ProxyType and proxy URLs
- Sends D-Bus signal to reload settings

### Windows

- Uses Windows Registry (`HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`)
- Sets `ProxyEnable` and `ProxyServer` keys
- Refreshes with `netsh winhttp import proxy source=ie`

### macOS

- Uses `networksetup` command-line tool
- Configures all network services (Wi-Fi, Ethernet, etc.)
- Sets web proxy, secure web proxy, and SOCKS proxy

## Usage

### For End Users

1. Start Clash and configure a proxy connection
2. Go to Settings page
3. Toggle "System Proxy" ON
4. Your system will now route traffic through Clash
5. Toggle OFF to disable system proxy

**Note**: On Linux and macOS, you may need to run Clash with appropriate permissions (sudo) for system proxy configuration to work.

### For Developers

The system proxy functionality is implemented in:
- `lib/services/system_proxy.dart`: Platform-specific proxy configuration
- `lib/services/clash_state.dart`: State management and orchestration
- `lib/pages/settings_page.dart`: UI toggle and feedback

To extend or modify:
1. Edit `SystemProxyService` class for platform implementations
2. Update `ClashState.setSystemProxy()` for state management changes
3. Modify Settings page UI for user feedback improvements

## Permissions

### Linux
- GNOME: No special permissions required (user-level gsettings)
- KDE: No special permissions required (user-level config)
- Some distributions may require PolicyKit authentication

### Windows
- Registry modifications work at user level (HKCU)
- No administrator rights required for basic functionality
- `netsh` commands may require elevation in some cases

### macOS
- `networksetup` commands require administrator privileges
- Users will be prompted for password when enabling system proxy
- Alternative: Run Clash with sudo (not recommended for security)

## Troubleshooting

### System proxy not working

1. Check application logs for error messages
2. Verify Clash proxy server is running
3. Test proxy manually:
   ```bash
   # Linux/macOS
   export http_proxy=http://127.0.0.1:1080
   curl -I https://www.google.com
   
   # Windows PowerShell
   $env:http_proxy="http://127.0.0.1:1080"
   Invoke-WebRequest https://www.google.com
   ```

### Permission errors

- **Linux**: Some desktop environments may require PolicyKit authentication
- **Windows**: Run as administrator if needed
- **macOS**: Enter your password when prompted by `networksetup`

### Changes not applying

1. Disable and re-enable system proxy
2. Restart your browser or application
3. Check that the correct port is configured
4. Verify "Allow LAN" setting matches your needs

## Implementation Details

### Code Structure

```dart
// System proxy service (platform-specific)
class SystemProxyService {
  static Future<bool> setSystemProxy(String address, int port);
  static Future<bool> clearSystemProxy();
  
  // Platform implementations
  static Future<bool> _setLinuxProxy(...);
  static Future<bool> _setWindowsProxy(...);
  static Future<bool> _setMacOSProxy(...);
}

// State management
class ClashState {
  void setSystemProxy(bool value) async {
    if (value) {
      await SystemProxyService.setSystemProxy(address, port);
    } else {
      await SystemProxyService.clearSystemProxy();
    }
  }
}
```

### Error Handling

- All platform-specific operations are wrapped in try-catch
- Failures are logged but don't crash the application
- Users receive feedback via application logs
- UI shows warning about potential privilege requirements

## Future Enhancements

Potential improvements for future versions:

1. **PAC File Support**: Generate and use Proxy Auto-Configuration files
2. **Bypass List**: Configure domains that should bypass the proxy
3. **Auto-disable on Exit**: Automatically clear system proxy when Clash closes
4. **Privilege Detection**: Detect and warn about missing permissions before attempting changes
5. **Per-Application Proxy**: Support for application-specific proxy settings (where available)
