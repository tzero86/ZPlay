import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/iptv/iptv_models.dart';

/// Verified portal store.
class IptvStore {
  static const _key = 'pt_iptv_verified_portals';
  static const _favorites = StringSetStore('pt_iptv_favorite_portal_keys');

  static Future<List<VerifiedPortal>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        return VerifiedPortal(
          portal: IptvPortal(
            url: o['url'] as String? ?? '',
            username: o['username'] as String? ?? '',
            password: o['password'] as String? ?? '',
            source: o['source'] as String? ?? '',
          ),
          name: o['name'] as String? ?? '',
          expiry: o['expiry'] as String? ?? '',
          maxConnections: o['max'] as String? ?? '1',
          activeConnections: o['active'] as String? ?? '0',
        );
      }).toList();
    } catch (e) {
      debugPrint('IptvStore.load failed: $e');
      return [];
    }
  }

  static Future<void> save(List<VerifiedPortal> list) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = list
        .map((v) => {
              'url': v.portal.url,
              'username': v.portal.username,
              'password': v.portal.password,
              'source': v.portal.source,
              'name': v.name,
              'expiry': v.expiry,
              'max': v.maxConnections,
              'active': v.activeConnections,
            })
        .toList();
    await prefs.setString(_key, json.encode(arr));
  }

  static Future<Set<String>> loadFavorites() => _favorites.load();

  static Future<void> saveFavorites(Set<String> keys) => _favorites.save(keys);
}

/// A set of strings persisted as one [SharedPreferences] string list under a
/// key it builds from [keyPrefix] and the caller's id.
///
/// [IptvStore]'s portal favourites, the per-channel favourite URLs and the
/// per-portal favourite stream ids are the same read/write pair under three
/// key spellings, so the pair lives here once. The global portal set passes no
/// id; the two per-id sets pass the channel id and the portal key.
class StringSetStore {
  final String keyPrefix;
  const StringSetStore(this.keyPrefix);

  Future<Set<String>> load({String id = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('$keyPrefix$id') ?? const <String>[]).toSet();
  }

  Future<void> save(Set<String> values, {String id = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$keyPrefix$id', values.toList());
  }
}

/// Per-portal cache of "alive" live channel IDs.
class IptvAliveStore {
  static String _aliveKey(String k) => 'pt_iptv_alive_$k';

  /// How long an alive snapshot stays worth acting on.
  ///
  /// A portal can drop a fight feed and reshuffle its line-up between rounds,
  /// so last night's answer is not an answer: the Live page ranks and skips
  /// streams from this snapshot, and a snapshot that has aged out is treated
  /// as no information at all rather than as "everything is dead".
  static Duration get ttl => const Duration(minutes: 30);

  /// Snapshots already read in this session, so health ranking can consult the
  /// last probe synchronously instead of awaiting prefs on the UI thread.
  static final Map<String, AliveSnapshot> _cached = {};

  /// Last snapshot seen for [key], or null when this session has not loaded
  /// one. Writes and loads both refresh it, and [clear] drops it.
  static AliveSnapshot? cached(String key) => _cached[key];

  /// True while [snapshot] is inside the staleness window.
  static bool isFresh(AliveSnapshot? snapshot) =>
      isFreshSince(snapshot?.checkedAt);

  /// [isFresh] for callers that kept the timestamp on its own (the live browser
  /// holds `aliveCheckedAt` and the id set as separate fields).
  static bool isFreshSince(int? checkedAtMillis) {
    if (checkedAtMillis == null || checkedAtMillis <= 0) return false;
    // A timestamp in the future passes: it means the clock moved, not that the
    // probe is old, and the snapshot cannot be older than the run that wrote it.
    final ageMillis =
        DateTime.now().millisecondsSinceEpoch - checkedAtMillis;
    return ageMillis <= ttl.inMilliseconds;
  }

  static Future<AliveSnapshot?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aliveKey(key));
    if (raw == null) return null;
    try {
      final o = json.decode(raw) as Map<String, dynamic>;
      final ids = (o['ids'] as List).map((e) => e as String).toSet();
      final snapshot = AliveSnapshot(
        checkedAt: (o['at'] as num?)?.toInt() ?? 0,
        aliveIds: ids,
      );
      _cached[key] = snapshot;
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String key, AliveSnapshot snap) async {
    _cached[key] = snap;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _aliveKey(key),
      json.encode({'at': snap.checkedAt, 'ids': snap.aliveIds.toList()}),
    );
  }

  static Future<void> clear(String key) async {
    _cached.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_aliveKey(key));
  }
}

class AliveSnapshot {
  final int checkedAt;
  final Set<String> aliveIds;
  const AliveSnapshot({required this.checkedAt, required this.aliveIds});
}

/// Remembers stream URLs that failed to play, so the Live pages stop offering
/// them first and the player stops switching back to them.
///
/// The shape follows DebridRejectionStore: a prefs-backed map, a TTL on every
/// entry, and a [revision] one listener can watch. The TTL is minutes rather
/// than days because IPTV panels reshuffle their line-up within the hour - a
/// URL that failed while a card was being announced can be carrying the main
/// event later that same night - so a permanent blacklist would throw away the
/// stream the user asked for.
class IptvDeadUrlStore {
  IptvDeadUrlStore._internal();

  static final IptvDeadUrlStore instance = IptvDeadUrlStore._internal();

  /// Bumped on every change, so the Live page and the player can re-rank a hit
  /// list without polling the store.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  ValueListenable<int> get revision => _revision;

  static const String _deadUrlsKey = 'pt_iptv_dead_urls';

  /// How long a failed URL stays on the books.
  static Duration get ttl => const Duration(minutes: 30);

  final Map<String, _DeadUrl> _dead = <String, _DeadUrl>{};

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Loads the remembered failures, dropping the ones that have expired.
  Future<void> initialize() async {
    _dead.clear();
    var pruned = false;
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_deadUrlsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final now = DateTime.now();
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! Map) {
              pruned = true;
              continue;
            }
            final record = _DeadUrl.fromJson(value);
            final url = _normalize(entry.key.toString());
            if (record == null || url == null) {
              pruned = true;
              continue;
            }
            if (now.difference(record.at) > ttl) {
              pruned = true;
              continue;
            }
            _dead[url] = record;
          }
        }
      }
    } catch (e) {
      debugPrint('[IptvDeadUrlStore] failed to load dead urls: $e');
    }
    if (pruned) {
      await _persist();
    }
    _revision.value++;
  }

  /// True when this URL is known to have failed recently.
  bool isDead(String? url) => _lookup(url) != null;

  /// Records a playback failure. [reason] is stored alongside the timestamp so
  /// a stream that keeps coming back can be explained later; no behaviour reads
  /// its wording.
  Future<void> remember(String url, {String? reason}) async {
    final key = _normalize(url);
    if (key == null) return;
    _dead[key] = _DeadUrl(reason: reason ?? '', at: DateTime.now());
    _revision.value++;
    await _persist();
  }

  /// Clears one remembered failure, so the URL is offered normally again.
  Future<void> forget(String url) async {
    final key = _normalize(url);
    if (key == null) return;
    if (_dead.remove(key) == null) return;
    _revision.value++;
    await _persist();
  }

  _DeadUrl? _lookup(String? url) {
    final key = _normalize(url);
    if (key == null) return null;
    final record = _dead[key];
    if (record == null) return null;
    if (DateTime.now().difference(record.at) > ttl) return null;
    return record;
  }

  /// URLs are trimmed but not case-folded: a panel's path and query are
  /// case-sensitive, and the same stream reaches the player spelled the same
  /// way every time.
  String? _normalize(String? url) {
    final key = url?.trim();
    if (key == null || key.isEmpty) return null;
    return key;
  }

  Future<void> _persist() async {
    try {
      final prefs = await _prefs;
      final encoded = <String, dynamic>{
        for (final entry in _dead.entries) entry.key: entry.value.toJson(),
      };
      await prefs.setString(_deadUrlsKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[IptvDeadUrlStore] failed to save dead urls: $e');
    }
  }
}

/// One remembered playback failure.
class _DeadUrl {
  final String reason;
  final DateTime at;

  const _DeadUrl({required this.reason, required this.at});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'reason': reason,
        'at': at.toIso8601String(),
      };

  static _DeadUrl? fromJson(Map<dynamic, dynamic> json) {
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    if (at == null) return null;
    return _DeadUrl(reason: json['reason']?.toString() ?? '', at: at);
  }
}

/// Per-HardcodedChannel persisted alive stream hits.
///
/// The rows are [ChannelHit]s - the cache only exists so a channel's verified
/// streams survive a restart, and the model owns the shape they are written in.
class IptvChannelResultsStore {
  static String _key(String channelId) => 'pt_iptv_ch_$channelId';

  static Future<List<ChannelHit>> load(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(channelId));
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr
          .map((e) => ChannelHit.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String channelId, List<ChannelHit> hits) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = hits.map((h) => h.toJson()).toList();
    await prefs.setString(_key(channelId), json.encode(arr));
  }
}

/// Per-HardcodedChannel set of favorited stream URLs (pinned to top).
class IptvChannelFavoritesStore {
  static const _store = StringSetStore('pt_iptv_chfav_');

  static Future<Set<String>> load(String channelId) =>
      _store.load(id: channelId);

  static Future<void> save(String channelId, Set<String> urls) =>
      _store.save(urls, id: channelId);
}

/// Per-Portal (or per-M3U playlist) set of favorited stream IDs.
class IptvPortalFavoritesStore {
  static const _store = StringSetStore('pt_iptv_portalfav_');

  static Future<Set<String>> load(String key) => _store.load(id: key);

  static Future<void> save(String key, Set<String> ids) =>
      _store.save(ids, id: key);
}

/// Custom quick channels store (user-added channels).
class IptvQuickChannelStore {
  static const String _key = 'pt_iptv_quick_channels';

  static Future<List<QuickChannel>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        return QuickChannel.fromJson(o);
      }).toList();
    } catch (e) {
      debugPrint('IptvQuickChannelStore.load failed: $e');
      return [];
    }
  }

  static Future<void> save(List<QuickChannel> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = channels.map((c) => c.toJson()).toList();
    await prefs.setString(_key, json.encode(arr));
  }

  static Future<void> add(QuickChannel channel) async {
    final list = await load();
    list.add(channel);
    await save(list);
  }

  static Future<void> remove(String id) async {
    final list = await load();
    list.removeWhere((c) => c.id == id);
    await save(list);
  }
}

/// Persisted state for a single MultiNutz cell.
class MultiNutzCellState {
  final int index;
  final String? channelName;
  final String? streamUrl;
  final double volume;
  final bool isMuted;
  final bool wasPlaying;

  const MultiNutzCellState({
    required this.index,
    this.channelName,
    this.streamUrl,
    this.volume = 0.5,
    this.isMuted = true,
    this.wasPlaying = false,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'channelName': channelName,
        'streamUrl': streamUrl,
        'volume': volume,
        'isMuted': isMuted,
        'wasPlaying': wasPlaying,
      };

  factory MultiNutzCellState.fromJson(Map<String, dynamic> o) =>
      MultiNutzCellState(
        index: o['index'] as int? ?? 0,
        channelName: o['channelName'] as String?,
        streamUrl: o['streamUrl'] as String?,
        volume: (o['volume'] as num?)?.toDouble() ?? 0.5,
        isMuted: o['isMuted'] as bool? ?? true,
        wasPlaying: o['wasPlaying'] as bool? ?? false,
      );
}

/// Persistent session store for the MultiNutz multi-window page.
/// Saves each cell's stream URL, name, volume, mute state and play state
/// so the user can leave the tab and return to find their streams still loaded.
class MultiNutzSessionStore {
  static const String _key = 'pt_multinutz_session';
  static const int maxCells = 6;

  static Future<List<MultiNutzCellState>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr
          .map((e) => MultiNutzCellState.fromJson(e as Map<String, dynamic>))
          .where((s) => s.streamUrl != null && s.streamUrl!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('MultiNutzSessionStore.load failed: $e');
      return [];
    }
  }

  static Future<void> save(List<MultiNutzCellState> states) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = states.map((s) => s.toJson()).toList();
    await prefs.setString(_key, json.encode(arr));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

