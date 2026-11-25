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
    this.onlineDevices,
    this.deviceLimit,
  });

  final SubscriptionAlertKind kind;
  final int? remainingPercent;
  final int? daysLeft;
  final int? onlineDevices;
  final int? deviceLimit;
}

SubscriptionAlert? evaluateSubscriptionAlert(
  SubscriptionInfo? info, {
  SubscriptionDeviceMeta? deviceMeta,
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
  if (expireDate != null) {
    final diff = expireDate.difference(refNow);
    if (diff <= const Duration(days: 3)) {
      final daysLeft = (diff.inHours / 24).ceil().clamp(1, 3);
      return SubscriptionAlert(
        kind: SubscriptionAlertKind.expiringSoon,
        daysLeft: daysLeft,
      );
    }
  }
  return null;
}
