import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// SOCKS5 Protocol Handler
/// Spec: RFC 1928 - SOCKS Protocol Version 5
class Socks5Handler {
  final Socket clientSocket;

  Socks5Handler(this.clientSocket);

  /// Handle SOCKS5 handshake and return target address
  /// Returns null if handshake fails
  Future<Socks5Request?> handleHandshake() async {
    try {
      // Step 1: Greeting
      // Client sends: VER | NMETHODS | METHODS
      final greeting = await _readBytes(2);
      if (greeting == null || greeting.length < 2) {
        return null;
      }

      final version = greeting[0];
      final nMethods = greeting[1];

      if (version != 0x05) {
        return null;
      }

      // Read authentication methods
      final methods = await _readBytes(nMethods);
      if (methods == null) {
        return null;
      }

      // Check if NO AUTHENTICATION (0x00) is supported
      if (!methods.contains(0x00)) {
        // Send unsupported method response
        clientSocket.add([0x05, 0xFF]);
        return null;
      }

      // Send method selection: VER | METHOD (0x00 = NO AUTHENTICATION)
      clientSocket.add([0x05, 0x00]);

      // Step 2: Request
      // Client sends: VER | CMD | RSV | ATYP | DST.ADDR | DST.PORT
      final requestHeader = await _readBytes(4);
      if (requestHeader == null || requestHeader.length < 4) {
        return null;
      }

      final reqVersion = requestHeader[0];
      final cmd = requestHeader[1];
      // final rsv = requestHeader[2]; // Reserved, must be 0x00
      final atyp = requestHeader[3];

      if (reqVersion != 0x05) {
        _sendReply(0x01); // General failure
        return null;
      }

      // We only support CONNECT command (0x01)
      if (cmd != 0x01) {
        _sendReply(0x07); // Command not supported
        return null;
      }

      // Parse destination address based on type
      String? targetHost;
      int? targetPort;

      switch (atyp) {
        case 0x01: // IPv4
          final addr = await _readBytes(4);
          if (addr == null || addr.length != 4) {
            _sendReply(0x01); // General failure
            return null;
          }
          targetHost = addr.join('.');
          break;

        case 0x03: // Domain name
          final lenBytes = await _readBytes(1);
          if (lenBytes == null || lenBytes.isEmpty) {
            _sendReply(0x01); // General failure
            return null;
          }
          final domainLen = lenBytes[0];
          final domain = await _readBytes(domainLen);
          if (domain == null || domain.length != domainLen) {
            _sendReply(0x01); // General failure
            return null;
          }
          targetHost = String.fromCharCodes(domain);
          break;

        case 0x04: // IPv6
          final addr = await _readBytes(16);
          if (addr == null || addr.length != 16) {
            _sendReply(0x01); // General failure
            return null;
          }
          // Convert IPv6 bytes to string
          final parts = <String>[];
          for (int i = 0; i < 16; i += 2) {
            parts.add((addr[i] << 8 | addr[i + 1]).toRadixString(16));
          }
          targetHost = parts.join(':');
          break;

        default:
          _sendReply(0x08); // Address type not supported
          return null;
      }

      // Read port (2 bytes, big endian)
      final portBytes = await _readBytes(2);
      if (portBytes == null || portBytes.length != 2) {
        _sendReply(0x01); // General failure
        return null;
      }
      targetPort = (portBytes[0] << 8) | portBytes[1];

      return Socks5Request(
        targetHost: targetHost,
        targetPort: targetPort,
        addressType: atyp,
      );
    } catch (e) {
      _sendReply(0x01); // General failure
      return null;
    }
  }

  /// Send SOCKS5 reply
  void sendSuccessReply() {
    _sendReply(0x00); // Succeeded
  }

  /// Send SOCKS5 reply with status code
  void _sendReply(int status) {
    // VER | REP | RSV | ATYP | BND.ADDR | BND.PORT
    // We use IPv4 0.0.0.0:0 as bind address
    final reply = Uint8List.fromList([
      0x05, // VER
      status, // REP (0x00 = succeeded, 0x01 = general failure, etc.)
      0x00, // RSV
      0x01, // ATYP (IPv4)
      0x00, 0x00, 0x00, 0x00, // BND.ADDR (0.0.0.0)
      0x00, 0x00, // BND.PORT (0)
    ]);
    clientSocket.add(reply);
  }

  /// Read exact number of bytes from socket
  Future<Uint8List?> _readBytes(int count) async {
    final buffer = BytesBuilder();

    await for (final data in clientSocket) {
      buffer.add(data);
      if (buffer.length >= count) {
        final result = buffer.toBytes();
        return Uint8List.fromList(result.sublist(0, count));
      }
    }

    return null;
  }
}

/// SOCKS5 request information
class Socks5Request {
  final String targetHost;
  final int targetPort;
  final int addressType;

  Socks5Request({
    required this.targetHost,
    required this.targetPort,
    required this.addressType,
  });
}

/// SOCKS5 Handler with pre-buffered data
class Socks5HandlerWithBuffer extends Socks5Handler {
  final List<int> initialBuffer;
  int bufferOffset = 0;

  Socks5HandlerWithBuffer(super.clientSocket, this.initialBuffer);

  @override
  Future<Uint8List?> _readBytes(int count) async {
    final result = <int>[];

    // First, consume from initial buffer
    while (bufferOffset < initialBuffer.length && result.length < count) {
      result.add(initialBuffer[bufferOffset++]);
    }

    // If we still need more bytes, read from socket
    if (result.length < count) {
      final remaining = count - result.length;
      final buffer = <int>[];

      await for (final data in clientSocket) {
        buffer.addAll(data);
        if (buffer.length >= remaining) {
          // Take what we need
          result.addAll(buffer.sublist(0, remaining));

          // Put back any extra bytes into initial buffer for next read
          if (buffer.length > remaining) {
            initialBuffer.addAll(buffer.sublist(remaining));
          }

          break;
        }
      }

      // If we didn't get enough data
      if (result.length < count) {
        result.addAll(buffer);
      }
    }

    return result.length == count ? Uint8List.fromList(result) : null;
  }
}

/// SOCKS5 Handler that uses a broadcast stream
class Socks5HandlerWithStream extends Socks5Handler {
  final List<int> initialBuffer;
  final Stream<List<int>> socketStream;
  int bufferOffset = 0;

  Socks5HandlerWithStream(
    super.clientSocket,
    this.initialBuffer,
    this.socketStream,
  );

  /// Get remaining data that wasn't consumed during handshake
  List<int> getRemainingData() {
    if (bufferOffset < initialBuffer.length) {
      final remaining = initialBuffer.sublist(bufferOffset);
      return remaining;
    }
    return [];
  }

  @override
  Future<Uint8List?> _readBytes(int count) async {
    final result = <int>[];

    // First, consume from initial buffer
    while (bufferOffset < initialBuffer.length && result.length < count) {
      result.add(initialBuffer[bufferOffset++]);
    }

    // If we got everything from the buffer, return it
    if (result.length >= count) {
      return Uint8List.fromList(result.sublist(0, count));
    }

    // Otherwise, need to read from the stream
    final remaining = count - result.length;
    final buffer = <int>[];

    await for (final data in socketStream) {
      buffer.addAll(data);
      if (buffer.length >= remaining) {
        // Take what we need
        result.addAll(buffer.sublist(0, remaining));

        // Save any extra bytes back to initial buffer for next read
        if (buffer.length > remaining) {
          initialBuffer.addAll(buffer.sublist(remaining));
        }

        break;
      }
    }

    // Add whatever we got from the stream
    if (buffer.isNotEmpty && buffer.length < remaining) {
      result.addAll(buffer);
    }

    return result.length == count ? Uint8List.fromList(result) : null;
  }
}
