import 'package:fl_clash/common/security_utils.dart';
import 'package:fl_clash/common/subscription_insights.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('security_utils', () {
    test('maskIfHidden obscures value only when hideIp is enabled', () {
      expect(maskIfHidden('192.168.1.5', hideIp: true), maskedSensitiveValue);
      expect(maskIfHidden('192.168.1.5', hideIp: false), '192.168.1.5');
    });

    test('parseCloudflareTrace extracts trimmed key-value fields', () {
      final parsed = parseCloudflareTrace(
        'fl=123\nip=203.0.113.5\nloc=SG\ntls=TLSv1.3\n\n',
      );
      expect(parsed['ip'], '203.0.113.5');
      expect(parsed['loc'], 'SG');
      expect(parsed['tls'], 'TLSv1.3');
    });

    test('applyEssentialAppsBypass rejects essential apps cleanly', () {
      const initial = AccessControlProps(
        enable: false,
        mode: AccessControlMode.rejectSelected,
        rejectList: ['com.existing.app'],
      );
      final res = applyEssentialAppsBypass(initial, const [
        'com.VCB',
        'com.vnid',
        'com.vnpay.bidv',
        'com.example.browser',
      ]);
      expect(res.matchedCount, 3);
      expect(res.props.enable, isTrue);
      expect(res.props.mode, AccessControlMode.rejectSelected);
      expect(
        res.props.rejectList,
        containsAll([
          'com.existing.app',
          'com.VCB',
          'com.vnid',
          'com.vnpay.bidv',
        ]),
      );
      expect(res.props.rejectList, isNot(contains('com.example.browser')));

      const whitelist = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['com.VCB', 'com.example.browser'],
      );
      final wlRes = applyEssentialAppsBypass(whitelist, const [
        'com.VCB',
        'com.example.browser',
      ]);
      expect(wlRes.matchedCount, 1);
      expect(wlRes.props.mode, AccessControlMode.acceptSelected);
      expect(wlRes.props.acceptList, ['com.example.browser']);
    });

    test(
      'evaluateSubscriptionAlert detects low quota, expiry, and healthy',
      () {
        final now = DateTime.utc(2026, 11, 25, 12);
        final healthy = SubscriptionInfo(
          upload: 100,
          download: 200,
          total: 10000,
          expire:
              now.add(const Duration(days: 15)).millisecondsSinceEpoch ~/ 1000,
        );
        expect(evaluateSubscriptionAlert(healthy, now: now), isNull);

        final lowQuota = SubscriptionInfo(
          upload: 4000,
          download: 5500,
          total: 10000,
          expire:
              now.add(const Duration(days: 15)).millisecondsSinceEpoch ~/ 1000,
        );
        final lowAlert = evaluateSubscriptionAlert(lowQuota, now: now);
        expect(lowAlert?.kind, SubscriptionAlertKind.lowQuota);
        expect(lowAlert?.remainingPercent, 5);

        final expiringSoon = SubscriptionInfo(
          upload: 100,
          download: 100,
          total: 10000,
          expire:
              now.add(const Duration(hours: 36)).millisecondsSinceEpoch ~/ 1000,
        );
        final expAlert = evaluateSubscriptionAlert(expiringSoon, now: now);
        expect(expAlert?.kind, SubscriptionAlertKind.expiringSoon);
        expect(expAlert?.daysLeft, 2);

        final exhausted = SubscriptionInfo(
          upload: 6000,
          download: 4000,
          total: 10000,
          expire:
              now.add(const Duration(days: 10)).millisecondsSinceEpoch ~/ 1000,
        );
        expect(
          evaluateSubscriptionAlert(exhausted, now: now)?.kind,
          SubscriptionAlertKind.expiredOrExhausted,
        );

        final withinDevices = evaluateSubscriptionAlert(
          healthy,
          deviceMeta: const SubscriptionDeviceMeta(
            onlineDevices: 2,
            deviceLimit: 2,
          ),
          now: now,
        );
        expect(withinDevices, isNull);

        final overDevices = evaluateSubscriptionAlert(
          healthy,
          deviceMeta: const SubscriptionDeviceMeta(
            onlineDevices: 3,
            deviceLimit: 2,
          ),
          now: now,
        );
        expect(overDevices?.kind, SubscriptionAlertKind.deviceLimitExceeded);
        expect(overDevices?.onlineDevices, 3);
        expect(overDevices?.deviceLimit, 2);
      },
    );
  });
}
