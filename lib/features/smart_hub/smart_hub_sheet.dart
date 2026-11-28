import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/ip_quality/leak_check_sheet.dart';
import 'package:fl_clash/features/smart_hub/portal_connect_sheet.dart';
import 'package:fl_clash/features/smart_hub/profile_security_sheet.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/widgets/profile_detail.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showSmartHubSheet(BuildContext context) {
  return showNestedSheet<void>(context, builder: (_) => const SmartHubSheet());
}

class SmartHubSheet extends ConsumerStatefulWidget {
  const SmartHubSheet({super.key});

  @override
  ConsumerState<SmartHubSheet> createState() => _SmartHubSheetState();
}

class _SmartHubSheetState extends ConsumerState<SmartHubSheet> {
  static const _builtinNames = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'};
  static const _selfHealSlowThresholdMs = 700;
  static const _multiWebTargets = [
    ServiceTarget.google,
    ServiceTarget.youtube,
    ServiceTarget.tiktok,
    ServiceTarget.chatgpt,
    ServiceTarget.github,
    ServiceTarget.discord,
  ];

  bool _footprintLoading = false;
  SessionFootprint? _footprint;
  bool _healing = false;
  int _healStep = 0;
  String? _healSummary;
  bool _healSuccess = true;
  bool _checkingWebs = false;
  Map<ServiceTarget, ServiceCheck>? _webResults;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshFootprint());
  }

  Future<void> _refreshFootprint({bool manual = false}) async {
    final profile = ref.read(currentProfileProvider);
    if (profile != null) {
      unawaited(
        ref
            .read(profilesActionProvider.notifier)
            .refreshPortalStatus(profile, force: manual),
      );
      if (manual ||
          !ref.read(profileSecurityProvider).containsKey(profile.id)) {
        unawaited(
          ref.read(profileSecurityProvider.notifier).scanProfile(profile),
        );
      }
    }
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      if (mounted) {
        setState(() {
          _footprint = null;
          _footprintLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _footprintLoading = true);
    }
    try {
      final footprint = await ref
          .read(coreActionProvider.notifier)
          .inspectSessionFootprint();
      if (!mounted) return;
      setState(() {
        _footprint = footprint;
        _footprintLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _footprintLoading = false);
    }
  }

  Proxy? _resolveActiveLeafProxy() {
    final target = ref.read(activeProxyTargetProvider);
    if (target == null || _builtinNames.contains(target.proxyName)) {
      return null;
    }
    final groups = ref.read(groupsProvider);
    return groups
        .expand((g) => g.all)
        .firstWhereOrNull((p) => p.name == target.proxyName);
  }

  int? _readActiveDelayMs() {
    final target = ref.read(activeProxyTargetProvider);
    if (target == null) return null;
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(selectedMapProvider);
    final delayMap = ref.read(delayDataSourceProvider);
    return computeProxyDelayState(
      proxyName: target.proxyName,
      testUrl: target.testUrl,
      groups: groups,
      selectedMap: selectedMap,
      delayMap: delayMap,
    ).delay;
  }

  Future<void> _runSelfHeal() async {
    if (_healing) return;
    final l = context.appLocalizations;
    if (!ref.read(isStartProvider)) {
      dialogs.showBanner(l.smartHealStartVpnFirst, level: BannerLevel.warning);
      return;
    }
    setState(() {
      _healing = true;
      _healStep = 1;
      _healSummary = null;
    });
    final coreAction = ref.read(coreActionProvider.notifier);
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    try {
      await coreAction.clearDnsCache();
      await coreAction.closeConnections();
      if (!mounted) return;

      setState(() => _healStep = 2);
      final target = ref.read(activeProxyTargetProvider);
      final leaf = _resolveActiveLeafProxy();
      int? activeDelay;
      if (target != null && leaf != null) {
        await proxiesAction.proxyDelayTest(leaf, target.testUrl);
        if (!mounted) return;
        activeDelay = _readActiveDelayMs();
      }

      if ((leaf == null ||
              activeDelay == null ||
              activeDelay <= 0 ||
              activeDelay >= _selfHealSlowThresholdMs) &&
          ref.read(isStartProvider)) {
        setState(() => _healStep = 3);
        await proxiesAction.selectFastestActiveGroup(
          automatic: true,
          manualHeal: true,
        );
        if (!mounted) return;
        activeDelay = _readActiveDelayMs();
      }

      setState(() => _healStep = 4);
      await _refreshFootprint();
      if (!mounted) return;

      final finalTarget = ref.read(activeProxyTargetProvider);
      final nodeName = finalTarget?.proxyName ?? '';
      final finalDelay = _readActiveDelayMs();
      final healthy =
          finalDelay != null && finalDelay > 0 && nodeName.isNotEmpty;
      final switched =
          target != null &&
          finalTarget != null &&
          target.proxyName != finalTarget.proxyName;

      final summary = healthy
          ? (switched
                ? l.smartHealDoneSwitched(nodeName)
                : l.smartHealDoneHealthy(nodeName, '${finalDelay}ms'))
          : l.smartHealDoneFailed;

      setState(() {
        _healing = false;
        _healSuccess = healthy;
        _healSummary = summary;
      });
      dialogs.showBanner(
        summary,
        level: healthy ? BannerLevel.success : BannerLevel.warning,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _healing = false;
        _healSuccess = false;
        _healSummary = l.smartHealDoneFailed;
      });
      dialogs.showBanner(l.smartHealDoneFailed, level: BannerLevel.warning);
    }
  }

  Future<void> _cleanupExtraStreams() async {
    final l = context.appLocalizations;
    await ref.read(coreActionProvider.notifier).closeConnections();
    await _refreshFootprint();
    if (!mounted) return;
    dialogs.showBanner(l.smartFootprintCleanedTip, level: BannerLevel.success);
  }

  Future<void> _applySingleDeviceGuard() async {
    final l = context.appLocalizations;
    ref.read(autoFailoverProvider.notifier).setEnabled(false);
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(closeConnections: true));
    if (system.isAndroid) {
      ref
          .read(vpnSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              ipv6: false,
              dnsHijacking: true,
              allowBypass: false,
            ),
          );
    }
    ref.read(patchClashConfigProvider.notifier).update((state) {
      return state.copyWith(
        ipv6: false,
        generalOverrideKeys: {
          ...state.generalOverrideKeys,
          GeneralOverrideKey.ipv6,
        },
        tunOverride: system.isDesktop
            ? state.tunOverride.copyWith(strictRoute: true)
            : state.tunOverride,
        tunOverrideKeys: system.isDesktop
            ? {...state.tunOverrideKeys, TunOverrideKey.strictRoute}
            : state.tunOverrideKeys,
      );
    });
    if (system.isDesktop) {
      ref
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(appendSystemDns: false));
    }
    await ref.read(setupActionProvider.notifier).applyPresetAndSyncTunnel();
    if (ref.read(coreStatusProvider) == CoreStatus.connected) {
      await ref.read(coreActionProvider.notifier).closeConnections();
      await _refreshFootprint();
    }
    if (!mounted) return;
    dialogs.showBanner(
      l.smartModeSingleDeviceApplied,
      level: BannerLevel.success,
    );
  }

  void _togglePrivacyMax(bool enable) {
    final l = context.appLocalizations;
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(hideIp: enable));
    if (system.isAndroid || system.isWindows) {
      ref.read(privacyScreenShieldProvider.notifier).value = enable;
    }
    if (enable) {
      dialogs.showBanner(l.smartModePrivacyMaxApplied);
    }
  }

  Future<void> _toggleOptimize4g(bool enable) async {
    final l = context.appLocalizations;
    final notifier = ref.read(optimize4gPresetProvider.notifier);
    if (enable) {
      await notifier.enablePreset();
    } else {
      await notifier.disablePresetAndRestore();
    }
    if (!mounted) return;
    await ref.read(setupActionProvider.notifier).applyPresetAndSyncTunnel();
    if (!mounted) return;
    if (enable) {
      dialogs.showBanner(l.optimize4gAppliedTip);
    }
  }

  Future<void> _toggleSpeedBoost(bool enable) async {
    final l = context.appLocalizations;
    final notifier = ref.read(speedBoostPresetProvider.notifier);
    if (enable) {
      await notifier.enablePreset();
    } else {
      await notifier.disablePresetAndRestore();
    }
    if (!mounted) return;
    await ref.read(setupActionProvider.notifier).applyPresetAndSyncTunnel();
    if (!mounted) return;
    if (enable) {
      dialogs.showBanner(l.speedBoostAppliedTip, level: BannerLevel.success);
    }
  }

  Future<void> _runMultiWebCheck() async {
    if (_checkingWebs) return;
    final l = context.appLocalizations;
    if (!ref.read(isStartProvider)) {
      dialogs.showBanner(l.smartHealStartVpnFirst, level: BannerLevel.warning);
      return;
    }
    setState(() => _checkingWebs = true);
    try {
      final results = await checkServices(
        ref.read(coreHandlerProvider),
        targets: _multiWebTargets,
        timeout: const Duration(seconds: 5),
      );
      if (!mounted) return;
      setState(() {
        _webResults = results;
        _checkingWebs = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingWebs = false);
      dialogs.showBanner(l.serviceFailed, level: BannerLevel.warning);
    }
  }

  String _probeStatusLabel(BuildContext context, ServiceProbeStatus status) {
    final l = context.appLocalizations;
    return switch (status) {
      ServiceProbeStatus.available => l.serviceAvailable,
      ServiceProbeStatus.restricted => l.serviceRestricted,
      ServiceProbeStatus.unavailable => l.serviceUnavailable,
      ServiceProbeStatus.disallowedIsp => l.serviceDisallowedIsp,
      ServiceProbeStatus.blocked => l.serviceBlocked,
      ServiceProbeStatus.unsupportedRegion => l.serviceUnsupportedRegion,
      ServiceProbeStatus.originalsOnly => l.serviceOriginalsOnly,
      ServiceProbeStatus.comingSoon => l.serviceComingSoon,
      ServiceProbeStatus.timeout => l.timeout,
      ServiceProbeStatus.failed => l.serviceFailed,
    };
  }

  String _multiWebSummaryText(BuildContext context) {
    final l = context.appLocalizations;
    final results = _webResults;
    if (results == null || results.isEmpty) {
      return l.smartMultiWebDesc;
    }
    var okCount = 0;
    var delaySum = 0;
    var delayCount = 0;
    final perSite = <String>[];
    for (final target in _multiWebTargets) {
      final item = results[target];
      if (item == null) continue;
      final reachableYoutube =
          target == ServiceTarget.youtube &&
          item.status == ServiceProbeStatus.unsupportedRegion &&
          (item.delay ?? 0) > 0;
      if (item.status == ServiceProbeStatus.available || reachableYoutube) {
        okCount++;
        final regionTag = (item.region != null && item.region!.isNotEmpty)
            ? ' (${item.region})'
            : '';
        if (item.delay != null && item.delay! > 0) {
          delaySum += item.delay!;
          delayCount++;
          perSite.add('${target.label} ${item.delay}ms$regionTag');
        } else {
          perSite.add('${target.label} OK$regionTag');
        }
      } else {
        final issue = _probeStatusLabel(context, item.status);
        final delayPrefix = (item.delay != null && item.delay! > 0)
            ? '${item.delay}ms · '
            : '';
        perSite.add('${target.label} ($delayPrefix$issue)');
      }
    }
    final avgMs = delayCount > 0 ? (delaySum ~/ delayCount) : 0;
    final headline = l.smartMultiWebSummary(
      okCount,
      _multiWebTargets.length,
      avgMs,
    );
    return perSite.isEmpty ? headline : '$headline\n${perSite.join(' · ')}';
  }

  Future<void> _pinHomeWidget() async {
    final l = context.appLocalizations;
    final requested = await app?.pinHomeWidget() ?? false;
    if (!mounted) return;
    dialogs.showBanner(
      requested ? l.homeWidgetPinRequested : l.homeWidgetPinFallback,
      level: requested ? BannerLevel.success : BannerLevel.info,
    );
  }

  String _healStepLabel(BuildContext context, int step) {
    final l = context.appLocalizations;
    return switch (step) {
      1 => l.smartHealStepClean,
      2 => l.smartHealStepProbe,
      3 => l.smartHealStepFallback,
      _ => l.smartHealStepVerify,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final colors = context.colorScheme;
    final profile = ref.watch(currentProfileProvider);
    final deviceMeta = profile == null
        ? null
        : ref.watch(effectiveProfileDeviceMetaProvider(profile.id));
    final portalBinding = profile == null
        ? null
        : ref.watch(portalAccountsProvider.select((s) => s[profile.id]));
    final forecast = ref.watch(currentQuotaForecastProvider);
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final dns = ref.watch(
      patchClashConfigProvider.select((state) => state.dns),
    );
    final ipv6Enabled = system.isAndroid
        ? ref.watch(vpnSettingProvider.select((state) => state.ipv6))
        : ref.watch(patchClashConfigProvider.select((state) => state.ipv6));
    final activeTarget = ref.watch(activeProxyTargetProvider);
    final groups = ref.watch(groupsProvider);
    final selectedMap = ref.watch(selectedMapProvider);
    final delayMap = ref.watch(delayDataSourceProvider);
    final activeDelayMs = activeTarget == null
        ? null
        : computeProxyDelayState(
            proxyName: activeTarget.proxyName,
            testUrl: activeTarget.testUrl,
            groups: groups,
            selectedMap: selectedMap,
            delayMap: delayMap,
          ).delay;

    final health = evaluateConnectionHealth(
      isRunning: isStart,
      suspended: suspended,
      activeDelayMs: activeDelayMs,
      dns: dns,
      ipv6Enabled: ipv6Enabled,
      isMobile: system.isAndroid,
      footprint: _footprint,
    );

    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    final supportsScreenShield = system.isAndroid || system.isWindows;
    final screenShield = supportsScreenShield
        ? ref.watch(privacyScreenShieldProvider)
        : false;
    final privacyMaxEnabled = hideIp && (!supportsScreenShield || screenShield);
    final optimize4gEnabled = ref.watch(optimize4gPresetProvider);
    final speedBoostEnabled = ref.watch(speedBoostPresetProvider);
    final expiryAlertsEnabled = ref.watch(expiryAlertsEnabledProvider);
    final dailyTrafficEnabled = ref.watch(dailyTrafficEnabledProvider);
    final dailyLedger = ref.watch(dailyTrafficProvider);
    final securityReport = profile == null
        ? null
        : ref.watch(profileSecurityProvider.select((s) => s[profile.id]));
    final autoFailover = ref.watch(autoFailoverProvider);
    final closeConnections = ref.watch(
      appSettingProvider.select((state) => state.closeConnections),
    );
    final singleDeviceGuarded =
        !autoFailover && closeConnections && !ipv6Enabled;

    final healthColor = switch (health.grade) {
      HealthGrade.excellent => colors.success,
      HealthGrade.stable => colors.primary,
      HealthGrade.attention => colors.warning,
      HealthGrade.stopped => colors.onSurfaceVariant,
    };
    final healthLabel = switch (health.grade) {
      HealthGrade.excellent =>
        '${health.score}/100 · ${l.smartHealthExcellent}',
      HealthGrade.stable => '${health.score}/100 · ${l.smartHealthStable}',
      HealthGrade.attention =>
        '${health.score}/100 · ${l.smartHealthAttention}',
      HealthGrade.stopped => l.smartHealthStopped,
    };

    final footprint = _footprint;
    final footprintText = !isStart
        ? l.smartFootprintIdle
        : footprint == null
        ? '...'
        : footprint.isSingleNodeSafe
        ? l.smartFootprintSingle(
            footprint.activeProxyNodes.firstOrNull ??
                activeTarget?.proxyName ??
                '—',
            footprint.proxiedConnections,
          )
        : l.smartFootprintMultiWarn(
            footprint.activeNodeCount,
            footprint.proxiedConnections,
          );

    final deviceValue = deviceMeta?.badgeLabel != null
        ? l.devicesShort(deviceMeta!.badgeLabel!)
        : l.devicesNotReported;
    final deviceColor = deviceMeta == null
        ? colors.onSurfaceVariant
        : deviceMeta.isOverLimit
        ? colors.error
        : deviceMeta.isAtLimit
        ? colors.warning
        : colors.success;

    return Scaffold(
      title: l.smartHubTitle,
      actions: [
        AppBarActionButton(
          data: IconButtonData(
            glyph: AppGlyphs.refresh,
            tooltip: l.retry,
            isLoading: _footprintLoading,
            onPressed: () => unawaited(_refreshFootprint(manual: true)),
          ),
        ),
      ],
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 20 + context.bottomInset,
        ),
        children: [
          generateSection(
            title: l.smartHealthTitle,
            items: [
              DetailRow(
                title: l.status,
                value: Text(
                  healthLabel,
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: healthColor),
                ),
              ),
              DetailRow(
                title: l.smartSelfHealTitle,
                value: Text(
                  _healing
                      ? _healStepLabel(context, _healStep)
                      : (_healSummary ?? l.smartSelfHealDesc),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(
                        color: _healSummary == null
                            ? colors.onSurfaceVariant
                            : (_healSuccess ? colors.success : colors.warning),
                      ),
                ),
              ),
              ListItem(
                leading: _healing
                    ? const ActivityIndicator(size: 18)
                    : const GlyphIcon(AppGlyphs.bolt),
                title: Text(
                  _healing ? l.smartSelfHealRunning : l.smartSelfHealRun,
                ),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: _healing ? null : () => unawaited(_runSelfHeal()),
              ),
              ListItem(
                leading: _checkingWebs
                    ? const ActivityIndicator(size: 18)
                    : const GlyphIcon(AppGlyphs.radar),
                title: Text(
                  _checkingWebs ? l.smartMultiWebRunning : l.smartMultiWebTitle,
                ),
                subtitle: Text(
                  _multiWebSummaryText(context),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: _checkingWebs
                    ? null
                    : () => unawaited(_runMultiWebCheck()),
              ),
            ],
          ),
          generateSection(
            title: l.activeDevices,
            items: [
              if (deviceMeta?.planName case final planName?)
                DetailRow(
                  title: l.planName,
                  value: Text(
                    planName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              DetailRow(
                title: profile?.realLabel ?? l.profile,
                value: Text(
                  deviceValue,
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: deviceColor),
                ),
              ),
              DetailRow(
                title: l.smartFootprintTitle,
                value: _footprintLoading
                    ? const SkeletonText(width: 96)
                    : Text(
                        footprintText,
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(
                              color:
                                  footprint != null &&
                                      !footprint.isSingleNodeSafe
                                  ? colors.error
                                  : colors.onSurface,
                            ),
                      ),
              ),
              if (footprint != null && !footprint.isSingleNodeSafe)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.broom),
                  title: Text(l.smartFootprintCleanup),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: () => unawaited(_cleanupExtraStreams()),
                ),
              if (profile != null)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.account),
                  title: Text(l.portalAccountSync),
                  subtitle: Text(
                    switch (portalBinding) {
                      null => l.portalConnectSubtitle,
                      final b when b.authExpired => l.portalSessionExpired,
                      final b => l.portalConnectedAs(b.email),
                    },
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: () =>
                      unawaited(showPortalConnectSheet(context, profile)),
                ),
              if (profile != null && profile.type == ProfileType.url)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.sync),
                  title: Text(l.update),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: () => unawaited(syncProfile(ref, profile)),
                ),
              if (deviceMeta?.portalUrl case final portalUrl?)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.openExternal),
                  title: Text(l.openPlanPortal),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: () => unawaited(dialogs.openUrl(portalUrl)),
                ),
            ],
          ),
          generateSection(
            title: l.smartModesSection,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.verified),
                title: Text(l.smartModeSingleDevice),
                subtitle: Text(l.smartModeSingleDeviceDesc),
                value: singleDeviceGuarded,
                onChanged: (value) {
                  if (value) {
                    unawaited(_applySingleDeviceGuard());
                  } else {
                    ref.read(autoFailoverProvider.notifier).setEnabled(true);
                  }
                },
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.lock),
                title: Text(l.smartModePrivacyMax),
                subtitle: Text(l.smartModePrivacyMaxDesc),
                value: privacyMaxEnabled,
                onChanged: _togglePrivacyMax,
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.sparkle),
                title: Text(l.optimize4gPreset),
                subtitle: Text(l.optimize4gPresetDesc),
                value: optimize4gEnabled,
                onChanged: (value) => unawaited(_toggleOptimize4g(value)),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.speed),
                title: Text(l.speedBoostPreset),
                subtitle: Text(l.speedBoostPresetDesc),
                value: speedBoostEnabled,
                onChanged: (value) => unawaited(_toggleSpeedBoost(value)),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(l.expiryAlertsToggle),
                subtitle: Text(l.expiryAlertsToggleDesc),
                value: expiryAlertsEnabled,
                onChanged: (value) {
                  ref.read(expiryAlertsEnabledProvider.notifier).value = value;
                },
              ),
              if (profile != null)
                ListItem(
                  leading: GlyphIcon(
                    securityReport?.isDangerous == true
                        ? AppGlyphs.warning
                        : AppGlyphs.verified,
                    color: switch (securityReport?.level) {
                      ProfileRiskLevel.danger => colors.error,
                      ProfileRiskLevel.caution => colors.warning,
                      ProfileRiskLevel.safe => colors.success,
                      null => null,
                    },
                  ),
                  title: Text(l.securityAuditTitle),
                  subtitle: Text(
                    securityReport == null
                        ? l.securityAuditSubtitle
                        : l.securityAuditSummary(
                            securityReport.score,
                            switch (securityReport.level) {
                              ProfileRiskLevel.danger => l.securityLevelDanger,
                              ProfileRiskLevel.caution =>
                                l.securityLevelCaution,
                              ProfileRiskLevel.safe => l.securityLevelSafe,
                            },
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: () =>
                      unawaited(showProfileSecuritySheet(context, profile)),
                ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.radar),
                title: Text(l.leakCheckTitle),
                subtitle: Text(l.leakCheckDesc),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => unawaited(showLeakCheckSheet(context)),
              ),
              if (system.isAndroid)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.customize),
                  title: Text(l.homeWidgetAddTitle),
                  subtitle: Text(l.homeWidgetAddDesc),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward),
                  onTap: () => unawaited(_pinHomeWidget()),
                ),
            ],
          ),
          if (dailyTrafficEnabled)
            generateSection(
              title: l.dailyTraffic,
              items: [
                for (final (label, stats) in [
                  (
                    l.dailyTrafficToday,
                    (
                      up: dailyLedger.today().up,
                      down: dailyLedger.today().down,
                      total: dailyLedger.today().total,
                    ),
                  ),
                  (l.dailyTraffic7Days, dailyLedger.sumDays(7)),
                  (l.dailyTraffic30Days, dailyLedger.sumDays(30)),
                ])
                  DetailRow(
                    title: label,
                    value: Text(
                      '${stats.total.traffic.show} (↓ ${stats.down.traffic.show} · ↑ ${stats.up.traffic.show})',
                    ),
                  ),
              ],
            ),
          if (forecast != null)
            generateSection(
              title: l.quotaForecast,
              items: [
                DetailRow(
                  title: l.quotaForecast,
                  value: Text(
                    _formatForecastText(context, forecast),
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(
                          color: switch (forecast.status) {
                            QuotaBurnStatus.exhausted ||
                            QuotaBurnStatus.critical => colors.error,
                            QuotaBurnStatus.tight => colors.warning,
                            QuotaBurnStatus.comfortable => colors.success,
                          },
                        ),
                  ),
                ),
                if (forecast.dailyBudgetBytes case final budget?)
                  DetailRow(
                    title: l.dailyTraffic,
                    value: Text(l.quotaDailyBudget(budget.traffic.show)),
                  ),
              ],
            ),
          if (footprint != null && footprint.topConsumers.isNotEmpty)
            generateSection(
              title: l.smartTopConsumers,
              items: [
                for (final consumer in footprint.topConsumers)
                  ListItem(
                    title: Text(
                      consumer.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${consumer.outbound.isNotEmpty ? consumer.outbound : 'DIRECT'} · ${consumer.activeStreams}',
                    ),
                    trailing: Text(
                      consumer.totalBytes.traffic.show,
                      style: AppTextStyle.subheadline.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _formatForecastText(BuildContext context, QuotaForecast forecast) {
    final l = context.appLocalizations;
    if (forecast.status == QuotaBurnStatus.exhausted) {
      return l.quotaExhaustedHint;
    }
    if (forecast.avgDailyBytes <= 0) {
      return l.quotaAvgDaily(0.traffic.show);
    }
    final avgLabel = forecast.avgDailyBytes.traffic.show;
    final days = forecast.estimatedDaysLeft;
    if (days == null) {
      return l.quotaAvgDaily(avgLabel);
    }
    if (forecast.daysUntilExpiry != null && days >= forecast.daysUntilExpiry!) {
      return l.quotaSafeUntilExpiry(avgLabel);
    }
    return l.quotaDaysEstimate(avgLabel, days);
  }
}
