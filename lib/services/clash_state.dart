import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart' as yaml;

import '../models/clash_models.dart';
import 'proxy_service.dart';

class ClashState extends ChangeNotifier {
  // Proxy service for handling connections
  late final ProxyService _proxyService;
  ProxyService get proxyService => _proxyService;

  // Traffic stats
  TrafficStats _trafficStats = TrafficStats();
  TrafficStats get trafficStats => _trafficStats;

  // Proxy mode
  String _proxyMode = 'Rule';
  String get proxyMode => _proxyMode;

  // Selected node
  ProxyNode? _selectedNode;
  ProxyNode? get selectedNode => _selectedNode;

  // IP info
  String _ipAddress = '0.0.0.0';
  String _country = 'Unknown';
  String get ipAddress => _ipAddress;
  String get country => _country;

  // Profiles
  final List<Profile> _profiles = [];
  List<Profile> get profiles => _profiles;

  static const _kProfilesKey = 'clash_profiles_v1';
  static const _kProxiesKey = 'clash_proxies_v1';
  static const _kGroupsKey = 'clash_groups_v1';
  static const _kLastSelectedNodeKey = 'clash_last_selected_node_v1';
  static const _kThemeModeKey = 'clash_theme_mode_v1';

  ClashState() {
    _proxyService = ProxyService(localPort: _mixedPort);
  }

  /// Initialize state from persistent storage
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_kProfilesKey);
    if (data != null && data.isNotEmpty) {
      try {
        final List<dynamic> list = json.decode(data) as List<dynamic>;
        _profiles.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _profiles.add(Profile.fromJson(item));
          } else if (item is Map) {
            _profiles.add(Profile.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      } catch (e) {
        // ignore and start fresh
      }
    }

    notifyListeners();
    // Load saved proxies if any
    final proxiesData = prefs.getString(_kProxiesKey);
    if (proxiesData != null && proxiesData.isNotEmpty) {
      try {
        final List<dynamic> list = json.decode(proxiesData) as List<dynamic>;
        _proxies.clear();
        for (final item in list) {
          ProxyNode? node;
          if (item is Map<String, dynamic>) {
            node = ProxyNode.fromJson(item);
          } else if (item is Map) {
            node = ProxyNode.fromJson(Map<String, dynamic>.from(item));
          }

          if (node != null) {
            _proxies.add(node);
          }
        }
        // sort loaded proxies by speed so UI shows fastest first
        // we'll reconcile proxies with groups after both are loaded
      } catch (_) {
        // ignore corrupt proxies data
      }
    }
    // Load saved groups if any
    final groupsData = prefs.getString(_kGroupsKey);
    if (groupsData != null && groupsData.isNotEmpty) {
      try {
        final List<dynamic> list = json.decode(groupsData) as List<dynamic>;
        _groups.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _groups.add(ProxyGroup.fromJson(item));
          } else if (item is Map) {
            _groups.add(ProxyGroup.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      } catch (_) {
        // ignore corrupt groups
      }
    }
    // Ensure _proxies only contains nodes referenced by groups; create placeholders when necessary
    _reconcileProxiesToGroups();
    _sortProxies(save: false);

    // Auto-connect to last selected proxy node if available
    await _autoConnectLastSelectedNode(prefs);
  }

  /// Automatically connect to the last selected proxy node on startup
  Future<void> _autoConnectLastSelectedNode(SharedPreferences prefs) async {
    try {
      final lastNodeName = prefs.getString(_kLastSelectedNodeKey);
      if (lastNodeName == null || lastNodeName.isEmpty) {
        return;
      }

      // Find the node by name
      final node = _proxies.firstWhere(
        (p) => p.name == lastNodeName,
        orElse: () => ProxyNode(name: '', type: ''),
      );

      if (node.name.isEmpty) {
        return;
      }

      if (node.type.toLowerCase().contains('trojan') && (node.password == null || node.password!.isEmpty)) {}

      // Connect to the proxy
      final success = await connectToProxy(node);

      if (success) {
      } else {}
    } catch (e) {
      // Don't rethrow - we don't want startup to fail because of auto-connect issues
    }
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _profiles.map((p) => p.toJson()).toList();
    await prefs.setString(_kProfilesKey, json.encode(list));
  }

  Future<void> _saveProxies() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _proxies.map((p) => p.toJson()).toList();
    await prefs.setString(_kProxiesKey, json.encode(list));
  }

  Future<void> _saveGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _groups.map((g) => g.toJson()).toList();
    await prefs.setString(_kGroupsKey, json.encode(list));
  }

  /// Sort proxies by measured delay (ascending). Tested nodes (delay > 0)
  /// appear before untested or errored nodes. If [save] is true, persist the order.
  /// Special nodes (DIRECT, REJECT, etc. without host/port) always stay at the front.
  void _sortProxies({bool save = true}) {
    // Helper to identify special proxy nodes (built-in policies without actual servers)
    bool isSpecialNode(ProxyNode node) {
      // Special nodes are those without host/port info (like DIRECT, REJECT, GLOBAL, etc.)
      return node.host == null || node.host!.isEmpty;
    }

    // Separate special nodes from regular proxies
    final specialNodes = _proxies.where(isSpecialNode).toList();
    final regularNodes = _proxies.where((p) => !isSpecialNode(p)).toList();

    // Sort only regular nodes by delay
    regularNodes.sort((a, b) {
      int norm(int d) {
        if (d > 0) return d; // measured
        if (d == -1) return 1 << 28; // error -> large
        return 1 << 29; // untested or zero -> larger
      }

      return norm(a.delay).compareTo(norm(b.delay));
    });

    // Combine: special nodes first, then sorted regular nodes
    _proxies.clear();
    _proxies.addAll(specialNodes);
    _proxies.addAll(regularNodes);

    // Also update group member order to match sorted proxies
    for (final group in _groups) {
      // Create a map of proxy name to its position in sorted list
      final positionMap = <String, int>{};
      for (int i = 0; i < _proxies.length; i++) {
        positionMap[_proxies[i].name] = i;
      }

      // Sort group members by their proxy position
      group.proxies.sort((a, b) {
        final aPos = positionMap[a] ?? 999999;
        final bPos = positionMap[b] ?? 999999;
        return aPos.compareTo(bPos);
      });
    }

    if (save) {
      _saveProxies();
      _saveGroups(); // Also save groups since member order changed
    }
    notifyListeners();
  }

  // Proxies
  final List<ProxyNode> _proxies = [];
  List<ProxyNode> get proxies => _proxies;

  // Currently testing nodes (by name)
  final Set<String> _testing = {};

  bool isTesting(ProxyNode node) => _testing.contains(node.name);

  // Connections
  final List<Connection> _connections = [];
  List<Connection> get connections => _connections;

  // Proxy groups
  final List<ProxyGroup> _groups = [];
  List<ProxyGroup> get groups => _groups;

  // Rules
  final List<Rule> _rules = [];
  List<Rule> get rules => _rules;

  // Logs
  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => _logs;

  // Settings
  bool _systemProxy = false;
  bool _allowLan = false;
  int _mixedPort = 1080;

  // Theme
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;

  /// Toggle between light and dark themes and persist the selection
  Future<void> toggleTheme() async {
    _themeMode = (_themeMode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, _themeMode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }

  bool get systemProxy => _systemProxy;
  bool get allowLan => _allowLan;
  int get mixedPort => _mixedPort;

  void setProxyMode(String mode) {
    _proxyMode = mode;
    notifyListeners();
  }

  void selectNode(ProxyNode node) {
    _selectedNode = node;
    notifyListeners();
  }

  /// Connect to the selected proxy node and start local proxy server
  /// If already connected to the same node, this will skip reconnection
  Future<bool> connectToProxy(ProxyNode node) async {
    try {
      // Check if already connected to this node
      if (_proxyService.isRunning && _proxyService.activeNode != null && _proxyService.activeNode!.name == node.name) {
        selectNode(node);
        notifyListeners();
        return true;
      }

      // Update selected node
      selectNode(node);

      // Connect through proxy service
      final success = await _proxyService.connect(node);

      if (success) {
        // Save the last selected node for auto-connect on startup
        await _saveLastSelectedNode(node.name);

        addLog(LogEntry(level: 'INFO', message: 'Connected to proxy: ${node.name} (${node.type})', time: DateTime.now()));
        addLog(LogEntry(level: 'INFO', message: 'Local proxy listening on 127.0.0.1:$_mixedPort', time: DateTime.now()));
      } else {
        addLog(LogEntry(level: 'ERROR', message: 'Failed to connect to proxy: ${node.name}', time: DateTime.now()));
      }

      notifyListeners();
      return success;
    } catch (e) {
      addLog(LogEntry(level: 'ERROR', message: 'Error connecting to proxy: $e', time: DateTime.now()));
      notifyListeners();
      return false;
    }
  }

  /// Save the last selected node name for auto-connect on startup
  Future<void> _saveLastSelectedNode(String nodeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSelectedNodeKey, nodeName);
  }

  /// Disconnect from current proxy
  Future<void> disconnectProxy() async {
    await _proxyService.disconnect();
    addLog(LogEntry(level: 'INFO', message: 'Disconnected from proxy', time: DateTime.now()));
    notifyListeners();
  }

  void updateTraffic(int upload, int download) {
    _trafficStats = TrafficStats(upload: upload, download: download, total: upload + download);
    notifyListeners();
  }

  void addProfile(Profile profile) {
    _profiles.add(profile);
    _saveProfiles();
    notifyListeners();
  }

  void removeProfile(Profile profile) {
    _profiles.remove(profile);
    _saveProfiles();
    notifyListeners();
  }

  void addConnection(Connection connection) {
    _connections.add(connection);
    notifyListeners();
  }

  void clearConnections() {
    _connections.clear();
    notifyListeners();
  }

  void addLog(LogEntry log) {
    _logs.insert(0, log);
    if (_logs.length > 1000) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void setSystemProxy(bool value) {
    _systemProxy = value;
    notifyListeners();
  }

  void setAllowLan(bool value) {
    _allowLan = value;
    notifyListeners();
  }

  void setMixedPort(int port) {
    _mixedPort = port;
    notifyListeners();
  }

  void simulateTraffic() {
    // Simulate traffic for demo
    _trafficStats = TrafficStats(
      upload: 1024 * 1024 * 100, // 100 MB
      download: 1024 * 1024 * 500, // 500 MB
      total: 1024 * 1024 * 600, // 600 MB
    );

    _ipAddress = '203.0.113.1';
    _country = 'United States';

    // Add some sample connections
    _connections.add(
      Connection(
        id: '1',
        network: 'TCP',
        type: 'HTTP',
        host: 'api.example.com',
        source: '192.168.1.100:54321',
        destination: '203.0.113.10:443',
        upload: 1024,
        download: 2048,
        startTime: DateTime.now(),
      ),
    );

    // Add some sample logs
    _logs.add(LogEntry(level: 'INFO', message: 'Clash started successfully', time: DateTime.now()));

    notifyListeners();
  }

  /// Activate a profile: fetch its subscription URL, parse YAML and populate proxies and rules.
  Future<void> activateProfile(Profile profile) async {
    try {
      final resp = await http.get(Uri.parse(profile.url));
      if (resp.statusCode == 200) {
        final body = resp.body;
        // If the subscription is base64 encoded (common for clash subs), try to decode
        String decoded = body;
        try {
          final maybeBytes = base64.decode(body);
          // if decoding yields readable text, use it
          final text = utf8.decode(maybeBytes);
          if (text.trim().isNotEmpty) decoded = text;
        } catch (_) {
          // not base64 or decoding failed, keep original
        }

        // Parse YAML (Clash config is YAML)
        final doc = yaml.loadYaml(decoded);

        // Reset proxies and rules
        _proxies.clear();
        _rules.clear();

        // Parse proxies
        if (doc is Map && doc['proxies'] is List) {
          for (final p in doc['proxies']) {
            if (p is Map) {
              final name = p['name']?.toString() ?? 'unknown';
              final type = p['type']?.toString() ?? 'Unknown';
              // Try to extract host/server and port if present
              String? host;
              int? port;
              String? protocol;
              if (p['server'] != null) host = p['server']?.toString();
              if (p['address'] != null) host = p['address']?.toString();
              if (p['host'] != null) host = p['host']?.toString();
              if (p['port'] != null) {
                try {
                  port = int.tryParse(p['port'].toString());
                } catch (_) {
                  port = null;
                }
              }
              // Parse protocol (network field or default to TCP)
              if (p['network'] != null) {
                protocol = p['network']?.toString().toUpperCase();
              } else if (p['protocol'] != null) {
                protocol = p['protocol']?.toString().toUpperCase();
              } else {
                // Default to TCP for most proxy types
                protocol = 'TCP';
              }

              // Parse authentication and encryption fields
              final password = p['password']?.toString();
              final cipher = p['cipher']?.toString();
              final sni = p['sni']?.toString();
              final udp = p['udp'] as bool?;
              final skipCertVerify = p['skip-cert-verify'] as bool?;
              final plugin = p['plugin']?.toString();
              final pluginOpts = p['plugin-opts'] is Map ? Map<String, dynamic>.from(p['plugin-opts'] as Map) : null;

              final newNode = ProxyNode(
                name: name,
                type: type,
                host: host,
                port: port,
                protocol: protocol,
                password: password,
                cipher: cipher,
                sni: sni,
                udp: udp,
                skipCertVerify: skipCertVerify,
                plugin: plugin,
                pluginOpts: pluginOpts,
              );

              // Debug: Log if this is a Trojan node
              if (type.toLowerCase().contains('trojan')) {}

              _proxies.add(newNode);
            }
          }
        }

        // Parse proxy-groups
        if (doc is Map && doc['proxy-groups'] is List) {
          for (final g in doc['proxy-groups']) {
            if (g is Map) {
              final name = g['name']?.toString() ?? 'group';
              final type = g['type']?.toString() ?? 'select';
              final proxiesList = <String>[];
              if (g['proxies'] is List) {
                for (final item in g['proxies']) {
                  proxiesList.add(item?.toString() ?? '');
                }
              }
              final selected = g['selected']?.toString();
              _groups.add(ProxyGroup(name: name, type: type, proxies: proxiesList, selected: selected));
            }
          }
        }

        // Parse rules
        if (doc is Map && doc['rules'] is List) {
          for (final r in doc['rules']) {
            if (r is List && r.length >= 2) {
              final type = r[0]?.toString() ?? '';
              final payload = r[1]?.toString() ?? '';
              final proxy = r.length >= 3 ? r[2]?.toString() ?? '' : '';
              _rules.add(Rule(type: type, payload: payload, proxy: proxy));
            } else if (r is String) {
              // e.g., DOMAIN-SUFFIX,google.com,DIRECT
              final parts = r.split(',');
              if (parts.length >= 2) {
                _rules.add(Rule(type: parts[0], payload: parts[1], proxy: parts.length >= 3 ? parts[2] : ''));
              }
            }
          }
        }

        // Mark active profile
        for (int i = 0; i < _profiles.length; i++) {
          final p = _profiles[i];
          _profiles[i] = p.copyWith(isActive: p.name == profile.name && p.url == profile.url);
        }

        await _saveProfiles();
        await _saveGroups();
        // Reconcile proxies to groups AFTER parsing both
        _reconcileProxiesToGroups();
        _sortProxies(save: true);
        notifyListeners();
      } else {
        addLog(LogEntry(level: 'ERROR', message: 'Failed to fetch profile: ${resp.statusCode}', time: DateTime.now()));
      }
    } catch (e) {
      addLog(LogEntry(level: 'ERROR', message: 'Error activating profile: $e', time: DateTime.now()));
    }
  }

  /// Run a single speed/latency test against the proxy node's host:port.
  /// Uses a simple TCP connect timing as a latency approximation.
  Future<void> runSpeedTest(ProxyNode node, {Duration timeout = const Duration(seconds: 3)}) async {
    if (node.host == null || node.port == null) {
      // cannot test without address
      addLog(LogEntry(level: 'WARN', message: 'No host/port for ${node.name}', time: DateTime.now()));
      return;
    }

    _testing.add(node.name);
    notifyListeners();

    final host = node.host!;
    final port = node.port!;

    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      node.delay = stopwatch.elapsedMilliseconds;
      node.lastTest = DateTime.now();
      socket.destroy();
    } on SocketException catch (e) {
      node.delay = -1;
      node.lastTest = DateTime.now();
      addLog(LogEntry(level: 'ERROR', message: 'Socket error testing ${node.name}: $e', time: DateTime.now()));
    } catch (e) {
      node.delay = -1;
      node.lastTest = DateTime.now();
      addLog(LogEntry(level: 'ERROR', message: 'Error testing ${node.name}: $e', time: DateTime.now()));
    } finally {
      _testing.remove(node.name);
      await _saveProxies();
      notifyListeners();
    }
  }

  /// Run speed tests for all proxies. Runs in batches to limit concurrency.
  Future<void> runSpeedTestAll({int concurrency = 8, Duration timeout = const Duration(seconds: 3)}) async {
    final List<ProxyNode> list = List.from(_proxies);
    final int total = list.length;
    int idx = 0;
    while (idx < total) {
      final end = (idx + concurrency) < total ? (idx + concurrency) : total;
      final batch = list.sublist(idx, end);
      await Future.wait(batch.map((node) => runSpeedTest(node, timeout: timeout)));
      idx = end;
    }
    // After batch testing, sort and save results
    _sortProxies(save: true);
  }

  /// Set selected proxy for a proxy group and activate that proxy
  Future<void> setGroupSelection(String groupName, String selectedProxy) async {
    for (final g in _groups) {
      if (g.name == groupName) {
        g.selected = selectedProxy;
        break;
      }
    }
    for (final p in _proxies) {
      p.isActive = (p.name == selectedProxy);
    }
    final found = _proxies.where((p) => p.name == selectedProxy).toList();
    final newSelectedNode = found.isNotEmpty ? found.first : (_proxies.isNotEmpty ? _proxies.first : null);

    // Connect to the selected proxy node only if it's different from the current one
    if (newSelectedNode != null && newSelectedNode.host != null) {
      // Check if we need to reconnect (different node or not currently running)
      final needsReconnect = _selectedNode == null || _selectedNode!.name != newSelectedNode.name || !_proxyService.isRunning;

      _selectedNode = newSelectedNode;

      if (needsReconnect) {
        await connectToProxy(_selectedNode!);
      } else {}
    } else {
      _selectedNode = newSelectedNode;
    }

    _saveGroups();
    notifyListeners();
  }

  /// Ensure _proxies only contains nodes that are referenced by proxy groups.
  /// If a group references a name that's not present in _proxies, create a placeholder ProxyNode.
  void _reconcileProxiesToGroups() {
    final referenced = <String>{};
    for (final g in _groups) {
      for (final name in g.proxies) {
        referenced.add(name);
      }
      if (g.selected != null) referenced.add(g.selected!);
    }

    // Remove proxies not referenced
    _proxies.removeWhere((p) => !referenced.contains(p.name));

    // Add placeholders for referenced names that are missing
    for (final name in referenced) {
      if (!_proxies.any((p) => p.name == name)) {
        _proxies.add(ProxyNode(name: name, type: 'Unknown', protocol: 'TCP'));
      }
    }
  }
}
