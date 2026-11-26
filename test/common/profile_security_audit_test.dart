import 'package:fl_clash/common/profile_security_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profile_security_audit', () {
    test('reports clean TLS/Reality profile as 100/100 safe', () {
      const yaml = '''
allow-lan: false
external-controller: 127.0.0.1:9090
secret: strong-random-secret
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query
proxies:
  - name: SG-TLS
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    tls: true
    reality-opts:
      public-key: abcdef
  - name: JP-Trojan
    type: trojan
    server: jp.example.com
    port: 443
    password: secret
    sni: jp.example.com
rules:
  - IP-CIDR,192.168.0.0/16,DIRECT
  - MATCH,Proxy
''';
      final report = auditProfileSecurity(
        rawYaml: yaml,
        subscriptionUrl:
            'https://panel.example.com/api/v1/client/subscribe?token=abc',
      );
      expect(report.score, 100);
      expect(report.level, ProfileRiskLevel.safe);
      expect(report.isDangerous, isFalse);
      expect(report.scannedProxies, 2);
      expect(report.scannedRules, 2);
      expect(report.findings, isEmpty);
    });

    test(
      'detects MITM, exposed controller, hosts hijack, plaintext, and skip-verify',
      () {
        const yaml = '''
allow-lan: true
external-controller: 0.0.0.0:9090
mitm:
  enable: true
  decrypt-untrusted: true
hosts:
  ibanking.vietcombank.com.vn: 203.0.113.99
  accounts.google.com: 198.51.100.42
dns:
  enable: true
  nameserver:
    - 203.0.113.55
proxy-providers:
  extra:
    type: http
    url: http://untrusted.example.com/sub.yaml
proxies:
  - name: Plain-HTTP
    type: http
    server: 198.51.100.10
    port: 8080
  - name: Weak-SS
    type: ss
    server: 198.51.100.11
    port: 8388
    cipher: none
    password: pw
  - name: Unverified-Trojan
    type: trojan
    server: bad.example.com
    port: 443
    password: pw
    skip-cert-verify: true
rules:
  - IP-CIDR,192.168.1.0/24,Proxy
  - MATCH,Proxy
''';
        final report = auditProfileSecurity(
          rawYaml: yaml,
          subscriptionUrl: 'http://sub.example.com/get',
        );
        expect(report.level, ProfileRiskLevel.danger);
        expect(report.isDangerous, isTrue);
        expect(report.canAutoHarden, isTrue);
        expect(report.score, lessThan(40));
        final codes = {for (final f in report.findings) f.code};
        expect(
          codes,
          containsAll([
            SecurityFindingCode.mitmEnabled,
            SecurityFindingCode.externalControllerExposed,
            SecurityFindingCode.sensitiveHostsHijack,
            SecurityFindingCode.plaintextNodes,
            SecurityFindingCode.skipCertVerifyNodes,
            SecurityFindingCode.insecureSubscriptionUrl,
            SecurityFindingCode.insecureProviderUrls,
            SecurityFindingCode.allowLanForced,
            SecurityFindingCode.privateLanRoutedToProxy,
            SecurityFindingCode.unencryptedCustomDns,
          ]),
        );
      },
    );

    test('treats localhost HTTP subscription without false alarm', () {
      final report = auditProfileSecurity(
        rawYaml: '',
        subscriptionUrl: 'http://127.0.0.1:8080/sub.yaml',
      );
      expect(report.findings, isEmpty);
      expect(report.level, ProfileRiskLevel.safe);
    });
  });
}
