import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../models/clash_models.dart';

/// Trojan Protocol Implementation
/// Spec: https://trojan-gfw.github.io/trojan/protocol
class TrojanProtocol {
  final ProxyNode node;
  final String password;

  TrojanProtocol({required this.node, required this.password});

  /// Connect to target through Trojan proxy
  Future<TrojanConnection> connect(
    String targetHost,
    int targetPort, {
    bool isUdp = false,
  }) async {
    if (node.host == null || node.port == null) {
      throw Exception('Invalid proxy node: missing host or port');
    }

    // Connect to Trojan server over TLS (Trojan expects TLS)
    final sniHost = (node.sni != null && node.sni!.isNotEmpty)
        ? node.sni!
        : node.host!;

    // Connect raw socket first (use IP or host as provided)
    final rawSocket = await Socket.connect(node.host!, node.port!);

    // Then perform TLS handshake with SNI/host verification using secure wrapper
    final secureSocket = await SecureSocket.secure(
      rawSocket,
      host: sniHost,
      onBadCertificate: (cert) {
        final skip = node.skipCertVerify ?? false;
        if (skip) {}
        return skip;
      },
    );
    // Log peer certificate info if available
    try {
      final cert = secureSocket.peerCertificate;
      if (cert != null) {}
    } catch (_) {}

    // Send Trojan request
    final request = _buildTrojanRequest(targetHost, targetPort, isUdp);
    // Debug: log outgoing request bytes (hex preview)
    try {} catch (_) {}

    secureSocket.add(request);

    return TrojanConnection(
      socket: secureSocket,
      targetHost: targetHost,
      targetPort: targetPort,
    );
  }

  /// Build Trojan request packet
  /// Format: password_hash + CRLF + command + address_type + address + port + CRLF
  Uint8List _buildTrojanRequest(String targetHost, int targetPort, bool isUdp) {
    final buffer = BytesBuilder();

    // 1. Password hash (SHA-224 in lowercase hex - 56 characters)
    final passwordHash = _hashPassword(password);
    buffer.add(utf8.encode(passwordHash));

    // 2. CRLF
    buffer.add([0x0D, 0x0A]);

    // 3. Command (1 byte): 0x01 = CONNECT (TCP), 0x03 = UDP ASSOCIATE
    buffer.addByte(isUdp ? 0x03 : 0x01);

    // 4. Address type + address + port
    if (_isIPv4(targetHost)) {
      // IPv4: type(0x01) + 4 bytes IP
      buffer.addByte(0x01);
      buffer.add(_ipv4ToBytes(targetHost));
    } else if (_isIPv6(targetHost)) {
      // IPv6: type(0x04) + 16 bytes IP
      buffer.addByte(0x04);
      buffer.add(_ipv6ToBytes(targetHost));
    } else {
      // Domain: type(0x03) + length(1 byte) + domain string
      buffer.addByte(0x03);
      final domainBytes = utf8.encode(targetHost);
      buffer.addByte(domainBytes.length);
      buffer.add(domainBytes);
    }

    // 5. Port (2 bytes, big endian)
    buffer.addByte((targetPort >> 8) & 0xFF);
    buffer.addByte(targetPort & 0xFF);

    // 6. CRLF
    buffer.add([0x0D, 0x0A]);

    return buffer.toBytes();
  }

  /// Hash password using SHA-224 and convert to lowercase hex (56 characters)
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha224.convert(bytes);
    return digest
        .toString(); // SHA-224 produces 56-character lowercase hex string
  }

  bool _isIPv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final num = int.tryParse(part);
      return num != null && num >= 0 && num <= 255;
    });
  }

  bool _isIPv6(String address) {
    return address.contains(':') && !address.contains('.');
  }

  Uint8List _ipv4ToBytes(String ip) {
    final parts = ip.split('.');
    return Uint8List.fromList(parts.map((p) => int.parse(p)).toList());
  }

  Uint8List _ipv6ToBytes(String ip) {
    // Simplified IPv6 parsing
    final address = InternetAddress(ip);
    return Uint8List.fromList(address.rawAddress);
  }
}

/// Represents an active Trojan connection
class TrojanConnection {
  final Socket socket;
  final String targetHost;
  final int targetPort;
  bool _closed = false;

  TrojanConnection({
    required this.socket,
    required this.targetHost,
    required this.targetPort,
  });

  bool get isClosed => _closed;

  /// Forward data from client to remote server
  void forwardFromClient(Stream<List<int>> clientData) {
    clientData.listen(
      (data) {
        if (!_closed) {
          socket.add(data);
        }
      },
      onDone: () {
        // Don't close the socket here - server might still be sending data
        // The socket will be closed when the server side is done or on error
      },
      onError: (error) => close(),
    );
  }

  /// Get data stream from remote server to forward to client
  Stream<Uint8List> get serverData => socket;

  /// Close the connection
  void close() {
    if (!_closed) {
      _closed = true;
      socket.destroy();
    }
  }
}
