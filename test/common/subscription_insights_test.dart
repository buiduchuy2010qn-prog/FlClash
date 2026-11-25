import 'dart:convert';

import 'package:fl_clash/common/daily_traffic_store.dart';
import 'package:fl_clash/common/subscription_insights.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _conn({
  required String id,
  required String leaf,
  required DateTime start,
  int upload = 0,
  int download = 0,
  String process = '',
  String host = '',
  String destIp = '1.1.1.1',
}) {
  return TrackerInfo(
    id: id,
    upload: upload,
    download: download,
    start: start,
    metadata: Metadata(process: process, host: host, destinationIP: destIp),
    chains: [leaf, 'Proxy'],
    rule: 'Match',
    rulePayload: '',
  );
}

void main() {
  group('subscription_insights', () {
    test('parses userinfo, standalone headers, and portal url', () {
      final now = DateTime.utc(2026, 11, 25, 12);
      final meta = parseSubscriptionDeviceMeta(
        userinfoHeader:
            'upload=100; download=200; total=1000; alive_ip=1; device_limit=2',
        headers: const {
          'profile-web-page-url': ['https://example.com/dashboard'],
        },
        now: now,
      );
      expect(meta, isNotNull);
      expect(meta!.onlineDevices, 1);
      expect(meta.deviceLimit, 2);
      expect(meta.badgeLabel, '1/2');
      expect(meta.isOverLimit, isFalse);
      expect(meta.isAtLimit, isFalse);
      expect(meta.portalUrl, 'https://example.com/dashboard');
      expect(meta.source, DeviceMetaSource.header);

      final headerFallback = parseSubscriptionDeviceMeta(
        headers: const {
          'x-online-devices': ['3'],
          'x-device-limit': ['2'],
          'profile-web-page-url': ['javascript:alert(1)'],
        },
        now: now,
      );
      expect(headerFallback?.onlineDevices, 3);
      expect(headerFallback?.deviceLimit, 2);
      expect(headerFallback?.isOverLimit, isTrue);
      expect(headerFallback?.portalUrl, isNull);
    });

    test('parses YAML and Base64 share-link payload device nodes cleanly', () {
      final yamlPayload = utf8.encode('''
proxies:
  - { name: "Expire: 23/12/2026", type: ss, server: 1.1.1.1, port: 443 }
  - { name: "Quota left: 2.42 TB", type: ss, server: 1.1.1.1, port: 443 }
  - { name: "📱 Thiết bị: 1/2", type: vmess, server: 2.2.2.2, port: 443 }
''');
      final fromYaml = parseSubscriptionDeviceMeta(payloadBytes: yamlPayload);
      expect(fromYaml, isNotNull);
      expect(fromYaml!.onlineDevices, 1);
      expect(fromYaml.deviceLimit, 2);
      expect(fromYaml.source, DeviceMetaSource.payload);

      final links = base64Encode(
        utf8.encode(
          'vless://id@example.com:443#Online%3A%202%2F2\n'
          'vless://id@example.com:443#Singapore%2001\n',
        ),
      );
      final fromLinks = parseSubscriptionDeviceMeta(
        payloadBytes: utf8.encode(links),
      );
      expect(fromLinks?.onlineDevices, 2);
      expect(fromLinks?.deviceLimit, 2);
      expect(fromLinks?.isAtLimit, isTrue);

      final nonDeviceDates = parseDeviceMetaFromNodeNames(const [
        'Expire: 23/12/2026',
        'Traffic: 2.42 TB',
        'SG Node 01',
      ]);
      expect(nonDeviceDates, isNull);
    });

    test('SubscriptionInsightsLedger round-trips JSON cleanly', () {
      final now = DateTime.utc(2026, 11, 25, 10);
      final initial = const SubscriptionInsightsLedger().withEntry(
        42,
        SubscriptionDeviceMeta(
          onlineDevices: 1,
          deviceLimit: 2,
          portalUrl: 'https://portal.example.org',
          updatedAt: now,
        ),
      );
      final decoded = SubscriptionInsightsLedger.decode(initial.encode());
      expect(decoded[42]?.onlineDevices, 1);
      expect(decoded[42]?.deviceLimit, 2);
      expect(decoded[42]?.portalUrl, 'https://portal.example.org');
      expect(decoded.withoutEntry(42)[42], isNull);
    });

    test('forecastSubscriptionQuota computes burn-rate and status', () {
      final now = DateTime.utc(2026, 11, 25, 12);
      const gb = 1024 * 1024 * 1024;
      var ledger = const DailyTrafficLedger();
      ledger = ledger.recordDelta(upDelta: 0, downDelta: 2 * gb, now: now);
      ledger = ledger.recordDelta(
        upDelta: 0,
        downDelta: 2 * gb,
        now: now.subtract(const Duration(days: 1)),
      );

      final healthyInfo = SubscriptionInfo(
        upload: 0,
        download: 10 * gb,
        total: 100 * gb,
        expire:
            now.add(const Duration(days: 20)).millisecondsSinceEpoch ~/ 1000,
      );
      final comfortable = forecastSubscriptionQuota(
        healthyInfo,
        ledger,
        now: now,
      );
      expect(comfortable, isNotNull);
      expect(comfortable!.avgDailyBytes, 2 * gb);
      expect(comfortable.estimatedDaysLeft, 45);
      expect(comfortable.status, QuotaBurnStatus.comfortable);

      final tightInfo = SubscriptionInfo(
        upload: 0,
        download: 90 * gb,
        total: 100 * gb,
        expire:
            now.add(const Duration(days: 20)).millisecondsSinceEpoch ~/ 1000,
      );
      final tight = forecastSubscriptionQuota(tightInfo, ledger, now: now);
      expect(tight!.estimatedDaysLeft, 5);
      expect(tight.status, QuotaBurnStatus.tight);

      final criticalInfo = SubscriptionInfo(
        upload: 0,
        download: 96 * gb,
        total: 100 * gb,
        expire:
            now.add(const Duration(days: 20)).millisecondsSinceEpoch ~/ 1000,
      );
      final critical = forecastSubscriptionQuota(
        criticalInfo,
        ledger,
        now: now,
      );
      expect(critical!.status, QuotaBurnStatus.critical);

      final exhaustedInfo = SubscriptionInfo(
        upload: 50 * gb,
        download: 50 * gb,
        total: 100 * gb,
        expire:
            now.add(const Duration(days: 10)).millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        forecastSubscriptionQuota(exhaustedInfo, ledger, now: now)?.status,
        QuotaBurnStatus.exhausted,
      );
    });

    test(
      'analyzeSessionFootprint detects single vs multi-node and top consumers',
      () {
        final now = DateTime.utc(2026, 11, 25, 12, 0, 30);
        final single = analyzeSessionFootprint([
          _conn(
            id: '1',
            leaf: 'SG-01',
            start: now.subtract(const Duration(seconds: 5)),
            upload: 1000,
            download: 9000,
            process: 'Chrome',
          ),
          _conn(
            id: '2',
            leaf: 'DIRECT',
            start: now.subtract(const Duration(seconds: 2)),
            upload: 500,
            download: 1500,
            host: 'lan.local',
          ),
        ], now: now);
        expect(single.isSingleNodeSafe, isTrue);
        expect(single.activeNodeCount, 1);
        expect(single.proxiedConnections, 1);
        expect(single.topConsumers.first.label, 'Chrome');

        final multi = analyzeSessionFootprint([
          _conn(
            id: '1',
            leaf: 'SG-01',
            start: now.subtract(const Duration(seconds: 20)),
            upload: 1024,
            download: 0,
            host: 'alpha.example',
          ),
          _conn(
            id: '2',
            leaf: 'JP-02',
            start: now.subtract(const Duration(seconds: 5)),
            upload: 200,
            download: 5000,
            host: 'beta.example',
          ),
        ], now: now);
        expect(multi.isSingleNodeSafe, isFalse);
        expect(multi.activeNodeCount, 2);
        expect(multi.stalledConnections, 1);
        expect(multi.topConsumers.first.label, 'beta.example');
      },
    );

    test(
      'evaluateConnectionHealth scores stopped, excellent, and multi-node',
      () {
        const safeDns = Dns(
          enable: true,
          enhancedMode: DnsMode.fakeIp,
          nameserver: ['https://1.1.1.1/dns-query'],
        );
        final stopped = evaluateConnectionHealth(
          isRunning: false,
          suspended: false,
          activeDelayMs: null,
          dns: safeDns,
          ipv6Enabled: false,
          isMobile: true,
          footprint: null,
        );
        expect(stopped.grade, HealthGrade.stopped);
        expect(stopped.score, 0);

        final excellent = evaluateConnectionHealth(
          isRunning: true,
          suspended: false,
          activeDelayMs: 65,
          dns: safeDns,
          ipv6Enabled: false,
          isMobile: true,
          footprint: const SessionFootprint(activeProxyNodes: ['SG-01']),
        );
        expect(excellent.grade, HealthGrade.excellent);
        expect(excellent.score, 100);

        final degraded = evaluateConnectionHealth(
          isRunning: true,
          suspended: false,
          activeDelayMs: 900,
          dns: const Dns(enable: false),
          ipv6Enabled: true,
          isMobile: true,
          footprint: const SessionFootprint(
            activeProxyNodes: ['SG-01', 'JP-02'],
          ),
        );
        expect(degraded.grade, HealthGrade.attention);
        expect(degraded.score, 40);
      },
    );

    test('portal origin, login token, subscribe snapshot, and ledger', () {
      expect(
        derivePortalOrigin(
          'https://example.com:8443/api/v1/client/subscribe?token=abc',
        ),
        'https://example.com:8443',
      );
      expect(derivePortalOrigin('ftp://example.com'), isNull);
      expect(
        parsePortalLoginToken({
          'data': {'auth_data': 'eyJ.auth.token', 'token': 'fallback'},
        }),
        'eyJ.auth.token',
      );
      expect(
        parsePortalErrorMessage({'message': 'Invalid credentials'}),
        'Invalid credentials',
      );
      expect(
        parsePortalErrorMessage({
          'message': 'The given data was invalid.',
          'errors': {
            'password': ['Password too short'],
          },
        }),
        'Password too short',
      );

      final snap = parsePortalSubscribeResponse({
        'data': {
          'alive_ip': 1,
          'device_limit': 2,
          'u': 1024,
          'd': 2048,
          'transfer_enable': 10737418240,
          'expired_at': 1800000000,
          'reset_day': 15,
          'plan': {'name': 'VIP 4G', 'device_limit': 3},
        },
      }, origin: 'https://example.com/dashboard');
      expect(snap, isNotNull);
      expect(snap!.deviceMeta.onlineDevices, 1);
      expect(snap.deviceMeta.deviceLimit, 2);
      expect(snap.deviceMeta.planName, 'VIP 4G');
      expect(snap.deviceMeta.resetDay, 15);
      expect(snap.deviceMeta.portalUrl, 'https://example.com');
      expect(snap.deviceMeta.source, DeviceMetaSource.portal);
      expect(snap.subscriptionInfo?.upload, 1024);
      expect(snap.subscriptionInfo?.download, 2048);
      expect(snap.subscriptionInfo?.total, 10737418240);

      final zeroDevices = parsePortalSubscribeResponse({
        'data': {'alive_ip': null, 'device_limit': 2},
      }, origin: 'https://example.com');
      expect(zeroDevices?.deviceMeta.onlineDevices, 0);
      expect(zeroDevices?.deviceMeta.deviceLimit, 2);
      expect(zeroDevices?.deviceMeta.badgeLabel, '0/2');

      final nestedLimit = parsePortalSubscribeResponse({
        'data': {
          'alive_ip': 3,
          'plan': {'name': 'Pro', 'limit_ip': 2},
        },
      }, origin: 'https://example.com');
      expect(nestedLimit?.deviceMeta.onlineDevices, 3);
      expect(nestedLimit?.deviceMeta.deviceLimit, 2);
      expect(nestedLimit?.deviceMeta.isOverLimit, isTrue);

      final now = DateTime.utc(2026, 11, 25, 21);
      final ledger = const PortalAccountsLedger().withEntry(
        9,
        PortalAccountBinding(
          origin: 'https://example.com',
          email: 'user@example.com',
          authToken: 'tok_123',
          lastSyncedAt: now,
        ),
      );
      final roundTrip = PortalAccountsLedger.decode(ledger.encode());
      expect(roundTrip[9]?.origin, 'https://example.com');
      expect(roundTrip[9]?.email, 'user@example.com');
      expect(roundTrip[9]?.authToken, 'tok_123');
      expect(roundTrip.withoutEntry(9)[9], isNull);
    });
  });
}
