class TrafficStats {
  final int upload;
  final int download;
  final int total;

  TrafficStats({
    this.upload = 0,
    this.download = 0,
    this.total = 0,
  });

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class ProxyNode {
  final String name;
  final String type;
  final int delay;
  final bool isActive;

  ProxyNode({
    required this.name,
    required this.type,
    this.delay = 0,
    this.isActive = false,
  });
}

class Profile {
  final String name;
  final String url;
  final DateTime lastUpdate;
  final bool isActive;

  Profile({
    required this.name,
    required this.url,
    required this.lastUpdate,
    this.isActive = false,
  });
}

class Connection {
  final String id;
  final String network;
  final String type;
  final String host;
  final String source;
  final String destination;
  final int upload;
  final int download;
  final DateTime startTime;

  Connection({
    required this.id,
    required this.network,
    required this.type,
    required this.host,
    required this.source,
    required this.destination,
    this.upload = 0,
    this.download = 0,
    required this.startTime,
  });
}

class Rule {
  final String type;
  final String payload;
  final String proxy;

  Rule({
    required this.type,
    required this.payload,
    required this.proxy,
  });
}

class LogEntry {
  final String level;
  final String message;
  final DateTime time;

  LogEntry({
    required this.level,
    required this.message,
    required this.time,
  });
}
