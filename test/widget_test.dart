import 'package:flutter_test/flutter_test.dart';
import 'package:clash/models/clash_models.dart';
import 'package:clash/services/clash_state.dart';

void main() {
  group('TrafficStats', () {
    test('formatBytes should format bytes correctly', () {
      final stats = TrafficStats(upload: 1024, download: 2048, total: 3072);

      expect(stats.formatBytes(500), '500 B');
      expect(stats.formatBytes(1024), '1.00 KB');
      expect(stats.formatBytes(1024 * 1024), '1.00 MB');
      expect(stats.formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });
  });

  group('ClashState', () {
    test('should initialize with default values', () {
      final state = ClashState();

      expect(state.proxyMode, 'Rule');
      expect(state.proxies.isNotEmpty, true);
      expect(state.rules.isNotEmpty, true);
    });

    test('should change proxy mode', () {
      final state = ClashState();

      state.setProxyMode('Global');
      expect(state.proxyMode, 'Global');

      state.setProxyMode('Direct');
      expect(state.proxyMode, 'Direct');
    });

    test('should add and remove profiles', () {
      final state = ClashState();
      final profile = Profile(
        name: 'Test Profile',
        url: 'https://example.com',
        lastUpdate: DateTime.now(),
      );

      state.addProfile(profile);
      expect(state.profiles.length, 1);

      state.removeProfile(profile);
      expect(state.profiles.length, 0);
    });

    test('should add and clear connections', () {
      final state = ClashState();
      final connection = Connection(
        id: '1',
        network: 'TCP',
        type: 'HTTP',
        host: 'example.com',
        source: '192.168.1.1:1234',
        destination: '1.2.3.4:80',
        startTime: DateTime.now(),
      );

      state.addConnection(connection);
      expect(state.connections.length, 1);

      state.clearConnections();
      expect(state.connections.length, 0);
    });

    test('should add and clear logs', () {
      final state = ClashState();
      final log = LogEntry(
        level: 'INFO',
        message: 'Test log',
        time: DateTime.now(),
      );

      state.addLog(log);
      expect(state.logs.length, 1);

      state.clearLogs();
      expect(state.logs.length, 0);
    });

    test('should update settings', () {
      final state = ClashState();

      state.setSystemProxy(true);
      expect(state.systemProxy, true);

      state.setAllowLan(true);
      expect(state.allowLan, true);

      state.setMixedPort(8080);
      expect(state.mixedPort, 8080);
    });
  });
}
