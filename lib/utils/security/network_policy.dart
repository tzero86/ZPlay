import 'dart:io';

/// Network trust rules for URLs supplied by remote content.
///
/// A playlist or API response may name the next request target. Remote
/// responses must not be able to turn the client into a probe for loopback,
/// LAN, link-local, or carrier-grade NAT addresses. The initial user-chosen
/// URL is still allowed to be local, so IPTV and LAN sources keep working.
///
/// These checks are synchronous and only inspect the literal host. A caller
/// that requests a remote hostname must also pin the resolved address at
/// connection time, as HLS downloads do through `PinnedHttpClient`.
class NetworkPolicy {
  NetworkPolicy._();

  /// True when [host] names a local, private, link-local, or otherwise
  /// non-public destination.
  static bool isLocalHost(String host) {
    var normalized = host.trim().toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isEmpty) return true;
    if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
      return true;
    }
    if (normalized.endsWith('.local') ||
        normalized.endsWith('.localdomain') ||
        normalized.endsWith('.lan') ||
        normalized.endsWith('.home') ||
        normalized.endsWith('.internal')) {
      return true;
    }

    final address = InternetAddress.tryParse(normalized);
    if (address == null) {
      // Numeric and shortened IPv4 forms are accepted by some resolvers even
      // though InternetAddress does not parse them. Treat them as local rather
      // than letting a playlist hide 127.0.0.1 behind `2130706433` or `127.1`.
      if (RegExp(r'^[0-9]+$').hasMatch(normalized)) return true;
      if (normalized.startsWith('0x')) return true;
      final labels = normalized.split('.');
      if (labels.length <= 4 &&
          labels.every(
            (label) => RegExp(r'^(0x[0-9a-f]+|[0-9]+)$').hasMatch(label),
          )) {
        // This is a numeric IPv4 form the Dart parser rejected. Resolvers may
        // still accept octal, hexadecimal, zero-padded, or overflowing parts,
        // so treat it as local rather than risk a loopback alias.
        return true;
      }
      return false;
    }

    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }

    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      return _isPrivateIpv4(bytes);
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      if (bytes.every((byte) => byte == 0)) return true;
      if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7

      // IPv4-mapped (::ffff:0:0/96) and the deprecated IPv4-compatible
      // (::/96) forms both reach an IPv4 destination.
      if (bytes.take(10).every((byte) => byte == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff) {
        return _isPrivateIpv4(bytes.sublist(12));
      }
      if (bytes.take(12).every((byte) => byte == 0)) return true;
    }
    return false;
  }

  /// True when [uri] is HTTP(S) and may be requested under [allowLocal].
  static bool isAllowedHttpUri(Uri uri, {required bool allowLocal}) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return allowLocal || !isLocalHost(uri.host);
  }

  /// Resolves [reference] against [base] and rejects it when the result is not
  /// an allowed HTTP(S) target.
  static Uri resolveHttpUri(
    Uri base,
    String reference, {
    required bool allowLocal,
  }) {
    final resolved = base.resolve(reference);
    if (!isAllowedHttpUri(resolved, allowLocal: allowLocal)) {
      throw FormatException(
        'Refusing URL outside the allowed HTTP(S) network: ${resolved.host}',
      );
    }
    return resolved;
  }

  /// True when the user-chosen [uri] itself is pointing at a local host.
  static bool isLocalUri(Uri uri) =>
      uri.host.isNotEmpty && isLocalHost(uri.host);

  static bool _isPrivateIpv4(List<int> bytes) {
    final a = bytes[0];
    final b = bytes[1];
    final c = bytes[2];
    if (a == 0 || a == 10 || a == 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10
    if (a == 192 && b == 0 && (c == 0 || c == 2)) return true;
    if (a == 198 && (b == 18 || b == 19)) return true; // 198.18.0.0/15
    if (a == 198 && b == 51 && c == 100) return true; // 198.51.100.0/24
    if (a == 203 && b == 0 && c == 113) return true; // 203.0.113.0/24
    if (a >= 224) return true; // multicast and reserved
    return false;
  }
}
