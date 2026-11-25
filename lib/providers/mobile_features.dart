import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class _PersistedBoolNotifier extends Notifier<bool> {
  var _disposed = false;
  Completer<bool>? _hydratedCompleter;

  bool get defaultValue => false;
  bool get syncAndroidAutoVpn => false;

  Future<bool> readValue();
  Future<void> writeValue(bool value);
  void onHydrated(bool saved) {}

  Future<bool> ensureHydrated() =>
      _hydratedCompleter?.future ?? Future<bool>.value(state);

  @override
  bool build() {
    _disposed = false;
    final completer = Completer<bool>();
    _hydratedCompleter = completer;
    ref.onDispose(() {
      _disposed = true;
      if (!completer.isCompleted) {
        completer.complete(defaultValue);
      }
    });
    unawaited(_hydrate(completer));
    return defaultValue;
  }

  Future<void> _hydrate(Completer<bool> completer) async {
    var result = defaultValue;
    try {
      final saved = await readValue();
      if (_disposed) return;
      state = saved;
      result = saved;
      onHydrated(saved);
      if (syncAndroidAutoVpn) {
        _pushAutoVpnSettings();
      }
    } catch (_) {
    } finally {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }
  }

  bool get value => state;

  set value(bool next) {
    if (state == next) return;
    state = next;
    unawaited(writeValue(next));
    if (syncAndroidAutoVpn) {
      _pushAutoVpnSettings();
    }
  }

  void _pushAutoVpnSettings() {
    unawaited(
      app?.syncAutoVpnSettings(
        onCellular: ref.read(autoVpnOnCellularProvider),
        offWifi: ref.read(autoVpnOffWifiProvider),
        startOnBoot: ref.read(autoStartOnBootProvider),
      ),
    );
  }
}

class AutoVpnOnCellularNotifier extends _PersistedBoolNotifier {
  @override
  bool get syncAndroidAutoVpn => true;

  @override
  Future<bool> readValue() => preferences.getAutoVpnOnCellular();

  @override
  Future<void> writeValue(bool value) =>
      preferences.setAutoVpnOnCellular(value);
}

final autoVpnOnCellularProvider =
    NotifierProvider<AutoVpnOnCellularNotifier, bool>(
      AutoVpnOnCellularNotifier.new,
    );

class AutoVpnOffWifiNotifier extends _PersistedBoolNotifier {
  @override
  bool get syncAndroidAutoVpn => true;

  @override
  Future<bool> readValue() => preferences.getAutoVpnOffWifi();

  @override
  Future<void> writeValue(bool value) => preferences.setAutoVpnOffWifi(value);
}

final autoVpnOffWifiProvider = NotifierProvider<AutoVpnOffWifiNotifier, bool>(
  AutoVpnOffWifiNotifier.new,
);

class AutoStartOnBootNotifier extends _PersistedBoolNotifier {
  @override
  bool get syncAndroidAutoVpn => true;

  @override
  Future<bool> readValue() => preferences.getAutoStartOnBoot();

  @override
  Future<void> writeValue(bool value) => preferences.setAutoStartOnBoot(value);
}

final autoStartOnBootProvider = NotifierProvider<AutoStartOnBootNotifier, bool>(
  AutoStartOnBootNotifier.new,
);

class RootHotspotShareNotifier extends _PersistedBoolNotifier {
  @override
  Future<bool> readValue() => preferences.getRootHotspotShare();

  @override
  Future<void> writeValue(bool value) => preferences.setRootHotspotShare(value);
}

final rootHotspotShareProvider =
    NotifierProvider<RootHotspotShareNotifier, bool>(
      RootHotspotShareNotifier.new,
    );

class Optimize4gPresetNotifier extends _PersistedBoolNotifier {
  static const _presetDnsOverrideKeys = {
    DnsOverrideKey.enable,
    DnsOverrideKey.ipv6,
    DnsOverrideKey.preferH3,
    DnsOverrideKey.useHosts,
    DnsOverrideKey.respectRules,
    DnsOverrideKey.enhancedMode,
    DnsOverrideKey.nameserver,
    DnsOverrideKey.defaultNameserver,
    DnsOverrideKey.proxyServerNameserver,
    DnsOverrideKey.directNameserver,
  };

  @override
  Future<bool> readValue() => preferences.getOptimize4gPreset();

  @override
  Future<void> writeValue(bool value) => preferences.setOptimize4gPreset(value);

  @override
  void onHydrated(bool saved) {
    if (saved) {
      applyMobilePreset();
    }
  }

  Future<void> enablePreset() async {
    if (await preferences.getOptimize4gSnapshot() == null) {
      if (_disposed) return;
      final snapshot = json.encode({
        'clash': ref.read(patchClashConfigProvider).toJson(),
        'vpn': ref.read(vpnSettingProvider).toJson(),
        'network': ref.read(networkSettingProvider).toJson(),
      });
      await preferences.setOptimize4gSnapshot(snapshot);
    }
    if (_disposed) return;
    value = true;
    applyMobilePreset();
  }

  Future<void> disablePresetAndRestore() async {
    value = false;
    final raw = await preferences.getOptimize4gSnapshot();
    await preferences.setOptimize4gSnapshot(null);
    if (_disposed) return;
    if (raw != null) {
      try {
        final decoded = json.decode(raw) as Map<String, Object?>;
        final savedClash = PatchClashConfig.fromJson(
          Map<String, Object?>.from(decoded['clash']! as Map),
        );
        final savedVpn = VpnProps.fromJson(
          Map<String, Object?>.from(decoded['vpn']! as Map),
        );
        final savedNetwork = NetworkProps.fromJson(
          Map<String, Object?>.from(decoded['network']! as Map),
        );
        ref.read(patchClashConfigProvider.notifier).update((state) {
          return state.copyWith(
            mode: savedClash.mode,
            ipv6: savedClash.ipv6,
            generalOverrideKeys: savedClash.generalOverrideKeys,
            tun: state.tun.copyWith(
              enable: savedClash.tun.enable,
              mtu: savedClash.tun.mtu,
            ),
            dns: savedClash.dns,
            dnsOverrideKeys: savedClash.dnsOverrideKeys,
          );
        });
        if (system.isAndroid) {
          ref.read(vpnSettingProvider.notifier).update((state) {
            return state.copyWith(
              enable: savedVpn.enable,
              systemProxy: savedVpn.systemProxy,
              ipv6: savedVpn.ipv6,
              dnsHijacking: savedVpn.dnsHijacking,
              allowBypass: savedVpn.allowBypass,
            );
          });
        }
        ref.read(networkSettingProvider.notifier).update((state) {
          return state.copyWith(
            bypassPrivateRoute: savedNetwork.bypassPrivateRoute,
            appendSystemDns: savedNetwork.appendSystemDns,
          );
        });
        return;
      } catch (_) {}
    }

    ref.read(patchClashConfigProvider.notifier).update((state) {
      return state.copyWith(
        mode: Mode.rule,
        generalOverrideKeys: {
          for (final key in state.generalOverrideKeys)
            if (key != GeneralOverrideKey.ipv6) key,
        },
        tun: state.tun.copyWith(mtu: defaultTunMtu),
        dnsOverrideKeys: {
          for (final key in state.dnsOverrideKeys)
            if (!_presetDnsOverrideKeys.contains(key)) key,
        },
      );
    });
    if (system.isAndroid) {
      ref.read(vpnSettingProvider.notifier).update((state) {
        return state.copyWith(dnsHijacking: false, allowBypass: true);
      });
    }
    ref.read(networkSettingProvider.notifier).update((state) {
      return state.copyWith(appendSystemDns: true);
    });
  }

  void applyMobilePreset() {
    if (_disposed) return;
    const dnsResolvers = [
      'https://1.1.1.1/dns-query',
      'https://8.8.8.8/dns-query',
      'tcp://1.1.1.1:53',
      'tcp://8.8.8.8:53',
    ];
    const systemBootstrap = ['system'];
    ref.read(patchClashConfigProvider.notifier).update((state) {
      return state.copyWith(
        mode: Mode.global,
        ipv6: false,
        generalOverrideKeys: {
          ...state.generalOverrideKeys,
          GeneralOverrideKey.ipv6,
        },
        tun: state.tun.copyWith(
          enable: system.isDesktop ? true : state.tun.enable,
          mtu: 1400,
        ),
        dns: state.dns.copyWith(
          enable: true,
          ipv6: false,
          preferH3: false,
          useHosts: true,
          respectRules: true,
          enhancedMode: DnsMode.fakeIp,
          nameserver: dnsResolvers,
          defaultNameserver: systemBootstrap,
          proxyServerNameserver: systemBootstrap,
          directNameserver: systemBootstrap,
        ),
        dnsOverrideKeys: {...state.dnsOverrideKeys, ..._presetDnsOverrideKeys},
      );
    });
    if (system.isAndroid) {
      ref
          .read(vpnSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              enable: true,
              systemProxy: false,
              ipv6: false,
              dnsHijacking: true,
              allowBypass: false,
            ),
          );
    }
    ref
        .read(networkSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(bypassPrivateRoute: true, appendSystemDns: false),
        );
  }
}

final optimize4gPresetProvider =
    NotifierProvider<Optimize4gPresetNotifier, bool>(
      Optimize4gPresetNotifier.new,
    );
