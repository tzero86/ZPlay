import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zplay/models/my_list/my_list_item.dart';
import 'package:zplay/services/my_list/my_list_service.dart';

MyListItem _makeItem({
  String title = 'Test',
  int? traktId,
  String? imdbId,
  int? tmdbId,
}) {
  return MyListItem(
    traktId: traktId,
    imdbId: imdbId,
    tmdbId: tmdbId,
    title: title,
    year: 2024,
    type: 'movie',
    addedAt: DateTime(2026),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MyListService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      MyListService.items.value = [];
      await MyListService.initialize();
    });

    group('add', () {
      test('adds item to list', () {
        final item = _makeItem(traktId: 1);
        MyListService.add(item);
        expect(MyListService.items.value.length, 1);
        expect(MyListService.items.value.first.traktId, 1);
      });

      test('does not add duplicate (same uniqueKey)', () {
        final item1 = _makeItem(traktId: 1, title: 'Movie A');
        final item2 = _makeItem(traktId: 1, title: 'Movie A Duplicate');
        MyListService.add(item1);
        MyListService.add(item2);
        expect(MyListService.items.value.length, 1);
      });

      test('adds items with different uniqueKeys', () {
        MyListService.add(_makeItem(title: 'Movie 1', traktId: 1));
        MyListService.add(_makeItem(title: 'Movie 2', imdbId: 'tt2'));
        MyListService.add(_makeItem(title: 'Movie 3', tmdbId: 3));
        expect(MyListService.items.value.length, 3);
      });

      test('sorts by addedAt descending (most recent first)', () {
        final older = MyListItem(
          traktId: 1,
          title: 'Older',
          type: 'movie',
          addedAt: DateTime(2026, 1, 1),
        );
        final newer = MyListItem(
          traktId: 2,
          title: 'Newer',
          type: 'movie',
          addedAt: DateTime(2026, 6, 1),
        );

        MyListService.add(older);
        MyListService.add(newer);

        expect(MyListService.items.value[0].title, 'Newer');
        expect(MyListService.items.value[1].title, 'Older');
      });

      test('enforces maxItems cap of 500', () {
        for (int i = 0; i < 510; i++) {
          MyListService.add(
            _makeItem(imdbId: 'tt${i.toString().padLeft(7, '0')}'),
          );
        }
        expect(MyListService.items.value.length, 500);
      });

      test('caps by removing oldest entries', () {
        for (int i = 0; i < 500; i++) {
          MyListService.add(
            _makeItem(imdbId: 'tt${i.toString().padLeft(7, '0')}'),
          );
        }
        // Add one more - this pushes out the oldest (first added)
        MyListService.add(_makeItem(imdbId: 'ttnewest'));
        expect(MyListService.items.value.length, 500);
        expect(
          MyListService.items.value.any((i) => i.imdbId == 'ttnewest'),
          true,
        );
      });
    });

    group('remove', () {
      test('removes item by uniqueKey', () {
        final item = _makeItem(traktId: 1);
        MyListService.add(item);
        expect(MyListService.items.value.length, 1);

        MyListService.remove(item);
        expect(MyListService.items.value.length, 0);
      });

      test('removes correct item when multiple exist', () {
        final item1 = _makeItem(traktId: 1);
        final item2 = _makeItem(traktId: 2);
        final item3 = _makeItem(traktId: 3);
        MyListService.add(item1);
        MyListService.add(item2);
        MyListService.add(item3);

        MyListService.remove(item2);
        expect(MyListService.items.value.length, 2);
        expect(MyListService.items.value.any((i) => i.traktId == 2), false);
        expect(MyListService.items.value.any((i) => i.traktId == 1), true);
        expect(MyListService.items.value.any((i) => i.traktId == 3), true);
      });

      test('removing non-existent item does nothing', () {
        final item = _makeItem(traktId: 1);
        MyListService.add(_makeItem(traktId: 2));
        MyListService.remove(item);
        expect(MyListService.items.value.length, 1);
      });
    });

    group('toggle', () {
      test('adds when not in list', () {
        final item = _makeItem(traktId: 1);
        MyListService.toggle(item);
        expect(MyListService.items.value.length, 1);
      });

      test('removes when already in list', () {
        final item = _makeItem(traktId: 1);
        MyListService.add(item);
        MyListService.toggle(item);
        expect(MyListService.items.value.length, 0);
      });

      test('toggle twice returns to original state', () {
        MyListService.toggle(_makeItem(traktId: 1));
        MyListService.toggle(_makeItem(traktId: 1));
        expect(MyListService.items.value.length, 0);
      });
    });

    group('isInList', () {
      test('returns true for added item', () {
        final item = _makeItem(traktId: 1);
        MyListService.add(item);
        expect(MyListService.isInList(item), true);
      });

      test('returns false for not added item', () {
        final item = _makeItem(traktId: 1);
        expect(MyListService.isInList(item), false);
      });

      test(
        'returns true for item with matching uniqueKey but different title',
        () {
          final item1 = _makeItem(traktId: 1, title: 'Title A');
          final item2 = _makeItem(traktId: 1, title: 'Title B');
          MyListService.add(item1);
          expect(MyListService.isInList(item2), true);
        },
      );
    });

    group('ValueNotifier reactivity', () {
      test('notifies listeners on add', () {
        int notifyCount = 0;
        MyListService.items.addListener(() => notifyCount++);

        MyListService.add(_makeItem(traktId: 1));
        expect(notifyCount, 1);

        MyListService.add(_makeItem(traktId: 2));
        expect(notifyCount, 2);
      });

      test('notifies listeners on remove', () {
        final item = _makeItem(traktId: 1);
        MyListService.add(item);

        int notifyCount = 0;
        MyListService.items.addListener(() => notifyCount++);

        MyListService.remove(item);
        expect(notifyCount, 1);
      });

      test('does not notify on duplicate add', () {
        final item = _makeItem(traktId: 1);
        MyListService.add(item);

        int notifyCount = 0;
        MyListService.items.addListener(() => notifyCount++);

        MyListService.add(item);
        expect(notifyCount, 0);
      });
    });

    group('durable storage', () {
      test(
        'loads legacy bare JSON and rewrites it in the envelope format',
        () async {
          SharedPreferences.setMockInitialValues({
            'my_list_v1': jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'traktId': 7,
                'title': 'Legacy Pick',
                'type': 'movie',
                'addedAt': DateTime(2026, 1, 1).toIso8601String(),
                'source': 'local',
              },
            ]),
          });
          MyListService.items.value = [];

          await MyListService.initialize();

          expect(MyListService.items.value, hasLength(1));
          expect(MyListService.items.value.single.title, 'Legacy Pick');

          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('my_list_v1')!;
          expect(raw, contains(r'$zplaySchema'));
          expect(raw, contains('Legacy Pick'));
        },
      );
    });
  });
}
