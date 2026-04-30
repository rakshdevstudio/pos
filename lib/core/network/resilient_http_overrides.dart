import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class ResilientHttpOverrides extends HttpOverrides {
  final _resolver = _DnsFallbackResolver();
  static const Duration _dnsTimeout = Duration(seconds: 3);
  static const Duration _primaryConnectCap = Duration(seconds: 4);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final targetHost = proxyHost ?? uri.host;
      final targetPort = proxyHost != null
          ? (proxyPort ?? _effectivePort(uri))
          : _effectivePort(uri);

      if (proxyHost != null || _shouldBypassCustomResolution(targetHost)) {
        return ConnectionTask.fromSocket(
          Socket.connect(
            targetHost,
            targetPort,
            timeout: client.connectionTimeout,
          ),
          () {},
        );
      }

      final shouldSecure = proxyHost == null && uri.scheme == 'https';
      return ConnectionTask.fromSocket(
        _connectWithFallback(
          targetHost,
          targetPort,
          timeout: client.connectionTimeout ?? _primaryConnectCap,
          secureHost: shouldSecure ? uri.host : null,
        ),
        () {},
      );
    };
    return client;
  }

  bool _shouldBypassCustomResolution(String host) {
    if (host == 'localhost') return true;
    return InternetAddress.tryParse(host) != null;
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort && uri.port > 0) {
      return uri.port;
    }
    return uri.scheme == 'https' ? 443 : 80;
  }

  Future<Socket> _connectWithFallback(
    String host,
    int port, {
    required Duration timeout,
    String? secureHost,
  }) async {
    final primaryTimeout = _boundedPrimaryTimeout(timeout);

    try {
      return await _connectDirect(
        host,
        port,
        timeout: primaryTimeout,
        secureHost: secureHost,
      );
    } on SocketException {
      // Fall through to the DNS-resolved retry below.
    } on HandshakeException {
      rethrow;
    } on TimeoutException {
      // Fall through to the DNS-resolved retry below.
    }

    final resolvedAddress = await _resolver.lookupIPv4(
      host,
      timeout: _dnsTimeout,
    );
    if (resolvedAddress == null) {
      return _connectDirect(
        host,
        port,
        timeout: timeout,
        secureHost: secureHost,
      );
    }

    return _connectResolved(
      resolvedAddress,
      port,
      timeout: timeout,
      secureHost: secureHost,
    );
  }

  Future<Socket> _connectDirect(
    String host,
    int port, {
    required Duration timeout,
    String? secureHost,
  }) {
    if (secureHost != null) {
      return SecureSocket.connect(
        host,
        port,
        timeout: timeout,
      );
    }

    return Socket.connect(
      host,
      port,
      timeout: timeout,
    );
  }

  Future<Socket> _connectResolved(
    InternetAddress address,
    int port, {
    required Duration timeout,
    String? secureHost,
  }) async {
    final socket = await Socket.connect(
      address,
      port,
      timeout: timeout,
    );
    if (secureHost == null) {
      return socket;
    }

    return SecureSocket.secure(
      socket,
      host: secureHost,
    );
  }

  Duration _boundedPrimaryTimeout(Duration timeout) {
    if (timeout <= Duration.zero) {
      return _primaryConnectCap;
    }
    return timeout < _primaryConnectCap ? timeout : _primaryConnectCap;
  }
}

class _DnsFallbackResolver {
  static final List<InternetAddress> _dnsServers = [
    InternetAddress('8.8.8.8'),
    InternetAddress('1.1.1.1'),
  ];

  final _random = Random();
  final Map<String, InternetAddress> _cache = {};

  Future<InternetAddress?> lookupIPv4(
    String host, {
    required Duration timeout,
  }) async {
    final cached = _cache[host];
    if (cached != null) {
      return cached;
    }

    for (final dnsServer in _dnsServers) {
      final resolved = await _queryDnsServer(
        dnsServer,
        host,
        timeout: timeout,
      );
      if (resolved != null) {
        _cache[host] = resolved;
        return resolved;
      }
    }

    return null;
  }

  Future<InternetAddress?> _queryDnsServer(
    InternetAddress dnsServer,
    String host, {
    required Duration timeout,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final response = Completer<InternetAddress?>();
    final queryId = _random.nextInt(0x10000);
    late final StreamSubscription<RawSocketEvent> subscription;

    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || response.isCompleted) {
        return;
      }

      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }

      final resolved = _parseResponse(datagram.data, queryId);
      if (resolved != null) {
        response.complete(resolved);
      }
    });

    socket.send(_buildQuery(host, queryId), dnsServer, 53);

    try {
      return await response.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  Uint8List _buildQuery(String host, int queryId) {
    final builder = BytesBuilder();
    builder.add(_word(queryId));
    builder.add(const [0x01, 0x00]); // standard recursive query
    builder.add(const [0x00, 0x01]); // one question
    builder.add(const [0x00, 0x00]); // answer count
    builder.add(const [0x00, 0x00]); // authority count
    builder.add(const [0x00, 0x00]); // additional count

    for (final label in host.split('.')) {
      final labelBytes = Uint8List.fromList(label.codeUnits);
      builder.add([labelBytes.length]);
      builder.add(labelBytes);
    }
    builder.addByte(0x00); // end of host
    builder.add(const [0x00, 0x01]); // QTYPE A
    builder.add(const [0x00, 0x01]); // QCLASS IN
    return builder.takeBytes();
  }

  InternetAddress? _parseResponse(Uint8List data, int queryId) {
    if (data.length < 12) return null;

    final byteData = ByteData.sublistView(data);
    if (byteData.getUint16(0) != queryId) return null;

    final answerCount = byteData.getUint16(6);
    if (answerCount == 0) return null;

    var offset = 12;
    offset = _skipQuestions(data, offset, byteData.getUint16(4));
    if (offset < 0) return null;

    for (var i = 0; i < answerCount; i++) {
      offset = _skipName(data, offset);
      if (offset < 0 || offset + 10 > data.length) return null;

      final type = byteData.getUint16(offset);
      final dataLength = byteData.getUint16(offset + 8);
      offset += 10;
      if (offset + dataLength > data.length) return null;

      if (type == 1 && dataLength == 4) {
        return InternetAddress.fromRawAddress(
          Uint8List.fromList(data.sublist(offset, offset + 4)),
          type: InternetAddressType.IPv4,
        );
      }

      offset += dataLength;
    }

    return null;
  }

  int _skipQuestions(Uint8List data, int offset, int questionCount) {
    for (var i = 0; i < questionCount; i++) {
      offset = _skipName(data, offset);
      if (offset < 0 || offset + 4 > data.length) return -1;
      offset += 4;
    }
    return offset;
  }

  int _skipName(Uint8List data, int offset) {
    while (offset < data.length) {
      final length = data[offset];
      if (length == 0) {
        return offset + 1;
      }

      if ((length & 0xC0) == 0xC0) {
        return offset + 2;
      }

      offset += length + 1;
    }
    return -1;
  }

  List<int> _word(int value) => [(value >> 8) & 0xFF, value & 0xFF];
}
