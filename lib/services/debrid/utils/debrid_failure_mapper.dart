import 'dart:convert';

import '../models/debrid_error.dart';

/// Turns a provider HTTP failure into a classified [DebridResolutionException].
///
/// Every provider answers a refused magnet with an HTTP status plus a JSON body
/// that carries a provider specific `error` string and sometimes a numeric
/// `error_code`. The provider strings that are known here get a precise kind,
/// and anything unrecognised falls back to the shared status rule: 401 and 403
/// are the account, 429 and 5xx are transient, 451 is a legal block, and any
/// other 4xx is a rejected source.
///
/// [detail] always carries the raw status and body, so the noisy part stays in
/// diagnostics while [DebridResolutionException.message] stays showable.
DebridResolutionException classifyHttpFailure({
  required String service,
  required int statusCode,
  required String body,
}) {
  final detail = 'HTTP $statusCode: $body';
  final json = _decodeJsonObject(body);
  final error = json == null ? null : _readErrorString(json['error']);

  if (error != null) {
    final byString = _classifyKnownErrorString(
      service: service,
      error: error,
      detail: detail,
    );
    if (byString != null) return byString;
  }

  // The numeric codes are used only when the body had no usable error string,
  // so a code from another provider can never override a known string.
  final rawCode = json?['error_code'];
  if (error == null && rawCode is int) {
    final byCode = _classifyKnownErrorCode(
      service: service,
      code: rawCode,
      detail: detail,
    );
    if (byCode != null) return byCode;
  }

  if (statusCode == 401 || statusCode == 403) {
    return DebridResolutionException.account(
      service: service,
      message: '$service rejected your API key. Check it in Settings.',
      detail: detail,
    );
  }
  if (statusCode == 429) {
    return DebridResolutionException.transient(
      service: service,
      message: '$service is rate limiting requests, try again in a moment.',
      detail: detail,
    );
  }
  if (statusCode >= 500 && statusCode < 600) {
    return DebridResolutionException.transient(
      service: service,
      message: '$service had a server error, try again in a moment.',
      detail: detail,
    );
  }
  if (statusCode == 451) {
    return DebridResolutionException.sourceRejected(
      service: service,
      message: '$service blocked this torrent over a copyright claim.',
      detail: detail,
    );
  }
  if (statusCode >= 400 && statusCode < 500) {
    // An unrecognised refusal is not worth blacklisting the torrent over, so
    // the player just walks on to the next source.
    return DebridResolutionException.sourceRejected(
      service: service,
      message: '$service refused this source.',
      detail: detail,
      rememberUnusable: false,
    );
  }
  if (json != null && _bodyReportsFailure(json)) {
    // Providers that answer a refusal with a 200 and a failure flag in the body.
    return DebridResolutionException.sourceRejected(
      service: service,
      message: '$service refused this source.',
      detail: detail,
      rememberUnusable: false,
    );
  }
  return DebridResolutionException.transient(
    service: service,
    message: '$service could not resolve this source right now.',
    detail: detail,
  );
}

/// Classifies a torrent status word a provider reports while resolving.
///
/// [magnet_error], [virus], [dead] and [banned] mean the torrent itself is not
/// servable and will not become servable, so they are remembered as unusable.
/// [error] and anything unrecognised are treated as transient, because the
/// provider may still be able to prepare the torrent later.
DebridResolutionException classifyTorrentStatus({
  required String service,
  required String status,
}) {
  final detail = 'Torrent status: $status';
  switch (status) {
    case 'magnet_error':
    case 'virus':
    case 'dead':
    case 'banned':
      return DebridResolutionException.sourceRejected(
        service: service,
        message: '$service cannot serve this torrent.',
        detail: detail,
      );
    case 'error':
      return DebridResolutionException.transient(
        service: service,
        message: '$service hit an error with this torrent, try again later.',
        detail: detail,
      );
    default:
      return DebridResolutionException.transient(
        service: service,
        message: '$service could not prepare this torrent, try again later.',
        detail: detail,
      );
  }
}

/// The error strings these API shapes are known to answer with.
DebridResolutionException? _classifyKnownErrorString({
  required String service,
  required String error,
  required String detail,
}) {
  switch (error) {
    case 'infringing_file':
      return DebridResolutionException.sourceRejected(
        service: service,
        message: '$service blocked this torrent over a copyright claim.',
        detail: detail,
      );
    case 'torrent_file_invalid':
      return DebridResolutionException.sourceRejected(
        service: service,
        message: '$service could not read that torrent file.',
        detail: detail,
      );
    case 'unavailable_file':
      return DebridResolutionException.sourceRejected(
        service: service,
        message: '$service says this torrent file is unavailable.',
        detail: detail,
        rememberUnusable: false,
      );
    case 'bad_token':
      return DebridResolutionException.account(
        service: service,
        message: '$service rejected your API key. Check it in Settings.',
        detail: detail,
      );
    default:
      return null;
  }
}

/// Real-Debrid error codes captured from the live API, used only when the body
/// carried no error string to match on.
DebridResolutionException? _classifyKnownErrorCode({
  required String service,
  required int code,
  required String detail,
}) {
  switch (code) {
    case 8: // {"error": "bad_token", "error_code": 8}
      return DebridResolutionException.account(
        service: service,
        message: '$service rejected your API key. Check it in Settings.',
        detail: detail,
      );
    case 30: // {"error": "torrent_file_invalid", "error_code": 30}
      return DebridResolutionException.sourceRejected(
        service: service,
        message: '$service could not read that torrent file.',
        detail: detail,
      );
    case 35: // {"error": "infringing_file", "error_code": 35}
      return DebridResolutionException.sourceRejected(
        service: service,
        message: '$service blocked this torrent over a copyright claim.',
        detail: detail,
      );
    default:
      return null;
  }
}

/// True for the body shapes providers use to report a failure under HTTP 200.
bool _bodyReportsFailure(Map<String, dynamic> json) {
  if (json['success'] == false) return true;
  final status = json['status'];
  return status == 'error' || status == 'failed';
}

/// Reads the provider error string. Some providers nest a map under `error`
/// instead of a string, and those bodies fall through to the status rule.
String? _readErrorString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

/// Decodes the body only when it is a JSON object, so an HTML error page or an
/// empty body simply falls through to the status rule.
Map<String, dynamic>? _decodeJsonObject(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
  try {
    final decoded = json.decode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
