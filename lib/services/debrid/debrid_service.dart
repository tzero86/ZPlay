import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/debrid_file.dart';
import 'providers/alldebrid_service.dart';
import 'providers/debrid_link_service.dart';
import 'providers/premiumize_service.dart';
import 'providers/real_debrid_service.dart';
import 'providers/torbox_service.dart';

class DebridService {
  static final DebridService _instance = DebridService._internal();
  factory DebridService() => _instance;
  DebridService._internal();

  final realDebrid = RealDebridService();
  final torBox = TorBoxService();
  final allDebrid = AllDebridService();
  final premiumize = PremiumizeService();
  final debridLink = DebridLinkService();

  static const String _debridServiceKey = 'debrid_service';
  static const String _useDebridForStreamsKey = 'use_debrid_for_streams';

  /// Cached answer to "would a torrent source play through Debrid right now?".
  ///
  /// Debrid resolves magnets in the cloud, so magnets stay playable even when the
  /// local P2P engine is switched off. The scraper layer has to decide
  /// synchronously whether to include the BitTorrent indexers, so the
  /// asynchronous preference check is cached here and refreshed at startup and
  /// whenever the user changes the Debrid settings.
  static final ValueNotifier<bool> isDebridReady = ValueNotifier<bool>(false);

  static Future<void> refreshDebridReady() async {
    try {
      isDebridReady.value = await DebridService().isDebridActiveForStreams();
    } catch (e) {
      debugPrint('[DebridService] refreshDebridReady error: $e');
      isDebridReady.value = false;
    }
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ── Active Service Selection ───────────────────────────────────────────────

  Future<String> getSelectedService() async {
    final prefs = await _prefs;
    return prefs.getString(_debridServiceKey) ?? 'None';
  }

  Future<void> saveSelectedService(String service) async {
    final prefs = await _prefs;
    await prefs.setString(_debridServiceKey, service.trim());
  }

  // ── "Use Debrid for streams" Toggle ────────────────────────────────────────

  Future<bool> getUseDebridForStreams() async {
    final prefs = await _prefs;
    return prefs.getBool(_useDebridForStreamsKey) ?? false;
  }

  Future<void> saveUseDebridForStreams(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_useDebridForStreamsKey, value);
  }

  /// Returns true if Debrid is fully setup AND the "Use Debrid for streams" toggle is ON.
  Future<bool> isDebridActiveForStreams() async {
    final enabled = await getUseDebridForStreams();
    if (!enabled) return false;

    final service = await getSelectedService();
    if (service == 'None' || service.isEmpty) return false;

    return await hasKeyForService(service);
  }

  Future<bool> hasKeyForService(String service) async {
    switch (service) {
      case 'Real-Debrid':
        return await realDebrid.hasKey();
      case 'TorBox':
        return await torBox.hasKey();
      case 'AllDebrid':
        return await allDebrid.hasKey();
      case 'Premiumize':
        return await premiumize.hasKey();
      case 'Debrid-Link':
        return await debridLink.hasKey();
      default:
        return false;
    }
  }

  // ── Stream Resolution Dispatcher ──────────────────────────────────────────

  Future<List<DebridFile>> resolveMagnet({
    required String magnet,
    String? service,
    int? fileIndex,
    String? filename,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    final activeService = service ?? await getSelectedService();
    if (activeService == 'None' || activeService.isEmpty) {
      throw Exception('No active Debrid service selected.');
    }

    switch (activeService) {
      case 'Real-Debrid':
        return await realDebrid.resolveMagnet(
          magnet,
          fileIndex: fileIndex,
          filename: filename,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
        );
      case 'TorBox':
        return await torBox.resolveMagnet(
          magnet,
          fileIndex: fileIndex,
          filename: filename,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
        );
      case 'AllDebrid':
        return await allDebrid.resolveMagnet(
          magnet,
          fileIndex: fileIndex,
          filename: filename,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
        );
      case 'Premiumize':
        return await premiumize.resolveMagnet(
          magnet,
          fileIndex: fileIndex,
          filename: filename,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
        );
      case 'Debrid-Link':
        return await debridLink.resolveMagnet(
          magnet,
          fileIndex: fileIndex,
          filename: filename,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
        );
      default:
        throw Exception('Unknown Debrid provider: $activeService');
    }
  }
}
