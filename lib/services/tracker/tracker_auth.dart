import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../profiles/profile_async_authorization.dart';
import '../profiles/profile_runtime.dart';

/// A captured profile authorization for a pending device-code / PIN attempt,
/// plus the moment that attempt stops being pollable.
///
/// The capture pins the account a resulting token belongs to; the deadline
/// keeps a code the provider no longer honours from being polled forever.
class TrackerAuthorization {
  final ProfileAsyncAuthorization authorization;
  final DateTime expiresAt;

  const TrackerAuthorization({
    required this.authorization,
    required this.expiresAt,
  });
}

/// How many pending attempts a service keeps. The cap is the same for Trakt
/// and Simkl; it exists so a user restarting pairing repeatedly can't grow the
/// map without bound.
const int kMaxPendingTrackerAuthorizations = 8;

/// Drop expired attempts, then the oldest insertions until fewer than
/// [kMaxPendingTrackerAuthorizations] remain — so the insert that follows
/// always fits.
void pruneTrackerAuthorizations(Map<String, TrackerAuthorization> attempts) {
  final now = DateTime.now();
  attempts.removeWhere((_, value) => value.expiresAt.isBefore(now));
  while (attempts.length >= kMaxPendingTrackerAuthorizations) {
    attempts.remove(attempts.keys.first);
  }
}

/// What a 200 poll response means: the work to run once the profile
/// authorization is confirmed, or a terminal status when the body carries no
/// usable token (the attempt then stays live for the next poll).
typedef TrackerPollOutcome = ({Future<void> Function()? commit, String? status});

/// One poll of a pending device-code / PIN authorization, shared by Trakt's
/// device flow and Simkl's PIN flow.
///
/// Returns null once the token was stored, or the status string both poll UIs
/// already handle: `access_denied` (the attempt belongs to another profile,
/// expired, or the commit lost a profile race), `network_error` (transient —
/// safe to retry), plus whatever [onSuccess]/[onFailure] derive from the
/// response (`authorization_pending`, `slow_down`, `error`).
///
/// Everything provider-specific stays at the call site: the request itself,
/// how a 200 body becomes a commit closure, how a non-200 maps to a status, and
/// the debug prefix used for transport failures.
Future<String?> pollTrackerAuthorization({
  required Map<String, TrackerAuthorization> attempts,
  required String code,
  required Future<http.Response> Function() request,
  required TrackerPollOutcome Function(http.Response response) onSuccess,
  required String Function(http.Response response) onFailure,
  required String debugLabel,
}) async {
  try {
    final attempt = attempts[code];
    if (ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted &&
        (attempt == null || attempt.expiresAt.isBefore(DateTime.now()))) {
      attempts.remove(code);
      return 'access_denied';
    }
    final response = await request();
    if (response.statusCode != 200) return onFailure(response);

    final outcome = onSuccess(response);
    final commit = outcome.commit;
    if (commit == null) return outcome.status ?? 'error';
    // Consume the attempt before committing: the code is single-use either way,
    // so a failed commit must not leave it pollable.
    attempts.remove(code);
    try {
      if (attempt == null) {
        await commit();
      } else {
        await attempt.authorization.run(commit);
      }
    } on StateError {
      return 'access_denied';
    }
    return null;
  } catch (error) {
    // Network timeout, socket exception, etc. — transient, safe to retry
    debugPrint('$debugLabel network error (${error.runtimeType})');
    return 'network_error';
  }
}