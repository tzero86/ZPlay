import 'dart:async';
import 'dart:io';

import '../security/network_policy.dart';

/// HTTP clients that pin connections to validated DNS addresses.
///
/// Checking a hostname before a request is not enough: DNS can return a public
/// address for the check and a loopback or LAN address when the socket
/// connects. The connection factory resolves once, rejects the host if any
/// answer is non-public, and connects to the checked address. TLS still uses
/// the original hostname for SNI and certificate validation.
class PinnedHttpClient {
  PinnedHttpClient._();

  static HttpClient create({
    Duration connectionTimeout = const Duration(seconds: 20),
    Future<List<InternetAddress>> Function(String host)? resolve,
  }) {
    final client = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..findProxy = ((_) => 'DIRECT');
    client.connectionFactory = connectionFactory(resolve: resolve);
    return client;
  }

  static Future<ConnectionTask<Socket>> Function(Uri, String?, int?)
  connectionFactory({
    Future<List<InternetAddress>> Function(String host)? resolve,
  }) {
    final resolver = resolve ?? InternetAddress.lookup;
    return (uri, proxyHost, proxyPort) =>
        _connect(uri, proxyHost, proxyPort, resolver);
  }

  static Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
    Future<List<InternetAddress>> Function(String host) resolve,
  ) async {
    if (proxyHost != null || proxyPort != null) {
      throw const SocketException(
        'Refusing to pin a connection through a proxy',
      );
    }

    final addresses = await resolve(
      uri.host,
    ).timeout(const Duration(seconds: 10));
    if (addresses.isEmpty) {
      throw SocketException('No DNS addresses for ${uri.host}');
    }
    for (final address in addresses) {
      if (NetworkPolicy.isLocalHost(address.address)) {
        throw SocketException(
          'Refusing non-public address ${address.address} for ${uri.host}',
        );
      }
    }

    final raw = await Socket.startConnect(addresses.first, uri.port);
    final secure = uri.scheme.toLowerCase() == 'https';
    final socketFuture = raw.socket.then<Socket>((socket) async {
      if (!secure) return socket;
      try {
        return await SecureSocket.secure(socket, host: uri.host);
      } catch (_) {
        socket.destroy();
        rethrow;
      }
    });
    return ConnectionTask.fromSocket(socketFuture, raw.cancel);
  }
}
