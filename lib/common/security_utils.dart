import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_clash/common/subscription_insights.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const maskedSensitiveValue = '*****';

String maskIfHidden(String value, {required bool hideIp}) =>
    hideIp ? maskedSensitiveValue : value;

Map<String, String> parseCloudflareTrace(String body) {
  final result = <String, String>{};
  for (final rawLine in body.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    if (key.isNotEmpty) {
      result[key] = value;
    }
  }
  return result;
}

const _essentialBypassExactPackages = <String>{
  'vn.gov.etax.etaxmobile',
  'com.vnid',
  'com.bhxhapp',
  'com.VCB',
  'com.mbmobile',
  'vn.com.techcombank.bb.app',
  'com.vnpay.bidv',
  'com.vietinbank.ipay',
  'mobile.acb.com.vn',
  'com.vnpay.vpbankonline',
  'com.tpb.mb.gprsandroid',
  'com.sacombank.ewallet',
  'vn.shb.mbanking',
  'com.vnpay.hdbank',
  'com.ocb.omniextra',
  'com.vnpay.Agribank3g',
  'vn.cake.bank',
  'io.lifestyle.timo',
  'com.mservice.momotransfer',
  'vn.zalopay.app',
  'vn.vnpay.wallet',
  'com.bplus.vtpay',
  'com.MSB.mbank',
  'ops.namabank.com.vn',
  'com.seabank.mbanking',
  'com.lpbank.lv24h',
};

const _essentialBypassPrefixes = <String>['vn.gov.', 'gov.vn.', 'com.vnpay.'];

bool isEssentialBypassPackage(String packageName) {
  if (_essentialBypassExactPackages.contains(packageName)) {
    return true;
  }
  return _essentialBypassPrefixes.any(packageName.startsWith);
}

({AccessControlProps props, int matchedCount}) applyEssentialAppsBypass(
  AccessControlProps current,
  Iterable<String> installedPackageNames,
) {
  final matched = installedPackageNames.where(isEssentialBypassPackage).toSet();
  if (matched.isEmpty) {
    return (props: current, matchedCount: 0);
  }
  if (current.enable && current.mode == AccessControlMode.acceptSelected) {
    final nextAccept = [
      for (final pkg in current.acceptList)
        if (!matched.contains(pkg)) pkg,
    ];
    return (
      props: current.copyWith(acceptList: nextAccept),
      matchedCount: matched.length,
    );
  }
  final nextReject = <String>{...current.rejectList, ...matched}.toList();
  return (
    props: current.copyWith(
      enable: true,
      mode: AccessControlMode.rejectSelected,
      rejectList: nextReject,
    ),
    matchedCount: matched.length,
  );
}

enum SubscriptionAlertKind {
  expiredOrExhausted,
  deviceLimitExceeded,
  lowQuota,
  expiringSoon,
}

class SubscriptionAlert {
  const SubscriptionAlert({
    required this.kind,
    this.remainingPercent,
    this.daysLeft,
    this.hoursLeft,
    this.onlineDevices,
    this.deviceLimit,
  });

  final SubscriptionAlertKind kind;
  final int? remainingPercent;
  final int? daysLeft;
  final int? hoursLeft;
  final int? onlineDevices;
  final int? deviceLimit;
}

SubscriptionAlert? evaluateSubscriptionAlert(
  SubscriptionInfo? info, {
  SubscriptionDeviceMeta? deviceMeta,
  int expiringSoonDays = 5,
  DateTime? now,
}) {
  final refNow = now ?? DateTime.now();
  if (info != null && (info.total > 0 || info.expire > 0)) {
    final expireDate = info.expireDate;
    if (expireDate != null && !expireDate.isAfter(refNow)) {
      return const SubscriptionAlert(
        kind: SubscriptionAlertKind.expiredOrExhausted,
      );
    }
    final used = info.upload + info.download;
    if (info.total > 0 && used >= info.total) {
      return const SubscriptionAlert(
        kind: SubscriptionAlertKind.expiredOrExhausted,
      );
    }
  }
  if (deviceMeta != null && deviceMeta.isOverLimit) {
    return SubscriptionAlert(
      kind: SubscriptionAlertKind.deviceLimitExceeded,
      onlineDevices: deviceMeta.onlineDevices,
      deviceLimit: deviceMeta.deviceLimit,
    );
  }
  if (info == null || (info.total <= 0 && info.expire <= 0)) {
    return null;
  }
  final expireDate = info.expireDate;
  final used = info.upload + info.download;
  if (info.total > 0) {
    final usedRatio = used / info.total;
    if (usedRatio >= 0.90) {
      final remainingPercent = ((1.0 - usedRatio) * 100).round().clamp(1, 10);
      return SubscriptionAlert(
        kind: SubscriptionAlertKind.lowQuota,
        remainingPercent: remainingPercent,
      );
    }
  }
  if (expireDate != null && expiringSoonDays >= 1) {
    final diff = expireDate.difference(refNow);
    if (diff <= Duration(days: expiringSoonDays)) {
      final daysLeft = (diff.inHours / 24).ceil().clamp(1, expiringSoonDays);
      final hoursLeft = diff.inHours < 24 ? math.max(1, diff.inHours) : null;
      return SubscriptionAlert(
        kind: SubscriptionAlertKind.expiringSoon,
        daysLeft: daysLeft,
        hoursLeft: hoursLeft,
      );
    }
  }
  return null;
}

String _alertBucketKey(SubscriptionAlert alert) {
  return switch (alert.kind) {
    SubscriptionAlertKind.expiringSoon => 'expiringSoon:${alert.daysLeft ?? 0}',
    SubscriptionAlertKind.lowQuota => 'lowQuota:${alert.remainingPercent ?? 0}',
    SubscriptionAlertKind.deviceLimitExceeded => 'deviceLimitExceeded',
    SubscriptionAlertKind.expiredOrExhausted => 'expiredOrExhausted',
  };
}

int _alertPriority(SubscriptionAlertKind kind) {
  return switch (kind) {
    SubscriptionAlertKind.lowQuota => 1,
    SubscriptionAlertKind.expiringSoon => 2,
    SubscriptionAlertKind.deviceLimitExceeded => 3,
    SubscriptionAlertKind.expiredOrExhausted => 4,
  };
}

bool shouldDispatchSubscriptionAlert(
  String? encodedLedger,
  int profileId,
  SubscriptionAlert alert, {
  Duration cooldown = const Duration(hours: 12),
  DateTime? now,
}) {
  if (encodedLedger == null || encodedLedger.trim().isEmpty) {
    return true;
  }
  try {
    final decoded = json.decode(encodedLedger);
    if (decoded is! Map) return true;
    final raw = decoded[profileId.toString()];
    if (raw is! Map) return true;
    final prevKindName = raw['kind']?.toString();
    final prevBucket = raw['bucket']?.toString();
    final prevMs = (raw['at'] as num?)?.toInt();
    if (prevKindName == null || prevMs == null) return true;
    final prevKind = SubscriptionAlertKind.values
        .where((v) => v.name == prevKindName)
        .firstOrNull;
    if (prevKind == null ||
        _alertPriority(alert.kind) > _alertPriority(prevKind)) {
      return true;
    }
    if (alert.kind == SubscriptionAlertKind.expiringSoon &&
        (alert.daysLeft ?? 99) <= 1 &&
        prevBucket != _alertBucketKey(alert)) {
      return true;
    }
    final refNow = now ?? DateTime.now();
    final elapsed = refNow.millisecondsSinceEpoch - prevMs;
    if (elapsed >= cooldown.inMilliseconds) {
      return true;
    }
    return prevBucket != _alertBucketKey(alert) &&
        elapsed >= const Duration(hours: 6).inMilliseconds;
  } catch (_) {
    return true;
  }
}

String recordDispatchedSubscriptionAlert(
  String? encodedLedger,
  int profileId,
  SubscriptionAlert alert, {
  DateTime? now,
}) {
  final map = <String, Object?>{};
  if (encodedLedger != null && encodedLedger.trim().isNotEmpty) {
    try {
      final decoded = json.decode(encodedLedger);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.key != null) {
            map[entry.key.toString()] = entry.value;
          }
        }
      }
    } catch (_) {}
  }
  final refNow = now ?? DateTime.now();
  map[profileId.toString()] = {
    'kind': alert.kind.name,
    'bucket': _alertBucketKey(alert),
    'at': refNow.millisecondsSinceEpoch,
  };
  return json.encode(map);
}
