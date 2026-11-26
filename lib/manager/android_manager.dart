import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/banner.dart';

class AndroidManager extends ConsumerStatefulWidget {
  final Widget child;

  const AndroidManager({super.key, required this.child});

  @override
  ConsumerState<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends ConsumerState<AndroidManager>
    with ServiceListener {
  @override
  void initState() {
    super.initState();
    ref.listenManual(appSettingProvider.select((state) => state.hidden), (
      prev,
      next,
    ) {
      app?.updateExcludeFromRecents(next);
    }, fireImmediately: true);
    ref.listenManual(loadedLocaleProvider, (prev, next) {
      if (prev != null && prev != next && !safeModeBuild) {
        app?.initShortcuts();
      }
    });
    ref.listenManual(sharedStateProvider, (prev, next) {
      if (prev != next) {
        debouncer.call(FunctionTag.saveSharedFile, () async {
          await preferences.saveShareState(next);
        }, duration: const Duration(seconds: 1));
        if (prev?.needSyncSharedState != next.needSyncSharedState) {
          service?.syncState(next.needSyncSharedState);
        }
      }
    });
    ref.listenManual(appVisibleProvider, (prev, next) {
      if (prev != next) {
        unawaited(service?.setTelemetryPaused(!next));
      }
    }, fireImmediately: true);
    ref.listenManual(
      currentProfileProvider,
      (_, _) => _scheduleWidgetSync(),
      fireImmediately: true,
    );
    ref.listenManual(
      activeProxyTargetProvider,
      (_, _) => _scheduleWidgetSync(),
    );
    ref.listenManual(delayDataSourceProvider, (_, _) => _scheduleWidgetSync());
    ref.listenManual(
      subscriptionInsightsProvider,
      (_, _) => _scheduleWidgetSync(),
    );
    ref.listenManual(profileSecurityProvider, (_, _) => _scheduleWidgetSync());
    ref.listenManual(speedBoostPresetProvider, (_, _) => _scheduleWidgetSync());
    ref.listenManual(
      expiryAlertsEnabledProvider,
      (_, _) => _scheduleWidgetSync(),
    );
    ref.listenManual(isStartProvider, (_, _) => _scheduleWidgetSync());
    service?.addListener(this);
    app?.onPackagesChanged = _reloadPackages;
    app?.onSwitchFastestProxy = _switchFastestProxy;
  }

  void _scheduleWidgetSync() {
    debouncer.call(FunctionTag.syncHomeWidget, () async {
      if (!mounted) return;
      final profile = ref.read(currentProfileProvider);
      final target = ref.read(activeProxyTargetProvider);
      final groups = ref.read(groupsProvider);
      final selectedMap = ref.read(selectedMapProvider);
      final delayMap = ref.read(delayDataSourceProvider);
      final delayMs = target == null
          ? null
          : computeProxyDelayState(
              proxyName: target.proxyName,
              testUrl: target.testUrl,
              groups: groups,
              selectedMap: selectedMap,
              delayMap: delayMap,
            ).delay;
      final deviceMeta = profile == null
          ? null
          : ref.read(effectiveProfileDeviceMetaProvider(profile.id));
      final security = profile == null
          ? null
          : ref.read(profileSecurityProvider)[profile.id];
      final expireSec = profile?.subscriptionInfo?.expire;
      await app?.updateHomeWidget(
        profileName: profile?.realLabel ?? '',
        activeNode: target?.proxyName ?? '',
        activeDelayMs: delayMs != null && delayMs > 0 ? delayMs : null,
        onlineDevices: deviceMeta?.onlineDevices,
        deviceLimit: deviceMeta?.deviceLimit,
        expireEpochSec: expireSec != null && expireSec > 0 ? expireSec : null,
        securityLevel: security?.level.name ?? 'safe',
        securityScore: security?.score ?? 100,
        speedBoost: ref.read(speedBoostPresetProvider),
        expiryAlertsEnabled: ref.read(expiryAlertsEnabledProvider),
      );
    }, duration: const Duration(milliseconds: 600));
  }

  /// A reload reads every installed app's label, and a round of store updates
  /// reports each app on its own.
  void _switchFastestProxy() {
    unawaited(
      ref.read(proxiesActionProvider.notifier).selectFastestActiveGroup(),
    );
  }

  void _reloadPackages() {
    if (ref.read(packagesProvider).isEmpty) {
      return;
    }
    debouncer.call(FunctionTag.reloadPackages, () async {
      if (mounted) {
        await ref.read(systemActionProvider.notifier).getPackages();
      }
    }, duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    debouncer.cancel(FunctionTag.reloadPackages);
    debouncer.cancel(FunctionTag.syncHomeWidget);
    if (app?.onPackagesChanged == _reloadPackages) {
      app?.onPackagesChanged = null;
    }
    if (app?.onSwitchFastestProxy == _switchFastestProxy) {
      app?.onSwitchFastestProxy = null;
    }
    service?.removeListener(this);
    super.dispose();
  }

  @override
  void onServiceEvent(CoreEvent event) {
    coreEventManager.sendEvent(event);
    super.onServiceEvent(event);
  }

  @override
  void onServiceStopped([ServiceStartFailure? failure]) {
    unawaited(ref.read(setupActionProvider.notifier).setRunning(false));
    if (failure != null) {
      dialogs.showBanner(failure.label, level: BannerLevel.error);
    }
    super.onServiceStopped(failure);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
