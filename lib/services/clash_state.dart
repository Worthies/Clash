import 'package:flutter/foundation.dart';
import '../models/clash_models.dart';

class ClashState extends ChangeNotifier {
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

  // Proxies
  final List<ProxyNode> _proxies = [
    ProxyNode(name: 'DIRECT', type: 'Direct', isActive: true),
    ProxyNode(name: 'HK-01', type: 'Shadowsocks', delay: 123),
    ProxyNode(name: 'US-02', type: 'VMess', delay: 256),
    ProxyNode(name: 'JP-03', type: 'Trojan', delay: 89),
  ];
  List<ProxyNode> get proxies => _proxies;

  // Connections
  final List<Connection> _connections = [];
  List<Connection> get connections => _connections;

  // Rules
  final List<Rule> _rules = [
    Rule(type: 'DOMAIN-SUFFIX', payload: 'google.com', proxy: 'DIRECT'),
    Rule(type: 'DOMAIN-KEYWORD', payload: 'github', proxy: 'Proxy'),
    Rule(type: 'IP-CIDR', payload: '192.168.0.0/16', proxy: 'DIRECT'),
    Rule(type: 'GEOIP', payload: 'CN', proxy: 'DIRECT'),
  ];
  List<Rule> get rules => _rules;

  // Logs
  final List<LogEntry> _logs = [];
  List<LogEntry> get logs => _logs;

  // Settings
  bool _systemProxy = false;
  bool _allowLan = false;
  int _mixedPort = 7890;
  
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

  void updateTraffic(int upload, int download) {
    _trafficStats = TrafficStats(
      upload: upload,
      download: download,
      total: upload + download,
    );
    notifyListeners();
  }

  void addProfile(Profile profile) {
    _profiles.add(profile);
    notifyListeners();
  }

  void removeProfile(Profile profile) {
    _profiles.remove(profile);
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
    _connections.add(Connection(
      id: '1',
      network: 'TCP',
      type: 'HTTP',
      host: 'api.example.com',
      source: '192.168.1.100:54321',
      destination: '203.0.113.10:443',
      upload: 1024,
      download: 2048,
      startTime: DateTime.now(),
    ));
    
    // Add some sample logs
    _logs.add(LogEntry(
      level: 'INFO',
      message: 'Clash started successfully',
      time: DateTime.now(),
    ));
    
    notifyListeners();
  }
}
