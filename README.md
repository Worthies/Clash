# Clash

A cross-platform Clash proxy tool built on Flutter 🎉🎉🎉

## Overview

This is a Clash proxy management tool similar to clash-verge-rev but built with Flutter 3.35.4 (Dart 3.9.2) for cross-platform support.

## Features

The application includes 8 major pages:

1. **Home** - Dashboard showing:
   - Current profile information
   - Selected proxy node
   - Network settings
   - Proxy mode (Rule/Global/Direct)
   - Traffic statistics
   - IP information
   - System information

2. **Proxies** - Manage proxy nodes:
   - View all available proxy servers
   - Switch between different proxy nodes
   - See latency information
   - Change proxy mode

3. **Profiles** - Manage subscription profiles:
   - Add/remove subscription profiles
   - View profile details
   - Update subscriptions

4. **Connections** - Monitor active connections:
   - View real-time connections
   - See detailed connection information
   - Clear connection history

5. **Rules** - View proxy rules:
   - Display routing rules
   - See rule types (DOMAIN, IP-CIDR, GEOIP, etc.)
   - View rule destinations

6. **Logs** - Application logs:
   - View application logs
   - Filter by log level
   - Clear log history

7. **Test** - Test proxy speed:
   - Run speed tests on proxy nodes
   - View latency results
   - Batch testing support

8. **Settings** - Application configuration:
   - System proxy settings
   - Network configuration
   - Port settings
   - Application information

## Traffic Monitor

The application includes a persistent traffic monitor panel that displays:
- Upload traffic
- Download traffic
- Total traffic

## Getting Started

### Prerequisites

- Flutter 3.35.4 or higher
- Dart 3.9.2 or higher

### Installation

1. Clone the repository:
```bash
git clone https://github.com/Worthies/Clash.git
cd Clash
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the application:
```bash
flutter run
```

### Running Tests

```bash
flutter test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
