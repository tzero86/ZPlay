import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/cloudstream/cloudstream_repo.dart';
import '../../models/cloudstream/cloudstream_source.dart';
import '../../models/stream/stream_model.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/movie/video.dart';
import 'runtime/cloudstream_downloader.dart';
import 'runtime/cloudstream_paths.dart';
import 'runtime/cloudstream_dispatcher.dart';
import 'stream/cloudstream_stream_provider.dart';

class CloudStreamManager {
  static final CloudStreamManager instance = CloudStreamManager._();
  CloudStreamManager._();

  static const String _reposKey = 'cloudstream_repos_v1';
  static const String _installedKey = 'cloudstream_installed_v1';
  static const String defaultPhisherRepoUrl =
      'https://raw.githubusercontent.com/phisher98/cloudstream-extensions-phisher/refs/heads/builds/repo.json';
  static const String _phisherRepoSeededKey = 'cs_phisher_repo_seeded_v1';

  final List<CloudStreamRepo> _repos = [];
  final List<CloudStreamSource> _installed = [];
  final List<CloudStreamSource> _available = [];
  final List<Map<String, dynamic>> _loadedProviders = [];

  bool _initialized = false;
  bool get isInitialized => _initialized;

  List<CloudStreamRepo> get repos => List.unmodifiable(_repos);
  List<CloudStreamSource> get installedExtensions {
    final seen = <String>{};
    final res = <CloudStreamSource>[];
    for (final e in _installed) {
      final k = (e.internalName != null && e.internalName!.isNotEmpty)
          ? e.internalName!.toLowerCase().trim()
          : e.name.toLowerCase().trim();
      if (!seen.contains(k)) {
        seen.add(k);
        res.add(e);
      }
    }
    return List.unmodifiable(res);
  }
  List<CloudStreamSource> get activeExtensions => _installed.where((e) => e.enabled).toList();
  List<CloudStreamSource> get availableExtensions => List.unmodifiable(_available);
  List<Map<String, dynamic>> get loadedProviders => List.unmodifiable(_loadedProviders);

  static bool get isSupported => !Platform.isIOS;

  /// The runtime dispatcher. Tests substitute a fake because the real one
  /// launches a Java sidecar process; production always uses the singleton.
  @visibleForTesting
  CloudStreamDispatcher dispatcher = CloudStreamDispatcher.instance;

  /// Registers an enabled extension without downloading a runtime and
  /// launching the sidecar, so the search fan-out can be driven on its own.
  @visibleForTesting
  void installExtensionForTest(CloudStreamSource source) {
    _installed.add(source);
  }

  final ValueNotifier<bool> isBusy = ValueNotifier(false);
  final ValueNotifier<String> busyMessage = ValueNotifier('');

  /// Sentinel the search timeout resolves to, so the timed-out extension is not
  /// also counted by the no-response branch further down.
  static final Object _searchTimedOut = Object();

  Future<void> initialize() async {
    if (_initialized) return;
    if (!isSupported) {
      debugPrint('[CloudStreamManager] CloudStream extensions are not supported on this platform (iOS).');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 1. Load repos
    final storedRepos = prefs.getStringList(_reposKey);
    if (storedRepos != null) {
      for (final r in storedRepos) {
        try {
          _repos.add(CloudStreamRepo.decode(r));
        } catch (_) {}
      }
    }

    // 2. Load installed
    final storedInstalled = prefs.getStringList(_installedKey);
    if (storedInstalled != null) {
      for (final s in storedInstalled) {
        try {
          _installed.add(CloudStreamSource.decode(s));
        } catch (_) {}
      }
    }

    // Auto-discover pre-existing compiled jars/cs3s in extensions folder
    try {
      final extDir = await CloudStreamPaths.instance.extensionsDir;
      if (await extDir.exists()) {
        final files = extDir.listSync().whereType<File>();
        bool addedAny = false;
        for (final f in files) {
          final ext = p.extension(f.path).toLowerCase();
          if (ext == '.jar' || ext == '.cs3') {
            final base = p.basenameWithoutExtension(f.path);
            if (!_installed.any((e) =>
                e.name.toLowerCase() == base.toLowerCase() ||
                (e.internalName != null && e.internalName!.toLowerCase() == base.toLowerCase()))) {
              _installed.add(CloudStreamSource(
                id: base,
                name: base,
                internalName: base,
                enabled: true,
              ));
              addedAny = true;
            }
          }
        }
        if (addedAny) {
          await _saveInstalled();
        }
      }
    } catch (_) {}

    // 3. Deduplicate installed extensions
    await _deduplicateInstalled();

    // 4. If runtime is ready on desktop, launch sidecar and register extensions
    final isReady = await CloudStreamDownloader.instance.checkIsReady();
    if (isReady) {
      try {
        await _connectRuntime();
      } catch (e) {
        debugPrint('[CloudStreamManager] Error connecting runtime on startup: $e');
      }
    }

    // 5. Seed default repository (Phisher) if runtime is ready or on Android
    try {
      await seedDefaultRepoIfEligible();
    } catch (e) {
      debugPrint('[CloudStreamManager] Error checking default repo seed on startup: $e');
    }

    _initialized = true;
    unawaited(fetchAvailableExtensions().catchError((e) {
      debugPrint('[CloudStreamManager] Error reconciling extensions on startup: $e');
      return <CloudStreamSource>[];
    }));
  }

  /// Automatically seeds the default Phisher repository built-in if:
  /// - On Android (no engine download required), OR desktop runtime is ready.
  /// - It hasn't been seeded previously (respects user uninstallation so it doesn't re-appear).
  Future<void> seedDefaultRepoIfEligible() async {
    if (!isSupported) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadySeeded = prefs.getBool(_phisherRepoSeededKey) ?? false;
    if (alreadySeeded) return;

    final isReady = Platform.isAndroid || await CloudStreamDownloader.instance.checkIsReady();
    if (!isReady) return;

    final normalizedPhisher = normalizeRepoUrl(defaultPhisherRepoUrl).toLowerCase();
    final alreadyInList = _repos.any((r) => normalizeRepoUrl(r.url).toLowerCase() == normalizedPhisher);

    if (!alreadyInList) {
      try {
        await addRepo(defaultPhisherRepoUrl);
        debugPrint('[CloudStreamManager] Successfully seeded default Phisher repository.');
      } catch (e) {
        debugPrint('[CloudStreamManager] Note on seeding default Phisher repo: $e');
      }
    }

    await prefs.setBool(_phisherRepoSeededKey, true);
  }

  Future<void> _deduplicateInstalled() async {
    if (_installed.isEmpty) return;
    final seen = <String>{};
    final unique = <CloudStreamSource>[];
    for (final s in _installed) {
      final key = (s.internalName != null && s.internalName!.isNotEmpty)
          ? s.internalName!.toLowerCase().trim()
          : s.name.toLowerCase().trim();
      final stripped = s.name.toLowerCase().replaceAll(RegExp(r'provider|plugin|scraper'), '').trim();

      final isDup = seen.contains(key) || (stripped.isNotEmpty && seen.contains(stripped));
      if (!isDup) {
        seen.add(key);
        if (stripped.isNotEmpty) seen.add(stripped);
        unique.add(s);
      } else {
        final idx = unique.indexWhere((u) {
          final uKey = (u.internalName != null && u.internalName!.isNotEmpty)
              ? u.internalName!.toLowerCase().trim()
              : u.name.toLowerCase().trim();
          final uStripped = u.name.toLowerCase().replaceAll(RegExp(r'provider|plugin|scraper'), '').trim();
          return uKey == key || (stripped.isNotEmpty && uStripped == stripped);
        });
        if (idx != -1 && (s.pluginUrl != null && s.pluginUrl!.isNotEmpty) && (unique[idx].pluginUrl == null || unique[idx].pluginUrl!.isEmpty)) {
          unique[idx] = s;
        }
      }
    }
    if (unique.length != _installed.length) {
      debugPrint('[CloudStreamManager] Deduplicated installed plugins: ${_installed.length} -> ${unique.length}');
      _installed.clear();
      _installed.addAll(unique);
      await _saveInstalled();
    }
  }

  Future<void> _connectRuntime() async {
    final extDir = await CloudStreamPaths.instance.extensionsDir;
    await CloudStreamDispatcher.instance.initialize();
    final res = await CloudStreamDispatcher.instance.loadExtensions(extDir.path);
    _loadedProviders.clear();
    if (res is List) {
      for (final item in res) {
        if (item is Map) {
          _loadedProviders.add(Map<String, dynamic>.from(item));
        }
      }
      debugPrint('[CloudStreamManager] Connected runtime: ${_loadedProviders.length} active providers registered.');

      // Reconcile installed extensions with loaded providers
      bool modified = false;
      for (final ext in _installed) {
        final matched = findLoadedProvider(ext);
        if (matched != null && matched['id'] != null) {
          final realId = matched['id'].toString();
          if (ext.internalName != realId) {
            debugPrint('[CloudStreamManager] Reconciled installed source ${ext.name} (${ext.internalName}) -> $realId');
            ext.internalName = realId;
            modified = true;
          }
        }
      }
      if (modified) {
        await _saveInstalled();
      }
      await _deduplicateInstalled();
    }
  }

  /// Resolves all registered sidecar providers for an extension source,
  /// matching by API ID, display name, class name, or stripped Provider/Plugin suffixes.
  List<Map<String, dynamic>> findLoadedProviders(CloudStreamSource ext) {
    if (_loadedProviders.isEmpty) return [];
    final extNameClean = ext.name.toLowerCase().trim();
    final extInternalClean = (ext.internalName ?? '').toLowerCase().trim();
    final strippedExtName = extNameClean.replaceAll(RegExp(r'provider|plugin|scraper'), '').trim();
    final sanitizedName = ext.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final sanitizedStripped = strippedExtName.replaceAll(RegExp(r'[^a-z0-9]'), '');

    final results = <Map<String, dynamic>>[];

    for (final p in _loadedProviders) {
      final pId = (p['id'] ?? '').toString().toLowerCase().trim();
      final pName = (p['name'] ?? '').toString().toLowerCase().trim();
      final pClass = (p['className'] ?? '').toString().toLowerCase().trim();

      bool matches = false;

      // 1. Exact ID or Name match
      if (pId == extInternalClean || pId == extNameClean || pName == extNameClean) {
        matches = true;
      } else if (pId == 'cs_$sanitizedName' || pId == 'cs_$sanitizedStripped') {
        matches = true;
      } else if (strippedExtName.isNotEmpty && (pName == strippedExtName || pId == 'cs_$strippedExtName')) {
        matches = true;
      } else if (extNameClean.startsWith(pName) || (pName.length >= 4 && extNameClean.contains(pName))) {
        matches = true;
      } else if (strippedExtName.isNotEmpty && (pName.contains(strippedExtName) || strippedExtName.contains(pName))) {
        matches = true;
      } else if (pClass.endsWith('.$extNameClean') ||
          pClass.endsWith('.$sanitizedName') ||
          (sanitizedStripped.isNotEmpty && pClass.contains(sanitizedStripped))) {
        matches = true;
      }

      if (matches && !results.any((r) => r['id'] == p['id'])) {
        results.add(p);
      }
    }

    return results;
  }

  /// Resolves the primary loaded provider map for an extension source.
  Map<String, dynamic>? findLoadedProvider(CloudStreamSource ext) {
    final list = findLoadedProviders(ext);
    return list.isNotEmpty ? list.first : null;
  }

  // ── Repositories ──────────────────────────────────────────────────────────

  static String normalizeRepoUrl(String input) {
    var url = input.trim();
    if ((url.startsWith('"') && url.endsWith('"')) ||
        (url.startsWith("'") && url.endsWith("'"))) {
      url = url.substring(1, url.length - 1).trim();
    }

    final schemePrefixes = ['cloudstreamrepo://', 'cloudstream://', 'cs3://'];
    for (final prefix in schemePrefixes) {
      if (url.toLowerCase().startsWith(prefix)) {
        url = url.substring(prefix.length).trim();
        break;
      }
    }

    if (url.toLowerCase().startsWith('http://') || url.toLowerCase().startsWith('https://')) {
      return url;
    }

    return 'https://$url';
  }

  Future<void> addRepo(String rawUrl) async {
    final url = normalizeRepoUrl(rawUrl);
    if (url.isEmpty) return;

    if (_repos.any((r) => r.url.toLowerCase() == url.toLowerCase())) {
      throw Exception('Repository already added.');
    }

    isBusy.value = true;
    busyMessage.value = 'Fetching repository...';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch repository (HTTP ${response.statusCode})');
      }

      final body = response.body.trim();
      final dynamic decoded = jsonDecode(body);

      // Infer repo name
      String repoName = 'CloudStream Repo';
      if (decoded is Map<String, dynamic>) {
        final manifestName = decoded['name']?.toString().trim();
        if (manifestName != null && manifestName.isNotEmpty) {
          repoName = manifestName;
        }
      }

      if (repoName == 'CloudStream Repo') {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          final meaningful = uri.pathSegments
              .where((s) => s != 'raw' && s != 'main' && s != 'master' && s != 'refs' && s != 'heads' && s != 'builds' && !s.endsWith('.json'))
              .toList();
          if (meaningful.isNotEmpty) {
            repoName = meaningful.last;
          }
        }
      }

      _repos.add(CloudStreamRepo(url: url, name: repoName));
      await _saveRepos();
      await fetchAvailableExtensions();
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> removeRepo(String url) async {
    _repos.removeWhere((r) => r.url == url);
    await _saveRepos();
    await fetchAvailableExtensions();
  }

  bool isRepoInstalled(String rawUrl) {
    final normalized = normalizeRepoUrl(rawUrl).toLowerCase();
    return _repos.any((r) => normalizeRepoUrl(r.url).toLowerCase() == normalized);
  }

  Future<void> _saveRepos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_reposKey, _repos.map((r) => r.encode()).toList());
  }

  Future<void> _saveInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_installedKey, _installed.map((i) => i.encode()).toList());
  }

  // ── Available Extensions ──────────────────────────────────────────────────

  Future<List<CloudStreamSource>> fetchAvailableExtensions() async {
    final List<CloudStreamSource> collected = [];

    for (final repo in _repos) {
      try {
        final res = await http.get(Uri.parse(repo.url)).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final dynamic data = jsonDecode(res.body);
          if (data is List) {
            _parsePluginList(data, repo.name, collected);
          } else if (data is Map) {
            // Case 1: repo.json format with pluginLists
            if (data['pluginLists'] is List) {
              final lists = (data['pluginLists'] as List).map((e) => e.toString()).toList();
              for (final listUrl in lists) {
                try {
                  final normalizedListUrl = normalizeRepoUrl(listUrl);
                  final subRes = await http.get(Uri.parse(normalizedListUrl)).timeout(const Duration(seconds: 12));
                  if (subRes.statusCode == 200) {
                    final dynamic subData = jsonDecode(subRes.body);
                    if (subData is List) {
                      _parsePluginList(subData, repo.name, collected);
                    }
                  }
                } catch (e) {
                  debugPrint('[CloudStreamManager] Error fetching pluginList $listUrl: $e');
                }
              }
            }
            // Case 2: repo containing 'plugins' list directly
            if (data['plugins'] is List) {
              _parsePluginList(data['plugins'] as List, repo.name, collected);
            }
          }
        }
      } catch (e) {
        debugPrint('[CloudStreamManager] Error reading repo ${repo.url}: $e');
      }
    }

    _available.clear();
    _available.addAll(collected);
    await _reconcileInstalledWithAvailable();
    return List.unmodifiable(_available);
  }

  /// Automatically backfills and synchronizes official manifest metadata (tvTypes,
  /// description, iconUrl, lang, isNsfw) from repository manifests into installed extensions.
  Future<void> _reconcileInstalledWithAvailable() async {
    if (_available.isEmpty || _installed.isEmpty) return;
    bool updated = false;

    for (final inst in _installed) {
      final match = _available.firstWhere(
        (a) =>
            a.id.toLowerCase() == inst.id.toLowerCase() ||
            a.name.toLowerCase() == inst.name.toLowerCase() ||
            (inst.internalName != null &&
                a.internalName != null &&
                a.internalName!.toLowerCase() == inst.internalName!.toLowerCase()) ||
            (inst.internalName != null &&
                a.name.toLowerCase() == inst.internalName!.toLowerCase()) ||
            (a.internalName != null &&
                a.internalName!.toLowerCase() == inst.name.toLowerCase()),
        orElse: () => inst,
      );

      if (!identical(match, inst)) {
        if ((inst.tvTypes == null || inst.tvTypes!.isEmpty) &&
            match.tvTypes != null &&
            match.tvTypes!.isNotEmpty) {
          inst.tvTypes = List<String>.from(match.tvTypes!);
          updated = true;
        }
      }
    }

    if (updated) {
      await _saveInstalled();
      debugPrint('[CloudStreamManager] Reconciled ${_installed.length} installed extensions with official repository metadata.');
    }
  }

  void _parsePluginList(List data, String repoTag, List<CloudStreamSource> target) {
    for (final item in data) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        map['repo'] = repoTag;
        target.add(CloudStreamSource.fromJson(map));
      }
    }
  }

  // ── Install / Uninstall / Toggle ──────────────────────────────────────────

  Future<void> toggleExtension(String id, bool enabled) async {
    for (final ext in _installed) {
      if (ext.id == id || ext.internalName == id || ext.name == id) {
        ext.enabled = enabled;
        break;
      }
    }
    await _saveInstalled();
  }

  Future<void> installExtension(CloudStreamSource source) async {
    isBusy.value = true;
    busyMessage.value = 'Preparing runtime...';

    try {
      final ready = await CloudStreamDownloader.instance.checkIsReady();
      if (!ready) {
        busyMessage.value = 'Setting up CloudStream runtime...';
        await CloudStreamDownloader.instance.setupRuntime();
        await seedDefaultRepoIfEligible();
      }

      final extDir = await CloudStreamPaths.instance.extensionsDir;
      await _installSingleInternal(source, extDir, reconnect: true);
      busyMessage.value = '${source.name} installed successfully!';
    } finally {
      isBusy.value = false;
    }
  }

  /// Installs multiple extensions in batch without restarting the runtime sidecar repeatedly.
  Future<int> installExtensions(
    List<CloudStreamSource> sources, {
    void Function(int current, int total, String name)? onProgress,
  }) async {
    if (sources.isEmpty) return 0;

    isBusy.value = true;
    busyMessage.value = 'Preparing CloudStream runtime...';

    int installedCount = 0;
    try {
      final ready = await CloudStreamDownloader.instance.checkIsReady();
      if (!ready) {
        busyMessage.value = 'Setting up CloudStream runtime...';
        await CloudStreamDownloader.instance.setupRuntime();
        await seedDefaultRepoIfEligible();
      }

      final extDir = await CloudStreamPaths.instance.extensionsDir;
      final total = sources.length;

      for (int i = 0; i < total; i++) {
        final src = sources[i];
        final current = i + 1;
        busyMessage.value = 'Installing ($current/$total): ${src.name}...';
        onProgress?.call(current, total, src.name);

        try {
          await _installSingleInternal(src, extDir, reconnect: false);
          installedCount++;
        } catch (e) {
          debugPrint('[CloudStreamManager] Failed to install ${src.name}: $e');
        }
      }

      busyMessage.value = 'Connecting installed extensions...';
      await _connectRuntime();
      await _saveInstalled();
      busyMessage.value = 'Installed $installedCount extension${installedCount == 1 ? '' : 's'} successfully!';
    } finally {
      isBusy.value = false;
    }
    return installedCount;
  }

  /// Installs all available plugins from a given repository URL.
  Future<int> installAllFromRepo(
    String repoUrl, {
    void Function(int current, int total, String name)? onProgress,
  }) async {
    final normalized = normalizeRepoUrl(repoUrl);
    if (_available.isEmpty) {
      await fetchAvailableExtensions();
    }

    final repoObj = _repos.firstWhere(
      (r) => normalizeRepoUrl(r.url).toLowerCase() == normalized.toLowerCase(),
      orElse: () => CloudStreamRepo(url: repoUrl, name: ''),
    );

    final repoPlugins = _available.where((p) {
      final repoTagMatch = repoObj.name.isNotEmpty && p.repo?.toLowerCase() == repoObj.name.toLowerCase();
      final urlMatch = p.pluginUrl != null && p.pluginUrl!.toLowerCase().contains(normalized.toLowerCase());
      return repoTagMatch || urlMatch;
    }).toList();

    final targetList = repoPlugins.isNotEmpty ? repoPlugins : _available;
    return installExtensions(targetList, onProgress: onProgress);
  }

  Future<void> _installSingleInternal(
    CloudStreamSource source,
    Directory extDir, {
    bool reconnect = true,
  }) async {
    final pluginUrl = source.pluginUrl;
    if (pluginUrl == null || pluginUrl.isEmpty) {
      throw Exception('Extension does not contain a valid .cs3 download URL.');
    }

    final extName = source.internalName ?? source.name;
    final tempDir = Directory(p.join(extDir.path, 'temp_$extName'));
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await tempDir.create(recursive: true);

    try {
      busyMessage.value = 'Downloading ${source.name}...';
      final cs3Res = await http.get(Uri.parse(pluginUrl));
      if (cs3Res.statusCode != 200) {
        throw Exception('Failed to download .cs3 (HTTP ${cs3Res.statusCode})');
      }

      if (Platform.isAndroid) {
        final targetPath = p.join(extDir.path, '$extName.cs3');
        await File(targetPath).writeAsBytes(cs3Res.bodyBytes);
        if (reconnect) {
          await CloudStreamDispatcher.instance.initialize();
          await CloudStreamDispatcher.instance.loadExtensions(extDir.path);
        }
      } else {
        busyMessage.value = 'Extracting DEX bytecode for ${source.name}...';
        final cs3Path = p.join(tempDir.path, 'plugin.cs3');
        await File(cs3Path).writeAsBytes(cs3Res.bodyBytes);

        final cs3Bytes = await File(cs3Path).readAsBytes();
        final cs3Archive = ZipDecoder().decodeBytes(cs3Bytes);

        ArchiveFile? dexFile;
        ArchiveFile? metadataFile;
        bool isBridgeManifest = false;

        for (final file in cs3Archive.files) {
          if (file.name == 'classes.dex') dexFile = file;
          if (file.name == 'plugins.manifest') {
            metadataFile = file;
            isBridgeManifest = false;
          }
          if (file.name == 'manifest.json' && metadataFile == null) {
            metadataFile = file;
            isBridgeManifest = true;
          }
        }

        if (dexFile == null || metadataFile == null) {
          throw Exception('.cs3 archive is missing classes.dex or manifest.');
        }

        final dexPath = p.join(tempDir.path, 'classes.dex');
        await File(dexPath).writeAsBytes(dexFile.content as List<int>);

        final finalJarPath = p.join(extDir.path, '$extName.jar');

        busyMessage.value = 'Compiling ${source.name} for Desktop...';
        await _runDex2Jar(dexPath, finalJarPath);

        // Inject manifest.json into output jar
        final jarBytes = await File(finalJarPath).readAsBytes();
        final jarArchive = ZipDecoder().decodeBytes(jarBytes);
        final finalArchive = Archive();

        for (final f in jarArchive.files) {
          if (f.name != 'manifest.json') finalArchive.addFile(f);
        }

        final Map<String, dynamic> bridgeJson;
        if (isBridgeManifest) {
          bridgeJson = jsonDecode(utf8.decode(metadataFile.content as List<int>));
        } else {
          final csJson = jsonDecode(utf8.decode(metadataFile.content as List<int>));
          bridgeJson = {
            'pluginClassName': csJson['pluginClassName'] ?? '',
            'name': source.name,
            'version': source.version ?? '1.0.0',
            'authors': (csJson['authors'] as List?)?.join(', ') ?? 'Unknown',
            'requires': 1,
          };
        }

        final encoded = utf8.encode(jsonEncode(bridgeJson));
        finalArchive.addFile(ArchiveFile('manifest.json', encoded.length, encoded));

        final patchedJarBytes = ZipEncoder().encode(finalArchive);
        await File(finalJarPath).writeAsBytes(patchedJarBytes);

        if (reconnect) {
          busyMessage.value = 'Registering with CloudStream engine...';
          await _connectRuntime();
        }
      }

      // Add to installed
      _installed.removeWhere((e) =>
          e.name == source.name ||
          (source.internalName != null && e.internalName == source.internalName));
      _installed.add(source);
      await _saveInstalled();
    } finally {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> uninstallExtension(CloudStreamSource source) async {
    final extDir = await CloudStreamPaths.instance.extensionsDir;

    final candidates = <String>{
      source.name,
      if (source.internalName != null) source.internalName!,
    };

    for (final baseName in candidates) {
      final jarFile = File(p.join(extDir.path, '$baseName.jar'));
      if (await jarFile.exists()) {
        try { await jarFile.delete(); } catch (_) {}
      }

      final cs3File = File(p.join(extDir.path, '$baseName.cs3'));
      if (await cs3File.exists()) {
        try { await cs3File.delete(); } catch (_) {}
      }
    }

    try {
      await CloudStreamDispatcher.instance.unloadExtension(source.internalName ?? source.name);
    } catch (_) {}

    _installed.removeWhere((e) =>
        e.name == source.name ||
        (source.internalName != null && e.internalName == source.internalName));
    _loadedProviders.removeWhere((p) {
      final pId = (p['id'] ?? '').toString().toLowerCase();
      final pName = (p['name'] ?? '').toString().toLowerCase();
      return pId == (source.internalName ?? '').toLowerCase() ||
          pName == source.name.toLowerCase();
    });
    await _saveInstalled();
  }

  Future<void> uninstallExtensions(List<CloudStreamSource> sources) async {
    if (sources.isEmpty) return;
    isBusy.value = true;
    busyMessage.value = 'Removing ${sources.length} plugins...';
    try {
      final extDir = await CloudStreamPaths.instance.extensionsDir;
      for (final source in sources) {
        final candidates = <String>{
          source.name,
          if (source.internalName != null) source.internalName!,
        };

        for (final baseName in candidates) {
          final jarFile = File(p.join(extDir.path, '$baseName.jar'));
          if (await jarFile.exists()) {
            try { await jarFile.delete(); } catch (_) {}
          }

          final cs3File = File(p.join(extDir.path, '$baseName.cs3'));
          if (await cs3File.exists()) {
            try { await cs3File.delete(); } catch (_) {}
          }
        }

        try {
          await CloudStreamDispatcher.instance.unloadExtension(source.internalName ?? source.name);
        } catch (_) {}

        _installed.removeWhere((e) =>
            e.name == source.name ||
            (source.internalName != null && e.internalName == source.internalName));
        _loadedProviders.removeWhere((p) {
          final pId = (p['id'] ?? '').toString().toLowerCase();
          final pName = (p['name'] ?? '').toString().toLowerCase();
          return pId == (source.internalName ?? '').toLowerCase() ||
              pName == source.name.toLowerCase();
        });
      }
      await _saveInstalled();
    } finally {
      isBusy.value = false;
      busyMessage.value = '';
    }
  }

  Future<void> _runDex2Jar(String dexPath, String outJarPath) async {
    final paths = CloudStreamPaths.instance;
    final dex2jarPath = await paths.dex2jarPath;
    final javaPath = await paths.javaExecutablePath;

    if (javaPath == null) {
      throw Exception('Java executable not found. Cannot run dex2jar.');
    }

    final javaBinDir = p.dirname(javaPath);
    final env = Map<String, String>.from(Platform.environment);
    final pathKey = env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    final separator = Platform.isWindows ? ';' : ':';

    env[pathKey] = '$javaBinDir$separator${env[pathKey] ?? ''}';
    env['JAVA_HOME'] = p.dirname(javaBinDir);

    final process = await Process.run(
      dex2jarPath,
      ['--force', dexPath, '-o', outJarPath],
      environment: env,
      runInShell: Platform.isWindows,
    );

    if (process.exitCode != 0) {
      throw Exception('dex2jar compilation failed: ${process.stderr}\n${process.stdout}');
    }
  }

  // ── Scraper & Stream Integration ─────────────────────────────────────────

  int _scrapeSessionId = 0;
  final List<StreamSubscription> _activeScrapeSubscriptions = [];

  /// Cancels all ongoing CloudStream scraping jobs immediately.
  void cancelActiveScrapes() {
    _scrapeSessionId++;
    if (_activeScrapeSubscriptions.isNotEmpty) {
      debugPrint('[CloudStreamManager] Cancelling ${_activeScrapeSubscriptions.length} active extension scrapes (session: $_scrapeSessionId)...');
      final subs = List<StreamSubscription>.from(_activeScrapeSubscriptions);
      _activeScrapeSubscriptions.clear();
      for (final sub in subs) {
        sub.cancel();
      }
    }

    CloudStreamDispatcher.instance.cancelOngoingRequests();
  }

  /// Scrapes streams across all active CloudStream extensions matching the content profile.
  Stream<StreamSource> scrapeStreams({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    List<String>? genres,
    List<String>? alternativeTitles,
  }) {
    final controller = StreamController<StreamSource>();
    if (!isSupported) {
      controller.close();
      return controller.stream;
    }
    final active = activeExtensions;

    if (active.isEmpty) {
      controller.close();
      return controller.stream;
    }

    // Build list of provider targets: (sourceId, providerDisplayName, isAnimeProvider)
    final List<_ProviderTarget> targets = [];

    for (final ext in active) {
      if (!ext.supportsType(type, genres: genres)) continue;

      final sanitizedName = ext.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      // Find matches in _loadedProviders using resilient fuzzy/className matcher
      final matched = findLoadedProviders(ext);

      if (matched.isNotEmpty) {
        for (final m in matched) {
          final sourceId = m['id']?.toString() ?? (m['internalName']?.toString() ?? 'cs_$sanitizedName');
          final providerName = m['name']?.toString() ?? ext.name;
          targets.add(_ProviderTarget(
            sourceId: sourceId,
            providerName: providerName,
            isAnimeProvider: ext.supportsAnime,
          ));
        }
      } else {
        // Fallback if not mapped yet
        final fallbackId = ext.internalName ?? 'cs_$sanitizedName';
        targets.add(_ProviderTarget(
          sourceId: fallbackId,
          providerName: ext.name,
          isAnimeProvider: ext.supportsAnime,
        ));
        if (ext.internalName != null && ext.internalName != ext.name) {
          targets.add(_ProviderTarget(
            sourceId: ext.internalName!,
            providerName: ext.name,
            isAnimeProvider: ext.supportsAnime,
          ));
        }
        final stripped = ext.name.replaceAll(RegExp(r'Provider|Plugin|Scraper', caseSensitive: false), '').trim();
        if (stripped.isNotEmpty && stripped != ext.name) {
          targets.add(_ProviderTarget(
            sourceId: stripped,
            providerName: ext.name,
            isAnimeProvider: ext.supportsAnime,
          ));
        }
      }
    }

    // Deduplicate targets by sourceId to prevent redundant queries
    final seenTargetIds = <String>{};
    targets.removeWhere((t) => !seenTargetIds.add(t.sourceId.toLowerCase()));

    if (targets.isEmpty) {
      debugPrint('[CloudStreamManager] scrapeStreams: 0 targets found for type "$type" (active extensions: ${active.length})');
      controller.close();
      return controller.stream;
    }

    final currentSession = ++_scrapeSessionId;
    final List<StreamSubscription> sessionSubs = [];

    controller.onCancel = () {
      for (final sub in sessionSubs) {
        sub.cancel();
      }
      _activeScrapeSubscriptions.removeWhere((s) => sessionSubs.contains(s));
      sessionSubs.clear();
      CloudStreamDispatcher.instance.cancelOngoingRequests();
    };

    debugPrint('[CloudStreamManager] scrapeStreams: Scraping "$title" (type: $type, S${season ?? "-"}:E${episode ?? "-"}, year: $year) across ${targets.length} targets: [${targets.map((t) => t.providerName).join(", ")}] (session: $currentSession)');

    int pending = targets.length;

    for (final target in targets) {
      final sub = _scrapeSingleExtension(
        sourceId: target.sourceId,
        providerName: target.providerName,
        isAnimeProvider: target.isAnimeProvider,
        type: type,
        title: title,
        year: year,
        season: season,
        episode: episode,
        alternativeTitles: alternativeTitles,
        sessionId: currentSession,
      ).listen(
        (src) {
          if (!controller.isClosed && currentSession == _scrapeSessionId) {
            controller.add(src);
          }
        },
        onError: (err) {
          debugPrint('[CloudStreamManager] [${target.providerName}] Stream error: $err');
        },
        onDone: () {
          pending--;
          if (pending <= 0 && !controller.isClosed) {
            controller.close();
          }
        },
      );

      sessionSubs.add(sub);
      _activeScrapeSubscriptions.add(sub);
    }

    return controller.stream;
  }

  Stream<StreamSource> _scrapeSingleExtension({
    required String sourceId,
    required String providerName,
    required bool isAnimeProvider,
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    List<String>? alternativeTitles,
    int? sessionId,
  }) async* {
    if (sessionId != null && sessionId != _scrapeSessionId) return;
    try {
      final isAnime = type == 'anime' || isAnimeProvider;
      final isSeries = type == 'series' || type == 'tv' || type == 'show' || isAnime;
      final queries = <String>[
        title,
        if (alternativeTitles != null) ...alternativeTitles,
      ];

      // For series/anime with season > 1, add season suffix queries
      if (season != null && season > 1) {
        queries.add('$title Season $season');
        queries.add('$title S$season');
      }

      final uniqueQueries = queries.where((q) => q.trim().isNotEmpty).toSet().toList();
      Map<String, dynamic>? bestMatch;

      for (final query in uniqueQueries) {
        if (sessionId != null && sessionId != _scrapeSessionId) return;
        debugPrint('[CloudStreamManager] [$providerName] Searching for "$query"...');
        final searchResult = await CloudStreamDispatcher.instance.search(
          sourceId: sourceId,
          query: query,
        ).timeout(const Duration(seconds: 8), onTimeout: () => null);
        if (sessionId != null && sessionId != _scrapeSessionId) return;

        List? items;
        if (searchResult is List) {
          items = searchResult;
        } else if (searchResult is Map) {
          items = (searchResult['list'] ?? searchResult['results'] ?? searchResult['data']) as List?;
        } else if (searchResult is String && searchResult.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(searchResult);
            if (decoded is List) {
              items = decoded;
            } else if (decoded is Map) {
              items = (decoded['list'] ?? decoded['results'] ?? decoded['data']) as List?;
            }
          } catch (_) {}
        }
        if (items == null || items.isEmpty) {
          debugPrint('[CloudStreamManager] [$providerName] No items returned for "$query"');
          continue;
        }

        final cleanQuery = query.trim().toLowerCase();
        final cleanQueryAlpha = cleanQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');
        final cleanQueryNoThe = cleanQuery.startsWith('the ') ? cleanQuery.substring(4).trim() : cleanQuery;

        for (final item in items) {
          if (item is Map) {
            final itemMap = Map<String, dynamic>.from(item);
            final itTitle = (itemMap['title'] ?? itemMap['name'] ?? '').toString().trim().toLowerCase();
            final itTitleAlpha = itTitle.replaceAll(RegExp(r'[^a-z0-9]'), '');
            final itTitleNoThe = itTitle.startsWith('the ') ? itTitle.substring(4).trim() : itTitle;

            // For TV series, do NOT reject based on episode release year vs series debut year
            final itYear = itemMap['year'] is num
                ? (itemMap['year'] as num).toInt()
                : int.tryParse(itemMap['year']?.toString() ?? '');
            if (!isAnime && !isSeries && year != null && itYear != null && (itYear - year).abs() > 1) {
              continue;
            }

            // Exact or stripped alpha match
            if (itTitle == cleanQuery ||
                itTitleAlpha == cleanQueryAlpha ||
                itTitleNoThe == cleanQueryNoThe ||
                (itTitleAlpha.isNotEmpty && cleanQueryAlpha.isNotEmpty &&
                    (itTitleAlpha == cleanQueryAlpha ||
                        itTitleAlpha.startsWith(cleanQueryAlpha) ||
                        cleanQueryAlpha.startsWith(itTitleAlpha)))) {
              bestMatch = itemMap;
              break;
            }

            // Prefix match (e.g. "Obsession: Part 1" or "Attack on Titan Season 2")
            if (itTitle.startsWith('$cleanQuery ') ||
                itTitle.startsWith('$cleanQuery:') ||
                itTitle.startsWith('$cleanQuery -') ||
                itTitleNoThe.startsWith('$cleanQueryNoThe ') ||
                (isAnime && itTitleAlpha.startsWith(cleanQueryAlpha))) {
              bestMatch ??= itemMap;
            }
          }
        }

        if (bestMatch != null) break;
      }

      // If no valid title matched, DO NOT return random recommendations
      if (bestMatch == null) {
        debugPrint('[CloudStreamManager] [$providerName] No matching show found for "$title"');
        return;
      }

      final mediaUrl = bestMatch['url']?.toString();
      if (mediaUrl == null || mediaUrl.isEmpty) {
        debugPrint('[CloudStreamManager] [$providerName] Match has empty URL');
        return;
      }

      if (sessionId != null && sessionId != _scrapeSessionId) return;
      final matchTitle = bestMatch['title'] ?? bestMatch['name'] ?? title;
      debugPrint('[CloudStreamManager] [$providerName] Matched "$matchTitle". Fetching details...');

      // 2. Fetch media details
      final detailsRes = await CloudStreamDispatcher.instance.getDetail(
        sourceId: sourceId,
        url: mediaUrl,
      ).timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (sessionId != null && sessionId != _scrapeSessionId) return;

      final detailsMap = detailsRes is Map ? detailsRes : (detailsRes is String ? jsonDecode(detailsRes) : null);
      if (detailsMap == null) {
        debugPrint('[CloudStreamManager] [$providerName] Failed to parse details map');
        return;
      }

      String? targetEpisodeDataUrl;

      if (isSeries && episode != null) {
        final episodesList = (detailsMap['episodes'] as List?) ??
            (detailsMap['extraData'] is Map ? (detailsMap['extraData'] as Map)['episodes'] as List? : null);
        debugPrint('[CloudStreamManager] [$providerName] Detail has ${episodesList?.length ?? 0} episode(s). Matching S${season ?? 1}:E$episode...');

        if (episodesList != null && episodesList.isNotEmpty) {
          for (int i = 0; i < episodesList.length; i++) {
            final ep = episodesList[i];
            if (ep is Map) {
              final epNum = _extractEpisodeNumber(ep) ?? (episodesList.length == 1 ? 1 : null);
              final sNum = _extractSeasonNumber(ep);

              final seasonMatches = isAnime ||
                  season == null ||
                  (sNum != null && sNum == season) ||
                  (sNum == null && (season == 1 || episodesList.length <= 30));

              if (epNum == episode && seasonMatches) {
                targetEpisodeDataUrl = _extractEpisodeStreamUrl(ep);
                debugPrint('[CloudStreamManager] [$providerName] Matched S${sNum ?? season ?? 1}:E$epNum ("${ep['name'] ?? 'Episode $epNum'}") -> $targetEpisodeDataUrl');
                break;
              }
            }
          }
        }
      } else {
        // Movie
        final episodesList = detailsMap['episodes'] as List?;
        if (episodesList != null && episodesList.isNotEmpty && episodesList.first is Map) {
          targetEpisodeDataUrl = _extractEpisodeStreamUrl(episodesList.first as Map);
        }
        targetEpisodeDataUrl ??= detailsMap['dataUrl']?.toString() ??
            detailsMap['data']?.toString() ??
            (detailsMap['extraData'] is Map ? (detailsMap['extraData'] as Map)['url']?.toString() : null) ??
            mediaUrl;
      }

      if (targetEpisodeDataUrl == null || targetEpisodeDataUrl.isEmpty) {
        debugPrint('[CloudStreamManager] [$providerName] No episode dataUrl found for S${season ?? 1}:E${episode ?? 1}');
        return;
      }

      if (sessionId != null && sessionId != _scrapeSessionId) return;
      debugPrint('[CloudStreamManager] [$providerName] Resolving video streams for "$targetEpisodeDataUrl"...');

      // 3. Stream links
      await for (final linkData in CloudStreamDispatcher.instance.getVideoListStream(
        sourceId: sourceId,
        url: targetEpisodeDataUrl,
      )) {
        if (sessionId != null && sessionId != _scrapeSessionId) return;
        Map<String, dynamic>? dataMap;
        if (linkData is Map) {
          dataMap = Map<String, dynamic>.from(linkData);
        } else if (linkData is String && linkData.trim().startsWith('{')) {
          try {
            dataMap = Map<String, dynamic>.from(jsonDecode(linkData));
          } catch (_) {}
        }
        if (dataMap != null) {
          final source = CloudStreamStreamProvider.toStreamSource(
            dataMap,
            extensionName: providerName,
            mediaTitle: title,
          );
          if (source != null) {
            debugPrint('[CloudStreamManager] [$providerName] Yielded stream: ${source.name}');
            yield source;
          }
        }
      }
    } catch (e) {
      debugPrint('[CloudStreamManager] Error scraping $providerName ($sourceId): $e');
    }
  }

  static int? _parseNumber(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    final str = val.toString().trim().split('.').first;
    return int.tryParse(str);
  }

  static int? _extractEpisodeNumber(Map ep) {
    int? epNum = _parseNumber(ep['episodeNumber']) ??
        _parseNumber(ep['episode']) ??
        _parseNumber(ep['epNum']);
    if (epNum != null) return epNum;

    if (ep['extraData'] is Map) {
      final extra = ep['extraData'] as Map;
      epNum = _parseNumber(extra['episodeNumber']) ??
          _parseNumber(extra['episode']) ??
          _parseNumber(extra['epNum']);
      if (epNum != null) return epNum;
    }

    final name = (ep['name'] ?? ep['title'] ?? '').toString();
    final match = RegExp(r'\b(?:ep|episode|e)\s*0*(\d+)\b', caseSensitive: false).firstMatch(name);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    return null;
  }

  static int? _extractSeasonNumber(Map ep) {
    int? sNum = _parseNumber(ep['season']) ??
        _parseNumber(ep['seasonNumber']) ??
        _parseNumber(ep['season_number']);
    if (sNum != null) return sNum;

    if (ep['extraData'] is Map) {
      final extra = ep['extraData'] as Map;
      sNum = _parseNumber(extra['season']) ??
          _parseNumber(extra['seasonNumber']) ??
          _parseNumber(extra['season_number']);
      if (sNum != null) return sNum;
    }

    final name = (ep['name'] ?? ep['title'] ?? '').toString();
    final match = RegExp(r'\b(?:season|s)\s*0*(\d+)\b', caseSensitive: false).firstMatch(name);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    return null;
  }

  static String? _extractEpisodeStreamUrl(Map ep) {
    final dataUrl = ep['dataUrl']?.toString().trim();
    if (dataUrl != null && dataUrl.isNotEmpty) return dataUrl;

    final data = ep['data']?.toString().trim();
    if (data != null && data.isNotEmpty) return data;

    if (ep['extraData'] is Map) {
      final extraUrl = (ep['extraData'] as Map)['url']?.toString().trim();
      if (extraUrl != null && extraUrl.isNotEmpty) return extraUrl;
      final extraData = (ep['extraData'] as Map)['data']?.toString().trim();
      if (extraData != null && extraData.isNotEmpty) return extraData;
    }

    final rawUrl = ep['url']?.toString().trim();
    if (rawUrl != null && rawUrl.isNotEmpty) {
      return rawUrl;
    }

    return null;
  }

  /// Searches across all active CloudStream extensions and groups results by provider name.
  /// Optionally streams each provider's results via [onProviderResult] as soon as it arrives.
  /// [onSourceError] is called once per extension that could not answer, naming
  /// it. A sidecar runtime that has expired, a dispatcher that returns null and
  /// an extension that throws are all the same thing to the user: this source
  /// is gone. A response with an empty list is not, and stays a clean miss.
  Future<Map<String, List<Map<String, dynamic>>>> searchAcrossExtensions(
    String query, {
    int limitPerExtension = 15,
    void Function(String providerName, List<Map<String, dynamic>> items)? onProviderResult,
    void Function(String source, Object error)? onSourceError,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return {};

    final active = activeExtensions;
    if (active.isEmpty) return {};

    if (!Platform.isAndroid && _loadedProviders.isEmpty) {
      try {
        await _connectRuntime();
      } catch (_) {}
    }

    debugPrint('[CloudStreamManager] searchAcrossExtensions: "$cleanQuery" across ${active.length} extensions');
    final Map<String, List<Map<String, dynamic>>> results = {};

    final futures = active.map((ext) async {
      try {
        final sanitizedName = ext.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        String sourceId = ext.internalName ?? 'cs_$sanitizedName';

        final matched = findLoadedProvider(ext);
        if (matched != null && matched['id'] != null) {
          sourceId = matched['id'].toString();
        }

        // A null response here is a dead sidecar runtime, not an extension that
        // matched nothing, so it is reported rather than silently skipped.
        final res = await dispatcher.search(
          sourceId: sourceId,
          query: cleanQuery,
        ).timeout(
          const Duration(seconds: 6),
          // A timeout is reported here and resolves to nothing below: this
          // extension already has its one report, and falling through to the
          // null-response branch would blame it twice for a single fault.
          onTimeout: () {
            onSourceError?.call(
              ext.name,
              TimeoutException('CloudStream search timed out for ${ext.name}'),
            );
            return _searchTimedOut;
          },
        );

        if (identical(res, _searchTimedOut)) return;

        final map = res is Map ? res : (res is String ? jsonDecode(res) : null);
        if (map == null) {
          onSourceError?.call(
            ext.name,
            StateError('CloudStream dispatcher returned no response for ${ext.name}'),
          );
          return;
        }

        final list = map['list'] as List?;
        if (list == null || list.isEmpty) return;

        final items = <Map<String, dynamic>>[];
        for (final item in list.take(limitPerExtension)) {
          if (item is Map) {
            final it = Map<String, dynamic>.from(item);
            it['_sourceId'] = sourceId;
            it['_providerName'] = ext.name;
            items.add(it);
          }
        }

        if (items.isNotEmpty) {
          results[ext.name] = items;
          debugPrint('[CloudStreamManager] [${ext.name}] Search returned ${items.length} items');
          onProviderResult?.call(ext.name, items);
        }
      } catch (e) {
        debugPrint('[CloudStreamManager] Error searching ${ext.name}: $e');
        onSourceError?.call(ext.name, e);
      }
    });

    await Future.wait(futures);
    return results;
  }

  /// Fetches media details directly from a CloudStream extension and converts into a MovieDetail.
  Future<MovieDetail?> fetchCloudStreamDetail({
    required String sourceId,
    required String mediaUrl,
    String? fallbackTitle,
    String? fallbackPoster,
  }) async {
    try {
      debugPrint('[CloudStreamManager] fetchCloudStreamDetail: sourceId=$sourceId, url=$mediaUrl');
      final res = await CloudStreamDispatcher.instance.getDetail(
        sourceId: sourceId,
        url: mediaUrl,
      ).timeout(const Duration(seconds: 10), onTimeout: () => null);

      final map = res is Map ? Map<String, dynamic>.from(res) : (res is String ? jsonDecode(res) as Map<String, dynamic> : null);
      if (map == null) return null;

      final title = map['title']?.toString() ?? fallbackTitle ?? 'Unknown Title';
      final poster = map['cover']?.toString() ?? map['poster']?.toString() ?? fallbackPoster;
      final description = map['description']?.toString() ?? map['plot']?.toString();
      final year = map['year']?.toString();
      final genres = (map['genre'] as List?)?.map((e) => e.toString()).toList() ??
          (map['genres'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[];

      final cast = <String>[];
      final rawActors = (map['actors'] as List?) ??
          (map['extraData'] is Map ? (map['extraData'] as Map)['actors'] as List? : null);
      if (rawActors != null) {
        for (final act in rawActors) {
          if (act is Map && act['actor'] is Map) {
            final aName = (act['actor'] as Map)['name']?.toString();
            if (aName != null && aName.isNotEmpty) cast.add(aName);
          } else if (act is Map && act['name'] != null) {
            cast.add(act['name'].toString());
          } else if (act is String && act.isNotEmpty) {
            cast.add(act);
          }
        }
      }

      final rawEpisodes = (map['episodes'] as List?) ??
          (map['extraData'] is Map ? (map['extraData'] as Map)['episodes'] as List? : null);
      final List<Video> videos = [];

      if (rawEpisodes != null && rawEpisodes.isNotEmpty) {
        for (int i = 0; i < rawEpisodes.length; i++) {
          final ep = rawEpisodes[i];
          if (ep is Map) {
            final epNum = _extractEpisodeNumber(ep) ?? (i + 1);
            final sNum = _extractSeasonNumber(ep) ?? 1;
            final epName = ep['name']?.toString() ?? 'Episode $epNum';
            final epThumb = ep['thumbnail']?.toString() ??
                (ep['extraData'] is Map ? (ep['extraData'] as Map)['thumbnail']?.toString() : null) ??
                ep['posterUrl']?.toString();
            final epDesc = ep['description']?.toString() ?? ep['plot']?.toString();
            final targetDataUrl = _extractEpisodeStreamUrl(ep) ?? mediaUrl;

            videos.add(
              Video(
                id: 'cloudstream_ep:$sourceId:${Uri.encodeComponent(targetDataUrl)}:$sNum:$epNum',
                title: epName,
                season: sNum,
                episode: epNum,
                thumbnail: epThumb,
                overview: epDesc,
              ),
            );
          }
        }
      }

      final isSeries = videos.isNotEmpty &&
          (videos.length > 1 ||
              videos.first.episode != null ||
              map['type']?.toString().toLowerCase().contains('series') == true);

      // Check if syncData or tmdbId exists to augment metadata
      String? tmdbId;
      if (map['syncData'] is Map) {
        final syncData = map['syncData'] as Map;
        for (final val in syncData.values) {
          if (val is String && val.contains('Tmdb')) {
            try {
              final parsedSync = jsonDecode(val);
              if (parsedSync['Tmdb'] != null) {
                tmdbId = parsedSync['Tmdb'].toString();
                break;
              }
            } catch (_) {}
          }
        }
      }

      return MovieDetail(
        id: 'cloudstream:$sourceId:${Uri.encodeComponent(mediaUrl)}',
        type: isSeries ? 'series' : 'movie',
        name: title,
        poster: poster,
        background: poster,
        description: description,
        year: year,
        genres: genres,
        cast: cast,
        videos: videos,
        tmdbId: tmdbId,
      );
    } catch (e) {
      debugPrint('[CloudStreamManager] Error fetching detail ($sourceId): $e');
      return null;
    }
  }

  /// Directly streams links from a CloudStream episode dataUrl.
  Stream<StreamSource> resolveStreamsForDataUrl({
    required String sourceId,
    required String dataUrl,
    String? providerName,
    String? title,
  }) async* {
    debugPrint('[CloudStreamManager] resolveStreamsForDataUrl: sourceId=$sourceId, url=$dataUrl');
    final extName = providerName ?? sourceId.replaceFirst('cs_', '');
    try {
      await for (final linkData in CloudStreamDispatcher.instance.getVideoListStream(
        sourceId: sourceId,
        url: dataUrl,
      )) {
        if (linkData is Map) {
          final source = CloudStreamStreamProvider.toStreamSource(
            Map<String, dynamic>.from(linkData),
            extensionName: extName,
            mediaTitle: title,
          );
          if (source != null) {
            debugPrint('[CloudStreamManager] [$extName] Yielded stream: ${source.name}');
            yield source;
          }
        }
      }
    } catch (e) {
      debugPrint('[CloudStreamManager] Error resolving stream links ($sourceId): $e');
    }
  }
}

class _ProviderTarget {
  final String sourceId;
  final String providerName;
  final bool isAnimeProvider;

  const _ProviderTarget({
    required this.sourceId,
    required this.providerName,
    required this.isAnimeProvider,
  });
}

