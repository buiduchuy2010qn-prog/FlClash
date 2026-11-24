import 'package:dio/dio.dart';
import 'package:fl_clash/common/version_gate.dart';
import 'package:test/test.dart';

void main() {
  group('VersionGateEvaluator', () {
    test('fails open when policy is null or minVersionCode is zero', () {
      expect(
        VersionGateEvaluator.isBlocked(currentVersionCode: 10, policy: null),
        isFalse,
      );
      expect(
        VersionGateEvaluator.isBlocked(
          currentVersionCode: 10,
          policy: VersionGatePolicy(
            minVersionCode: 0,
            latestVersion: '0.9.7',
            downloadUrl: '',
            message: '',
            fetchedAt: DateTime.now(),
          ),
        ),
        isFalse,
      );
    });

    test('blocks outdated builds and allows current or newer builds', () {
      final policy = VersionGatePolicy(
        minVersionCode: 2026120100,
        latestVersion: '1.0.0',
        downloadUrl: 'https://github.com/buiduchuy2010qn-prog/FlClash/releases',
        message: 'Update required',
        fetchedAt: DateTime.now(),
      );
      expect(
        VersionGateEvaluator.isBlocked(
          currentVersionCode: 2026110100,
          policy: policy,
        ),
        isTrue,
      );
      expect(
        VersionGateEvaluator.isBlocked(
          currentVersionCode: 2026120100,
          policy: policy,
        ),
        isFalse,
      );
      expect(
        VersionGateEvaluator.isBlocked(
          currentVersionCode: 2027010100,
          policy: policy,
        ),
        isFalse,
      );
    });

    test(
      'respects 6 hour cache TTL and fails open on network errors',
      () async {
        final now = DateTime(2026, 11, 24, 12);
        final fresh = VersionGatePolicy(
          minVersionCode: 100,
          latestVersion: '0.9.8',
          downloadUrl: '',
          message: '',
          fetchedAt: now.subtract(const Duration(hours: 5, minutes: 59)),
        );
        final stale = VersionGatePolicy(
          minVersionCode: 100,
          latestVersion: '0.9.8',
          downloadUrl: '',
          message: '',
          fetchedAt: now.subtract(const Duration(hours: 6)),
        );
        expect(fresh.isExpired(now: now), isFalse);
        expect(stale.isExpired(now: now), isTrue);

        final roundtrip = VersionGatePolicy.decodeCache(fresh.encodeCache());
        expect(roundtrip?.minVersionCode, 100);
        expect(roundtrip?.latestVersion, '0.9.8');

        final dio = Dio(
          BaseOptions(connectTimeout: const Duration(milliseconds: 50)),
        );
        final failed = await const VersionGateEvaluator().fetchPolicy(
          client: dio,
          url: 'http://127.0.0.1:1/nonexistent.json',
        );
        dio.close();
        expect(failed, isNull);
      },
    );
  });
}
