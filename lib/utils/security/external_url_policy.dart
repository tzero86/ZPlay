/// Scheme policy for links that leave the app.
///
/// Stream payloads can carry an `externalUrl`. Passing that to the operating
/// system without a scheme check lets a remote payload invoke `file:`,
/// `javascript:`, `intent:`, or an arbitrary registered handler.
class ExternalUrlPolicy {
  ExternalUrlPolicy._();

  static const Set<String> _allowedSchemes = {'http', 'https', 'stremio'};

  /// Parses [raw] and returns it only when its scheme is allowed.
  ///
  /// The triple-slash `stremio:///detail/...` form used by Stremio payloads is
  /// normalized to `stremio://detail/...` so the existing route parser works.
  static Uri? parse(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('stremio:///')) {
      value = value.replaceFirst('stremio:///', 'stremio://');
    }

    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) return null;
    if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isEmpty) {
      return null;
    }
    return uri;
  }
}
