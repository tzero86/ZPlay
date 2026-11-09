import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/stream/stream_model.dart';

enum BuiltinProvidersMode {
  defaultMode,
  customMode,
}

class BuiltinProviderMeta {
  final String id;
  final String name;
  final String description;

  const BuiltinProviderMeta({
    required this.id,
    required this.name,
    this.description = 'Direct HTTP & HLS stream provider',
  });
}

class BuiltinProvidersSettingsService extends ChangeNotifier {
  BuiltinProvidersSettingsService._internal();
  static final BuiltinProvidersSettingsService instance =
      BuiltinProvidersSettingsService._internal();

  static const String _prefModeKey = 'builtin_providers_mode';
  static const String _prefOrderKey = 'builtin_providers_custom_order';
  static const String _prefDisabledKey = 'builtin_providers_disabled_ids';

  /// Master list of all 46 ZPlayHTTP providers in standard default order.
  static const List<BuiltinProviderMeta> defaultProviders = [
    BuiltinProviderMeta(id: 'a111477', name: '111477', description: 'Stremio-based multi-resolution HTTP stream scraper'),
    BuiltinProviderMeta(id: 'vadapav', name: 'Vadapav', description: 'Direct high-speed HTTP media storage scraper'),
    BuiltinProviderMeta(id: 'fourkhdhub', name: '4KHDHub', description: '4K & HD direct stream extractor'),
    BuiltinProviderMeta(id: 'xdownloader', name: 'XDownloader', description: 'Fast multi-source stream downloader'),
    BuiltinProviderMeta(id: 'videasy', name: 'Videasy', description: 'Videasy multi-CDN encrypted HLS scraper'),
    BuiltinProviderMeta(id: 'vidsrc', name: 'VidSrc', description: 'VidSrc streaming network resolver'),
    BuiltinProviderMeta(id: 'multiembed', name: 'MultiEmbed', description: '2Embed multi-host stream aggregator'),
    BuiltinProviderMeta(id: 'vidcore', name: 'VidCore', description: 'Multi-source HD video core extractor'),
    BuiltinProviderMeta(id: 'flystream', name: 'FlyStream', description: 'Ultra-fast HLS streaming network'),
    BuiltinProviderMeta(id: 'movienight', name: 'MovieNight', description: 'MovieNight multi-server HLS streams'),
    BuiltinProviderMeta(id: 'downloadeverything', name: 'DownloadEverything', description: 'Direct media download & stream extractor'),
    BuiltinProviderMeta(id: 'movy', name: 'Movy', description: 'Direct encrypted MP4/HLS source provider'),
    BuiltinProviderMeta(id: 'vuflix', name: 'Vuflix', description: 'Fast cloud HLS stream resolver'),
    BuiltinProviderMeta(id: 'rivestream', name: 'RiveStream', description: 'Rive multi-server direct stream provider'),
    BuiltinProviderMeta(id: 'cinejoy', name: 'Cinejoy', description: 'Cinejoy multi-CDN video source provider'),
    BuiltinProviderMeta(id: 'dulo', name: 'Dulo', description: 'Dulo high-speed direct stream network'),
    BuiltinProviderMeta(id: 'vidup', name: 'VidUp', description: 'VidUp cloud video hosting scraper'),
    BuiltinProviderMeta(id: 'flaxmovies', name: 'FlaxMovies', description: 'FlaxMovies multi-CDN direct streams'),
    BuiltinProviderMeta(id: 'vidgod', name: 'VidGod', description: 'Multi-server cloud video streams'),
    BuiltinProviderMeta(id: 'vidfast', name: 'VidFast', description: 'Low-latency direct streaming provider'),
    BuiltinProviderMeta(id: 'peestream', name: 'PeeStream', description: 'Fast cloud video source provider'),
    BuiltinProviderMeta(id: 'lookmovie', name: 'LookMovie', description: 'LookMovie direct multi-quality streams'),
    BuiltinProviderMeta(id: 'hexa', name: 'Hexa', description: 'Hexa multi-host video extractor'),
    BuiltinProviderMeta(id: 'bcine', name: 'Bcine', description: 'Bcine direct master HLS provider'),
    BuiltinProviderMeta(id: 'mapple', name: 'Mapple', description: 'Mapple fast streaming provider'),
    BuiltinProviderMeta(id: 'nova', name: 'Nova', description: 'Nova multi-server stream extractor'),
    BuiltinProviderMeta(id: 'megasource', name: 'MegaSource', description: 'MegaSource multi-CDN video network'),
    BuiltinProviderMeta(id: 'purstream', name: 'Purstream', description: 'Purstream direct video stream resolver'),
    BuiltinProviderMeta(id: 'vidapi', name: 'VidApi', description: 'VidApi direct video source extractor'),
    BuiltinProviderMeta(id: 'vidrock', name: 'VidRock', description: 'VidRock cloud video provider'),
    BuiltinProviderMeta(id: 'vidvault', name: 'VidVault', description: 'VidVault secure streaming network'),
    BuiltinProviderMeta(id: 'vidzee', name: 'VidZee', description: 'VidZee high-speed video provider'),
    BuiltinProviderMeta(id: 'cinesrc', name: 'CineSrc', description: 'CineSrc direct master HLS with bright67 subtitles'),
    BuiltinProviderMeta(id: 'cinesu', name: 'CineSu', description: 'CineSu direct video stream extractor'),
    BuiltinProviderMeta(id: 'frame', name: 'Frame', description: 'Frame multi-resolution stream provider'),
    BuiltinProviderMeta(id: 'fsharetv', name: 'FshareTV', description: 'FshareTV cloud streaming network'),
    BuiltinProviderMeta(id: 'fsonic', name: 'FSonic', description: 'FSonic direct cloud video scraper'),
    BuiltinProviderMeta(id: 'fsonline', name: 'FSOnline', description: 'FSOnline multi-host stream resolver'),
    BuiltinProviderMeta(id: 'kisskh', name: 'KissKH', description: 'KissKH Asian drama & anime streaming provider'),
    BuiltinProviderMeta(id: 'lmscript', name: 'LMScript', description: 'LMScript video source extractor'),
    BuiltinProviderMeta(id: 'meowtv', name: 'MeowTV', description: 'MeowTV direct streaming network'),
    BuiltinProviderMeta(id: 'vidlink', name: 'VidLink', description: 'VidLink fast multi-CDN stream provider'),
    BuiltinProviderMeta(id: 'vixsrc', name: 'VixSrc', description: 'VixSrc direct master streaming extractor'),
    BuiltinProviderMeta(id: 'xpass', name: 'XPass', description: 'XPass multi-server video scraper'),
    BuiltinProviderMeta(id: 'zxcstream', name: 'ZxcStream', description: 'ZxcStream multi-source direct provider'),
    BuiltinProviderMeta(id: 'hindmoviez', name: 'HindMoviez', description: 'Bollywood, Hindi Dual-Audio & Hollywood direct streams'),
  ];

  BuiltinProvidersMode _mode = BuiltinProvidersMode.defaultMode;
  List<String> _customOrder = [];
  Set<String> _disabledIds = {};
  bool _initialized = false;

  BuiltinProvidersMode get mode => _mode;
  bool get isCustom => _mode == BuiltinProvidersMode.customMode;
  List<String> get customOrder => List.unmodifiable(_customOrder);
  Set<String> get disabledIds => Set.unmodifiable(_disabledIds);

  /// Initializes the service and loads persisted preferences.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_prefModeKey);
      if (modeStr == 'custom') {
        _mode = BuiltinProvidersMode.customMode;
      } else {
        _mode = BuiltinProvidersMode.defaultMode;
      }

      final savedOrder = prefs.getStringList(_prefOrderKey);
      if (savedOrder != null && savedOrder.isNotEmpty) {
        _customOrder = List.from(savedOrder);
        // Ensure any newly added providers exist in the order list
        for (final p in defaultProviders) {
          if (!_customOrder.contains(p.id)) {
            _customOrder.add(p.id);
          }
        }
      } else {
        _customOrder = defaultProviders.map((p) => p.id).toList();
      }

      final savedDisabled = prefs.getStringList(_prefDisabledKey);
      if (savedDisabled != null) {
        _disabledIds = savedDisabled.toSet();
        // If all or virtually all providers are disabled, it was almost certainly an accidental "Disable All"
        // or broken preference state that shuts down ZPlayHTTP entirely. Restore all enabled.
        if (_disabledIds.length >= defaultProviders.length - 1) {
          debugPrint('[BuiltinProvidersSettingsService] Detected all or almost all providers disabled in custom mode (${_disabledIds.length}/${defaultProviders.length}). Resetting to enabled to prevent scraping outage.');
          _disabledIds.clear();
          _mode = BuiltinProvidersMode.defaultMode;
          await prefs.setString(_prefModeKey, 'default');
          await prefs.setStringList(_prefDisabledKey, []);
        }
      } else {
        _disabledIds = {};
      }
    } catch (e) {
      debugPrint('[BuiltinProvidersSettingsService] init error: $e');
      _customOrder = defaultProviders.map((p) => p.id).toList();
      _disabledIds = {};
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Whether a provider is currently active/enabled.
  bool isProviderEnabled(String id) {
    if (!isCustom) return true; // In default mode, all are enabled
    return !_disabledIds.contains(id.toLowerCase());
  }

  /// Returns the priority rank index of a provider (0 = highest priority).
  int getProviderRank(String id) {
    final lower = id.toLowerCase();
    final idx = _customOrder.indexOf(lower);
    if (idx != -1) return idx;
    // Fallback: check by default list index
    final defaultIdx = defaultProviders.indexWhere((p) => p.id == lower);
    return defaultIdx != -1 ? defaultIdx : 999;
  }

  /// Returns the metadata for a given provider id: never null, because an id this
  /// build does not know gets a generated entry so the row still renders.
  BuiltinProviderMeta getMeta(String id) {
    final lower = id.toLowerCase();
    return defaultProviders.firstWhere(
      (p) => p.id == lower,
      orElse: () => BuiltinProviderMeta(
        id: lower,
        name: id,
        description: 'Direct HTTP streaming provider',
      ),
    );
  }

  /// Returns the ordered list of providers for custom mode.
  List<BuiltinProviderMeta> getOrderedProviders() {
    final list = <BuiltinProviderMeta>[];
    for (final id in _customOrder) {
      list.add(getMeta(id));
    }
    // Append any default providers missing from customOrder
    for (final p in defaultProviders) {
      if (!list.any((item) => item.id == p.id)) {
        list.add(p);
      }
    }
    return list;
  }

  /// Switch mode between Default and Custom.
  Future<void> setMode(BuiltinProvidersMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefModeKey,
        newMode == BuiltinProvidersMode.customMode ? 'custom' : 'default',
      );
    } catch (_) {}
  }

  /// Toggle a provider's enabled state.
  Future<void> toggleProvider(String id, bool enabled) async {
    final lower = id.toLowerCase();
    if (enabled) {
      _disabledIds.remove(lower);
    } else {
      _disabledIds.add(lower);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefDisabledKey, _disabledIds.toList());
    } catch (_) {}
  }

  /// Reorder providers via drag-and-drop.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _customOrder.length) return;
    if (newIndex < 0) newIndex = 0;
    if (newIndex > _customOrder.length) newIndex = _customOrder.length;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _customOrder.removeAt(oldIndex);
    _customOrder.insert(newIndex, item);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefOrderKey, _customOrder);
    } catch (_) {}
  }

  /// Move a provider up or down by delta (-1 for up, +1 for down).
  Future<void> moveProvider(String id, int delta) async {
    final lower = id.toLowerCase();
    final index = _customOrder.indexOf(lower);
    if (index == -1) return;
    final newIndex = (index + delta).clamp(0, _customOrder.length - 1);
    if (newIndex == index) return;
    final item = _customOrder.removeAt(index);
    _customOrder.insert(newIndex, item);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefOrderKey, _customOrder);
    } catch (_) {}
  }

  /// Enable all providers.
  Future<void> enableAll() async {
    _disabledIds.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefDisabledKey, []);
    } catch (_) {}
  }

  /// Disable all providers.
  Future<void> disableAll() async {
    _disabledIds = defaultProviders.map((p) => p.id).toSet();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefDisabledKey, _disabledIds.toList());
    } catch (_) {}
  }

  /// Reset order and enabled state to default.
  Future<void> resetToDefault() async {
    _customOrder = defaultProviders.map((p) => p.id).toList();
    _disabledIds.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefOrderKey, _customOrder);
      await prefs.setStringList(_prefDisabledKey, []);
    } catch (_) {}
  }

  /// Tries to identify which provider produced a stream from its title, description, or url.
  static String detectProviderId(StreamSource source) {
    if (source.providerId != null && source.providerId!.isNotEmpty) {
      return source.providerId!.toLowerCase();
    }

    final combined = '${source.title ?? ''} ${source.description ?? ''} ${source.name ?? ''}'.toLowerCase();

    for (final p in defaultProviders) {
      if (combined.contains(p.id)) return p.id;
      if (combined.contains(p.name.toLowerCase())) return p.id;
    }

    return 'unknown';
  }
}
