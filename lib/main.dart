import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'dart:io' show Platform;
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });
  }

  final state = ClashState();
  await state.init();
  state.simulateTraffic();

  // Capture Flutter framework errors and add them to app logs
  FlutterError.onError = (FlutterErrorDetails details) {
    try {
      state.addLog(
        LogEntry(
          level: 'ERROR',
          message: 'Flutter error: ${details.exceptionAsString()}\n${details.stack ?? ''}',
          time: DateTime.now(),
        ),
      );
    } catch (_) {}
    // Still print to console for debugging when running locally
    FlutterError.presentError(details);
  };

  // Capture uncaught async errors via Zone
  runZonedGuarded(
    () {
      runApp(ChangeNotifierProvider(create: (_) => state, child: const ClashApp()));
    },
    (error, stack) {
      try {
        state.addLog(LogEntry(level: 'ERROR', message: 'Uncaught error: $error\n$stack', time: DateTime.now()));
      } catch (_) {}
    },
  );

  // Platform-level errors (engine) - return true to indicate handled
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    try {
      state.addLog(LogEntry(level: 'ERROR', message: 'Platform error: $error\n$stack', time: DateTime.now()));
    } catch (_) {}
    return true;
  };
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

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initSystemTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    String path = Platform.isWindows ? 'icon.png' : 'icon.png';

    // Initialize system tray
    await _systemTray.initSystemTray(title: "Clash", iconPath: path);

    // Setup context menu
    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: 'Show Clash', onClicked: (menuItem) => _showWindow()),
      MenuSeparator(),
      MenuItemLabel(label: 'Exit', onClicked: (menuItem) => _exitApp()),
    ]);

    // Set context menu
    await _systemTray.setContextMenu(menu);

    // Handle system tray click
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        _showWindow();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideToTray() async {
    await windowManager.hide();
  }

  Future<void> _exitApp() async {
    await _systemTray.destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    // Hide to tray instead of closing
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      _hideToTray();
    }
  }

  final List<Widget> _pages = const [
    HomePage(),
    ProxiesPage(),
    ProfilesPage(),
    ConnectionsPage(),
    RulesPage(),
    LogsPage(),
    TestPage(),
    SettingsPage(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.router_outlined), selectedIcon: Icon(Icons.router), label: 'Proxies'),
    NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: 'Profiles'),
    NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: 'Connections'),
    NavigationDestination(icon: Icon(Icons.rule_outlined), selectedIcon: Icon(Icons.rule), label: 'Rules'),
    NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Logs'),
    NavigationDestination(icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'Test'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
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
                    width: 200,
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      children: [
                        // Navigation rail area
                        Expanded(
                          child: NavigationRail(
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: (index) {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                            labelType: NavigationRailLabelType.all,
                            destinations: _destinations
                                .map(
                                  (d) => NavigationRailDestination(
                                    indicatorColor: Colors.blue,
                                    icon: d.icon,
                                    selectedIcon: d.selectedIcon,
                                    label: Text(d.label),
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                        // Traffic panel (left-bottom)
                        Padding(
                          padding: const EdgeInsets.all(0.0),
                          child: Consumer<ClashState>(
                            builder: (context, state, _) {
                              final stats = state.trafficStats;
                              return SizedBox(
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.all(0.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('🔺${state.trafficStats.formatBytes(stats.upload)}'),
                                        Text('🔻${state.trafficStats.formatBytes(stats.download)}'),
                                        Text('⚖️${state.trafficStats.formatBytes(stats.total)}'),
                                      ],
                                    ),
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

    // Mobile/Tablet layout: keep bottom navigation
    return Scaffold(
      body: Column(
        children: [
          // no custom title bar on mobile
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: _destinations,
      ),
    );
  }

  Widget _buildCustomTitleBar(BuildContext context) {
    return Container(
      height: 40,
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
      width: 46,
      height: 40,
      child: InkWell(
        onTap: onPressed,
        hoverColor: isClose ? Colors.red.withValues(alpha: 0.9) : null,
        child: Icon(icon, size: 16, color: isClose ? Colors.red.shade400 : null),
      ),
    );
  }
}
