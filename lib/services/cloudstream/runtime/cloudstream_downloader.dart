import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

import '../../../utils/security/safe_paths.dart';
import 'cloudstream_paths.dart';

class CloudStreamDownloader {
  static final CloudStreamDownloader instance = CloudStreamDownloader._();
  CloudStreamDownloader._();

  final _paths = CloudStreamPaths.instance;
  final _client = http.Client();

  final ValueNotifier<bool> isDownloading = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0.0);
  final ValueNotifier<String> status = ValueNotifier('');
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<bool> isReady = ValueNotifier(false);

  static const String androidApkUrl =
      'https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/releases/latest/download/anymex_runtime_host.apk';
  static const String desktopJarUrl =
      'https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/releases/latest/download/anymex_desktop_runtime.jar';
  static const String dex2jarUrl =
      'https://github.com/pxb1988/dex2jar/releases/download/v2.4/dex-tools-v2.4.zip';

  static String get _jreUrl {
    if (Platform.isWindows) {
      return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_windows_hotspot_17.0.12_7.zip';
    } else if (Platform.isMacOS) {
      final arch = _getMacArch();
      if (arch == 'arm64') {
        return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_aarch64_mac_hotspot_17.0.12_7.tar.gz';
      } else {
        return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_mac_hotspot_17.0.12_7.tar.gz';
      }
    } else {
      final arch = _getLinuxArch();
      if (arch == 'aarch64' || arch == 'arm64') {
        return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_aarch64_linux_hotspot_17.0.12_7.tar.gz';
      } else {
        return 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_linux_hotspot_17.0.12_7.tar.gz';
      }
    }
  }

  static String _getMacArch() {
    try {
      final result = Process.runSync('uname', ['-m']);
      return result.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return 'x64';
    }
  }

  static String _getLinuxArch() {
    try {
      final result = Process.runSync('uname', ['-m']);
      return result.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return 'x64';
    }
  }

  /// Checks if all necessary files exist for CloudStream execution.
  Future<bool> checkIsReady() async {
    if (Platform.isIOS) {
      isReady.value = false;
      return false;
    }

    if (Platform.isAndroid) {
      final apkPath = await _paths.runtimeApkPath;
      final ready =
          await File(apkPath).exists() && (await File(apkPath).length()) > 1000;
      isReady.value = ready;
      return ready;
    }

    // Desktop check
    final javaExe = await _paths.javaExecutablePath;
    final jarPath = await _paths.bridgeJarPath;
    final dex2jarPath = await _paths.dex2jarPath;

    final hasJava = javaExe != null && await File(javaExe).exists();
    final hasJar =
        await File(jarPath).exists() && (await File(jarPath).length()) > 1000;
    final hasDex2jar = await File(dex2jarPath).exists();

    final ready = hasJava && hasJar && hasDex2jar;
    isReady.value = ready;
    return ready;
  }

  /// Sets up the CloudStream runtime (JRE, dex2jar, runtime JAR/APK).
  Future<void> setupRuntime({bool force = false}) async {
    if (isDownloading.value) return;

    isDownloading.value = true;
    errorMessage.value = null;
    status.value = 'Initializing runtime setup...';
    progress.value = 0.0;

    try {
      if (Platform.isAndroid) {
        final apkPath = await _paths.runtimeApkPath;
        final apkFile = File(apkPath);
        if (force ||
            !await apkFile.exists() ||
            (await apkFile.length()) < 1000) {
          await _downloadFile(androidApkUrl, apkFile.path, 'Runtime Host APK');
        }
        isReady.value = true;
        status.value = 'CloudStream runtime is ready.';
        return;
      }

      // Desktop setup
      final bridgePath = await _paths.bridgeJarPath;
      final bridgeFile = File(bridgePath);
      final jreDir = await _paths.jreDir;
      final toolsDir = await _paths.toolsDir;
      final dex2jarPath = await _paths.dex2jarPath;

      final bool needsBridge =
          force ||
          !await bridgeFile.exists() ||
          (await bridgeFile.length()) < 1000;
      final bool needsJre =
          force ||
          !await jreDir.exists() ||
          (await _paths.javaExecutablePath) == null;
      final bool needsDex2jar = force || !await File(dex2jarPath).exists();

      int totalFiles =
          (needsBridge ? 1 : 0) + (needsJre ? 1 : 0) + (needsDex2jar ? 1 : 0);
      int currentFileIndex = 0;

      if (needsBridge) {
        currentFileIndex++;
        final stepPrefix = totalFiles > 1
            ? '($currentFileIndex/$totalFiles) '
            : '';
        await _downloadFile(
          desktopJarUrl,
          bridgeFile.path,
          '${stepPrefix}Bridge JAR',
        );
      }

      if (needsJre) {
        currentFileIndex++;
        final ext = Platform.isWindows ? '.zip' : '.tar.gz';
        final rDir = await _paths.runtimeDir;
        final jreArchive = File(p.join(rDir.path, 'jre_archive$ext'));

        final stepPrefix = totalFiles > 1
            ? '($currentFileIndex/$totalFiles) '
            : '';
        await _downloadFile(
          _jreUrl,
          jreArchive.path,
          '${stepPrefix}Java Runtime (Adoptium OpenJDK 17)',
        );

        status.value = 'Extracting Java Runtime...';
        await _extractArchive(jreArchive.path, jreDir.path);

        if (await jreArchive.exists()) await jreArchive.delete();

        if (Platform.isMacOS) {
          status.value = 'Applying macOS permissions...';
          await Process.run('xattr', ['-cr', jreDir.path]);
          final jreBinDir = Directory(
            p.join(jreDir.path, 'Contents', 'Home', 'bin'),
          );
          if (await jreBinDir.exists()) {
            await Process.run('chmod', ['-R', '+x', jreBinDir.path]);
          } else {
            final altBinDir = Directory(p.join(jreDir.path, 'bin'));
            if (await altBinDir.exists()) {
              await Process.run('chmod', ['-R', '+x', altBinDir.path]);
            }
          }
        } else if (Platform.isLinux) {
          status.value = 'Applying Linux permissions...';
          final binDir = Directory(p.join(jreDir.path, 'bin'));
          if (await binDir.exists()) {
            await Process.run('chmod', ['-R', '+x', binDir.path]);
          }
          final libDir = Directory(p.join(jreDir.path, 'lib'));
          if (await libDir.exists()) {
            await Process.run('chmod', ['-R', 'a+r', libDir.path]);
          }
        }
      }

      if (needsDex2jar) {
        currentFileIndex++;
        final stepPrefix = totalFiles > 1
            ? '($currentFileIndex/$totalFiles) '
            : '';
        final zipPath = p.join(toolsDir.path, 'dex2jar.zip');
        await _downloadFile(dex2jarUrl, zipPath, '${stepPrefix}Dex2Jar tools');

        status.value = 'Extracting Dex2Jar tools...';
        await _extractArchive(zipPath, toolsDir.path);
        if (File(zipPath).existsSync()) File(zipPath).deleteSync();

        if (Platform.isLinux || Platform.isMacOS) {
          status.value = 'Applying Dex2Jar permissions...';
          final dPath = await _paths.dex2jarPath;
          await Process.run('chmod', ['+x', dPath]);
          final dexBinDir = Directory(p.dirname(dPath));
          if (await dexBinDir.exists()) {
            await for (final file in dexBinDir.list()) {
              if (file is File && file.path.endsWith('.sh')) {
                await Process.run('chmod', ['+x', file.path]);
              }
            }
          }
        }
      }

      final ready = await checkIsReady();
      if (ready) {
        status.value = 'CloudStream runtime ready.';
      } else {
        throw Exception(
          'Runtime setup finished but components failed verification.',
        );
      }
    } catch (e) {
      errorMessage.value = e.toString().replaceFirst('Exception: ', '');
      status.value = 'Setup failed.';
      rethrow;
    } finally {
      isDownloading.value = false;
    }
  }

  Future<void> _downloadFile(String url, String savePath, String label) async {
    status.value = 'Downloading $label...';

    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Failed to download $label: HTTP ${response.statusCode}');
    }

    final totalSize = response.contentLength ?? 0;
    var downloaded = 0;
    final file = File(savePath);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloaded += chunk.length;

      if (totalSize > 0) {
        final pVal = (downloaded / totalSize).clamp(0.0, 1.0);
        progress.value = pVal;
        final mbDown = (downloaded / (1024 * 1024)).toStringAsFixed(1);
        final mbTotal = (totalSize / (1024 * 1024)).toStringAsFixed(1);
        status.value = 'Downloading $label: $mbDown MB / $mbTotal MB';
      } else {
        final mbDown = (downloaded / (1024 * 1024)).toStringAsFixed(1);
        status.value = 'Downloading $label: $mbDown MB';
      }
    }
    await sink.close();
  }

  Future<void> _extractArchive(String archivePath, String targetDir) async {
    final targetDirObj = Directory(targetDir);
    if (!await targetDirObj.exists()) {
      await targetDirObj.create(recursive: true);
    }

    if (archivePath.endsWith('.zip')) {
      final bytes = await File(archivePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final filename = file.name;
        final targetPath = safeChildPath(targetDir, filename);
        if (file.isFile) {
          final data = file.content as List<int>;
          File(targetPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(targetPath).createSync(recursive: true);
        }
      }
    } else if (archivePath.endsWith('.tar.gz')) {
      final bytes = await File(archivePath).readAsBytes();
      final gzipBytes = const GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzipBytes);
      for (final file in archive) {
        final filename = file.name;
        final targetPath = safeChildPath(targetDir, filename);
        if (file.isFile) {
          final data = file.content as List<int>;
          File(targetPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(targetPath).createSync(recursive: true);
        }
      }
    }

    await _flattenFolder(targetDir);
  }

  Future<void> _flattenFolder(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    final entities = await dir.list().toList();
    if (entities.length == 1 && entities.first is Directory) {
      final innerDir = entities.first as Directory;
      for (final entity in await innerDir.list().toList()) {
        final newPath = p.join(dirPath, p.basename(entity.path));
        await entity.rename(newPath);
      }
      try {
        await innerDir.delete();
      } catch (_) {}
    }
  }
}
