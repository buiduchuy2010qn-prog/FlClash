import 'dart:math' as math;

import 'package:fl_clash/common/yaml.dart';

enum ProfileRiskLevel { safe, caution, danger }

enum SecurityFindingSeverity { critical, warning, info }

enum SecurityFindingCode {
  mitmEnabled,
  externalControllerExposed,
  sensitiveHostsHijack,
  plaintextNodes,
  skipCertVerifyNodes,
  insecureSubscriptionUrl,
  insecureProviderUrls,
  allowLanForced,
  privateLanRoutedToProxy,
  unencryptedCustomDns,
}

class ProfileSecurityFinding {
  const ProfileSecurityFinding({
    required this.code,
    required this.severity,
    this.affectedCount = 0,
    this.samples = const [],
  });

  final SecurityFindingCode code;
  final SecurityFindingSeverity severity;
  final int affectedCount;
  final List<String> samples;
}

class ProfileSecurityReport {
  const ProfileSecurityReport({
    required this.score,
    required this.level,
    required this.scannedProxies,
    required this.scannedRules,
    required this.findings,
    required this.scannedAt,
  });

  final int score;
  final ProfileRiskLevel level;
  final int scannedProxies;
  final int scannedRules;
  final List<ProfileSecurityFinding> findings;
  final DateTime scannedAt;

  int get criticalCount => findings
      .where((f) => f.severity == SecurityFindingSeverity.critical)
      .length;

  int get warningCount => findings
      .where((f) => f.severity == SecurityFindingSeverity.warning)
      .length;

  bool get isDangerous => level == ProfileRiskLevel.danger;

  bool get canAutoHarden => findings.any(
    (f) => switch (f.code) {
      SecurityFindingCode.mitmEnabled ||
      SecurityFindingCode.externalControllerExposed ||
      SecurityFindingCode.sensitiveHostsHijack ||
      SecurityFindingCode.allowLanForced ||
      SecurityFindingCode.privateLanRoutedToProxy ||
      SecurityFindingCode.unencryptedCustomDns ||
      SecurityFindingCode.skipCertVerifyNodes => true,
      _ => false,
    },
  );
}

const _maxAuditYamlBytes = 4 * 1024 * 1024;
const _maxSamples = 4;

const _loopbackHosts = {'127.0.0.1', 'localhost', '::1', '[::1]', '0.0.0.0'};
const _safeHijackIps = {'127.0.0.1', '::1', '0.0.0.0', 'localhost'};
const _weakCiphers = {
  'none',
  'plain',
  'table',
  'rc4',
  'rc4-md5',
  'aes-128-cfb',
  'aes-192-cfb',
  'aes-256-cfb',
};
const _wellKnownPlainResolvers = {
  '1.1.1.1',
  '1.0.0.1',
  '8.8.8.8',
  '8.8.4.4',
  '9.9.9.9',
  '223.5.5.5',
  '119.29.29.29',
  '208.67.222.222',
  '94.140.14.14',
};
const _sensitiveHostKeywords = [
  'vietcombank',
  'techcombank',
  'mbbank',
  'bidv',
  'acb',
  'vpbank',
  'tpbank',
  'sacombank',
  'agribank',
  'momo',
  'zalopay',
  'vnpay',
  'gov.vn',
  'google.com',
  'apple.com',
  'icloud.com',
  'facebook.com',
  'zalo.me',
  'microsoft.com',
  'live.com',
  'github.com',
  'paypal.com',
  'binance.com',
  'okx.com',
  'coinbase.com',
  'telegram.org',
];
const _directTargets = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'};

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  if (value is num) return value != 0;
  return false;
}

String _str(Object? value) => value?.toString().trim() ?? '';

Map<String, Object?> _asStringMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key != null) entry.key.toString().toLowerCase(): entry.value,
  };
}

String _extractHost(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('[')) {
    final end = trimmed.indexOf(']');
    if (end > 1) return trimmed.substring(1, end).toLowerCase();
  }
  final colon = trimmed.lastIndexOf(':');
  if (colon > 0 && !trimmed.substring(0, colon).contains(':')) {
    return trimmed.substring(0, colon).toLowerCase();
  }
  return trimmed.toLowerCase();
}

bool _isPlaintextProxy(Map<String, Object?> proxy) {
  final type = _str(proxy['type']).toLowerCase();
  final tls = _asBool(proxy['tls']);
  if (type == 'http' || type == 'socks5' || type == 'socks') {
    return !tls;
  }
  if (type == 'ss' || type == 'ssr') {
    final cipher = _str(proxy['cipher']).toLowerCase();
    return cipher.isNotEmpty && _weakCiphers.contains(cipher);
  }
  if (type == 'vmess') {
    final cipher = _str(proxy['cipher']).toLowerCase();
    final security = _str(proxy['security']).toLowerCase();
    return (cipher == 'none' || security == 'none') && !tls;
  }
  if (type == 'vless') {
    final hasReality =
        proxy['reality-opts'] is Map &&
        (proxy['reality-opts'] as Map).isNotEmpty;
    return !tls && !hasReality;
  }
  return false;
}

bool _isHttpInsecureUrl(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.toLowerCase().startsWith('http://')) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return true;
  return !_loopbackHosts.contains(uri.host.toLowerCase());
}

bool _isSensitiveDomain(String domain) {
  final normalized = domain.toLowerCase().trim();
  if (normalized == 'vib' ||
      normalized.endsWith('.vib.com.vn') ||
      normalized == 'vib.com.vn') {
    return true;
  }
  return _sensitiveHostKeywords.any(normalized.contains);
}

bool _isPrivateRuleTarget(String criterion) {
  final lower = criterion.toLowerCase();
  return lower.startsWith('192.168.') ||
      lower.startsWith('10.') ||
      lower.startsWith('172.16.') ||
      lower.startsWith('127.') ||
      lower == 'localhost' ||
      lower.endsWith('.local');
}

String _bareDnsAddress(String server) {
  var s = server.trim().toLowerCase();
  if (s.startsWith('udp://') || s.startsWith('tcp://')) {
    s = s.substring(6);
  }
  final hash = s.indexOf('#');
  if (hash > 0) s = s.substring(0, hash);
  return _extractHost(s);
}

bool _isEncryptedOrSystemResolver(String server) {
  final lower = server.trim().toLowerCase();
  return lower.startsWith('https://') ||
      lower.startsWith('tls://') ||
      lower.startsWith('quic://') ||
      lower.startsWith('h3://') ||
      lower.startsWith('dhcp://') ||
      lower == 'system';
}

ProfileSecurityReport auditProfileSecurityTask(
  ({String rawYaml, String? subscriptionUrl}) input,
) {
  return auditProfileSecurity(
    rawYaml: input.rawYaml,
    subscriptionUrl: input.subscriptionUrl,
  );
}

ProfileSecurityReport auditProfileSecurity({
  required String rawYaml,
  String? subscriptionUrl,
  DateTime? now,
}) {
  final refNow = now ?? DateTime.now();
  final findings = <ProfileSecurityFinding>[];
  var penalty = 0;

  if (subscriptionUrl != null && _isHttpInsecureUrl(subscriptionUrl)) {
    findings.add(
      ProfileSecurityFinding(
        code: SecurityFindingCode.insecureSubscriptionUrl,
        severity: SecurityFindingSeverity.warning,
        affectedCount: 1,
        samples: [subscriptionUrl.trim()],
      ),
    );
    penalty += 15;
  }

  Map<String, Object?> root = const {};
  if (rawYaml.isNotEmpty && rawYaml.length <= _maxAuditYamlBytes) {
    try {
      final parsed = loadPlainYaml(rawYaml);
      if (parsed is Map) {
        root = _asStringMap(parsed);
      }
    } catch (_) {}
  }

  final mitm = _asStringMap(root['mitm']);
  if (_asBool(mitm['enable']) ||
      _asBool(mitm['decrypt-untrusted']) ||
      _asBool(mitm['capture'])) {
    findings.add(
      const ProfileSecurityFinding(
        code: SecurityFindingCode.mitmEnabled,
        severity: SecurityFindingSeverity.critical,
        affectedCount: 1,
      ),
    );
    penalty += 35;
  }

  final controllerRaw = _str(root['external-controller']);
  if (controllerRaw.isNotEmpty) {
    final host = _extractHost(controllerRaw);
    final secret = _str(root['secret']);
    if ((host.isNotEmpty && !_loopbackHosts.contains(host)) || secret.isEmpty) {
      findings.add(
        ProfileSecurityFinding(
          code: SecurityFindingCode.externalControllerExposed,
          severity: SecurityFindingSeverity.critical,
          affectedCount: 1,
          samples: [controllerRaw],
        ),
      );
      penalty += 30;
    }
  }

  final hosts = _asStringMap(root['hosts']);
  if (hosts.isNotEmpty) {
    final hijacked = <String>[];
    for (final entry in hosts.entries) {
      final domain = entry.key;
      if (!_isSensitiveDomain(domain)) continue;
      final val = entry.value;
      final targets = val is List
          ? [for (final item in val) _str(item)]
          : [_str(val)];
      final suspicious = targets.any(
        (ip) => ip.isNotEmpty && !_safeHijackIps.contains(ip.toLowerCase()),
      );
      if (suspicious) {
        hijacked.add(domain);
      }
    }
    if (hijacked.isNotEmpty) {
      findings.add(
        ProfileSecurityFinding(
          code: SecurityFindingCode.sensitiveHostsHijack,
          severity: SecurityFindingSeverity.critical,
          affectedCount: hijacked.length,
          samples: hijacked.take(_maxSamples).toList(),
        ),
      );
      penalty += 35;
    }
  }

  final rawProxies = root['proxies'];
  final proxies = rawProxies is List ? rawProxies : const [];
  var scannedProxies = 0;
  final plaintextSamples = <String>[];
  var plaintextCount = 0;
  final skipVerifySamples = <String>[];
  var skipVerifyCount = 0;

  for (final item in proxies) {
    if (item is! Map) continue;
    final proxy = _asStringMap(item);
    scannedProxies++;
    final label = _str(proxy['name']).isNotEmpty
        ? _str(proxy['name'])
        : _str(proxy['server']);
    if (_isPlaintextProxy(proxy)) {
      plaintextCount++;
      if (plaintextSamples.length < _maxSamples && label.isNotEmpty) {
        plaintextSamples.add(label);
      }
    }
    if (_asBool(proxy['skip-cert-verify'])) {
      skipVerifyCount++;
      if (skipVerifySamples.length < _maxSamples && label.isNotEmpty) {
        skipVerifySamples.add(label);
      }
    }
  }

  if (plaintextCount > 0) {
    final severe =
        plaintextCount >= 3 ||
        (scannedProxies > 0 && plaintextCount * 2 >= scannedProxies);
    findings.add(
      ProfileSecurityFinding(
        code: SecurityFindingCode.plaintextNodes,
        severity: severe
            ? SecurityFindingSeverity.critical
            : SecurityFindingSeverity.warning,
        affectedCount: plaintextCount,
        samples: plaintextSamples,
      ),
    );
    penalty += severe ? 25 : 12;
  }

  if (skipVerifyCount > 0) {
    final severe = scannedProxies > 0 && skipVerifyCount * 2 >= scannedProxies;
    findings.add(
      ProfileSecurityFinding(
        code: SecurityFindingCode.skipCertVerifyNodes,
        severity: severe
            ? SecurityFindingSeverity.critical
            : SecurityFindingSeverity.warning,
        affectedCount: skipVerifyCount,
        samples: skipVerifySamples,
      ),
    );
    penalty += severe ? 25 : 15;
  }

  final insecureProviders = <String>[];
  for (final section in const ['proxy-providers', 'rule-providers']) {
    final map = _asStringMap(root[section]);
    for (final entry in map.entries) {
      final cfg = _asStringMap(entry.value);
      final url = _str(cfg['url']);
      if (url.isNotEmpty && _isHttpInsecureUrl(url)) {
        insecureProviders.add(entry.key);
      }
    }
  }
  if (insecureProviders.isNotEmpty) {
    findings.add(
      ProfileSecurityFinding(
        code: SecurityFindingCode.insecureProviderUrls,
        severity: SecurityFindingSeverity.warning,
        affectedCount: insecureProviders.length,
        samples: insecureProviders.take(_maxSamples).toList(),
      ),
    );
    penalty += 12;
  }

  if (_asBool(root['allow-lan'])) {
    findings.add(
      const ProfileSecurityFinding(
        code: SecurityFindingCode.allowLanForced,
        severity: SecurityFindingSeverity.warning,
        affectedCount: 1,
      ),
    );
    penalty += 12;
  }

  final rawRules = root['rules'];
  final rules = rawRules is List ? rawRules : const [];
  var scannedRules = 0;
  final leakedLanRules = <String>[];
  for (final item in rules) {
    final line = _str(item);
    if (line.isEmpty) continue;
    scannedRules++;
    final parts = line.split(',');
    if (parts.length < 3) continue;
    final kind = parts[0].trim().toUpperCase();
    final criterion = parts[1].trim();
    final target = parts[2].trim();
    final isLanMatch =
        (kind == 'IP-CIDR' ||
            kind == 'IP-CIDR6' ||
            kind == 'DOMAIN' ||
            kind == 'DOMAIN-SUFFIX') &&
        _isPrivateRuleTarget(criterion);
    if (isLanMatch && !_directTargets.contains(target.toUpperCase())) {
      leakedLanRules.add(line);
    }
  }
  if (leakedLanRules.isNotEmpty) {
    findings.add(
      ProfileSecurityFinding(
        code: SecurityFindingCode.privateLanRoutedToProxy,
        severity: SecurityFindingSeverity.warning,
        affectedCount: leakedLanRules.length,
        samples: leakedLanRules.take(_maxSamples).toList(),
      ),
    );
    penalty += 15;
  }

  final dns = _asStringMap(root['dns']);
  final rawNameservers = dns['nameserver'];
  if (_asBool(dns['enable']) &&
      rawNameservers is List &&
      rawNameservers.isNotEmpty) {
    final resolvers = [
      for (final item in rawNameservers)
        if (_str(item).isNotEmpty) _str(item),
    ];
    if (resolvers.isNotEmpty) {
      final hasEncrypted = resolvers.any(_isEncryptedOrSystemResolver);
      final customPlain = [
        for (final ns in resolvers)
          if (!_isEncryptedOrSystemResolver(ns) &&
              !_wellKnownPlainResolvers.contains(_bareDnsAddress(ns)))
            ns,
      ];
      if (!hasEncrypted && customPlain.isNotEmpty) {
        findings.add(
          ProfileSecurityFinding(
            code: SecurityFindingCode.unencryptedCustomDns,
            severity: SecurityFindingSeverity.warning,
            affectedCount: customPlain.length,
            samples: customPlain.take(_maxSamples).toList(),
          ),
        );
        penalty += 8;
      }
    }
  }

  final score = math.max(0, math.min(100, 100 - penalty));
  final hasCritical = findings.any(
    (f) => f.severity == SecurityFindingSeverity.critical,
  );
  final level = (hasCritical && score < 70) || score < 50
      ? ProfileRiskLevel.danger
      : (score < 85 || findings.isNotEmpty)
      ? ProfileRiskLevel.caution
      : ProfileRiskLevel.safe;

  return ProfileSecurityReport(
    score: score,
    level: level,
    scannedProxies: scannedProxies,
    scannedRules: scannedRules,
    findings: List.unmodifiable(findings),
    scannedAt: refNow,
  );
}
