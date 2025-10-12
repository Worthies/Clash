# Quick Start Guide

## Installation

1. **Install Flutter**
   - Download Flutter SDK from https://flutter.dev/docs/get-started/install
   - Add Flutter to your PATH
   - Run `flutter doctor` to verify installation

2. **Clone the repository**
   ```bash
   git clone https://github.com/Worthies/Clash.git
   cd Clash
   ```

3. **Install dependencies**
   ```bash
   flutter pub get
   ```

4. **Run the app**
   
   For desktop (if supported):
   ```bash
   flutter run -d linux    # For Linux
   flutter run -d windows  # For Windows
   flutter run -d macos    # For macOS
   ```
   
   For mobile:
   ```bash
   flutter run -d android  # For Android
   flutter run -d ios      # For iOS
   ```
   
   For web:
   ```bash
   flutter run -d chrome   # For web browser
   ```

## Usage Guide

### Home Page
The Home page is your dashboard. It shows:
- Current traffic usage (upload/download/total)
- Active profile and proxy node
- Proxy mode (Rule/Global/Direct)
- Network settings and IP information

### Managing Proxies

1. **Go to Proxies page**
2. **Select a proxy node** by tapping on it
3. **Change proxy mode** using the segmented button at the top
   - **Rule**: Routes traffic based on rules
   - **Global**: All traffic goes through proxy
   - **Direct**: Direct connection without proxy

### Managing Profiles

1. **Go to Profiles page**
2. **Click the "Add Profile" button**
3. **Enter profile details**:
   - Profile Name: A friendly name for the profile
   - Subscription URL: The subscription link
4. **Click "Add"** to save

To remove a profile, click the trash icon.

### Monitoring Connections

1. **Go to Connections page**
2. **View active connections** in real-time
3. **Click on a connection** to see details:
   - Source and destination addresses
   - Upload and download traffic
   - Connection type and protocol
4. **Click "Clear"** to remove all connections

### Viewing Rules

1. **Go to Rules page**
2. **Browse routing rules**
   - Different colors indicate different rule types
   - Each rule shows which proxy it uses

### Viewing Logs

1. **Go to Logs page**
2. **Monitor application logs**
   - Color-coded by level (INFO, WARNING, ERROR, DEBUG)
   - Timestamps for each entry
3. **Click "Clear"** to remove all logs

### Testing Proxies

1. **Go to Test page**
2. **Click "Start Test"**
3. **Wait for results**
   - Green: Fast (< 100ms)
   - Orange: Moderate (100-200ms)
   - Red: Slow (> 200ms)

### Configuring Settings

1. **Go to Settings page**
2. **Configure options**:
   - **System Proxy**: Enable/disable system proxy
   - **Allow LAN**: Allow LAN connections
   - **Mixed Port**: Set the port number (default: 7890)

## Development

### Running Tests

```bash
flutter test
```

### Building for Production

For Android:
```bash
flutter build apk --release
```

For iOS:
```bash
flutter build ios --release
```

For Web:
```bash
flutter build web --release
```

For Desktop:
```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

## Troubleshooting

### Issue: Flutter not found
**Solution**: Make sure Flutter is installed and added to your PATH

### Issue: Dependencies not resolving
**Solution**: Run `flutter pub get` or `flutter clean && flutter pub get`

### Issue: Build errors
**Solution**: Run `flutter clean` and rebuild

## Features Coming Soon

- Real Clash core integration
- Subscription auto-update
- System tray support
- Advanced rule editing
- Profile switching shortcuts
- Traffic charts and graphs
- Connection filtering
- Export/import configurations

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
