import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'env_service.dart';
import 'legacy_upstream_credentials.dart';

/// A third-party credential an integration needs. The user can supply one in
/// Settings, a private build can inject one with `--dart-define`, and whatever
/// is left unresolved falls back to the inherited upstream value.
enum ServiceCredential {
  wyzie,
  audiobookSearch,
  audiobookService,
  paper2audio,
  vidgod,
  xdownloader,
  // Trakt and Simkl are the same shape of dependency as the five above - an
  // OAuth app that has to be registered with somebody - but they were left out
  // of this enum, which is why Trakt could not be paired at all on a build
  // without a `.env`: the device flow rejected an empty `client_id` and the page
  // reported only that the pairing code could not be requested.
  trakt,
  traktSecret,
}

/// Which rung of the ladder the value in use came from, for the Settings status
/// line.
enum CredentialSource { user, buildTime, inherited, none }

abstract final class ServiceCredentials {
  static const String _prefsPrefix = 'service_key_';

  static SharedPreferences? _prefs;
  static bool _hydrating = false;

  static final Map<ServiceCredential, ValueNotifier<String>> _notifiers = {
    for (final credential in ServiceCredential.values)
      credential: _PersistedServiceCredential(credential, ''),
  };

  /// Human label, the Settings row title and the UI hint share this.
  static String labelFor(ServiceCredential credential) {
    switch (credential) {
      case ServiceCredential.wyzie:
        return 'Wyzie Subtitles';
      case ServiceCredential.audiobookSearch:
        return 'Audionest Search';
      case ServiceCredential.audiobookService:
        return 'Audionest Service';
      case ServiceCredential.paper2audio:
        return 'Paper2Audio';
      case ServiceCredential.vidgod:
        return 'VidGod Cache';
      case ServiceCredential.xdownloader:
        return 'Films365 Downloader';
      case ServiceCredential.trakt:
        return 'Trakt.tv Client ID';
      case ServiceCredential.traktSecret:
        return 'Trakt.tv Client Secret';
    }
  }

  /// Where the user obtains their own value, e.g. 'wyzie.ru'. Shown in Settings.
  /// For the credentials nobody can obtain, it states why instead.
  static String sourceHintFor(ServiceCredential credential) {
    switch (credential) {
      case ServiceCredential.wyzie:
        return 'Free key at store.wyzie.io/redeem';
      case ServiceCredential.audiobookSearch:
      case ServiceCredential.audiobookService:
      case ServiceCredential.paper2audio:
      case ServiceCredential.vidgod:
      case ServiceCredential.xdownloader:
        return 'A credential for a third-party service that did not issue it '
            'to ZPlay. Leave blank unless you have your own.';
      case ServiceCredential.trakt:
        return 'Create a free app at app.trakt.tv/settings/apps/api/new and copy '
            'its Client ID. Without this, Trakt cannot be paired at all.';
      case ServiceCredential.traktSecret:
        return 'The Client Secret from the same app. Optional: Trakt has '
            'deprecated the secret for user sign-in, so a build without one '
            'still pairs.';
    }
  }

  /// True when a user can realistically obtain their own value. Only the
  /// credentials backed by a public signup page qualify; the rest are
  /// upstream private backends where a field exists only so the value can be
  /// replaced at build time or blanked deliberately.
  static bool isUserObtainable(ServiceCredential credential) {
    switch (credential) {
      case ServiceCredential.wyzie:
        return true;
      // Registering a Trakt app is a public, free signup - the same bar as the
      // Wyzie key - so the pair belongs on the editable side of the page.
      case ServiceCredential.trakt:
      case ServiceCredential.traktSecret:
        return true;
      case ServiceCredential.audiobookSearch:
      case ServiceCredential.audiobookService:
      case ServiceCredential.paper2audio:
      case ServiceCredential.vidgod:
      case ServiceCredential.xdownloader:
        return false;
    }
  }

  /// dart-define or .env name, e.g. 'WYZIE_API_KEY'.
  static String defineNameFor(ServiceCredential credential) {
    switch (credential) {
      case ServiceCredential.wyzie:
        return 'WYZIE_API_KEY';
      case ServiceCredential.audiobookSearch:
        return 'AUDIOBOOK_SEARCH_KEY';
      case ServiceCredential.audiobookService:
        return 'AUDIOBOOK_SERVICE_KEY';
      case ServiceCredential.paper2audio:
        return 'PAPER2AUDIO_KEY';
      case ServiceCredential.vidgod:
        return 'VIDGOD_TOKEN';
      case ServiceCredential.xdownloader:
        return 'XDOWNLOADER_TOKEN';
      case ServiceCredential.trakt:
        return 'TRAKT_CLIENT_ID';
      case ServiceCredential.traktSecret:
        return 'TRAKT_CLIENT_SECRET';
    }
  }

  /// user value -> build-time value -> inherited fallback (may be empty).
  static String value(ServiceCredential credential) => _resolve(credential).$2;

  /// Which rung of the ladder supplied [value].
  static CredentialSource sourceFor(ServiceCredential credential) =>
      _resolve(credential).$1;

  static (CredentialSource, String) _resolve(ServiceCredential credential) {
    final fromUser = notifier(credential).value.trim();
    if (fromUser.isNotEmpty) return (CredentialSource.user, fromUser);
    final fromBuild = _buildTimeValue(credential);
    if (fromBuild.isNotEmpty) return (CredentialSource.buildTime, fromBuild);
    final inherited = legacyUpstreamCredentialValues[credential] ?? '';
    if (inherited.isNotEmpty) return (CredentialSource.inherited, inherited);
    return (CredentialSource.none, '');
  }

  static bool isUserProvided(ServiceCredential credential) =>
      notifier(credential).value.trim().isNotEmpty;

  static bool isConfigured(ServiceCredential credential) =>
      value(credential).isNotEmpty;

  static ValueNotifier<String> notifier(ServiceCredential credential) =>
      _notifiers[credential]!;

  static Future<void> save(ServiceCredential credential, String raw) async {
    final next = raw.trim();
    await _write(credential, next);
    _hydrating = true;
    notifier(credential).value = next;
    _hydrating = false;
  }

  static Future<void> clear(ServiceCredential credential) async {
    await _write(credential, '');
    _hydrating = true;
    notifier(credential).value = '';
    _hydrating = false;
  }

  /// The read currently in flight, so a caller that arrives while one is
  /// running waits on it instead of starting a second one. Two interleaved
  /// reads would fight over [_hydrating], and the one that finishes first
  /// would leave the other's assignments writing every credential back to
  /// storage.
  static Future<void>? _reading;

  static Future<void> initialize() =>
      _reading ??= _read().whenComplete(() => _reading = null);

  static Future<void> _read() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _hydrating = true;
      for (final credential in ServiceCredential.values) {
        final stored = _prefs?.getString(_prefsKeyFor(credential)) ?? '';
        notifier(credential).value = stored;
      }
      _hydrating = false;
    } catch (e) {
      _hydrating = false;
      debugPrint('[ServiceCredentials] Error initializing: $e');
    }
  }

  /// Re-reads the stored credentials into the notifiers.
  ///
  /// [initialize] reads them once, at startup. A profile import writes the
  /// store underneath a running app, and without this the notifiers keep
  /// serving the pre-import values: Settings reports the keys the export
  /// carried as unset, and every consumer of [value] uses the old ones until
  /// the app is restarted.
  static Future<void> reload() async {
    // Let the startup read land first, so the values the import just wrote are
    // the last ones applied.
    await _reading;
    await initialize();
  }

  static Future<void> _write(ServiceCredential credential, String next) async {
    try {
      if (next.isEmpty) {
        await _prefs?.remove(_prefsKeyFor(credential));
      } else {
        await _prefs?.setString(_prefsKeyFor(credential), next);
      }
    } catch (e) {
      debugPrint('[ServiceCredentials] Error saving ${labelFor(credential)}: $e');
    }
  }

  static String _prefsKeyFor(ServiceCredential credential) =>
      '$_prefsPrefix${_nameFor(credential)}';

  static String _nameFor(ServiceCredential credential) {
    switch (credential) {
      case ServiceCredential.wyzie:
        return 'wyzie';
      case ServiceCredential.audiobookSearch:
        return 'audiobook_search';
      case ServiceCredential.audiobookService:
        return 'audiobook_service';
      case ServiceCredential.paper2audio:
        return 'paper2audio';
      case ServiceCredential.vidgod:
        return 'vidgod';
      case ServiceCredential.xdownloader:
        return 'xdownloader';
      case ServiceCredential.trakt:
        return 'trakt';
      case ServiceCredential.traktSecret:
        return 'trakt_secret';
    }
  }

  /// Stands in for the compile-time define in tests, which cannot set one.
  @visibleForTesting
  static final Map<ServiceCredential, String> buildTimeOverridesForTesting = {};

  static String _buildTimeValue(ServiceCredential credential) {
    final override = buildTimeOverridesForTesting[credential];
    if (override != null) return override;
    switch (credential) {
      case ServiceCredential.wyzie:
        return EnvService.wyzieApiKey;
      case ServiceCredential.audiobookSearch:
        return EnvService.audiobookSearchKey;
      case ServiceCredential.audiobookService:
        return EnvService.audiobookServiceKey;
      case ServiceCredential.paper2audio:
        return EnvService.paper2audioKey;
      case ServiceCredential.vidgod:
        return EnvService.vidgodToken;
      case ServiceCredential.xdownloader:
        return EnvService.xdownloaderToken;
      case ServiceCredential.trakt:
        return EnvService.traktClientId;
      case ServiceCredential.traktSecret:
        return EnvService.traktClientSecret;
    }
  }
}

/// A credential that persists itself on assignment. The hydration path used by
/// [ServiceCredentials.initialize] writes the field without a round trip back
/// to storage.
class _PersistedServiceCredential extends ValueNotifier<String> {
  _PersistedServiceCredential(this.credential, super.initialValue);

  final ServiceCredential credential;

  @override
  set value(String next) {
    super.value = next;
    if (!ServiceCredentials._hydrating) {
      unawaited(ServiceCredentials._write(credential, next));
    }
  }
}
