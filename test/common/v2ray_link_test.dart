import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/link.dart';
import 'package:fl_clash/common/protocol.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Uri> links;
  late List<String> received;

  setUp(() {
    links = StreamController<Uri>.broadcast();
    received = [];
    linkManager.uriLinkStream = () => links.stream;
  });

  tearDown(() async {
    linkManager.destroy();
    await links.close();
  });

  test('parseProfileTitleHeader decodes base64 and plain headers', () {
    final encoded = base64Url
        .encode(utf8.encode('Cấu hình di động'))
        .replaceAll('=', '');
    expect(parseProfileTitleHeader('base64:$encoded'), 'Cấu hình di động');
    expect(parseProfileTitleHeader('  BASE64:RVhBTVBMRQ== '), 'EXAMPLE');
    expect(parseProfileTitleHeader('Plain Label'), 'Plain Label');
    expect(parseProfileTitleHeader('   '), isNull);
    expect(parseProfileTitleHeader(null), isNull);
    expect(parseProfileTitleHeader('base64:'), isNull);
    expect(parseProfileTitleHeader('base64:!!!invalid!!!'), isNull);
  });

  test('protocol and share link schemes support v2rayng and compat links', () {
    expect(protocolSchemes, contains('v2rayng'));
    expect(
      shareLinkSchemes,
      containsAll(['wireguard', 'wg', 'socks4', 'socks4a', 'v2rayn']),
    );
  });

  test('linkManager accepts v2rayng install-sub and install-config', () async {
    await linkManager.initAppLinksListen(received.add);

    links.add(
      Uri.parse('v2rayng://install-sub?url=https://example.com/sub.txt'),
    );
    links.add(
      Uri.parse('v2rayng://install-config?url=https://example.com/cfg.yaml'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, [
      'https://example.com/sub.txt',
      'https://example.com/cfg.yaml',
    ]);
  });
}
