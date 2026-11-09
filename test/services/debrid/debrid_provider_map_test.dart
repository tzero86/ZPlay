import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/services/debrid/debrid_service.dart';

/// Debrid dispatch is one map lookup now, keyed by the provider's display name.
/// The settings page builds its dropdown from this map, so the order is part of
/// the UI contract, not an implementation detail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every provider is reachable by its own name, in dropdown order', () {
    final providers = DebridService().providers;
    expect(
      providers.keys.toList(),
      <String>[
        'Real-Debrid',
        'TorBox',
        'AllDebrid',
        'Premiumize',
        'Debrid-Link',
      ],
      reason: 'the settings dropdown renders in map order',
    );
    for (final entry in providers.entries) {
      expect(entry.value.name, entry.key);
    }
  });
}