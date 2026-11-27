import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/ip_quality/leak_check_sheet.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showProfileSecuritySheet(BuildContext context, Profile profile) {
  return showNestedSheet<void>(
    context,
    builder: (_) => ProfileSecuritySheet(profile: profile),
  );
}

class ProfileSecuritySheet extends ConsumerStatefulWidget {
  const ProfileSecuritySheet({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<ProfileSecuritySheet> createState() =>
      _ProfileSecuritySheetState();
}

class _ProfileSecuritySheetState extends ConsumerState<ProfileSecuritySheet> {
  bool _scanning = false;
  bool _hardening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    if (_scanning) return;
    if (mounted) {
      setState(() => _scanning = true);
    }
    try {
      await ref
          .read(profileSecurityProvider.notifier)
          .scanProfile(widget.profile);
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _applyAutoHarden() async {
    if (_hardening) return;
    setState(() => _hardening = true);
    final l = context.appLocalizations;
    try {
      final hardDns = system.isDesktop
          ? const [
              '1.1.1.1',
              '8.8.8.8',
              'https://1.1.1.1/dns-query',
              'https://8.8.8.8/dns-query',
            ]
          : const [
              'https://1.1.1.1/dns-query',
              'https://8.8.8.8/dns-query',
              'tcp://1.1.1.1:53',
              'tcp://8.8.8.8:53',
            ];
      final bootstrapDns = system.isDesktop
          ? const ['1.1.1.1', '8.8.8.8', '223.5.5.5']
          : const ['1.1.1.1', '8.8.8.8', 'system'];
      const directDns = ['1.1.1.1', '8.8.8.8'];
      ref.read(patchClashConfigProvider.notifier).update((state) {
        return state.copyWith(
          allowLan: false,
          ipv6: false,
          generalOverrideKeys: {
            ...state.generalOverrideKeys,
            GeneralOverrideKey.ipv6,
          },
          externalController: ExternalControllerStatus.close,
          hosts: const {},
          tunOverride: system.isDesktop
              ? state.tunOverride.copyWith(strictRoute: true)
              : state.tunOverride,
          tunOverrideKeys: system.isDesktop
              ? {...state.tunOverrideKeys, TunOverrideKey.strictRoute}
              : state.tunOverrideKeys,
          dns: state.dns.copyWith(
            enable: true,
            ipv6: false,
            preferH3: false,
            useHosts: true,
            respectRules: false,
            enhancedMode: DnsMode.fakeIp,
            nameserver: hardDns,
            defaultNameserver: bootstrapDns,
            proxyServerNameserver: bootstrapDns,
            directNameserver: directDns,
          ),
          dnsOverrideKeys: {
            ...state.dnsOverrideKeys,
            DnsOverrideKey.enable,
            DnsOverrideKey.ipv6,
            DnsOverrideKey.preferH3,
            DnsOverrideKey.useHosts,
            DnsOverrideKey.respectRules,
            DnsOverrideKey.enhancedMode,
            DnsOverrideKey.nameserver,
            DnsOverrideKey.defaultNameserver,
            DnsOverrideKey.proxyServerNameserver,
            DnsOverrideKey.directNameserver,
          },
        );
      });
      ref
          .read(networkSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              bypassPrivateRoute: true,
              appendSystemDns: false,
            ),
          );
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(hideIp: true));
      if (system.isAndroid || system.isWindows) {
        ref.read(privacyScreenShieldProvider.notifier).value = true;
      }
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
        final packages = ref.read(packagesProvider);
        if (packages.isNotEmpty) {
          final currentAccess = ref.read(vpnSettingProvider).accessControlProps;
          final bypass = applyEssentialAppsBypass(currentAccess, [
            for (final pkg in packages) pkg.packageName,
          ]);
          if (bypass.matchedCount > 0) {
            ref
                .read(vpnSettingProvider.notifier)
                .update(
                  (state) => state.copyWith(accessControlProps: bypass.props),
                );
          }
        }
      }
      await ref.read(setupActionProvider.notifier).applyPresetAndSyncTunnel();
      await ref
          .read(profileSecurityProvider.notifier)
          .scanProfile(widget.profile);
      if (!mounted) return;
      dialogs.showBanner(
        l.securityAutoHardenApplied,
        level: BannerLevel.success,
      );
    } finally {
      if (mounted) {
        setState(() => _hardening = false);
      }
    }
  }

  String _findingTitle(AppLocalizations l, SecurityFindingCode code) {
    return switch (code) {
      SecurityFindingCode.mitmEnabled => l.securityFindingMitmTitle,
      SecurityFindingCode.externalControllerExposed =>
        l.securityFindingControllerTitle,
      SecurityFindingCode.sensitiveHostsHijack => l.securityFindingHostsTitle,
      SecurityFindingCode.plaintextNodes => l.securityFindingPlaintextTitle,
      SecurityFindingCode.skipCertVerifyNodes =>
        l.securityFindingSkipVerifyTitle,
      SecurityFindingCode.insecureSubscriptionUrl =>
        l.securityFindingHttpSubTitle,
      SecurityFindingCode.insecureProviderUrls =>
        l.securityFindingHttpProviderTitle,
      SecurityFindingCode.allowLanForced => l.securityFindingAllowLanTitle,
      SecurityFindingCode.privateLanRoutedToProxy =>
        l.securityFindingLanRouteTitle,
      SecurityFindingCode.unencryptedCustomDns =>
        l.securityFindingPlainDnsTitle,
    };
  }

  String _findingDesc(AppLocalizations l, ProfileSecurityFinding finding) {
    final base = switch (finding.code) {
      SecurityFindingCode.mitmEnabled => l.securityFindingMitmDesc,
      SecurityFindingCode.externalControllerExposed =>
        l.securityFindingControllerDesc,
      SecurityFindingCode.sensitiveHostsHijack => l.securityFindingHostsDesc,
      SecurityFindingCode.plaintextNodes => l.securityFindingPlaintextDesc(
        finding.affectedCount,
      ),
      SecurityFindingCode.skipCertVerifyNodes =>
        l.securityFindingSkipVerifyDesc(finding.affectedCount),
      SecurityFindingCode.insecureSubscriptionUrl =>
        l.securityFindingHttpSubDesc,
      SecurityFindingCode.insecureProviderUrls =>
        l.securityFindingHttpProviderDesc(finding.affectedCount),
      SecurityFindingCode.allowLanForced => l.securityFindingAllowLanDesc,
      SecurityFindingCode.privateLanRoutedToProxy =>
        l.securityFindingLanRouteDesc(finding.affectedCount),
      SecurityFindingCode.unencryptedCustomDns => l.securityFindingPlainDnsDesc,
    };
    if (finding.samples.isEmpty) return base;
    return '$base (${finding.samples.join(', ')})';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final colors = context.colorScheme;
    final report = ref.watch(
      profileSecurityProvider.select((s) => s[widget.profile.id]),
    );

    final (levelLabel, levelColor) = switch (report?.level) {
      ProfileRiskLevel.danger => (l.securityLevelDanger, colors.error),
      ProfileRiskLevel.caution => (l.securityLevelCaution, colors.warning),
      ProfileRiskLevel.safe => (l.securityLevelSafe, colors.success),
      null => ('...', colors.onSurfaceVariant),
    };

    return Scaffold(
      title: l.securityAuditTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: l.securityRescan,
          isLoading: _scanning,
          onPressed: _scanning ? null : () => unawaited(_scan()),
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
            title: widget.profile.realLabel,
            items: [
              DetailRow(
                title: l.status,
                value: _scanning && report == null
                    ? const SkeletonText(width: 96)
                    : Text(
                        report != null
                            ? '${report.score}/100 · $levelLabel'
                            : '...',
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(color: levelColor),
                      ),
              ),
              if (report != null)
                DetailRow(
                  title: l.securityScannedCounts,
                  value: Text(
                    l.securityScannedCountsValue(
                      report.scannedProxies,
                      report.scannedRules,
                    ),
                  ),
                ),
              ListItem(
                leading: _hardening
                    ? const ActivityIndicator(size: 18)
                    : const GlyphIcon(AppGlyphs.verified),
                title: Text(l.securityAutoHarden),
                subtitle: Text(l.securityAutoHardenDesc),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: _hardening ? null : () => unawaited(_applyAutoHarden()),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.radar),
                title: Text(l.leakCheckTitle),
                subtitle: Text(l.leakCheckDesc),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => unawaited(showLeakCheckSheet(context)),
              ),
            ],
          ),
          if (report != null && report.findings.isEmpty)
            generateSection(
              title: l.securityFindingsTitle,
              items: [
                ListItem(
                  leading: GlyphIcon(AppGlyphs.verified, color: colors.success),
                  title: Text(l.securityNoRisksTitle),
                  subtitle: Text(l.securityNoRisksDesc),
                ),
              ],
            ),
          if (report != null && report.findings.isNotEmpty)
            generateSection(
              title: l.securityFindingsTitle,
              items: [
                for (final finding in report.findings)
                  ListItem(
                    leading: GlyphIcon(
                      finding.severity == SecurityFindingSeverity.critical
                          ? AppGlyphs.error
                          : AppGlyphs.warning,
                      color:
                          finding.severity == SecurityFindingSeverity.critical
                          ? colors.error
                          : colors.warning,
                    ),
                    title: Text(_findingTitle(l, finding.code)),
                    subtitle: Text(_findingDesc(l, finding)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
