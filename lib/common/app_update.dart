import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/macos_update.dart';
import 'package:fl_clash/common/release_asset.dart';
import 'package:fl_clash/common/release_version.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' hide windows;
import 'package:url_launcher/url_launcher.dart';

sealed class UpdateDownload {
  const UpdateDownload(this.tag);

  final String tag;
}

final class UpdateDownloading extends UpdateDownload {
  const UpdateDownloading(
    super.tag, {
    this.received = 0,
    this.total = 0,
    this.speedBytesPerSec = 0,
  });

  final int received;

  /// Zero until the server reports a length.
  final int total;

  final int speedBytesPerSec;
}

final class UpdateVerifying extends UpdateDownload {
  const UpdateVerifying(super.tag, {this.total = 0});

  final int total;
}

final class UpdateInstalling extends UpdateDownload {
  const UpdateInstalling(super.tag, this.path);

  final String path;
}

final class UpdateReady extends UpdateDownload {
  const UpdateReady(super.tag, this.path);

  final String path;
}

@visibleForTesting
SelfUpdateAsset? Function() resolveSelfUpdateAsset = () => selfUpdateAssetFor(
  Abi.current(),
  replaceable: system.isWindows
      ? isInstalledWindowsBuild
      : macosAppUpdate?.canReplace ?? false,
);

final MacosAppUpdate? macosAppUpdate = switch (system.isMacOS
    ? appBundleOf(Platform.resolvedExecutable)
    : null) {
  final bundle? => MacosAppUpdate(bundle),
  null => null,
};

Future<String> get macosInstallFailurePath async {
  return join(await appPath.updateDirPath, 'install-failed');
}

SelfUpdateAsset? get selfUpdateAsset => resolveSelfUpdateAsset();

@visibleForTesting
ReleaseOs? Function() resolveCurrentReleaseOs = () =>
    releaseOsForAbi(Abi.current());

ReleaseOs? get currentReleaseOs => resolveCurrentReleaseOs();

bool releaseHasAsset(Map<String, dynamic> release, SelfUpdateAsset asset) {
  final tag = release['tag_name'];
  if (tag is! String || tag.isEmpty) {
    return false;
  }
  final assets = release['assets'];
  if (assets is! List || assets.isEmpty) {
    return false;
  }
  final expected = updateAssetName(tag, asset);
  return assets.any((item) => item is Map && item['name'] == expected);
}

bool releaseSupportsPlatform(
  Map<String, dynamic> release, {
  SelfUpdateAsset? asset,
  ReleaseOs? os,
}) {
  if (asset != null) {
    return releaseHasAsset(release, asset);
  }
  if (os == null) {
    return false;
  }
  final tag = release['tag_name'];
  if (tag is! String || tag.isEmpty) {
    return false;
  }
  final assets = release['assets'];
  if (assets is! List || assets.isEmpty) {
    return false;
  }
  final prefix = '$releaseFilePrefix-${releaseVersionOfTag(tag)}-${os.name}-';
  return assets.any((item) {
    final name = item is Map ? item['name'] : null;
    return name is String && name.startsWith(prefix);
  });
}

@visibleForTesting
Future<bool> Function(Uri uri) launchReleasePage = launchUrl;

@visibleForTesting
bool? Function(String path, String arguments) runWindowsUpdateInstaller =
    (path, arguments) => windows?.runas(path, arguments);

bool? launchWindowsUpdateInstaller(String path, String arguments) =>
    runWindowsUpdateInstaller(path, arguments);

const appReleaseLine = ReleaseLine.dev;

const _builtReleaseTag = String.fromEnvironment('RELEASE_TAG');

/// A prerelease build carries only `X.Y.Z` as its version name, so the tag
/// tool/package.dart writes into env.json is what tells it apart.
ReleaseVersion installedReleaseVersion(
  String packageVersion, {
  String builtTag = _builtReleaseTag,
}) {
  return ReleaseVersion.tryParse(builtTag) ??
      ReleaseVersion.tryParse(packageVersion) ??
      const ReleaseVersion(0, 0, 0);
}

/// About names a prerelease by its tag, which its version name leaves out.
String installedVersionLabel(
  String packageVersion, {
  String builtTag = _builtReleaseTag,
}) => ReleaseVersion.tryParse(builtTag)?.toString() ?? 'v$packageVersion';

/// The installed version as the update card sets it beside a tag without its
/// leading `v`.
String installedVersionName(
  String packageVersion, {
  String builtTag = _builtReleaseTag,
}) => installedVersionLabel(
  packageVersion,
  builtTag: builtTag,
).replaceFirst(RegExp('^v'), '');

Future<bool> openReleasePage([String? tag]) {
  final path = tag != null && tag.isNotEmpty
      ? '/$repository/releases/tag/$tag'
      : '/$repository/releases/latest';
  return launchReleasePage(Uri.https('github.com', path));
}

Uri releaseAssetUri(String tag, String name) {
  return Uri.https('github.com', '/$repository/releases/download/$tag/$name');
}

Future<String> fileSha256(String path) {
  return Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  });
}

final _updateAssetVersion = RegExp(
  r'^FlClash-(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)-',
);

/// Removes downloaded installers for [currentVersion] or older from [directory]
/// while preserving a newer pending installer so tapping Update again reuses it
/// without re-downloading.
@visibleForTesting
Future<({int freedBytes, bool keptNewer})> cleanObsoleteUpdateFilesIn(
  String directory,
  String currentVersion,
) async {
  var freedBytes = 0;
  var keptNewer = false;
  final updateDir = Directory(directory);
  if (!await updateDir.exists()) {
    return (freedBytes: 0, keptNewer: false);
  }
  await for (final entity in updateDir.list(followLinks: false)) {
    if (entity is! File) {
      await safeDeletePath(entity.path);
      continue;
    }
    final match = _updateAssetVersion.firstMatch(basename(entity.path));
    final version = match?.group(1);
    final isNewer =
        version != null && compareVersions(version, currentVersion) > 0;
    if (isNewer) {
      keptNewer = true;
      continue;
    }
    freedBytes += await entity.length();
    await safeDeletePath(entity.path);
  }
  return (freedBytes: freedBytes, keptNewer: keptNewer);
}

Future<int> cleanObsoleteUpdateDownloads(String currentVersion) async {
  var freedBytes = 0;
  try {
    final result = await cleanObsoleteUpdateFilesIn(
      await appPath.updateDirPath,
      currentVersion,
    );
    freedBytes = result.freedBytes;
    if (!result.keptNewer) {
      final systemBytes = await app?.clearDownloads() ?? 0;
      if (systemBytes > freedBytes) {
        freedBytes = systemBytes;
      }
    }
  } on PlatformException catch (error) {
    commonPrint.log(
      'Clearing obsolete system downloads failed: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  } on FileSystemException catch (error) {
    commonPrint.log(
      'Clearing obsolete update downloads failed: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  }
  return freedBytes;
}

// The installer that relaunched the app may still hold its file open.
Future<int> clearUpdateDownloads() async {
  var dirBytes = 0;
  var systemBytes = 0;
  try {
    final updateDir = Directory(await appPath.updateDirPath);
    if (await updateDir.exists()) {
      await for (final entity in updateDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          dirBytes += await entity.length();
        }
      }
    }
    systemBytes = await app?.clearDownloads() ?? 0;
    await safeDeletePath(updateDir.path);
  } on PlatformException catch (error) {
    commonPrint.log(
      'Clearing system downloads failed: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  } on FileSystemException catch (error) {
    commonPrint.log(
      'Clearing update downloads failed: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  }
  return systemBytes > dirBytes ? systemBytes : dirBytes;
}

// Inno Setup writes unins000.exe beside the app; the portable zip has none.
bool get isInstalledWindowsBuild {
  return File(join(appPath.executableDirPath, 'unins000.exe')).existsSync();
}

// inno_setup.iss waits for `updatefrom` to exit, then relaunches the app.
String windowsUpdateArguments(int pid) {
  return '/SILENT /SUPPRESSMSGBOXES /NORESTART /SP- /updatefrom=$pid';
}
