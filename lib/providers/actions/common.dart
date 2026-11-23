part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;
  bool _isUpdateDialogOpen = false;
  CancelToken? _updateCancelToken;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    if (running && ref.read(coreStatusProvider) == CoreStatus.disconnected) {
      ref.read(setupActionProvider.notifier).resumeOnRestart();
      unawaited(
        globalState.safeRun(ref.read(coreActionProvider.notifier).restartCore),
      );
      return;
    }
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await request.checkForUpdate();
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      final tag = data['tag_name'] as String;
      var existing = ref.read(updateDownloadStateProvider);
      if (existing is UpdateReady && !File(existing.path).existsSync()) {
        ref.read(updateDownloadStateProvider.notifier).value = null;
        existing = null;
      }
      if (existing is UpdateReady && existing.tag == tag) {
        if (isUser) {
          unawaited(installUpdate());
        }
        return;
      }
      if (existing != null && existing.tag == tag) {
        if (isUser) {
          dialogs.showBanner(
            existing is UpdateInstalling
                ? currentAppLocalizations.updateInstalling
                : currentAppLocalizations.updateDownloadStarted,
          );
        }
        return;
      }
      if (_isUpdateDialogOpen) return;
      _isUpdateDialogOpen = true;
      final bool? res;
      final asset = selfUpdateAsset;
      try {
        res = await dialogs.showMessage(
          title: currentAppLocalizations.discoverNewVersion,
          message: _releaseSpan(context, tag, data['body'] as String?),
          confirmText: asset == null
              ? currentAppLocalizations.goDownload
              : currentAppLocalizations.update,
          cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
        );
      } finally {
        _isUpdateDialogOpen = false;
      }
      if (res == true) {
        if (asset == null) {
          _openReleasePage();
        } else {
          unawaited(_downloadUpdate(tag, updateAssetName(tag, asset)));
        }
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }

  void _openReleasePage() {
    unawaited(openReleasePage());
  }

  /// Downloads the latest release for this build even when it is not newer.
  Future<void> testUpdateDownload() async {
    final asset = selfUpdateAsset;
    if (asset == null || ref.read(updateDownloadStateProvider) != null) {
      return;
    }
    final release = await globalState.loadingRun(
      request.latestRelease,
      title: currentAppLocalizations.updateDownloadTest,
      tag: LoadingTag.checkUpdate,
    );
    if (release == null) return;
    final tag = release['tag_name'] as String;
    await _downloadUpdate(tag, updateAssetName(tag, asset));
  }

  Future<void> _downloadUpdate(String tag, String name) async {
    final download = ref.read(updateDownloadStateProvider.notifier);
    final existing = download.value;
    if (existing != null) {
      if (existing is UpdateReady &&
          existing.tag == tag &&
          File(existing.path).existsSync()) {
        unawaited(installUpdate());
        return;
      }
      if (existing.tag == tag || existing is UpdateInstalling) {
        return;
      }
      cancelUpdateDownload();
    }
    final cancelToken = CancelToken();
    _updateCancelToken = cancelToken;
    download.value = UpdateDownloading(tag);
    dialogs.showBanner(currentAppLocalizations.updateDownloadStarted);
    try {
      final directory = await appPath.updateDirPath;
      final updateDir = Directory(directory);
      if (await updateDir.exists()) {
        await for (final entity in updateDir.list(followLinks: false)) {
          if (basename(entity.path) != name) {
            await safeDeletePath(entity.path);
          }
        }
      } else {
        await updateDir.create(recursive: true);
      }
      var shown = 0;
      var lastTotal = 0;
      var lastSampleAt = DateTime.now();
      var lastSampleBytes = 0;
      var smoothedSpeed = 0;
      final path = await request.downloadVerifiedRelease(
        tag: tag,
        name: name,
        directory: directory,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          lastTotal = total;
          final now = DateTime.now();
          final elapsedMs = now.difference(lastSampleAt).inMilliseconds;
          if (elapsedMs >= 250 || (received == total && elapsedMs > 0)) {
            final delta = received - lastSampleBytes;
            if (delta > 0 && elapsedMs > 0) {
              final instant = (delta * 1000) ~/ elapsedMs;
              smoothedSpeed = smoothedSpeed == 0
                  ? instant
                  : (smoothedSpeed * 6 + instant * 4) ~/ 10;
            }
            lastSampleAt = now;
            lastSampleBytes = received;
          }
          // Every chunk would otherwise rebuild the status on its own frame.
          final step = total > 0 ? total / 100 : 1 << 20;
          if (received - shown < step && elapsedMs < 250 && received != total) {
            return;
          }
          shown = received;
          download.value = UpdateDownloading(
            tag,
            received: received,
            total: total,
            speedBytesPerSec: smoothedSpeed,
          );
        },
        onVerifying: () {
          download.value = UpdateVerifying(tag, total: lastTotal);
        },
      );
      download.value = UpdateReady(tag, path);
      final isResumed =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (system.isAndroid && app != null && isResumed) {
        unawaited(installUpdate());
      } else {
        dialogs.showBanner(
          currentAppLocalizations.updateReadyTip,
          level: BannerLevel.success,
          onTap: () => unawaited(installUpdate()),
        );
      }
    } catch (error) {
      download.value = null;
      await clearUpdateDownloads();
      if (error is DioException && CancelToken.isCancel(error)) {
        return;
      }
      if (error is ReleaseFileMissingException) {
        _openReleasePage();
        dialogs.showBanner(currentAppLocalizations.updateFileMissing);
        return;
      }
      commonPrint.log(
        'Update download failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      await _showUpdateFailure(
        userFacingErrorMessage(error, currentAppLocalizations),
      );
    } finally {
      if (identical(_updateCancelToken, cancelToken)) {
        _updateCancelToken = null;
      }
    }
  }

  void cancelUpdateDownload() {
    _updateCancelToken?.cancel();
  }

  Future<void> discardUpdate() async {
    if (ref.read(updateDownloadStateProvider) is! UpdateReady) return;
    ref.read(updateDownloadStateProvider.notifier).value = null;
    await clearUpdateDownloads();
  }

  Future<void> installUpdate() async {
    final download = ref.read(updateDownloadStateProvider);
    if (download is! UpdateReady) return;
    if (system.isAndroid) {
      ref.read(updateDownloadStateProvider.notifier).value = UpdateInstalling(
        download.tag,
        download.path,
      );
      final status = await app?.installPackage(download.path);
      if (status != null && packageInstallAborted(status)) {
        ref.read(updateDownloadStateProvider.notifier).value = UpdateReady(
          download.tag,
          download.path,
        );
        return;
      }
      if (status != null && packageInstallFailed(status)) {
        ref.read(updateDownloadStateProvider.notifier).value =
            File(download.path).existsSync() ? download : null;
        await _showUpdateFailure(currentAppLocalizations.updateInstallFailed);
        return;
      }
      ref.read(updateDownloadStateProvider.notifier).value = null;
      await clearUpdateDownloads();
      return;
    }
    final started = windows?.runas(download.path, windowsUpdateArguments(pid));
    if (started == true) {
      await ref.read(systemActionProvider.notifier).handleExit();
    } else if (started == false) {
      await _showUpdateFailure(currentAppLocalizations.updateInstallFailed);
    }
  }

  Future<void> _showUpdateFailure(String message) async {
    final res = await dialogs.showMessage(
      title: currentAppLocalizations.updateFailed,
      message: TextSpan(text: message),
      confirmText: currentAppLocalizations.goDownload,
    );
    if (res == true) {
      _openReleasePage();
    }
  }
}
