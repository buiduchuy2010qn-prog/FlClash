import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_clash/common/daily_traffic_store.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

enum DeviceMetaSource { header, payload, liveGroup, portal }

class SubscriptionDeviceMeta {
  const SubscriptionDeviceMeta({
    this.onlineDevices,
    this.deviceLimit,
    this.portalUrl,
    this.planName,
    this.resetDay,
    this.source = DeviceMetaSource.header,
    this.updatedAt,
  });

  final int? onlineDevices;
  final int? deviceLimit;
  final String? portalUrl;
  final String? planName;
  final int? resetDay;
  final DeviceMetaSource source;
  final DateTime? updatedAt;

  bool get hasCounts => onlineDevices != null || deviceLimit != null;

  bool get isOverLimit =>
      onlineDevices != null &&
      deviceLimit != null &&
      deviceLimit! > 0 &&
      onlineDevices! > deviceLimit!;

  bool get isAtLimit =>
      onlineDevices != null &&
      deviceLimit != null &&
      deviceLimit! > 0 &&
      onlineDevices! >= deviceLimit!;

  String? get badgeLabel {
    if (onlineDevices != null && deviceLimit != null) {
      return '$onlineDevices/$deviceLimit';
    }
    if (deviceLimit != null) {
      return '/$deviceLimit';
    }
    if (onlineDevices != null) {
      return '$onlineDevices';
    }
    return null;
  }

  SubscriptionDeviceMeta withPortalUrl(String? nextPortalUrl) {
    final normalized = _normalizePortalUrl(nextPortalUrl);
    if (normalized == null || normalized == portalUrl) {
      return this;
    }
    return SubscriptionDeviceMeta(
      onlineDevices: onlineDevices,
      deviceLimit: deviceLimit,
      portalUrl: normalized,
      planName: planName,
      resetDay: resetDay,
      source: source,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    if (onlineDevices != null) 'onlineDevices': onlineDevices,
    if (deviceLimit != null) 'deviceLimit': deviceLimit,
    if (portalUrl != null) 'portalUrl': portalUrl,
    if (planName != null) 'planName': planName,
    if (resetDay != null) 'resetDay': resetDay,
    'source': source.name,
    if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
  };

  static SubscriptionDeviceMeta? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final online = (raw['onlineDevices'] as num?)?.toInt();
    final limit = (raw['deviceLimit'] as num?)?.toInt();
    final portal = _normalizePortalUrl(raw['portalUrl']?.toString());
    final rawPlan = raw['planName']?.toString().trim();
    final planName = (rawPlan != null && rawPlan.isNotEmpty) ? rawPlan : null;
    final resetDay = (raw['resetDay'] as num?)?.toInt();
    if (online == null && limit == null && portal == null && planName == null) {
      return null;
    }
    final sourceName = raw['source']?.toString();
    final source =
        DeviceMetaSource.values
            .where((v) => v.name == sourceName)
            .firstOrNull ??
        DeviceMetaSource.header;
    final updatedMs = (raw['updatedAt'] as num?)?.toInt();
    return SubscriptionDeviceMeta(
      onlineDevices: online,
      deviceLimit: limit,
      portalUrl: portal,
      planName: planName,
      resetDay: resetDay,
      source: source,
      updatedAt: updatedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedMs)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SubscriptionDeviceMeta &&
            other.onlineDevices == onlineDevices &&
            other.deviceLimit == deviceLimit &&
            other.portalUrl == portalUrl &&
            other.planName == planName &&
            other.resetDay == resetDay &&
            other.source == source &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    onlineDevices,
    deviceLimit,
    portalUrl,
    planName,
    resetDay,
    source,
    updatedAt,
  );
}

const _onlineInfoKeys = {
  'alive_ip',
  'alive',
  'online',
  'online_devices',
  'active_devices',
  'devices',
  'current_devices',
  'used_devices',
  'online_count',
  'device_online',
};

const _limitInfoKeys = {
  'device_limit',
  'max_devices',
  'limit_devices',
  'max_device',
  'devices_limit',
  'limit_ip',
  'ip_limit',
};

const _onlineHeaders = [
  'x-alive-ip',
  'alive-ip',
  'x-online-devices',
  'online-devices',
  'x-active-devices',
  'active-devices',
  'x-device-online',
];

const _limitHeaders = [
  'x-device-limit',
  'device-limit',
  'subscription-device-limit',
  'x-max-devices',
  'max-devices',
  'x-ip-limit',
  'ip-limit',
];

const _portalHeaders = ['profile-web-page-url', 'support-url'];

const _maxPayloadInspectBytes = 2 * 1024 * 1024;

final _deviceKeywordPattern = RegExp(
  r'device|thiết\s*bị|thiet\s*bi|online|active\s*ip|alive|ip\s*limit|giới\s*hạn|gioi\s*han|设备|在线|端末|기기|устройств',
  caseSensitive: false,
);

final _ratioPattern = RegExp(
  r'(?<!/)\b(\d{1,3})\s*/\s*(\d{1,3})\b(?!\s*/\s*\d)',
);

final _limitHintPattern = RegExp(
  r'limit|max|giới\s*hạn|gioi\s*han|限制|上限',
  caseSensitive: false,
);

final _onlineHintPattern = RegExp(
  r'online|active|alive|đang\s*dùng|dang\s*dung|在线',
  caseSensitive: false,
);

final _standaloneCountPattern = RegExp(
  r'(?<![.\d/])(\d{1,3})(?![\d./]|\s*(?:gb|mb|tb|kb|%|ms|d\b))',
  caseSensitive: false,
);

final _yamlNamePattern = RegExp(
  r'''(?:^|[{,\s])name\s*:\s*(?:'([^'\r\n]+)'|"([^"\r\n]+)"|([^,}\]\r\n]+))''',
  multiLine: true,
);

String? _normalizePortalUrl(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return uri.toString();
}

int? _parseCount(String? raw, {required int min, int max = 999}) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = int.tryParse(trimmed);
  if (parsed != null) {
    return parsed >= min && parsed <= max ? parsed : null;
  }
  final decimal = double.tryParse(trimmed);
  if (decimal == null || !decimal.isFinite) return null;
  final truncated = decimal.truncate();
  return truncated >= min && truncated <= max ? truncated : null;
}

Map<String, String> _flattenHeaders(Map<String, List<String>> headers) {
  final result = <String, String>{};
  for (final entry in headers.entries) {
    final key = entry.key.trim().toLowerCase();
    if (key.isEmpty || entry.value.isEmpty) continue;
    final first = entry.value.firstWhere(
      (item) => item.trim().isNotEmpty,
      orElse: () => '',
    );
    if (first.isNotEmpty) {
      result[key] = first.trim();
    }
  }
  return result;
}

String? _decodeUriComponentSafe(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    return Uri.decodeComponent(trimmed).trim();
  } catch (_) {
    return trimmed;
  }
}

String? _tryDecodeBase64Text(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (compact.length < 12) return null;
  final padded = compact.padRight((compact.length + 3) & ~3, '=');
  final normalized = padded.replaceAll('-', '+').replaceAll('_', '/');
  try {
    final decoded = utf8.decode(
      base64.decode(normalized),
      allowMalformed: true,
    );
    return decoded.contains('://') || decoded.contains('proxies:')
        ? decoded
        : null;
  } catch (_) {
    return null;
  }
}

Iterable<String> _extractCandidateNodeNames(List<int> payloadBytes) {
  if (payloadBytes.isEmpty || payloadBytes.length > _maxPayloadInspectBytes) {
    return const [];
  }
  var text = utf8.decode(payloadBytes, allowMalformed: true);
  if (!text.contains('proxies:') && !text.contains('://')) {
    final decoded = _tryDecodeBase64Text(text);
    if (decoded != null) {
      text = decoded;
    }
  }
  final names = <String>[];
  for (final match in _yamlNamePattern.allMatches(text)) {
    final value = (match.group(1) ?? match.group(2) ?? match.group(3) ?? '')
        .trim();
    if (value.isNotEmpty) {
      names.add(value);
    }
  }
  for (final rawLine in LineSplitter.split(text)) {
    final line = rawLine.trim();
    final schemeIdx = line.indexOf('://');
    if (schemeIdx <= 0) continue;
    final hashIdx = line.indexOf('#', schemeIdx + 3);
    if (hashIdx == -1 || hashIdx + 1 >= line.length) continue;
    final decoded = _decodeUriComponentSafe(line.substring(hashIdx + 1));
    if (decoded != null && decoded.isNotEmpty) {
      names.add(decoded);
    }
  }
  return names;
}

SubscriptionDeviceMeta? parseDeviceMetaFromNodeNames(
  Iterable<String> names, {
  DateTime? now,
  DeviceMetaSource source = DeviceMetaSource.payload,
}) {
  int? onlineDevices;
  int? deviceLimit;

  for (final rawName in names) {
    final name = rawName.trim();
    if (name.isEmpty || !_deviceKeywordPattern.hasMatch(name)) {
      continue;
    }
    final ratio = _ratioPattern.firstMatch(name);
    if (ratio != null) {
      final online = _parseCount(ratio.group(1), min: 0);
      final limit = _parseCount(ratio.group(2), min: 1);
      if (online != null && limit != null) {
        onlineDevices ??= online;
        deviceLimit ??= limit;
        break;
      }
    }
    final standalone = _standaloneCountPattern.firstMatch(name);
    if (standalone != null) {
      if (deviceLimit == null && _limitHintPattern.hasMatch(name)) {
        final limit = _parseCount(standalone.group(1), min: 1);
        if (limit != null) {
          deviceLimit = limit;
          continue;
        }
      }
      if (onlineDevices == null && _onlineHintPattern.hasMatch(name)) {
        final online = _parseCount(standalone.group(1), min: 0);
        if (online != null) {
          onlineDevices = online;
        }
      }
    }
  }

  if (onlineDevices == null && deviceLimit == null) {
    return null;
  }
  return SubscriptionDeviceMeta(
    onlineDevices: onlineDevices,
    deviceLimit: deviceLimit,
    source: source,
    updatedAt: now ?? DateTime.now(),
  );
}

SubscriptionDeviceMeta? parseSubscriptionDeviceMeta({
  Map<String, List<String>> headers = const {},
  String? userinfoHeader,
  List<int>? payloadBytes,
  DateTime? now,
}) {
  final refNow = now ?? DateTime.now();
  final flatHeaders = _flattenHeaders(headers);
  final userinfo = userinfoHeader ?? flatHeaders['subscription-userinfo'];

  int? onlineDevices;
  int? deviceLimit;
  var source = DeviceMetaSource.header;

  if (userinfo != null && userinfo.trim().isNotEmpty) {
    for (final field in userinfo.split(';')) {
      final sep = field.indexOf('=');
      if (sep <= 0) continue;
      final key = field.substring(0, sep).trim().toLowerCase();
      final val = field.substring(sep + 1).trim();
      if (onlineDevices == null && _onlineInfoKeys.contains(key)) {
        onlineDevices = _parseCount(val, min: 0);
      } else if (deviceLimit == null && _limitInfoKeys.contains(key)) {
        deviceLimit = _parseCount(val, min: 1);
      }
    }
  }

  for (final key in _onlineHeaders) {
    if (onlineDevices != null) break;
    onlineDevices = _parseCount(flatHeaders[key], min: 0);
  }
  for (final key in _limitHeaders) {
    if (deviceLimit != null) break;
    deviceLimit = _parseCount(flatHeaders[key], min: 1);
  }

  String? portalUrl;
  for (final key in _portalHeaders) {
    portalUrl = _normalizePortalUrl(flatHeaders[key]);
    if (portalUrl != null) break;
  }

  final hadHeaderCounts = onlineDevices != null || deviceLimit != null;
  if ((onlineDevices == null || deviceLimit == null) &&
      payloadBytes != null &&
      payloadBytes.isNotEmpty) {
    final fromPayload = parseDeviceMetaFromNodeNames(
      _extractCandidateNodeNames(payloadBytes),
      now: refNow,
      source: DeviceMetaSource.payload,
    );
    if (fromPayload != null) {
      onlineDevices ??= fromPayload.onlineDevices;
      deviceLimit ??= fromPayload.deviceLimit;
      if (!hadHeaderCounts && (onlineDevices != null || deviceLimit != null)) {
        source = DeviceMetaSource.payload;
      }
    }
  }

  if (onlineDevices == null && deviceLimit == null && portalUrl == null) {
    return null;
  }
  return SubscriptionDeviceMeta(
    onlineDevices: onlineDevices,
    deviceLimit: deviceLimit,
    portalUrl: portalUrl,
    source: source,
    updatedAt: refNow,
  );
}

class SubscriptionInsightsLedger {
  const SubscriptionInsightsLedger({this.entries = const {}});

  final Map<int, SubscriptionDeviceMeta> entries;

  SubscriptionDeviceMeta? operator [](int profileId) => entries[profileId];

  SubscriptionInsightsLedger withEntry(
    int profileId,
    SubscriptionDeviceMeta meta,
  ) {
    final updated = Map<int, SubscriptionDeviceMeta>.from(entries)
      ..[profileId] = meta;
    return SubscriptionInsightsLedger(entries: Map.unmodifiable(updated));
  }

  SubscriptionInsightsLedger withoutEntry(int profileId) {
    if (!entries.containsKey(profileId)) return this;
    final updated = Map<int, SubscriptionDeviceMeta>.from(entries)
      ..remove(profileId);
    return SubscriptionInsightsLedger(entries: Map.unmodifiable(updated));
  }

  String encode() {
    return json.encode({
      'v': 1,
      'entries': {
        for (final entry in entries.entries)
          entry.key.toString(): entry.value.toJson(),
      },
    });
  }

  static SubscriptionInsightsLedger decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const SubscriptionInsightsLedger();
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return const SubscriptionInsightsLedger();
      final rawEntries = decoded['entries'];
      if (rawEntries is! Map) return const SubscriptionInsightsLedger();
      final parsed = <int, SubscriptionDeviceMeta>{};
      for (final entry in rawEntries.entries) {
        final id = int.tryParse(entry.key?.toString() ?? '');
        if (id == null) continue;
        final meta = SubscriptionDeviceMeta.fromJson(entry.value);
        if (meta != null) {
          parsed[id] = meta;
        }
      }
      return SubscriptionInsightsLedger(entries: Map.unmodifiable(parsed));
    } catch (_) {
      return const SubscriptionInsightsLedger();
    }
  }
}

enum QuotaBurnStatus { comfortable, tight, critical, exhausted }

class QuotaForecast {
  const QuotaForecast({
    required this.remainingBytes,
    required this.avgDailyBytes,
    required this.estimatedDaysLeft,
    required this.dailyBudgetBytes,
    required this.daysUntilExpiry,
    required this.status,
  });

  final int remainingBytes;
  final int avgDailyBytes;
  final int? estimatedDaysLeft;
  final int? dailyBudgetBytes;
  final int? daysUntilExpiry;
  final QuotaBurnStatus status;
}

QuotaForecast? forecastSubscriptionQuota(
  SubscriptionInfo? info,
  DailyTrafficLedger ledger, {
  DateTime? now,
}) {
  if (info == null || info.total <= 0) {
    return null;
  }
  final refNow = now ?? DateTime.now();
  final used = math.max(0, info.upload + info.download);
  final remainingBytes = math.max(0, info.total - used);
  final recent = ledger.recentDays(7, now: refNow);
  var activeDays = 0;
  var total7d = 0;
  for (final day in recent) {
    if (day.total > 0) {
      activeDays++;
      total7d += day.total;
    }
  }
  final avgDailyBytes = activeDays == 0 ? 0 : total7d ~/ activeDays;

  final expireDate = info.expireDate;
  final daysUntilExpiry = expireDate != null
      ? math.max(0, expireDate.difference(refNow).inDays)
      : null;
  final dailyBudgetBytes = daysUntilExpiry != null && daysUntilExpiry > 0
      ? remainingBytes ~/ daysUntilExpiry
      : null;
  final estimatedDaysLeft = remainingBytes <= 0
      ? 0
      : (avgDailyBytes > 0 ? (remainingBytes / avgDailyBytes).floor() : null);

  final QuotaBurnStatus status;
  if (remainingBytes <= 0 ||
      (expireDate != null && !expireDate.isAfter(refNow))) {
    status = QuotaBurnStatus.exhausted;
  } else if ((estimatedDaysLeft != null && estimatedDaysLeft <= 3) ||
      (remainingBytes / info.total < 0.10)) {
    status = QuotaBurnStatus.critical;
  } else if (daysUntilExpiry != null &&
      estimatedDaysLeft != null &&
      estimatedDaysLeft < daysUntilExpiry) {
    status = QuotaBurnStatus.tight;
  } else {
    status = QuotaBurnStatus.comfortable;
  }

  return QuotaForecast(
    remainingBytes: remainingBytes,
    avgDailyBytes: avgDailyBytes,
    estimatedDaysLeft: estimatedDaysLeft,
    dailyBudgetBytes: dailyBudgetBytes,
    daysUntilExpiry: daysUntilExpiry,
    status: status,
  );
}

class TopConsumerEntry {
  const TopConsumerEntry({
    required this.label,
    required this.outbound,
    required this.totalBytes,
    required this.activeStreams,
  });

  final String label;
  final String outbound;
  final int totalBytes;
  final int activeStreams;
}

class SessionFootprint {
  const SessionFootprint({
    this.totalConnections = 0,
    this.proxiedConnections = 0,
    this.activeProxyNodes = const [],
    this.stalledConnections = 0,
    this.topConsumers = const [],
  });

  final int totalConnections;
  final int proxiedConnections;
  final List<String> activeProxyNodes;
  final int stalledConnections;
  final List<TopConsumerEntry> topConsumers;

  int get activeNodeCount => activeProxyNodes.length;

  bool get isSingleNodeSafe => activeNodeCount <= 1;
}

const _footprintBuiltinOutbounds = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'};

SessionFootprint analyzeSessionFootprint(
  List<TrackerInfo> connections, {
  DateTime? now,
}) {
  if (connections.isEmpty) {
    return const SessionFootprint();
  }
  final refNow = now ?? DateTime.now();
  final activeNodes = <String>{};
  var proxiedConnections = 0;
  var stalledConnections = 0;
  final consumerTotals =
      <String, ({String outbound, int totalBytes, int activeStreams})>{};

  for (final conn in connections) {
    final leaf = conn.chains.firstOrNull?.trim() ?? '';
    if (leaf.isNotEmpty && !_footprintBuiltinOutbounds.contains(leaf)) {
      activeNodes.add(leaf);
      proxiedConnections++;
    }
    if (refNow.difference(conn.start) >= const Duration(seconds: 15) &&
        conn.upload >= 512 &&
        conn.download == 0) {
      stalledConnections++;
    }
    final process = conn.metadata.process.trim();
    final host = conn.metadata.host.trim();
    final destIp = conn.metadata.destinationIP.trim();
    final key = process.isNotEmpty
        ? process
        : (host.isNotEmpty ? host : destIp);
    if (key.isEmpty) continue;
    final bytes =
        math.max<int>(0, conn.upload) + math.max<int>(0, conn.download);
    final prev = consumerTotals[key];
    if (prev == null) {
      consumerTotals[key] = (
        outbound: leaf,
        totalBytes: bytes,
        activeStreams: 1,
      );
    } else {
      consumerTotals[key] = (
        outbound: prev.outbound.isNotEmpty ? prev.outbound : leaf,
        totalBytes: prev.totalBytes + bytes,
        activeStreams: prev.activeStreams + 1,
      );
    }
  }

  final sortedNodes = activeNodes.toList()..sort();
  final consumers =
      [
        for (final entry in consumerTotals.entries)
          TopConsumerEntry(
            label: entry.key,
            outbound: entry.value.outbound,
            totalBytes: entry.value.totalBytes,
            activeStreams: entry.value.activeStreams,
          ),
      ]..sort((a, b) {
        final cmp = b.totalBytes.compareTo(a.totalBytes);
        return cmp != 0 ? cmp : b.activeStreams.compareTo(a.activeStreams);
      });

  return SessionFootprint(
    totalConnections: connections.length,
    proxiedConnections: proxiedConnections,
    activeProxyNodes: List.unmodifiable(sortedNodes),
    stalledConnections: stalledConnections,
    topConsumers: List.unmodifiable(consumers.take(3)),
  );
}

enum HealthGrade { excellent, stable, attention, stopped }

class ConnectionHealthReport {
  const ConnectionHealthReport({
    required this.score,
    required this.grade,
    required this.encryptedDns,
    required this.singleNodeSafe,
    required this.ipv6Safe,
  });

  final int score;
  final HealthGrade grade;
  final bool encryptedDns;
  final bool singleNodeSafe;
  final bool ipv6Safe;
}

ConnectionHealthReport evaluateConnectionHealth({
  required bool isRunning,
  required bool suspended,
  required int? activeDelayMs,
  required Dns dns,
  required bool ipv6Enabled,
  required bool isMobile,
  required SessionFootprint? footprint,
}) {
  final encryptedDns =
      dns.enable &&
      (dns.enhancedMode == DnsMode.fakeIp ||
          dns.nameserver.any(
            (s) =>
                s.startsWith('https://') ||
                s.startsWith('tls://') ||
                s.startsWith('quic://'),
          ));
  final singleNodeSafe = footprint == null || footprint.isSingleNodeSafe;
  final ipv6Safe = !isMobile || !ipv6Enabled;

  if (!isRunning) {
    return ConnectionHealthReport(
      score: 0,
      grade: HealthGrade.stopped,
      encryptedDns: encryptedDns,
      singleNodeSafe: singleNodeSafe,
      ipv6Safe: ipv6Safe,
    );
  }

  var score = suspended ? 10 : 30;
  if (activeDelayMs == null) {
    score += 15;
  } else if (activeDelayMs <= 0) {
    score += 0;
  } else if (activeDelayMs < 180) {
    score += 25;
  } else if (activeDelayMs < 450) {
    score += 18;
  } else if (activeDelayMs < 1200) {
    score += 10;
  } else {
    score += 4;
  }
  if (singleNodeSafe) score += 20;
  if (encryptedDns) score += 15;
  if (ipv6Safe) score += 10;

  final clamped = score.clamp(0, 100);
  final grade = clamped >= 85
      ? HealthGrade.excellent
      : clamped >= 60
      ? HealthGrade.stable
      : HealthGrade.attention;

  return ConnectionHealthReport(
    score: clamped,
    grade: grade,
    encryptedDns: encryptedDns,
    singleNodeSafe: singleNodeSafe,
    ipv6Safe: ipv6Safe,
  );
}

String? derivePortalOrigin(String? rawUrl) {
  final trimmed = rawUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final hasExplicitPort =
      uri.hasPort &&
      !((scheme == 'http' && uri.port == 80) ||
          (scheme == 'https' && uri.port == 443));
  return '$scheme://${uri.host}${hasExplicitPort ? ':${uri.port}' : ''}';
}

class PortalAuthExpiredException implements Exception {
  const PortalAuthExpiredException();
}

class PortalAccountBinding {
  const PortalAccountBinding({
    required this.origin,
    required this.email,
    required this.authToken,
    this.lastSyncedAt,
    this.authExpired = false,
  });

  final String origin;
  final String email;
  final String authToken;
  final DateTime? lastSyncedAt;
  final bool authExpired;

  PortalAccountBinding copyWith({
    String? origin,
    String? email,
    String? authToken,
    DateTime? lastSyncedAt,
    bool? authExpired,
  }) {
    return PortalAccountBinding(
      origin: origin ?? this.origin,
      email: email ?? this.email,
      authToken: authToken ?? this.authToken,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      authExpired: authExpired ?? this.authExpired,
    );
  }

  Map<String, Object?> toJson() => {
    'origin': origin,
    'email': email,
    'authToken': authToken,
    if (lastSyncedAt != null)
      'lastSyncedAt': lastSyncedAt!.millisecondsSinceEpoch,
    if (authExpired) 'authExpired': true,
  };

  static PortalAccountBinding? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final origin = derivePortalOrigin(raw['origin']?.toString());
    final email = raw['email']?.toString().trim() ?? '';
    final token = raw['authToken']?.toString().trim() ?? '';
    if (origin == null || email.isEmpty || token.isEmpty) {
      return null;
    }
    final syncedMs = (raw['lastSyncedAt'] as num?)?.toInt();
    return PortalAccountBinding(
      origin: origin,
      email: email,
      authToken: token,
      lastSyncedAt: syncedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(syncedMs)
          : null,
      authExpired: raw['authExpired'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PortalAccountBinding &&
            other.origin == origin &&
            other.email == email &&
            other.authToken == authToken &&
            other.lastSyncedAt == lastSyncedAt &&
            other.authExpired == authExpired;
  }

  @override
  int get hashCode =>
      Object.hash(origin, email, authToken, lastSyncedAt, authExpired);
}

class PortalAccountsLedger {
  const PortalAccountsLedger({this.entries = const {}});

  final Map<int, PortalAccountBinding> entries;

  PortalAccountBinding? operator [](int profileId) => entries[profileId];

  PortalAccountsLedger withEntry(int profileId, PortalAccountBinding binding) {
    final updated = Map<int, PortalAccountBinding>.from(entries)
      ..[profileId] = binding;
    return PortalAccountsLedger(entries: Map.unmodifiable(updated));
  }

  PortalAccountsLedger withoutEntry(int profileId) {
    if (!entries.containsKey(profileId)) return this;
    final updated = Map<int, PortalAccountBinding>.from(entries)
      ..remove(profileId);
    return PortalAccountsLedger(entries: Map.unmodifiable(updated));
  }

  String encode() {
    return json.encode({
      'v': 1,
      'entries': {
        for (final entry in entries.entries)
          entry.key.toString(): entry.value.toJson(),
      },
    });
  }

  static PortalAccountsLedger decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const PortalAccountsLedger();
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return const PortalAccountsLedger();
      final rawEntries = decoded['entries'];
      if (rawEntries is! Map) return const PortalAccountsLedger();
      final parsed = <int, PortalAccountBinding>{};
      for (final entry in rawEntries.entries) {
        final id = int.tryParse(entry.key?.toString() ?? '');
        if (id == null) continue;
        final binding = PortalAccountBinding.fromJson(entry.value);
        if (binding != null) {
          parsed[id] = binding;
        }
      }
      return PortalAccountsLedger(entries: Map.unmodifiable(parsed));
    } catch (_) {
      return const PortalAccountsLedger();
    }
  }
}

class PortalSubscribeSnapshot {
  const PortalSubscribeSnapshot({
    required this.deviceMeta,
    this.subscriptionInfo,
  });

  final SubscriptionDeviceMeta deviceMeta;
  final SubscriptionInfo? subscriptionInfo;
}

int? _parseNonNegInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw >= 0 ? raw : null;
  if (raw is num) {
    if (!raw.isFinite || raw < 0) return null;
    return raw.truncate();
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final parsed = int.tryParse(s);
  if (parsed != null) return parsed >= 0 ? parsed : null;
  final dec = double.tryParse(s);
  if (dec != null && dec.isFinite && dec >= 0) return dec.truncate();
  return null;
}

String? parsePortalLoginToken(Object? raw) {
  if (raw is! Map) return null;
  final inner = raw['data'] is Map ? raw['data'] as Map : raw;
  final authData = inner['auth_data']?.toString().trim();
  if (authData != null && authData.isNotEmpty) return authData;
  final token = inner['token']?.toString().trim();
  if (token != null && token.isNotEmpty) return token;
  return null;
}

String? parsePortalErrorMessage(Object? raw) {
  if (raw is! Map) return null;
  for (final key in const ['message', 'error', 'msg']) {
    final value = raw[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

PortalSubscribeSnapshot? parsePortalSubscribeResponse(
  Object? raw, {
  required String origin,
  DateTime? now,
}) {
  if (raw is! Map) return null;
  final data = raw['data'] is Map ? raw['data'] as Map : raw;
  final plan = data['plan'] is Map ? data['plan'] as Map : null;

  int? onlineDevices;
  for (final key in const [
    'alive_ip',
    'online_devices',
    'active_devices',
    'online_count',
    'online',
    'alive',
  ]) {
    final candidate = _parseCount(data[key]?.toString(), min: 0);
    if (candidate != null) {
      onlineDevices = candidate;
      break;
    }
  }

  int? deviceLimit;
  for (final rawVal in [
    data['device_limit'],
    plan?['device_limit'],
    data['max_devices'],
    data['limit_ip'],
    plan?['limit_ip'],
  ]) {
    final candidate = _parseCount(rawVal?.toString(), min: 1);
    if (candidate != null) {
      deviceLimit = candidate;
      break;
    }
  }

  final rawPlanName = (plan?['name'] ?? data['plan_name'])?.toString().trim();
  final planName = (rawPlanName != null && rawPlanName.isNotEmpty)
      ? rawPlanName
      : null;
  final resetDay = _parseCount(data['reset_day']?.toString(), min: 0, max: 31);

  final upload = _parseNonNegInt(data['u']) ?? 0;
  final download = _parseNonNegInt(data['d']) ?? 0;
  final total = _parseNonNegInt(data['transfer_enable']) ?? 0;
  final expire = _parseNonNegInt(data['expired_at']) ?? 0;
  final subInfo = (total > 0 || expire > 0)
      ? SubscriptionInfo(
          upload: upload,
          download: download,
          total: total,
          expire: expire,
        )
      : null;

  if (onlineDevices == null &&
      deviceLimit == null &&
      planName == null &&
      subInfo == null) {
    return null;
  }

  return PortalSubscribeSnapshot(
    deviceMeta: SubscriptionDeviceMeta(
      onlineDevices: onlineDevices,
      deviceLimit: deviceLimit,
      portalUrl: derivePortalOrigin(origin),
      planName: planName,
      resetDay: resetDay,
      source: DeviceMetaSource.portal,
      updatedAt: now ?? DateTime.now(),
    ),
    subscriptionInfo: subInfo,
  );
}
