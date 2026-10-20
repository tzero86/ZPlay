/// Preference keys whose values are credentials.
///
/// These are the keys [SecureStore] keeps in the platform keystore. The
/// registry also drives backup redaction: a profile export must never carry a
/// value whose contents grant access to somebody's account.
abstract final class SecretKeys {
  static const String traktAccessToken = 'trakt_access_token';
  static const String traktRefreshToken = 'trakt_refresh_token';
  static const String simklAccessToken = 'simkl_access_token';
  static const String tmdbApiKey = 'tmdb_api_key';

  static const String realDebridToken = 'rd_access_token';
  static const String allDebridApiKey = 'alldebrid_api_key';
  static const String premiumizeApiKey = 'premiumize_api_key';
  static const String debridLinkApiKey = 'debridlink_api_key';
  static const String torboxApiKey = 'torbox_api_key';

  /// Qobuz's generated session token, and the endpoint/manifest URL that
  /// embeds it in the path.
  static const String qobuzEclipseToken = 'qobuz_eclipse_token';
  static const String qobuzEclipseEndpoint = 'qobuz_eclipse_endpoint';
  static const String qobuzEclipseManifestUrl = 'qobuz_eclipse_manifest_url';

  /// Prefix of the `ServiceCredential` registry's preference keys.
  static const String serviceCredentialPrefix = 'service_key_';

  static const Set<String> values = <String>{
    traktAccessToken,
    traktRefreshToken,
    simklAccessToken,
    tmdbApiKey,
    realDebridToken,
    allDebridApiKey,
    premiumizeApiKey,
    debridLinkApiKey,
    torboxApiKey,
    qobuzEclipseToken,
    qobuzEclipseEndpoint,
    qobuzEclipseManifestUrl,
  };

  /// Whether [prefKey] names a credential rather than ordinary settings.
  static bool isSecret(String prefKey) =>
      values.contains(prefKey) || prefKey.startsWith(serviceCredentialPrefix);
}
