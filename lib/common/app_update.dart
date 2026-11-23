import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/release_asset.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart';
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
  windowsInstalled: system.isWindows && isInstalledWindowsBuild,
);

SelfUpdateAsset? get selfUpdateAsset => resolveSelfUpdateAsset();

@visibleForTesting
Future<bool> Function(Uri uri) launchReleasePage = launchUrl;

Future<bool> openReleasePage() {
  return launchReleasePage(
    Uri.https('github.com', '/$repository/releases/latest'),
  );
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
