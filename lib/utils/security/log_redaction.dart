/// Reduces a URL to scheme, host, and port before it reaches a log.
///
/// Stream URLs frequently carry credentials in the userinfo, path, or query
/// (Xtream, debrid links, signed CDN tokens), so none of those parts are safe.
String redactUrl(String? value) {
  if (value == null || value.trim().isEmpty) return '<redacted>';
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '<redacted>';
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

/// Redacts every HTTP(S) URL embedded in free-form diagnostic text.
String redactTextUrls(String text) {
  return text.replaceAllMapped(
    RegExp(r'''https?://[^\s<>"']+'''),
    (match) => redactUrl(match.group(0)),
  );
}
