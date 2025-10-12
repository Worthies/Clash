import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../models/clash_models.dart';

/// Shadowsocks Protocol Implementation
/// Spec: https://shadowsocks.org/en/spec/AEAD-Ciphers.html
class ShadowsocksProtocol {
  final ProxyNode node;
  final String password;
  final String method;

  ShadowsocksProtocol({required this.node, required this.password, required this.method});

  /// Connect to target through Shadowsocks proxy
  Future<ShadowsocksConnection> connect(String targetHost, int targetPort) async {
    if (node.host == null || node.port == null) {
      throw Exception('Invalid proxy node: missing host or port');
    }

    // Connect to Shadowsocks server
    final socket = await Socket.connect(node.host!, node.port!);

    // Generate salt for AEAD
    final salt = _generateSalt();

    // Derive keys
    final cipher = _createCipher(salt);

    // Build and encrypt request
    final request = _buildRequest(targetHost, targetPort);
    final encryptedRequest = cipher.encrypt(request);

    // Send salt + encrypted request
    socket.add(salt);
    socket.add(encryptedRequest);

    return ShadowsocksConnection(socket: socket, cipher: cipher, targetHost: targetHost, targetPort: targetPort);
  }

  /// Build SOCKS5-like address request
  /// Format: address_type + address + port
  Uint8List _buildRequest(String targetHost, int targetPort) {
    final buffer = BytesBuilder();

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

    // Port (2 bytes, big endian)
    buffer.addByte((targetPort >> 8) & 0xFF);
    buffer.addByte(targetPort & 0xFF);

    return buffer.toBytes();
  }

  /// Create cipher based on method
  ShadowsocksCipher _createCipher(Uint8List salt) {
    // Derive key using EVP_BytesToKey
    final key = _deriveKey(password, salt);

    if (method.contains('aes-256-gcm')) {
      return AesGcmCipher(key: key, salt: salt);
    } else if (method.contains('aes-128-gcm')) {
      return AesGcmCipher(key: key, salt: salt);
    } else if (method.contains('chacha20-ietf-poly1305')) {
      return ChaCha20Poly1305Cipher(key: key, salt: salt);
    } else {
      throw UnsupportedError('Cipher method not supported: $method');
    }
  }

  /// Derive encryption key from password and salt
  Uint8List _deriveKey(String password, Uint8List salt) {
    final keySize = _getKeySize(method);
    final passwordBytes = utf8.encode(password);

    // HKDF-SHA1 key derivation
    final result = BytesBuilder();
    var previous = Uint8List(0);

    while (result.length < keySize) {
      final data = BytesBuilder();
      data.add(previous);
      data.add(passwordBytes);
      data.add(salt);

      final digest = sha1.convert(data.toBytes());
      previous = Uint8List.fromList(digest.bytes);
      result.add(previous);
    }

    return Uint8List.fromList(result.toBytes().sublist(0, keySize));
  }

  int _getKeySize(String method) {
    if (method.contains('256')) return 32;
    if (method.contains('128')) return 16;
    return 32; // Default to 256-bit
  }

  Uint8List _generateSalt() {
    final saltSize = _getSaltSize(method);
    final random = Random.secure();
    return Uint8List.fromList(List.generate(saltSize, (_) => random.nextInt(256)));
  }

  int _getSaltSize(String method) {
    if (method.contains('aes-256-gcm')) return 32;
    if (method.contains('aes-128-gcm')) return 16;
    if (method.contains('chacha20')) return 32;
    return 32;
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
    final address = InternetAddress(ip);
    return Uint8List.fromList(address.rawAddress);
  }
}

/// Abstract cipher interface
abstract class ShadowsocksCipher {
  Uint8List encrypt(Uint8List data);
  Uint8List decrypt(Uint8List data);
}

/// AES-GCM cipher implementation (simplified)
class AesGcmCipher implements ShadowsocksCipher {
  final Uint8List key;
  final Uint8List salt;

  AesGcmCipher({required this.key, required this.salt});

  @override
  Uint8List encrypt(Uint8List data) {
    // Note: This is a simplified implementation
    // Production code should use platform-specific crypto libraries
    // or FFI to OpenSSL/BoringSSL for proper AEAD encryption

    // For now, return data with length prefix (basic framing)
    final buffer = BytesBuilder();
    buffer.addByte((data.length >> 8) & 0xFF);
    buffer.addByte(data.length & 0xFF);
    buffer.add(data);

    return buffer.toBytes();
  }

  @override
  Uint8List decrypt(Uint8List data) {
    // Simplified decryption - skip length prefix
    if (data.length < 2) return Uint8List(0);

    final length = (data[0] << 8) | data[1];
    if (data.length < 2 + length) return Uint8List(0);

    return Uint8List.fromList(data.sublist(2, 2 + length));
  }
}

/// ChaCha20-Poly1305 cipher implementation (simplified)
class ChaCha20Poly1305Cipher implements ShadowsocksCipher {
  final Uint8List key;
  final Uint8List salt;

  ChaCha20Poly1305Cipher({required this.key, required this.salt});

  @override
  Uint8List encrypt(Uint8List data) {
    // Simplified implementation - see note in AesGcmCipher
    final buffer = BytesBuilder();
    buffer.addByte((data.length >> 8) & 0xFF);
    buffer.addByte(data.length & 0xFF);
    buffer.add(data);

    return buffer.toBytes();
  }

  @override
  Uint8List decrypt(Uint8List data) {
    if (data.length < 2) return Uint8List(0);

    final length = (data[0] << 8) | data[1];
    if (data.length < 2 + length) return Uint8List(0);

    return Uint8List.fromList(data.sublist(2, 2 + length));
  }
}

/// Represents an active Shadowsocks connection
class ShadowsocksConnection {
  final Socket socket;
  final ShadowsocksCipher cipher;
  final String targetHost;
  final int targetPort;
  bool _closed = false;

  final _controller = StreamController<Uint8List>();

  ShadowsocksConnection({required this.socket, required this.cipher, required this.targetHost, required this.targetPort}) {
    // Listen to socket and decrypt incoming data
    socket.listen(
      (data) {
        if (!_closed) {
          final decrypted = cipher.decrypt(Uint8List.fromList(data));
          _controller.add(decrypted);
        }
      },
      onDone: () => close(),
      onError: (error) => close(),
    );
  }

  bool get isClosed => _closed;

  /// Forward encrypted data from client to remote server
  void forwardFromClient(Stream<List<int>> clientData) {
    clientData.listen(
      (data) {
        if (!_closed) {
          final encrypted = cipher.encrypt(Uint8List.fromList(data));
          socket.add(encrypted);
        }
      },
      onDone: () {
        // Don't close the socket here - server might still be sending data
        // The socket will be closed when the server side is done or on error
      },
      onError: (error) => close(),
    );
  }

  /// Get decrypted data stream from remote server
  Stream<Uint8List> get serverData => _controller.stream;

  /// Close the connection
  void close() {
    if (!_closed) {
      _closed = true;
      socket.destroy();
      _controller.close();
    }
  }
}
