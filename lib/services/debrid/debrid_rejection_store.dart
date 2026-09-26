import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers sources a Debrid provider refused, so the player can skip them and
/// show a short reason instead of retrying a torrent that will never work.
///
/// A refusal that cannot change on its own (a copyright claim, a virus flag, a
/// dead torrent) is stored as permanent. Anything softer, for example a magnet
/// that is still converting, expires after [_ttl] so the source gets another
/// chance later.
class DebridRejectionStore {
  DebridRejectionStore._internal();

  static final DebridRejectionStore instance = DebridRejectionStore._internal();

  /// Bumped on every change, so a single listener can rebuild a badge or a
  /// source list without polling the store.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const String _rejectionsKey = 'debrid_rejections';

  /// How long a non permanent refusal stays on the books.
  static const Duration _ttl = Duration(days: 14);

  final Map<String, _Rejection> _rejections = <String, _Rejection>{};

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Loads the stored refusals, dropping the ones that have expired.
  Future<void> initialize() async {
    _rejections.clear();
    var pruned = false;
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_rejectionsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final now = DateTime.now();
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! Map) continue;
            final rejection = _Rejection.fromJson(value);
            final hash = _normalize(entry.key.toString());
            if (rejection == null || hash == null) {
              pruned = true;
              continue;
            }
            if (!rejection.permanent && now.difference(rejection.at) > _ttl) {
              pruned = true;
              continue;
            }
            _rejections[hash] = rejection;
          }
        }
      }
    } catch (e) {
      debugPrint('[DebridRejectionStore] failed to load refusals: $e');
    }
    if (pruned) {
      await _persist();
    }
    revision.value++;
  }

  /// True when this source is known to be refused right now.
  bool isRejected(String? infoHash) {
    final rejection = _lookup(infoHash);
    return rejection != null;
  }

  /// Short reason for the badge, or null when nothing is remembered.
  String? reasonFor(String? infoHash) => _lookup(infoHash)?.reason;

  /// Records a refusal. [permanent] is for refusals that will not change on
  /// their own, such as a copyright claim.
  Future<void> remember({
    required String infoHash,
    required String service,
    required String reason,
    required bool permanent,
  }) async {
    final hash = _normalize(infoHash);
    if (hash == null) return;
    _rejections[hash] = _Rejection(
      service: service,
      reason: reason,
      at: DateTime.now(),
      permanent: permanent,
    );
    revision.value++;
    await _persist();
  }

  /// Clears every remembered refusal.
  Future<void> forgetAll() async {
    _rejections.clear();
    revision.value++;
    await _persist();
  }

  _Rejection? _lookup(String? infoHash) {
    final hash = _normalize(infoHash);
    if (hash == null) return null;
    final rejection = _rejections[hash];
    if (rejection == null) return null;
    if (!rejection.permanent &&
        DateTime.now().difference(rejection.at) > _ttl) {
      return null;
    }
    return rejection;
  }

  /// Sources reach us uppercase from indexers and lowercase from magnets, so
  /// everything is compared in lowercase.
  String? _normalize(String? infoHash) {
    final hash = infoHash?.trim().toLowerCase();
    if (hash == null || hash.isEmpty) return null;
    return hash;
  }

  Future<void> _persist() async {
    try {
      final prefs = await _prefs;
      final encoded = <String, dynamic>{
        for (final entry in _rejections.entries) entry.key: entry.value.toJson(),
      };
      await prefs.setString(_rejectionsKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[DebridRejectionStore] failed to save refusals: $e');
    }
  }
}

/// One remembered refusal.
class _Rejection {
  final String service;
  final String reason;
  final DateTime at;
  final bool permanent;

  const _Rejection({
    required this.service,
    required this.reason,
    required this.at,
    required this.permanent,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'service': service,
        'reason': reason,
        'at': at.toIso8601String(),
        'permanent': permanent,
      };

  static _Rejection? fromJson(Map<dynamic, dynamic> json) {
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    final reason = json['reason']?.toString();
    if (at == null || reason == null || reason.isEmpty) return null;
    return _Rejection(
      service: json['service']?.toString() ?? '',
      reason: reason,
      at: at,
      permanent: json['permanent'] == true,
    );
  }
}
