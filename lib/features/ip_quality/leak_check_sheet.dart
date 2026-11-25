import 'dart:async';
import 'dart:io' show InternetAddress;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showLeakCheckSheet(BuildContext context) {
  return showNestedSheet<void>(
    context,
    builder: (_) => const _LeakCheckSheet(),
  );
}

typedef _TraceProbe = ({
  String? ip,
  String? countryCode,
  String? tls,
  String? exit,
  int? delayMs,
});

class _LeakCheckSheet extends ConsumerStatefulWidget {
  const _LeakCheckSheet();

  @override
  ConsumerState<_LeakCheckSheet> createState() => _LeakCheckSheetState();
}

class _LeakCheckSheetState extends ConsumerState<_LeakCheckSheet> {
  static const _v4TraceUrls = [
    'https://1.1.1.1/cdn-cgi/trace',
    'https://www.cloudflare.com/cdn-cgi/trace',
    'https://api.ipify.org',
  ];

  static const _v6TraceUrls = [
    'https://[2606:4700:4700::1111]/cdn-cgi/trace',
    'https://api6.ipify.org',
  ];

  bool _loading = true;
  _TraceProbe _tunnelV4 = _emptyProbe;
  _TraceProbe _directV4 = _emptyProbe;
  _TraceProbe _tunnelV6 = _emptyProbe;
  _TraceProbe _directV6 = _emptyProbe;

  static const _TraceProbe _emptyProbe = (
    ip: null,
    countryCode: null,
    tls: null,
    exit: null,
    delayMs: null,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_runCheck());
  }

  _TraceProbe _parseTraceResult(OutboundIpResult result) {
    if (result.error != null || result.body.isEmpty) {
      return _emptyProbe;
    }
    final parsed = parseOutboundIp(result);
    if (parsed != null) {
      final trace = parseCloudflareTrace(result.body);
      return (
        ip: parsed.ip,
        countryCode: parsed.countryCode.isNotEmpty
            ? parsed.countryCode
            : trace['loc'],
        tls: trace['tls'],
        exit: result.chains.firstOrNull,
        delayMs: result.delay > 0 ? result.delay : null,
      );
    }
    final trace = parseCloudflareTrace(result.body);
    final traceIp = trace['ip'];
    if (traceIp != null && InternetAddress.tryParse(traceIp) != null) {
      return (
        ip: traceIp,
        countryCode: trace['loc'],
        tls: trace['tls'],
        exit: result.chains.firstOrNull,
        delayMs: result.delay > 0 ? result.delay : null,
      );
    }
    final trimmed = result.body.trim();
    if (InternetAddress.tryParse(trimmed) != null) {
      return (
        ip: trimmed,
        countryCode: null,
        tls: null,
        exit: result.chains.firstOrNull,
        delayMs: result.delay > 0 ? result.delay : null,
      );
    }
    return _emptyProbe;
  }

  Future<void> _runCheck() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    final core = ref.read(coreHandlerProvider);
    Future<_TraceProbe> probe(
      String proxyName,
      List<String> urls,
      int timeout,
    ) {
      return core
          .outboundIp(
            OutboundIpParams(
              proxyName: proxyName,
              urls: urls,
              timeout: timeout,
            ),
          )
          .then(_parseTraceResult)
          .catchError((_) => _emptyProbe);
    }

    final results = await Future.wait([
      probe(routedOutbound, _v4TraceUrls, 6000),
      probe(directOutbound, _v4TraceUrls, 5000),
      probe(routedOutbound, _v6TraceUrls, 4000),
      probe(directOutbound, _v6TraceUrls, 4000),
    ]);
    if (!mounted) return;
    setState(() {
      _tunnelV4 = results[0];
      _directV4 = results[1];
      _tunnelV6 = results[2];
      _directV6 = results[3];
      _loading = false;
    });
  }

  String _formatIp(
    _TraceProbe probe, {
    required bool hideIp,
    required String unavailableLabel,
  }) {
    final ip = probe.ip;
    if (ip == null || ip.isEmpty) {
      return unavailableLabel;
    }
    final shown = maskIfHidden(ip, hideIp: hideIp);
    final cc = probe.countryCode;
    if (cc != null && cc.isNotEmpty) {
      return '$shown ($cc)';
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final colors = context.colorScheme;
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    final isStart = ref.watch(isStartProvider);
    final dns = ref.watch(
      patchClashConfigProvider.select((state) => state.dns),
    );

    final dnsSafe =
        dns.enable &&
        (dns.enhancedMode == DnsMode.fakeIp ||
            dns.nameserver.any(
              (s) =>
                  s.startsWith('https://') ||
                  s.startsWith('tls://') ||
                  s.startsWith('quic://'),
            ));

    final tunnelIp = _tunnelV4.ip;
    final directIp = _directV4.ip;
    final tunnelProtected =
        isStart &&
        tunnelIp != null &&
        _tunnelV4.exit != directOutbound &&
        (directIp == null || tunnelIp != directIp);

    final ipv6Leaked =
        isStart &&
        _tunnelV6.ip != null &&
        _directV6.ip != null &&
        _tunnelV6.ip == _directV6.ip;

    final metaParts = <String>[
      if (_tunnelV4.exit case final exit? when exit.isNotEmpty) exit,
      if (_tunnelV4.delayMs case final ms?) '${ms}ms',
      if (_tunnelV4.tls case final tls? when tls.isNotEmpty) tls,
    ];

    return Scaffold(
      title: l.leakCheckTitle,
      actions: [
        AppBarActionButton(
          data: IconButtonData(
            glyph: AppGlyphs.refresh,
            tooltip: l.ipQualityRetry,
            isLoading: _loading,
            onPressed: _runCheck,
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
            title: l.basicInfo,
            items: [
              DetailRow(
                title: l.status,
                value: _loading
                    ? const SkeletonText(width: 96)
                    : Text(
                        tunnelProtected
                            ? l.leakCheckProtected
                            : l.leakCheckExposed,
                        style: TextStyle(
                          color: tunnelProtected
                              ? colors.success
                              : colors.error,
                        ),
                      ),
              ),
              if (metaParts.isNotEmpty && !_loading)
                DetailRow(
                  title: l.outbound,
                  value: Text(metaParts.join(' · ')),
                ),
            ],
          ),
          generateSection(
            title: l.network,
            items: [
              DetailRow(
                title: l.leakCheckTunnelIp,
                copyText: _tunnelV4.ip,
                value: _loading
                    ? const SkeletonText(width: 110)
                    : Text(
                        _formatIp(
                          _tunnelV4,
                          hideIp: hideIp,
                          unavailableLabel: l.serviceFailed,
                        ),
                      ),
              ),
              DetailRow(
                title: l.leakCheckDirectIp,
                copyText: _directV4.ip,
                value: _loading
                    ? const SkeletonText(width: 110)
                    : Text(
                        _formatIp(
                          _directV4,
                          hideIp: hideIp,
                          unavailableLabel: l.none,
                        ),
                      ),
              ),
              DetailRow(
                title: l.leakCheckDnsStatus,
                value: Text(
                  dnsSafe ? l.leakCheckDnsSafe : l.leakCheckDnsWarn,
                  style: TextStyle(
                    color: dnsSafe ? colors.success : colors.warning,
                  ),
                ),
              ),
              DetailRow(
                title: 'IPv6',
                value: _loading
                    ? const SkeletonText(width: 84)
                    : Text(
                        ipv6Leaked ? l.leakCheckIpv6Warn : l.leakCheckIpv6Safe,
                        style: TextStyle(
                          color: ipv6Leaked ? colors.error : colors.success,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
