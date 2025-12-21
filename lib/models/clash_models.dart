class TrafficStats {
  final int upload;
  final int download;
  final int total;

  TrafficStats({this.upload = 0, this.download = 0, this.total = 0});

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class ProxyNode {
  final String name;
  final String type;
  int delay;
  bool isActive;
  final String? host;
  final int? port;
  final String? protocol; // TCP or UDP
  DateTime? lastTest;
  final int originalIndex; // Original index from profile

  // Authentication and encryption
  final String? password;
  final String? cipher; // For Shadowsocks
  final String? sni; // For Trojan (Server Name Indication)
  final bool? udp; // UDP support
  final bool? skipCertVerify; // For Trojan

  // Shadowsocks plugin
  final String? plugin;
  final Map<String, dynamic>? pluginOpts;

  ProxyNode({
    required this.name,
    required this.type,
    this.delay = 0,
    this.isActive = false,
    this.host,
    this.port,
    this.protocol,
    this.lastTest,
    this.originalIndex = -1,
    this.password,
    this.cipher,
    this.sni,
    this.udp,
    this.skipCertVerify,
    this.plugin,
    this.pluginOpts,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'delay': delay,
      'isActive': isActive,
      'host': host,
      'port': port,
      'protocol': protocol,
      'lastTest': lastTest?.toIso8601String(),
      'originalIndex': originalIndex,
      'password': password,
      'cipher': cipher,
      'sni': sni,
      'udp': udp,
      'skipCertVerify': skipCertVerify,
      'plugin': plugin,
      'pluginOpts': pluginOpts,
    };
  }

  factory ProxyNode.fromJson(Map<String, dynamic> json) {
    return ProxyNode(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      delay: (json['delay'] is int) ? json['delay'] as int : int.tryParse(json['delay']?.toString() ?? '') ?? 0,
      isActive: json['isActive'] as bool? ?? false,
      host: json['host'] as String?,
      port: json['port'] is int ? json['port'] as int : int.tryParse(json['port']?.toString() ?? ''),
      protocol: json['protocol'] as String?,
      lastTest: DateTime.tryParse(json['lastTest'] as String? ?? DateTime.now().toIso8601String()),
      originalIndex: json['originalIndex'] is int
          ? json['originalIndex'] as int
          : int.tryParse(json['originalIndex']?.toString() ?? '') ?? -1,
      password: json['password'] as String?,
      cipher: json['cipher'] as String?,
      sni: json['sni'] as String?,
      udp: json['udp'] as bool?,
      skipCertVerify: json['skipCertVerify'] as bool?,
      plugin: json['plugin'] as String?,
      pluginOpts: json['pluginOpts'] as Map<String, dynamic>?,
    );
  }
}

class ProxyGroup {
  final String name;
  final String type;
  final List<String> proxies;
  String? selected;

  ProxyGroup({required this.name, required this.type, required this.proxies, this.selected});

  Map<String, dynamic> toJson() {
    return {'name': name, 'type': type, 'proxies': proxies, 'selected': selected};
  }

  factory ProxyGroup.fromJson(Map<String, dynamic> json) {
    final List<String> list = [];
    if (json['proxies'] is List) {
      for (final item in json['proxies']) {
        list.add(item?.toString() ?? '');
      }
    }
    return ProxyGroup(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'select',
      proxies: list,
      selected: json['selected'] as String?,
    );
  }
}

class Profile {
  final String name;
  final String url;
  final DateTime lastUpdate;
  final bool isActive;

  Profile({required this.name, required this.url, required this.lastUpdate, this.isActive = false});

  Map<String, dynamic> toJson() {
    return {'name': name, 'url': url, 'lastUpdate': lastUpdate.toIso8601String(), 'isActive': isActive};
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      lastUpdate: DateTime.tryParse(json['lastUpdate'] as String? ?? '') ?? DateTime.now(),
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  Profile copyWith({String? name, String? url, DateTime? lastUpdate, bool? isActive}) {
    return Profile(
      name: name ?? this.name,
      url: url ?? this.url,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isActive: isActive ?? this.isActive,
    );
  }
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

  Rule({required this.type, required this.payload, required this.proxy});
}

class LogEntry {
  final String level;
  final String message;
  final DateTime time;

  LogEntry({required this.level, required this.message, required this.time});
}
