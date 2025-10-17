import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/clash_models.dart';
import '../protocols/trojan_protocol.dart';
import '../protocols/shadowsocks_protocol.dart';
import '../protocols/socks5_handler.dart';

/// Service to manage proxy connections and local proxy server
class ProxyService {
  ProxyNode? _activeNode;
  ServerSocket? _localServer;
  final int _localPort;
  bool _isRunning = false;

  // Traffic statistics (cumulative bytes)
  int _totalUpload = 0;
  int _totalDownload = 0;
  Timer? _trafficUpdateTimer;
  final void Function(int upload, int download)? _onTrafficUpdate;
  final void Function(Connection)? _onConnectionStart;
  final void Function(String)? _onConnectionEnd;

  ProxyService({
    int localPort = 1080,
    void Function(int, int)? onTrafficUpdate,
    void Function(Connection)? onConnectionStart,
    void Function(String)? onConnectionEnd,
  }) : _localPort = localPort,
       _onTrafficUpdate = onTrafficUpdate,
       _onConnectionStart = onConnectionStart,
       _onConnectionEnd = onConnectionEnd;

  bool get isRunning => _isRunning;
  ProxyNode? get activeNode => _activeNode;
  int get localPort => _localPort;

  /// Start local proxy server and connect through the specified proxy node
  Future<bool> connect(ProxyNode node) async {
    try {
      // Stop any existing connection
      await disconnect();

      _activeNode = node;

      // Start local SOCKS/HTTP proxy server
      await _startLocalServer();

      // Start traffic monitoring timer (update every 500ms)
      _startTrafficMonitoring();

      _isRunning = true;
      return true;
    } catch (e) {
      _isRunning = false;
      return false;
    }
  }

  /// Stop the proxy connection and local server
  Future<void> disconnect() async {
    if (_localServer != null) {
      await _localServer!.close();
      _localServer = null;
    }
    _trafficUpdateTimer?.cancel();
    _trafficUpdateTimer = null;
    _activeNode = null;
    _isRunning = false;
  }

  /// Start periodic traffic monitoring
  void _startTrafficMonitoring() {
    _trafficUpdateTimer?.cancel();
    _trafficUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) {
      _onTrafficUpdate?.call(_totalUpload, _totalDownload);
    });
  }

  /// Track uploaded bytes
  void _trackUpload(int bytes) {
    _totalUpload += bytes;
  }

  /// Track downloaded bytes
  void _trackDownload(int bytes) {
    _totalDownload += bytes;
  }

  /// Start local SOCKS5/HTTP proxy server
  Future<void> _startLocalServer() async {
    try {
      _localServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _localPort,
      );

      _localServer!.listen((Socket clientSocket) async {
        await _handleClientConnection(clientSocket);
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Handle incoming client connection (detect SOCKS5 or HTTP)
  Future<void> _handleClientConnection(Socket clientSocket) async {
    try {
      // Convert socket to broadcast stream so we can listen multiple times
      final broadcastStream = clientSocket.asBroadcastStream();
      final buffer = <int>[];
      late StreamSubscription subscription;

      // Listen for initial data to detect protocol
      subscription = broadcastStream.listen(
        (data) {
          buffer.addAll(data);
        },
        onError: (_) {},
        cancelOnError: false,
      );

      // Wait for some data to arrive
      await Future.delayed(const Duration(milliseconds: 100));

      if (buffer.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
      }

      if (buffer.isEmpty) {
        await subscription.cancel();
        clientSocket.destroy();
        return;
      }

      // Cancel the detection subscription
      await subscription.cancel();

      final firstByte = buffer[0];

      if (firstByte == 0x05) {
        // SOCKS5 protocol - pass buffered data
        await _handleSocks5WithBuffer(clientSocket, buffer, broadcastStream);
      } else if (firstByte >= 0x41 && firstByte <= 0x5A) {
        // Looks like HTTP (uppercase ASCII letters)
        await _handleHttpProtocol(clientSocket, buffer, broadcastStream);
      } else {
        clientSocket.destroy();
      }
    } catch (_) {
      clientSocket.destroy();
    }
  }

  /// Handle SOCKS5 protocol with buffered initial data
  Future<void> _handleSocks5WithBuffer(
    Socket clientSocket,
    List<int> initialBuffer,
    Stream<List<int>> socketStream,
  ) async {
    if (_activeNode == null) {
      clientSocket.destroy();
      return;
    }

    try {
      // Create handler with buffered data and stream
      final handler = Socks5HandlerWithStream(
        clientSocket,
        initialBuffer,
        socketStream,
      );
      final request = await handler.handleHandshake();

      if (request == null) {
        clientSocket.destroy();
        return;
      }

      // Send success reply
      handler.sendSuccessReply();

      // Get remaining data after handshake from the handler's buffer
      final remainingData = handler.getRemainingData();

      // Create stream controller to handle post-handshake data
      final dataController = StreamController<List<int>>();

      // Listen to new data from the broadcast stream and forward to controller
      socketStream.listen(
        (data) => dataController.add(data),
        onDone: () => dataController.close(),
        onError: (e) => dataController.addError(e),
      );

      // Connect through proxy - pass the controller's stream for data forwarding
      await _connectThroughProxy(
        clientSocket,
        dataController.stream,
        remainingData,
        request.targetHost,
        request.targetPort,
      );
    } catch (e) {
      clientSocket.destroy();
    }
  }

  /// Handle HTTP CONNECT protocol connection
  Future<void> _handleHttpProtocol(
    Socket clientSocket,
    List<int> initialBuffer,
    Stream<List<int>> socketStream,
  ) async {
    if (_activeNode == null) {
      clientSocket.destroy();
      return;
    }

    try {
      // Use the provided initial buffer and stream
      final buffer = <int>[];
      buffer.addAll(initialBuffer);
      String? requestLine;

      // First, check if the initial buffer already contains the request line
      String str = String.fromCharCodes(buffer);
      int lineEnd = str.indexOf('\r\n');

      if (lineEnd == -1) {
        // Read data until we get the first line (CONNECT request)
        await for (final data in socketStream) {
          buffer.addAll(data);
          str = String.fromCharCodes(buffer);
          lineEnd = str.indexOf('\r\n');

          if (lineEnd != -1) {
            requestLine = str.substring(0, lineEnd);
            break;
          }

          // Safety: if buffer gets too large, bail out
          if (buffer.length > 8192) {
            clientSocket.destroy();
            return;
          }
        }
      } else {
        requestLine = str.substring(0, lineEnd);
      }

      if (requestLine == null) {
        clientSocket.destroy();
        return;
      }

      // Parse CONNECT request: "CONNECT host:port HTTP/1.1"
      final parts = requestLine.split(' ');
      if (parts.length < 2 || parts[0] != 'CONNECT') {
        // Not a CONNECT request, send 400 Bad Request
        clientSocket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        clientSocket.destroy();
        return;
      }

      // Extract host:port
      final hostPort = parts[1];
      final colonIndex = hostPort.lastIndexOf(':');
      if (colonIndex == -1) {
        clientSocket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        clientSocket.destroy();
        return;
      }

      final targetHost = hostPort.substring(0, colonIndex);
      final targetPort = int.tryParse(hostPort.substring(colonIndex + 1));

      if (targetPort == null) {
        clientSocket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        clientSocket.destroy();
        return;
      }

      // Read and discard remaining headers until we find \r\n\r\n
      while (true) {
        final str = String.fromCharCodes(buffer);
        final headersEnd = str.indexOf('\r\n\r\n');

        if (headersEnd != -1) {
          // Found end of headers, any data after is payload (shouldn't be any for CONNECT)
          final remainingData = buffer.length > headersEnd + 4
              ? buffer.sublist(headersEnd + 4)
              : <int>[];

          // Send 200 Connection Established
          clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
          await clientSocket.flush();

          // Bridge the socket stream to a fresh controller so downstream listeners
          // receive events even though we consumed some earlier while parsing headers.
          final dataController = StreamController<List<int>>();
          socketStream.listen(
            (data) => dataController.add(data),
            onDone: () => dataController.close(),
            onError: (e) => dataController.addError(e),
          );

          // Now forward traffic through the proxy using the controller's stream
          await _connectThroughProxy(
            clientSocket,
            dataController.stream,
            remainingData,
            targetHost,
            targetPort,
          );
          return;
        }

        // Continue reading headers
        final chunk = await socketStream.first;
        buffer.addAll(chunk);

        // Safety limit
        if (buffer.length > 16384) {
          clientSocket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
          clientSocket.destroy();
          return;
        }
      }
    } catch (_) {
      try {
        clientSocket.destroy();
      } catch (_) {}
    }
  }

  /// Connect through proxy and forward traffic bidirectionally
  Future<void> _connectThroughProxy(
    Socket clientSocket,
    Stream<List<int>> clientStream,
    List<int> initialData,
    String targetHost,
    int targetPort,
  ) async {
    if (_activeNode == null) {
      clientSocket.destroy();
      return;
    }

    try {
      final nodeType = _activeNode!.type.toLowerCase();

      if (nodeType.contains('trojan')) {
        await _connectTrojan(
          clientSocket,
          clientStream,
          initialData,
          targetHost,
          targetPort,
        );
      } else if (nodeType.contains('ss') || nodeType.contains('shadowsocks')) {
        await _connectShadowsocks(
          clientSocket,
          clientStream,
          initialData,
          targetHost,
          targetPort,
        );
      } else if (nodeType.contains('vmess')) {
        await _connectVMess(
          clientSocket,
          clientStream,
          initialData,
          targetHost,
          targetPort,
        );
      } else {
        clientSocket.destroy();
      }
    } catch (_) {
      clientSocket.destroy();
    }
  }

  /// Connect using Trojan protocol
  Future<void> _connectTrojan(
    Socket clientSocket,
    Stream<List<int>> clientStream,
    List<int> initialData,
    String targetHost,
    int targetPort,
  ) async {
    try {
      // Get password from node
      final password = _activeNode!.password;
      if (password == null || password.isEmpty) {
        throw Exception('Trojan node missing password');
      }

      final trojan = TrojanProtocol(node: _activeNode!, password: password);
      final connection = await trojan.connect(targetHost, targetPort);

      // Send any initial data immediately (data after SOCKS5 handshake)
      if (initialData.isNotEmpty) {
        // Small delay to let the upstream process the auth packet
        await Future.delayed(const Duration(milliseconds: 50));
        connection.socket.add(initialData);
        _trackUpload(initialData.length);
      }

      // Forward data bidirectionally using the broadcast stream with tracking
      clientStream.listen(
        (data) {
          connection.socket.add(data);
          _trackUpload(data.length);
        },
        onDone: () => connection.close(),
        onError: (_) => connection.close(),
      );

      // Notify about connection start
      try {
        final conn = Connection(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          network: 'TCP',
          type: 'HTTP',
          host: '$targetHost:$targetPort',
          source:
              '${clientSocket.remoteAddress.address}:${clientSocket.remotePort}',
          destination:
              '${connection.socket.remoteAddress.address}:${connection.socket.remotePort}',
          upload: 0,
          download: 0,
          startTime: DateTime.now(),
        );
        _onConnectionStart?.call(conn);
      } catch (_) {}

      connection.serverData.listen(
        (data) {
          clientSocket.add(data);
          _trackDownload(data.length);
        },
        onDone: () {
          // Server finished sending data, close both ends
          clientSocket.destroy();
          connection.close();
          // notify connection end
          try {
            _onConnectionEnd?.call(
              '${clientSocket.remoteAddress.address}:${clientSocket.remotePort}',
            );
          } catch (_) {}
        },
        onError: (_) {
          clientSocket.destroy();
          connection.close();
          try {
            _onConnectionEnd?.call(
              '${clientSocket.remoteAddress.address}:${clientSocket.remotePort}',
            );
          } catch (_) {}
        },
      );
    } catch (e) {
      clientSocket.destroy();
      rethrow;
    }
  }

  /// Connect using Shadowsocks protocol
  Future<void> _connectShadowsocks(
    Socket clientSocket,
    Stream<List<int>> clientStream,
    List<int> initialData,
    String targetHost,
    int targetPort,
  ) async {
    try {
      // Get password and cipher from node
      final password = _activeNode!.password;
      final cipher = _activeNode!.cipher ?? 'aes-256-gcm'; // Default cipher

      if (password == null || password.isEmpty) {
        throw Exception('Shadowsocks node missing password');
      }

      final ss = ShadowsocksProtocol(
        node: _activeNode!,
        password: password,
        method: cipher,
      );
      final connection = await ss.connect(targetHost, targetPort);

      // Send any initial data immediately (data after SOCKS5 handshake)
      if (initialData.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 50));
        final encrypted = connection.cipher.encrypt(
          Uint8List.fromList(initialData),
        );
        connection.socket.add(encrypted);
        _trackUpload(encrypted.length);
      }

      // Forward data bidirectionally using the broadcast stream with tracking
      clientStream.listen(
        (data) {
          final encrypted = connection.cipher.encrypt(Uint8List.fromList(data));
          connection.socket.add(encrypted);
          _trackUpload(encrypted.length);
        },
        onDone: () => connection.close(),
        onError: (_) => connection.close(),
      );

      // Notify about connection start
      try {
        final conn = Connection(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          network: 'TCP',
          type: 'HTTP',
          host: '$targetHost:$targetPort',
          source:
              '${clientSocket.remoteAddress.address}:${clientSocket.remotePort}',
          destination:
              '${connection.socket.remoteAddress.address}:${connection.socket.remotePort}',
          upload: 0,
          download: 0,
          startTime: DateTime.now(),
        );
        _onConnectionStart?.call(conn);
      } catch (_) {}

      connection.serverData.listen(
        (data) {
          clientSocket.add(data);
          _trackDownload(data.length);
        },
        onDone: () {
          // Server finished sending data, close both ends
          clientSocket.destroy();
          connection.close();
          try {
            _onConnectionEnd?.call(
              '${clientSocket.remoteAddress.address}:${clientSocket.remotePort}',
            );
          } catch (_) {}
        },
        onError: (_) {
          clientSocket.destroy();
          connection.close();
          try {
            _onConnectionEnd?.call(
              '${clientSocket.remoteAddress.address}:${clientSocket.remotePort}',
            );
          } catch (_) {}
        },
      );
    } catch (e) {
      clientSocket.destroy();
      rethrow;
    }
  }

  /// Connect using VMess protocol
  Future<void> _connectVMess(
    Socket clientSocket,
    Stream<List<int>> clientStream,
    List<int> initialData,
    String targetHost,
    int targetPort,
  ) async {
    // VMess is complex - recommend using FFI to v2ray-core
    clientSocket.destroy();
    throw UnimplementedError(
      'VMess protocol requires FFI integration with v2ray-core',
    );
  }

  /// Get connection statistics
  Map<String, dynamic> getStats() {
    return {
      'isRunning': _isRunning,
      'activeNode': _activeNode?.name ?? 'None',
      'localPort': _localPort,
      'protocol': _activeNode?.type ?? 'None',
    };
  }
}
