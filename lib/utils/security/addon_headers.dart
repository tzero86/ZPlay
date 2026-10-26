/// Request headers an installed addon is allowed to contribute to playback.
///
/// Addons are third-party code. Their stream payload can carry a `headers`
/// map or `behaviorHints.proxyHeaders.request`, and the player previously
/// merged both verbatim. That let an addon set credential-bearing or
/// request-routing headers on a request to another host.
///
/// Only headers that describe the media request are kept. Names are
/// canonicalized so a lower-case addon key cannot sit beside the player's
/// default header of the same name.
class AddonHeaders {
  AddonHeaders._();

  static const Map<String, String> _allowed = {
    'accept': 'Accept',
    'accept-language': 'Accept-Language',
    'if-range': 'If-Range',
    'origin': 'Origin',
    'range': 'Range',
    'referer': 'Referer',
    'user-agent': 'User-Agent',
    'x-playback-session-id': 'X-Playback-Session-Id',
    'x-requested-with': 'X-Requested-With',
  };

  /// Returns only safe headers, with canonical names, or null when none are
  /// left. Values containing CR/LF are dropped rather than normalized.
  static Map<String, String>? sanitize(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return null;

    final cleaned = <String, String>{};
    for (final entry in headers.entries) {
      final canonical = _allowed[entry.key.trim().toLowerCase()];
      if (canonical == null) continue;
      final value = entry.value;
      if (value.isEmpty || value.contains('\r') || value.contains('\n')) {
        continue;
      }
      cleaned[canonical] = value;
    }
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Removes the raw request-header maps from behavior hints.
  ///
  /// The sanitized values are already in [StreamSource.headers]; leaving the
  /// originals in the hints lets the player merge them again and bypass the
  /// sanitizer.
  static Map<String, dynamic>? stripRequestHeaderHints(
    Map<String, dynamic>? hints,
  ) {
    if (hints == null || hints.isEmpty) return hints;
    if (!hints.containsKey('proxyHeaders') &&
        !hints.containsKey('requestHeaders')) {
      return hints;
    }

    final cleaned = Map<String, dynamic>.from(hints)..remove('proxyHeaders');
    cleaned.remove('requestHeaders');
    return cleaned.isEmpty ? null : cleaned;
  }
}
