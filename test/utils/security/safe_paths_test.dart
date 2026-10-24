import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zplay/utils/security/safe_paths.dart';

void main() {
  final root = p.join(
    p.separator == '\\' ? r'C:\tmp' : '/tmp',
    'zplay-safe-paths',
  );

  group('isWithinDirectory', () {
    test('accepts nested paths', () {
      expect(isWithinDirectory(root, p.join(root, 'movie.mkv')), isTrue);
    });

    test('rejects the root itself and siblings', () {
      expect(isWithinDirectory(root, root), isFalse);
      expect(isWithinDirectory(root, p.join(root, '..', 'other')), isFalse);
      expect(isWithinDirectory(root, ''), isFalse);
    });
  });

  group('safeChildPath', () {
    test('keeps nested entries under the root', () {
      expect(
        safeChildPath(root, 'lib/foo.dll'),
        p.join(root, 'lib', 'foo.dll'),
      );
    });

    test('normalizes backslash separators', () {
      expect(
        safeChildPath(root, r'lib\foo.dll'),
        p.join(root, 'lib', 'foo.dll'),
      );
    });

    test('rejects parent traversal', () {
      expect(() => safeChildPath(root, '../evil'), throwsFormatException);
      expect(
        () => safeChildPath(root, 'lib/../../evil'),
        throwsFormatException,
      );
    });

    test('rejects absolute paths and drive-relative paths', () {
      expect(() => safeChildPath(root, '/etc/passwd'), throwsFormatException);
      expect(() => safeChildPath(root, r'C:\evil'), throwsFormatException);
      expect(() => safeChildPath(root, 'C:evil'), throwsFormatException);
    });

    test('rejects empty entries', () {
      expect(() => safeChildPath(root, ''), throwsFormatException);
    });
  });

  group('sanitizeFileComponent', () {
    test('removes path separators and reserved characters', () {
      final sanitized = sanitizeFileComponent(r'..\evil/name?.jar');
      expect(sanitized, isNot(contains('/')));
      expect(sanitized, isNot(contains(r'\')));
      expect(sanitized, isNot(contains('?')));
      expect(sanitizeFileComponent('a&b|c^d%e!f'), 'a_b_c_d_e_f');
    });

    test('never returns a traversal component', () {
      expect(sanitizeFileComponent('..'), 'file');
      expect(sanitizeFileComponent('   '), 'file');
      final traversal = sanitizeFileComponent('../../evil');
      expect(traversal, isNot('..'));
      expect(traversal, isNot(contains('/')));
    });

    test('uses the requested fallback', () {
      expect(sanitizeFileComponent('', fallback: 'extension'), 'extension');
    });

    test('keeps readable names', () {
      expect(sanitizeFileComponent('My Extension 1.0'), 'My Extension 1.0');
    });
  });
}
