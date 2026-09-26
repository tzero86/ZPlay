import 'package:flutter_test/flutter_test.dart';
import 'package:zplay/pages/search/search_page.dart';

void main() {
  group('classifySearchResult', () {
    test('a dead source behind an empty result set is a failure, not a miss', () {
      // The reported bug: a dead addon, with the keyless title leg also
      // coming back empty, rendered 'No results for "The Bear"'. One
      // unreachable source is enough to make that claim untrue.
      expect(classifySearchResult(resultCount: 0, failureCount: 1),
          SearchOutcome.failed);
      expect(classifySearchResult(resultCount: 0, failureCount: 3),
          SearchOutcome.failed);
    });

    test('every source answering with nothing found stays a no-results', () {
      expect(classifySearchResult(resultCount: 0, failureCount: 0),
          SearchOutcome.noResults);
    });

    test('results from healthy sources are complete', () {
      expect(classifySearchResult(resultCount: 2, failureCount: 0),
          SearchOutcome.complete);
    });

    test('results alongside failures are incomplete, never complete', () {
      expect(classifySearchResult(resultCount: 1, failureCount: 1),
          SearchOutcome.incomplete);
      expect(classifySearchResult(resultCount: 7, failureCount: 2),
          SearchOutcome.incomplete);
    });

    test('the empty result set branches only on whether anything failed', () {
      for (var failures = 0; failures < 4; failures++) {
        expect(
          classifySearchResult(resultCount: 0, failureCount: failures),
          failures == 0 ? SearchOutcome.noResults : SearchOutcome.failed,
          reason: 'a dead source must never read as a missing title',
        );
      }
    });
  });

  group('SearchFailureLedger', () {
    test('counts one failure per leg that threw', () {
      final ledger = SearchFailureLedger();
      expect(ledger.failedSources, 0);

      ledger.sourceErrors.add('Addons');
      ledger.sourceErrors.add('CloudStream');

      expect(ledger.failedSources, 2);
      expect(ledger.sourceErrors, ['Addons', 'CloudStream']);
    });

    test('a dead addon with no title behind it classifies as failed', () {
      final ledger = SearchFailureLedger()
        ..searchedSourceCount = 2
        ..sourceErrors.add('Addons');

      expect(
        classifySearchResult(resultCount: 0, failureCount: ledger.failedSources),
        SearchOutcome.failed,
      );
    });

    test('a new query clears the previous query failures', () {
      final ledger = SearchFailureLedger()..searchedSourceCount = 3;
      ledger.sourceErrors
        ..add('Addons')
        ..add('CloudStream');
      expect(ledger.failedSources, 2);

      ledger.reset();
      ledger.searchedSourceCount = 3;

      expect(ledger.failedSources, 0);
      expect(ledger.sourceErrors, isEmpty);
      expect(
        classifySearchResult(resultCount: 0, failureCount: ledger.failedSources),
        SearchOutcome.noResults,
        reason: 'a fresh query must not inherit the previous outage',
      );
    });

    test('partial results stay visible and are only marked incomplete', () {
      final ledger = SearchFailureLedger()
        ..searchedSourceCount = 3
        ..sourceErrors.add('CloudStream');

      expect(
        classifySearchResult(resultCount: 2, failureCount: ledger.failedSources),
        SearchOutcome.incomplete,
      );
    });
  });
}
