import '../debrid/debrid_service.dart';
import '../debrid/providers/alldebrid_service.dart';
import '../debrid/providers/debrid_link_service.dart';
import '../debrid/providers/premiumize_service.dart';
import '../debrid/providers/real_debrid_service.dart';
import '../debrid/providers/torbox_service.dart';

/// Substitutes Debrid placeholders in addon URLs with the user's own key.
///
/// The placeholder form is `{alias}`, for example:
///   https://torrentio.strem.fun/realdebrid={realdebrid}
///
/// Aliases: {debrid} (whichever service is selected), {realdebrid}, {torbox},
/// {alldebrid}, {premiumize}, {debridlink}.
class AddonUrlResolver {
  AddonUrlResolver._();

  /// Placeholders we know how to fill, matched case-insensitively.
  static final RegExp _placeholderPattern = RegExp(
    r'\{(debrid|realdebrid|torbox|alldebrid|premiumize|debridlink)\}',
    caseSensitive: false,
  );

  /// Alias to provider key, filled lazily. Empty keys are never cached, so a
  /// key saved later in the same session is picked up without a cache drop.
  static final Map<String, String> _keyCache = {};

  /// True when [url] contains at least one supported placeholder.
  static bool hasPlaceholder(String url) =>
      _placeholderPattern.hasMatch(url);

  /// Returns [url] with supported placeholders replaced by the saved key of the
  /// matching Debrid provider. A placeholder whose key is not configured is left
  /// in place, so a misconfigured addon fails visibly instead of silently
  /// querying the wrong endpoint. Never throws.
  static Future<String> resolve(String url) async {
    if (!hasPlaceholder(url)) return url;

    var resolved = url;
    for (final match in _placeholderPattern.allMatches(url)) {
      final alias = match.group(1)!.toLowerCase();
      final raw = match.group(0)!;
      try {
        final key = await _keyForAlias(alias);
        if (key.isEmpty) continue;
        resolved = resolved.replaceAll(raw, key);
      } catch (_) {
        // Leave the placeholder in place on any lookup failure.
      }
    }
    return resolved;
  }

  /// Drops cached keys. Call whenever Debrid settings change so a rotated key
  /// takes effect on the next request.
  static void clearCache() {
    _keyCache.clear();
  }

  /// Returns the trimmed key for [alias], or an empty string when unconfigured
  /// or unsupported.
  static Future<String> _keyForAlias(String alias) async {
    switch (alias) {
      case 'realdebrid':
        return _cachedKey('realdebrid', () => RealDebridService().getToken());
      case 'torbox':
        return _cachedKey('torbox', () => TorBoxService().getKey());
      case 'alldebrid':
        return _cachedKey('alldebrid', () => AllDebridService().getKey());
      case 'premiumize':
        return _cachedKey('premiumize', () => PremiumizeService().getKey());
      case 'debridlink':
        return _cachedKey('debridlink', () => DebridLinkService().getKey());
      case 'debrid':
        final service = await DebridService().getSelectedService();
        switch (service) {
          case 'Real-Debrid':
            return _keyForAlias('realdebrid');
          case 'TorBox':
            return _keyForAlias('torbox');
          case 'AllDebrid':
            return _keyForAlias('alldebrid');
          case 'Premiumize':
            return _keyForAlias('premiumize');
          case 'Debrid-Link':
            return _keyForAlias('debridlink');
          default:
            return '';
        }
      default:
        return '';
    }
  }

  static Future<String> _cachedKey(
    String alias,
    Future<String?> Function() read,
  ) async {
    final cached = _keyCache[alias];
    if (cached != null) return cached;

    final key = (await read())?.trim() ?? '';
    if (key.isNotEmpty) {
      _keyCache[alias] = key;
    }
    return key;
  }
}
