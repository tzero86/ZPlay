/// How a Debrid provider failed, which is what decides what the caller does.
///
/// Providers answer with wildly different shapes, Real-Debrid for example uses an
/// HTTP status plus an `error` string plus a numeric `error_code`, so every
/// provider classifies its own failure into one of these instead of handing raw
/// JSON up to the player.
enum DebridFailureKind {
  /// The provider refuses this torrent for good: a copyright claim, a virus
  /// flag, a dead torrent, or nothing in it that matches the requested episode.
  sourceRejected,

  /// The provider could serve it, but not yet: still converting the magnet,
  /// still fetching the torrent, or the download window closed.
  notCached,

  /// The key or the account is the problem, so every source would fail the same
  /// way. Never skip a source over this, tell the user to fix the key.
  account,

  /// Network trouble, a rate limit, or a provider side error. Worth trying
  /// another source, and worth trying the same one again later.
  transient,
}

/// A Debrid failure that says what went wrong and what to do about it.
///
/// [message] is safe to show: one short sentence, no status codes and no JSON.
/// [detail] keeps the raw status and body for the breadcrumbs, so the noisy part
/// stays in diagnostics instead of in the user's face.
class DebridResolutionException implements Exception {
  /// What kind of failure this is.
  final DebridFailureKind kind;

  /// Provider name as the UI writes it, for example 'Real-Debrid'.
  final String service;

  /// Short, user facing sentence.
  final String message;

  /// Raw status and body, for diagnostics only.
  final String detail;

  /// True when this exact torrent should be remembered as unusable, which is for
  /// refusals that will not change: a copyright claim, a virus flag, a dead
  /// torrent. Not set for "not ready yet" or for network trouble.
  final bool rememberUnusable;

  const DebridResolutionException({
    required this.kind,
    required this.service,
    required this.message,
    this.detail = '',
    this.rememberUnusable = false,
  });

  /// The provider refuses this torrent for good.
  DebridResolutionException.sourceRejected({
    required this.service,
    required this.message,
    this.detail = '',
    this.rememberUnusable = true,
  }) : kind = DebridFailureKind.sourceRejected;

  /// The provider can serve it, but it is not ready yet.
  DebridResolutionException.notCached({
    required this.service,
    required this.message,
    this.detail = '',
  })  : kind = DebridFailureKind.notCached,
        rememberUnusable = false;

  /// The key or the account is the problem.
  DebridResolutionException.account({
    required this.service,
    required this.message,
    this.detail = '',
  })  : kind = DebridFailureKind.account,
        rememberUnusable = false;

  /// Network, rate limit, or provider side trouble.
  DebridResolutionException.transient({
    required this.service,
    required this.message,
    this.detail = '',
  })  : kind = DebridFailureKind.transient,
        rememberUnusable = false;

  /// True when the player should walk on to the next ranked source instead of
  /// stopping on this error.
  bool get canTryAnotherSource => kind != DebridFailureKind.account;

  /// Keeps a stray dump of the exception readable, since a bare
  /// `Exception('Real-Debrid rejected magnet (451): {...}')` is what this type
  /// exists to replace.
  @override
  String toString() => message;
}
