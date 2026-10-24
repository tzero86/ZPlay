import 'dart:math';

import 'package:path/path.dart' as p;

/// Resolves [entryName] below [root], rejecting absolute paths and `..`
/// segments. Archive entry names are untrusted and must never escape the
/// extraction directory.
String safeChildPath(String root, String entryName) {
  final normalizedEntry = entryName.replaceAll('\\', '/');
  if (normalizedEntry.isEmpty) {
    throw const FormatException('Empty archive entry');
  }
  if (p.isAbsolute(normalizedEntry) ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalizedEntry)) {
    throw FormatException('Absolute archive entry: $entryName');
  }

  final segments = normalizedEntry.split('/');
  if (segments.any((segment) => segment == '..' || segment.contains(':'))) {
    throw FormatException('Archive entry escapes target directory: $entryName');
  }

  final rootPath = p.normalize(p.absolute(root));
  final targetPath = p.normalize(p.absolute(p.join(rootPath, normalizedEntry)));
  if (p.equals(rootPath, targetPath) || !p.isWithin(rootPath, targetPath)) {
    throw FormatException('Archive entry escapes target directory: $entryName');
  }
  return targetPath;
}

/// Makes a single path component safe for use below a known directory.
///
/// This preserves readable names while removing path separators, Windows
/// reserved characters, control characters, and leading/trailing dots or
/// spaces. The result is never `.` or `..`.
String sanitizeFileComponent(String input, {String fallback = 'file'}) {
  var value = input
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (value.length > 120) {
    value = value.substring(0, 120);
  }
  if (value.isEmpty || value == '.' || value == '..') {
    return fallback;
  }
  return value;
}

/// Returns a cryptographically secure hex token.
String secureRandomHex(int byteCount) {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < byteCount; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
