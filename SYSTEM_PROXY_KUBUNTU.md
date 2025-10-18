# System Proxy Configuration for Kubuntu/KDE Plasma

## Overview

This application can configure system-wide proxy settings for KDE Plasma (Kubuntu) environments.

## How It Works

### KDE Plasma Implementation

1. **Settings Storage**: Proxy settings are stored in `~/.config/kioslaverc` under the `[Proxy Settings]` group
2. **Configuration Tool**: Uses `kwriteconfig5` (KDE 5) or `kwriteconfig6` (KDE 6) to write settings
3. **Notification**: Sends D-Bus signals to notify KDE to reload proxy configuration

### Settings Applied

When "System Proxy" is enabled, the following settings are configured:

- `ProxyType`: Set to `1` (manual proxy)
- `httpProxy`: `http://ADDRESS:PORT`
- `httpsProxy`: `http://ADDRESS:PORT`
- `ftpProxy`: `http://ADDRESS:PORT`
- `socksProxy`: `socks://ADDRESS:PORT`

Where ADDRESS is either:
- `127.0.0.1` (localhost only) when "Allow LAN" is OFF
- `0.0.0.0` (all interfaces) when "Allow LAN" is ON

### D-Bus Notifications

Three methods are used to notify KDE to reload settings:

1. **dbus-send**: `dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:`
2. **qdbus**: `qdbus org.kde.KIO /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration ''`
3. **kded reload**: `pkill -HUP kded5` or `pkill -HUP kded6`

## Verification

### Check Configuration File

```bash
cat ~/.config/kioslaverc | grep -A 10 "\[Proxy Settings\]"
```

You should see:
```ini
[Proxy Settings]
ProxyType=1
httpProxy=http://127.0.0.1:1080
httpsProxy=http://127.0.0.1:1080
ftpProxy=http://127.0.0.1:1080
socksProxy=socks://127.0.0.1:1080
```

### Check System Settings

1. Open System Settings
2. Go to Network → Proxy
3. Verify that "Manual proxy configuration" is selected
4. Check that HTTP/HTTPS/FTP/SOCKS proxy addresses are set correctly

### Test with Applications

KDE applications (like Dolphin, Konqueror, etc.) should respect these settings immediately after the D-Bus signal is sent. Other applications may need to be restarted.

## Troubleshooting

### Proxy Settings Not Showing in System Settings

1. **Manually send D-Bus signal**:
   ```bash
   dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:
   ```

2. **Check if kded5 is running**:
   ```bash
   ps aux | grep kded5
   ```

3. **Restart kded5**:
   ```bash
   pkill -HUP kded5
   ```

### Applications Not Using Proxy

Some applications (like browsers) may use their own proxy settings instead of the system settings. Check the application's own proxy configuration.

### Debug Output

The application now prints debug messages when D-Bus commands fail. Check the console/terminal output for messages like:
- `dbus-send failed: [error message]`
- `qdbus failed: [error message]`
- `pkill error: [error message]`

## Manual Configuration

If automatic configuration doesn't work, you can manually configure:

1. **Using kwriteconfig5**:
   ```bash
   kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key ProxyType 1
   kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key httpProxy "http://127.0.0.1:1080"
   kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key httpsProxy "http://127.0.0.1:1080"
   dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:
   ```

2. **Using System Settings GUI**:
   - Open System Settings → Network → Proxy
   - Select "Manual proxy configuration"
   - Set HTTP Proxy: `127.0.0.1:1080`
   - Set HTTPS Proxy: `127.0.0.1:1080`
   - Set SOCKS Proxy: `127.0.0.1:1080`

## Known Limitations

- Changes may not apply to already-running applications
- Some applications ignore system proxy settings
- Requires the proxy server to be actually running
