# Clash Application Architecture

## Project Structure

```
Clash/
├── lib/
│   ├── main.dart                 # App entry point & navigation
│   ├── models/
│   │   └── clash_models.dart     # Data models
│   ├── pages/
│   │   ├── home_page.dart        # Home dashboard
│   │   ├── proxies_page.dart     # Proxy management
│   │   ├── profiles_page.dart    # Profile management
│   │   ├── connections_page.dart # Active connections
│   │   ├── rules_page.dart       # Routing rules
│   │   ├── logs_page.dart        # Application logs
│   │   ├── test_page.dart        # Speed testing
│   │   └── settings_page.dart    # App settings
│   ├── services/
│   │   └── clash_state.dart      # State management
│   └── widgets/
│       └── traffic_monitor.dart  # Traffic monitor widget
├── test/
│   └── widget_test.dart          # Unit tests
└── web/                          # Web platform support
```

## Features Implemented

### 1. Home Page
- **Current Profile Display**: Shows active profile name
- **Selected Node**: Displays currently selected proxy node
- **Proxy Mode**: Shows current mode (Rule/Global/Direct)
- **Network Settings**: Mixed port and LAN settings
- **Traffic Statistics**: Upload/Download/Total traffic with visual monitor
- **IP Information**: Current IP address and country
- **System Information**: System proxy status and connection count

### 2. Proxies Page
- **Proxy List**: Display all available proxy nodes
- **Node Selection**: Click to select a proxy node
- **Latency Display**: Shows delay in milliseconds with color coding
- **Mode Switching**: Toggle between Rule/Global/Direct modes
- **Node Types**: Support for Shadowsocks, VMess, Trojan, Direct

### 3. Profiles Page
- **Profile Management**: Add/remove subscription profiles
- **Profile Details**: Name, URL, last update time
- **Active Profile**: Visual indicator for active profile
- **Add Dialog**: Form to add new profiles

### 4. Connections Page
- **Active Connections**: Real-time connection monitoring
- **Connection Details**: Source, destination, protocol, traffic
- **Expandable Cards**: Click to see detailed connection info
- **Clear Function**: Button to clear all connections

### 5. Rules Page
- **Rule Display**: Shows all routing rules
- **Rule Types**: DOMAIN-SUFFIX, DOMAIN-KEYWORD, IP-CIDR, GEOIP
- **Color Coding**: Different colors for different rule types
- **Rule Destination**: Shows which proxy each rule uses

### 6. Logs Page
- **Log Levels**: INFO, WARNING, ERROR, DEBUG
- **Color Coding**: Different colors for different log levels
- **Timestamps**: Each log entry has a timestamp
- **Clear Function**: Button to clear all logs
- **Auto-limit**: Keeps only 1000 most recent logs

### 7. Test Page
- **Speed Testing**: Test latency of all proxy nodes
- **Batch Testing**: Test all proxies sequentially
- **Results Display**: Shows delay and success/failure status
- **Visual Feedback**: Color-coded results (green/orange/red)

### 8. Settings Page
- **System Proxy**: Toggle system proxy on/off
- **Allow LAN**: Enable/disable LAN connections
- **Mixed Port**: Configure port number
- **About Section**: Version, framework, license information

### Traffic Monitor Panel
- **Upload Traffic**: Shows total uploaded data
- **Download Traffic**: Shows total downloaded data
- **Total Traffic**: Shows combined traffic
- **Auto-formatting**: Displays in B, KB, MB, or GB as appropriate
- **Visual Icons**: Upload/download/total icons with color coding

## State Management

Uses Provider pattern with `ClashState` class to manage:
- Traffic statistics
- Proxy mode and selected node
- Profiles, proxies, connections
- Rules and logs
- Settings (system proxy, LAN, port)

## Navigation

Bottom navigation bar with 8 destinations:
1. Home
2. Proxies
3. Profiles
4. Connections
5. Rules
6. Logs
7. Test
8. Settings

## Testing

Comprehensive unit tests for:
- Traffic statistics formatting
- State management operations
- Profile/connection/log management
- Settings updates

## Platform Support

- **Android**: Ready for Android deployment
- **iOS**: Ready for iOS deployment
- **Web**: Includes web support with manifest
- **Desktop**: Can be extended for Windows/Linux/macOS

## Dependencies

- `flutter`: SDK
- `provider`: State management
- `http`: HTTP requests
- `shared_preferences`: Local storage
- `cupertino_icons`: iOS-style icons
- `flutter_lints`: Code linting

## Design

- **Material Design 3**: Modern, clean UI
- **Dark/Light Theme**: Automatic theme switching
- **Responsive Layout**: Adapts to different screen sizes
- **Color Scheme**: Blue-based with semantic colors
