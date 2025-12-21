import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'dart:io' show Platform, File, Directory, FileMode;
import 'dart:async';
import 'dart:ui';
import 'services/clash_state.dart';
import 'models/clash_models.dart';
import 'pages/home_page.dart';
import 'pages/proxies_page.dart';
import 'pages/profiles_page.dart';
import 'pages/connections_page.dart';
import 'pages/rules_page.dart';
import 'pages/logs_page.dart';
import 'pages/test_page.dart';
import 'pages/settings_page.dart';
import 'widgets/bandwidth_chart.dart';

void main() {
  // Keep a reference to state so zone and platform handlers can log to it
  ClashState? state;

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize window manager for desktop platforms
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.ensureInitialized();

        WindowOptions windowOptions = const WindowOptions(
          size: Size(1200, 800),
          minimumSize: Size(900, 600),
          center: true,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.hidden,
        );

        windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setPreventClose(true);

          // Set window icon for taskbar (Linux/KDE/GNOME window managers)
          // Prefer non-alpha / opaque variants of the tray icon to avoid
          // transparent/empty rectangles in some desktop setups (IBus/fcitx
          // interaction). Fall back to system pixmaps and bundled icon.
          if (Platform.isLinux) {
            final cwd = Directory.current.path;
            String exeDir = '';
            try {
              exeDir = File(Platform.resolvedExecutable).parent.path;
            } catch (_) {}

            // For Cinnamon: use a single, known-good icon with no alpha.
            // Keep a couple of fallbacks for installed/system locations.
            final iconCandidates = <String>[
              if (exeDir.isNotEmpty) '$exeDir/data/flutter_assets/assets/taskbar_icon_noalpha.png',
              '$cwd/assets/taskbar_icon_noalpha.png',
              '/usr/share/pixmaps/com.github.worthies.clash.png',
              '/usr/share/pixmaps/clash.png',
              '/opt/clash/data/flutter_assets/icon.png',
              '$cwd/icon.png',
            ];
            for (final iconPath in iconCandidates) {
              try {
                if (File(iconPath).existsSync()) {
                  await windowManager.setIcon(iconPath);
                  debugPrint('Set window icon from $iconPath');
                  break;
                }
              } catch (e) {
                debugPrint('Failed to set window icon from $iconPath: $e');
              }
            }
          }
        });
      }

      state = ClashState();
      await state!.init();
      // state!.simulateTraffic();

      // Capture Flutter framework errors and add them to app logs
      FlutterError.onError = (FlutterErrorDetails details) {
        try {
          state?.addLog(
            LogEntry(
              level: 'ERROR',
              message: 'Flutter error: ${details.exceptionAsString()}\n${details.stack ?? ''}',
              time: DateTime.now(),
            ),
          );
        } catch (_) {}
        FlutterError.presentError(details);
      };

      // Run app inside the same zone
      runApp(ChangeNotifierProvider(create: (_) => state!, child: const ClashApp()));

      // Platform-level errors (engine) - return true to indicate handled
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        try {
          state?.addLog(LogEntry(level: 'ERROR', message: 'Platform error: $error\n$stack', time: DateTime.now()));
        } catch (_) {}
        return true;
      };
    },
    (error, stack) {
      // Zone-level uncaught errors — prefer logging into state if available
      try {
        state?.addLog(LogEntry(level: 'ERROR', message: 'Uncaught error: $error\n$stack', time: DateTime.now()));
      } catch (_) {
        // Fallback to console if state is not available
        FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
      }
    },
  );
}

class ClashApp extends StatelessWidget {
  const ClashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClashState>(
      builder: (context, state, _) {
        return MaterialApp(
          title: 'Clash',
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: state.themeMode,
          home: const MainPage(),
        );
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WindowListener {
  int _selectedIndex = 0;
  final SystemTray _systemTray = SystemTray();
  bool _trayReady = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Only initialize system tray on desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _initSystemTray();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    // Resolve a best-effort absolute icon path so the system tray plugin
    // can find the icon when the app is launched from an installed location
    // (for example /opt/clash). Fall back to the bundled asset name.
    // For Cinnamon and other desktop environments, prefer smaller icons (24x24, 32x32)
    // with simpler color formats to avoid transparency rendering issues.
    String path = 'icon.png';
    if (!Platform.isWindows) {
      final exe = Platform.resolvedExecutable;
      String exeDir;
      try {
        exeDir = File(exe).parent.path;
      } catch (_) {
        exeDir = '';
      }

      // Build real candidates (avoid interpolation issues above)
      // Priority: exeDir/currentDir (prefers running bundle) > local assets > system icons > installed dir
      final realCandidates = <String>[];

      // If executable directory is known, prefer its bundled assets first
      if (exeDir.isNotEmpty) {
        // Prefer opaque variants first for better compatibility
        realCandidates.add('$exeDir/data/flutter_assets/assets/icon.png');
        realCandidates.add('$exeDir/../data/flutter_assets/assets/icon.png');
      }

      // Try current working directory next (for direct run from bundle dir)
      final currentDir = Directory.current.path;
      // Prefer opaque variants in current dir
      realCandidates.add('$currentDir/data/flutter_assets/assets/icon.png');
      realCandidates.add('$currentDir/assets/icon.png');

      // Prefer smaller icon sizes for system tray (better compatibility with Cinnamon)
      realCandidates.add('/usr/share/icons/hicolor/24x24/apps/com.github.worthies.clash.png');
      realCandidates.add('/usr/share/icons/hicolor/24x24/apps/clash.png');
      realCandidates.add('/usr/share/icons/hicolor/32x32/apps/com.github.worthies.clash.png');
      realCandidates.add('/usr/share/icons/hicolor/32x32/apps/clash.png');
      realCandidates.add('/usr/share/icons/hicolor/48x48/apps/com.github.worthies.clash.png');
      realCandidates.add('/usr/share/icons/hicolor/48x48/apps/clash.png');

      // Standard pixmaps location (common for tray icons)
      realCandidates.add('/usr/share/pixmaps/com.github.worthies.clash.png');
      realCandidates.add('/usr/share/pixmaps/clash.png');

      // Installed app directory /opt and fallback
      realCandidates.add('/opt/clash/data/flutter_assets/assets/icon.png');
      realCandidates.add('/opt/clash/data/flutter_assets/icon.png');

      for (final c in realCandidates) {
        try {
          if (File(c).existsSync()) {
            // Ensure we use absolute path for system_tray plugin
            path = File(c).absolute.path;
            debugPrint('System tray: Found icon at: $path');
            break;
          } else {
            debugPrint('System tray: Icon not found at: $c');
          }
        } catch (e) {
          debugPrint('System tray: Error checking path $c: $e');
        }
      }
    }

    // Initialize system tray and log the result
    bool initOk = false;
    try {
      // Debug: Log the icon path being used
      debugPrint('System tray: Attempting to initialize with icon path: $path');

      // For Cinnamon/GNOME, ensure SNI (Status Notifier Item) protocol is available
      // by setting XDG_CURRENT_DESKTOP if not already set
      if (Platform.isLinux && Platform.environment['XDG_CURRENT_DESKTOP'] == null) {
        final desktop = Platform.environment['DESKTOP_SESSION'] ?? '';
        if (desktop.contains('cinnamon') || desktop.contains('gnome') || desktop.contains('kde') || desktop.contains('plasma')) {
          debugPrint('System tray: Detected desktop environment: $desktop');
        }
      }

      initOk = await _systemTray.initSystemTray(title: 'Clash', iconPath: path, toolTip: 'Clash');
      _trayReady = initOk;

      if (initOk) {
        debugPrint('System tray: Successfully initialized');
      } else {
        debugPrint('System tray: Initialization returned false');
      }
    } catch (e, s) {
      debugPrint('System tray: Initialization exception: $e\n$s');
      // also report the Flutter error channel for visibility
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s as StackTrace?));
    }
    if (!initOk) {
      debugPrint('System tray: Failed to initialize - will continue without tray');
      FlutterError.reportError(const FlutterErrorDetails(exception: 'Init system tray failed'));
      return; // Don't continue with menu setup if tray failed to initialize
    }

    // Setup context menu only if tray initialized successfully
    final Menu menu = Menu();
    try {
      await menu.buildFrom([
        MenuItemLabel(label: 'Show Clash', onClicked: (menuItem) => _showWindow()),
        MenuSeparator(),
        MenuItemLabel(label: 'Exit', onClicked: (menuItem) => _exitApp()),
      ]);

      // Set context menu
      await _systemTray.setContextMenu(menu);
      debugPrint('System tray: Context menu set successfully');
    } catch (e, s) {
      debugPrint('System tray: Failed to set context menu: $e\n$s');
    }

    // Handle system tray click
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        _showWindow();
      } else if (eventName == kSystemTrayEventRightClick) {
        // Call popUpContextMenu asynchronously and guard errors — some
        // platforms may report a GDK device assertion when the native
        // call is made synchronously from the event thread. Running the
        // popup in a microtask and catching exceptions avoids crashing
        // the app and suppresses the GTK assertion.
        Future.microtask(() async {
          try {
            await _systemTray.popUpContextMenu();
          } catch (e, s) {
            debugPrint('system_tray: popUpContextMenu failed: $e\n$s');
            // also write a short log file for post-mortem
            try {
              final logDir = Directory('${Platform.environment['HOME']}/.cache/clash');
              if (!logDir.existsSync()) logDir.createSync(recursive: true);
              final f = File('${logDir.path}/clash_tray.log');
              f.writeAsStringSync('${DateTime.now().toIso8601String()} popUpContextMenu failed: $e\n', mode: FileMode.append);
            } catch (_) {}
          }
        });
      }
    });
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideToTray() async {
    await windowManager.hide();
    // If the tray wasn't ready when the app started, try to initialize it now
    // so a user click on the tray can restore the window.
    if (!_trayReady) {
      // attempt initialization with retries in background
      _ensureTrayReady(retries: 5, delay: const Duration(seconds: 1));
    }
  }

  // Try to initialize the tray several times with a delay. Runs in background
  // and sets _trayReady when successful.
  Future<void> _ensureTrayReady({int retries = 3, Duration delay = const Duration(seconds: 1)}) async {
    for (int i = 0; i < retries; i++) {
      try {
        if (_trayReady) return;
        await _initSystemTray();
        if (_trayReady) return;
      } catch (_) {}
      await Future.delayed(delay);
    }
  }

  Future<void> _exitApp() async {
    await _systemTray.destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    // Hide to tray instead of closing
    _hideToTray();
  }

  final List<Widget> _pages = const [
    HomePage(),
    SettingsPage(),
    ProxiesPage(),
    ProfilesPage(),
    ConnectionsPage(),
    RulesPage(),
    LogsPage(),
    TestPage(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
    NavigationDestination(icon: Icon(Icons.router_outlined), selectedIcon: Icon(Icons.router), label: 'Proxies'),
    NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: 'Profiles'),
    NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: 'Connections'),
    NavigationDestination(icon: Icon(Icons.rule_outlined), selectedIcon: Icon(Icons.rule), label: 'Rules'),
    NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Logs'),
    NavigationDestination(icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'Test'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    if (isDesktop) {
      // Desktop layout: left navigation rail with traffic panel at bottom-left
      return Scaffold(
        body: Column(
          children: [
            if (isDesktop) _buildCustomTitleBar(context),
            Expanded(
              child: Row(
                children: [
                  // Left rail + traffic panel stacked vertically
                  Container(
                    width: 220,
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      children: [
                        // Navigation rail area
                        Expanded(
                          child: NavigationRail(
                            extended: true,
                            // minExtendedWidth: 200,
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: (index) {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                            labelType: NavigationRailLabelType.none,
                            destinations: _destinations
                                .map(
                                  (d) => NavigationRailDestination(
                                    padding: const EdgeInsets.all(4),
                                    indicatorColor: Colors.blue,
                                    icon: d.icon,
                                    selectedIcon: d.selectedIcon,
                                    label: Text(d.label),
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                        // Traffic panel (left-bottom) with bandwidth chart
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Consumer<ClashState>(
                            builder: (context, state, _) {
                              return SizedBox(
                                height: 120,
                                child: Card(
                                  margin: const EdgeInsets.all(4),
                                  child: BandwidthChart(
                                    uploadBytes: state.trafficStats.upload,
                                    downloadBytes: state.trafficStats.download,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Main page area
                  Expanded(child: _pages[_selectedIndex]),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile/Tablet layout: keep bottom navigation with horizontal scroll
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // no custom title bar on mobile
            Expanded(child: _pages[_selectedIndex]),
          ],
        ),
      ),
      bottomNavigationBar: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: (_destinations.length * 90.0).clamp(MediaQuery.of(context).size.width, double.infinity),
          height: 80,
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: _destinations,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomTitleBar(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          // Draggable area
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                windowManager.startDragging();
              },
              onDoubleTap: () async {
                bool isMaximized = await windowManager.isMaximized();
                if (isMaximized) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Image.asset('icon.png', width: 20, height: 20),
                    const SizedBox(width: 8),
                    Text('Clash', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          // Window controls (theme toggle added left of minimize)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Consumer<ClashState>(
              builder: (context, state, _) {
                final isDark = state.themeMode == ThemeMode.dark;
                return IconButton(
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 16),
                  onPressed: () {
                    state.toggleTheme();
                  },
                  tooltip: 'Switch theme',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                );
              },
            ),
          ),
          _buildWindowButton(
            icon: Icons.minimize,
            onPressed: () {
              windowManager.minimize();
            },
          ),
          _buildWindowButton(
            icon: Icons.crop_square,
            onPressed: () async {
              bool isMaximized = await windowManager.isMaximized();
              if (isMaximized) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
          ),
          _buildWindowButton(
            icon: Icons.close,
            onPressed: () {
              _hideToTray();
            },
            isClose: true,
          ),
        ],
      ),
    );
  }

  Widget _buildWindowButton({required IconData icon, required VoidCallback onPressed, bool isClose = false}) {
    return SizedBox(
      width: 60,
      height: 60,
      child: InkWell(
        onTap: onPressed,
        hoverColor: isClose ? Colors.red.withValues(alpha: 0.9) : null,
        child: Icon(icon, size: 16, color: isClose ? Colors.red.shade400 : null),
      ),
    );
  }
}
