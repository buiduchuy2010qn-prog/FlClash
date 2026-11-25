import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/package.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/common/release_asset.dart';
import 'package:fl_clash/common/request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/preferences.dart';

class _StalledHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  String Function(Uri url)? findProxy;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;
}

class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.byHost);

  final Map<String, ResponseBody Function()> byHost;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return byHost[options.uri.host]!();
  }

  @override
  void close({bool force = false}) {}
}

class _PathAdapter implements HttpClientAdapter {
  _PathAdapter(this.byPath);

  final Map<String, ResponseBody Function()> byPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final answer = byPath[options.uri.path];
    return answer == null ? ResponseBody.fromString('', 404) : answer();
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  group('latestRelease', () {
    Request requestAnswering(Map<String, ResponseBody Function()> byHost) {
      return Request()..dio.httpClientAdapter = _HostAdapter(byHost);
    }

    test('reads the release from the API', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString(
          '{"tag_name":"v1.2.3","body":"notes"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      });

      expect(await request.latestRelease(), {
        'tag_name': 'v1.2.3',
        'body': 'notes',
      });
    });

    test(
      'falls back to the release page when the API is rate limited',
      () async {
        final request = requestAnswering({
          'api.github.com': () => ResponseBody.fromString('{}', 403),
          'github.com': () => ResponseBody.fromString(
            '',
            302,
            headers: {
              HttpHeaders.locationHeader: [
                'https://github.com/owner/repo/releases/tag/v1.2.4',
              ],
            },
          ),
        });

        expect(await request.latestRelease(), {'tag_name': 'v1.2.4'});
      },
    );

    test('fails instead of answering when neither endpoint does', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString('{}', 403),
        'github.com': () => ResponseBody.fromString('', 503),
      });

      await expectLater(request.latestRelease(), throwsA(isA<DioException>()));
    });
  });

  group('downloadVerifiedRelease', () {
    final name = releaseAssetName(
      version: '1.2.3',
      os: ReleaseOs.android,
      arch: ReleaseArch.arm64,
      extension: 'apk',
    );
    final package = utf8.encode('package');
    final digest = sha256.convert(package).toString();
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('release');
    });

    tearDown(() => directory.delete(recursive: true));

    const release = '/$repository/releases/download/v1.2.3';
    final sumsPath = '$release/${updateChecksumsName('v1.2.3')}';

    Request requestAt(Map<String, ResponseBody Function()> byPath) {
      return Request()..releaseDio.httpClientAdapter = _PathAdapter(byPath);
    }

    Request requestServing(String sums, List<int> asset) {
      return requestAt({
        sumsPath: () => ResponseBody.fromString(sums, 200),
        '$release/$name': () => ResponseBody.fromBytes(asset, 200),
      });
    }

    Future<String> download(Request request) {
      return request.downloadVerifiedRelease(
        tag: 'v1.2.3',
        name: name,
        directory: directory.path,
      );
    }

    test('keeps a file matching the published digest', () async {
      final request = requestServing('$digest  $name\n', package);

      final path = await download(request);

      expect(await File(path).readAsBytes(), package);
    });

    test('refuses a file that does not match', () async {
      final request = requestServing('$digest  $name\n', utf8.encode('x'));

      await expectLater(
        download(request),
        throwsA(isA<ReleaseNotVerifiedException>()),
      );
    });

    test('reports an asset the listing does not name as missing', () async {
      final request = requestServing('$digest  other.apk\n', package);

      await expectLater(
        download(request),
        throwsA(isA<ReleaseFileMissingException>()),
      );
      expect(directory.listSync(), isEmpty);
    });

    test('reports a checksum file the release lacks as missing', () async {
      final request = requestAt({});

      await expectLater(
        download(request),
        throwsA(isA<ReleaseFileMissingException>()),
      );
    });

    test('reports an asset the release lacks as missing', () async {
      final request = requestAt({
        sumsPath: () => ResponseBody.fromString('$digest  $name\n', 200),
      });

      await expectLater(
        download(request),
        throwsA(
          isA<ReleaseFileMissingException>().having(
            (error) => error.name,
            'name',
            name,
          ),
        ),
      );
    });

    test('leaves any other failure as it was', () async {
      final request = requestAt({
        sumsPath: () => ResponseBody.fromString('', 503),
      });

      await expectLater(download(request), throwsA(isA<DioException>()));
    });

    test('reuses verified installer already on disk', () async {
      await File('${directory.path}/$name').writeAsBytes(package);
      var downloaded = false;
      final request = requestAt({
        sumsPath: () => ResponseBody.fromString('$digest  $name\n', 200),
        '$release/$name': () {
          downloaded = true;
          return ResponseBody.fromBytes(package, 200);
        },
      });

      final path = await download(request);

      expect(downloaded, isFalse);
      expect(await File(path).readAsBytes(), package);
    });
  });

  group('downloadTarget', () {
    test('sends a URL without credentials unchanged', () {
      final target = downloadTarget('https://example.com/a.yaml?x=1');

      expect(target.uri.toString(), 'https://example.com/a.yaml?x=1');
      expect(target.headers, isEmpty);
    });

    test('moves decoded credentials into the Authorization header', () {
      for (final url in [
        'https://me@mail.com:p:w@dav.example.com/dav/a.yaml',
        'https://me%40mail.com:p%3Aw@dav.example.com/dav/a.yaml',
      ]) {
        final target = downloadTarget(url);

        expect(target.uri.toString(), 'https://dav.example.com/dav/a.yaml');
        expect(
          target.headers[HttpHeaders.authorizationHeader],
          'Basic ${base64.encode(utf8.encode('me@mail.com:p:w'))}',
        );
      }
    });
  });

  group('decompressUnlabeled', () {
    final yaml = utf8.encode('proxies: []\n');

    test('inflates a gzip or zlib body that arrived unlabeled', () {
      for (final codec in [gzip, zlib]) {
        final body = Uint8List.fromList(codec.encode(yaml));

        expect(decompressUnlabeled(body), yaml);
      }
    });

    test('leaves a plain body untouched', () {
      final body = Uint8List.fromList(yaml);

      expect(decompressUnlabeled(body), same(body));
    });

    test('keeps a body that only starts like gzip', () {
      final body = Uint8List.fromList([0x1f, 0x8b, 1, 2, 3]);

      expect(decompressUnlabeled(body), same(body));
    });
  });

  testWidgets('a stalled download fails at the shared download deadline', (
    tester,
  ) async {
    late final Future<Response<String>> pending;
    HttpOverrides.runZoned(() {
      pending = Request().getTextResponseForUrl('http://127.0.0.1/stalled');
    }, createHttpClient: (_) => _StalledHttpClient());
    var settled = false;
    final outcome = expectLater(
      pending.whenComplete(() => settled = true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    await tester.pump(downloadTimeoutDuration - const Duration(seconds: 1));
    expect(settled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await outcome;
  });

  group('subscription device identity and routing', () {
    test(
      'getOrCreateDeviceHwid returns stable 32-hex ID across reloads',
      () async {
        await mockPreferences();
        final first = await preferences.getOrCreateDeviceHwid();
        expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));

        await preferences.rebind();
        final second = await preferences.getOrCreateDeviceHwid();
        expect(second, first);
      },
    );

    test('PackageInfoExtension.ua stays stable across patch releases', () {
      PackageInfo buildInfo(String ver) => PackageInfo(
        appName: appName,
        packageName: packageName,
        version: ver,
        buildNumber: '1',
      );
      final ua17 = buildInfo('0.9.17').ua;
      final ua18 = buildInfo('0.9.18').ua;
      final ua19 = buildInfo('0.9.19').ua;
      expect(
        ua17,
        '$appName/v0.9 clash-verge Platform/${Platform.operatingSystem}',
      );
      expect(ua18, ua17);
      expect(ua19, ua17);
    });

    test(
      'getSubscriptionResponseForUrl uses directDio first and falls back to clashDio on network failure',
      () async {
        await mockPreferences();
        final req = Request();
        final capturedDirect = <Map<String, dynamic>>[];
        final capturedClash = <Map<String, dynamic>>[];

        req.directDio.httpClientAdapter = _CaptureAdapter((options) {
          capturedDirect.add(Map<String, dynamic>.from(options.headers));
          return ResponseBody.fromString('proxies: []', 200);
        });
        req.clashDio.httpClientAdapter = _CaptureAdapter((options) {
          capturedClash.add(Map<String, dynamic>.from(options.headers));
          return ResponseBody.fromString('proxies: []', 200);
        });

        final directRes = await req.getSubscriptionResponseForUrl(
          'https://sub.example.com/profile',
          hwid: '0123456789abcdef0123456789abcdef',
        );
        expect(utf8.decode(directRes.data!), 'proxies: []');
        expect(capturedDirect, hasLength(1));
        expect(capturedClash, isEmpty);
        expect(
          capturedDirect.single['x-hwid'],
          '0123456789abcdef0123456789abcdef',
        );
        expect(capturedDirect.single['x-device-os'], Platform.operatingSystem);

        req.allowProxyFallbackForTesting = true;
        req.directDio.httpClientAdapter = _FailingAdapter(
          DioExceptionType.connectionTimeout,
        );
        final fallbackRes = await req.getSubscriptionResponseForUrl(
          'https://sub.example.com/profile',
          hwid: '0123456789abcdef0123456789abcdef',
        );
        expect(utf8.decode(fallbackRes.data!), 'proxies: []');
        expect(capturedClash, hasLength(1));
        expect(
          capturedClash.single['x-hwid'],
          '0123456789abcdef0123456789abcdef',
        );
        expect(capturedClash.single['x-device-os'], Platform.operatingSystem);

        final releaseHeaders = <Map<String, dynamic>>[];
        req.dio.httpClientAdapter = _CaptureAdapter((options) {
          releaseHeaders.add(Map<String, dynamic>.from(options.headers));
          return ResponseBody.fromString(
            '{"tag_name":"v1.0.0"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
        await req.latestRelease();
        expect(releaseHeaders.single.containsKey('x-hwid'), isFalse);
        expect(releaseHeaders.single.containsKey('x-device-os'), isFalse);
      },
    );
  });
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.onFetch);

  final ResponseBody Function(RequestOptions options) onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return onFetch(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FailingAdapter implements HttpClientAdapter {
  _FailingAdapter(this.type);

  final DioExceptionType type;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, type: type);
  }

  @override
  void close({bool force = false}) {}
}
