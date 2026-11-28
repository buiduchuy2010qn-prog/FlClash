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

List<String> get _presetDnsResolvers => system.isDesktop
    ? const [
        '1.1.1.1',
        '8.8.8.8',
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
      ]
    : const [
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
        'tcp://1.1.1.1:53',
        'tcp://8.8.8.8:53',
      ];

List<String> get _presetBootstrapDns => system.isDesktop
    ? const ['1.1.1.1', '8.8.8.8', '223.5.5.5']
    : const ['1.1.1.1', '8.8.8.8', 'system'];

const _presetDirectDns = ['1.1.1.1', '8.8.8.8'];

class Optimize4gPresetNotifier extends _PersistedBoolNotifier {
  static const _presetTunOverrideKeys = {
    TunOverrideKey.strictRoute,
    TunOverrideKey.mtu,
  };
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
              stack: savedClash.tun.stack,
              mtu: savedClash.tun.mtu,
            ),
            tunOverride: savedClash.tunOverride,
            tunOverrideKeys: savedClash.tunOverrideKeys,
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
        if (ref.read(speedBoostPresetProvider)) {
          ref.read(speedBoostPresetProvider.notifier).applySpeedPreset();
        }
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
        tun: state.tun.copyWith(stack: TunStack.mips, mtu: defaultTunMtu),
        tunOverride: state.tunOverride.copyWith(
          strictRoute: false,
          mtu: defaultTunMtu,
        ),
        tunOverrideKeys: {
          for (final key in state.tunOverrideKeys)
            if (!_presetTunOverrideKeys.contains(key)) key,
        },
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
    if (ref.read(speedBoostPresetProvider)) {
      ref.read(speedBoostPresetProvider.notifier).applySpeedPreset();
    }
  }

  void applyMobilePreset() {
    if (_disposed) return;
    final speedBoostOn = ref.read(speedBoostPresetProvider);
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
          stack: TunStack.mixed,
          mtu: (speedBoostOn || system.isDesktop) ? defaultTunMtu : 1400,
        ),
        tunOverride: system.isDesktop
            ? state.tunOverride.copyWith(strictRoute: true, mtu: defaultTunMtu)
            : state.tunOverride,
        tunOverrideKeys: system.isDesktop
            ? {...state.tunOverrideKeys, ..._presetTunOverrideKeys}
            : state.tunOverrideKeys,
        dns: state.dns.copyWith(
          enable: true,
          ipv6: false,
          preferH3: false,
          useHosts: true,
          respectRules: false,
          enhancedMode: DnsMode.fakeIp,
          nameserver: _presetDnsResolvers,
          defaultNameserver: _presetBootstrapDns,
          proxyServerNameserver: _presetBootstrapDns,
          directNameserver: _presetDirectDns,
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
              systemProxy: true,
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

class ExpiryAlertsEnabledNotifier extends _PersistedBoolNotifier {
  @override
  bool get defaultValue => true;

  @override
  Future<bool> readValue() => preferences.getExpiryAlertsEnabled();

  @override
  Future<void> writeValue(bool value) =>
      preferences.setExpiryAlertsEnabled(value);
}

final expiryAlertsEnabledProvider =
    NotifierProvider<ExpiryAlertsEnabledNotifier, bool>(
      ExpiryAlertsEnabledNotifier.new,
    );

class SpeedBoostPresetNotifier extends _PersistedBoolNotifier {
  static const _speedTunOverrideKeys = {TunOverrideKey.mtu};
  static const _speedGeneralOverrideKeys = {
    GeneralOverrideKey.unifiedDelay,
    GeneralOverrideKey.tcpConcurrent,
  };
  static const _speedDnsOverrideKeys = {
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
  Future<bool> readValue() => preferences.getSpeedBoostPreset();

  @override
  Future<void> writeValue(bool value) => preferences.setSpeedBoostPreset(value);

  @override
  void onHydrated(bool saved) {
    if (saved) {
      applySpeedPreset();
    }
  }

  Future<void> enablePreset() async {
    if (await preferences.getSpeedBoostSnapshot() == null) {
      if (_disposed) return;
      final snapshot = json.encode({
        'clash': ref.read(patchClashConfigProvider).toJson(),
        'vpn': ref.read(vpnSettingProvider).toJson(),
        'network': ref.read(networkSettingProvider).toJson(),
      });
      await preferences.setSpeedBoostSnapshot(snapshot);
    }
    if (_disposed) return;
    value = true;
    applySpeedPreset();
  }

  Future<void> disablePresetAndRestore() async {
    value = false;
    final raw = await preferences.getSpeedBoostSnapshot();
    await preferences.setSpeedBoostSnapshot(null);
    if (_disposed) return;
    if (raw != null) {
      try {
        final decoded = json.decode(raw) as Map<String, Object?>;
        final savedClash = PatchClashConfig.fromJson(
          Map<String, Object?>.from(decoded['clash']! as Map),
        );
        final savedNetwork = NetworkProps.fromJson(
          Map<String, Object?>.from(decoded['network']! as Map),
        );
        ref.read(patchClashConfigProvider.notifier).update((state) {
          return state.copyWith(
            ipv6: savedClash.ipv6,
            unifiedDelay: savedClash.unifiedDelay,
            tcpConcurrent: savedClash.tcpConcurrent,
            disableKeepAlive: savedClash.disableKeepAlive,
            keepAliveInterval: savedClash.keepAliveInterval,
            keepAliveIdle: savedClash.keepAliveIdle,
            generalOverrideKeys: savedClash.generalOverrideKeys,
            tun: state.tun.copyWith(
              stack: savedClash.tun.stack,
              mtu: savedClash.tun.mtu,
              congestionController: savedClash.tun.congestionController,
            ),
            tunOverride: savedClash.tunOverride,
            tunOverrideKeys: savedClash.tunOverrideKeys,
            dns: savedClash.dns,
            dnsOverrideKeys: savedClash.dnsOverrideKeys,
          );
        });
        if (decoded['vpn'] case final Map rawVpn when system.isAndroid) {
          final savedVpn = VpnProps.fromJson(Map<String, Object?>.from(rawVpn));
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
            systemProxy: system.isDesktop
                ? savedNetwork.systemProxy
                : state.systemProxy,
          );
        });
        if (ref.read(optimize4gPresetProvider)) {
          ref.read(optimize4gPresetProvider.notifier).applyMobilePreset();
        }
        return;
      } catch (_) {}
    }

    ref.read(patchClashConfigProvider.notifier).update((state) {
      return state.copyWith(
        unifiedDelay: true,
        tcpConcurrent: false,
        disableKeepAlive: false,
        keepAliveInterval: defaultKeepAliveInterval,
        keepAliveIdle: defaultKeepAliveInterval,
        generalOverrideKeys: {
          for (final key in state.generalOverrideKeys)
            if (!_speedGeneralOverrideKeys.contains(key) &&
                key != GeneralOverrideKey.ipv6)
              key,
        },
        tun: state.tun.copyWith(
          stack: TunStack.mips,
          mtu: defaultTunMtu,
          congestionController: defaultCongestionController,
        ),
        tunOverride: state.tunOverride.copyWith(
          strictRoute: false,
          mtu: defaultTunMtu,
          congestionController: defaultCongestionController,
        ),
        tunOverrideKeys: {
          for (final key in state.tunOverrideKeys)
            if (!_speedTunOverrideKeys.contains(key) &&
                key != TunOverrideKey.congestionController &&
                key != TunOverrideKey.mtu &&
                key != TunOverrideKey.strictRoute)
              key,
        },
        dnsOverrideKeys: {
          for (final key in state.dnsOverrideKeys)
            if (!_speedDnsOverrideKeys.contains(key)) key,
        },
      );
    });
    if (!ref.read(optimize4gPresetProvider)) {
      ref.read(networkSettingProvider.notifier).update((state) {
        return state.copyWith(appendSystemDns: true);
      });
    } else {
      ref.read(optimize4gPresetProvider.notifier).applyMobilePreset();
    }
  }

  void applySpeedPreset() {
    if (_disposed) return;
    ref.read(patchClashConfigProvider.notifier).update((state) {
      return state.copyWith(
        ipv6: false,
        unifiedDelay: true,
        // Keep parallel TCP dial disabled to preserve single-device session limit.
        tcpConcurrent: false,
        disableKeepAlive: false,
        keepAliveInterval: 15,
        keepAliveIdle: 15,
        generalOverrideKeys: {
          ...state.generalOverrideKeys,
          ..._speedGeneralOverrideKeys,
          GeneralOverrideKey.ipv6,
        },
        tun: state.tun.copyWith(
          enable: system.isDesktop ? true : state.tun.enable,
          stack: TunStack.mixed,
          congestionController: defaultCongestionController,
          mtu: defaultTunMtu,
        ),
        tunOverride: state.tunOverride.copyWith(
          strictRoute: system.isDesktop ? true : state.tunOverride.strictRoute,
          congestionController: defaultCongestionController,
          mtu: defaultTunMtu,
        ),
        tunOverrideKeys: {
          ...state.tunOverrideKeys,
          ..._speedTunOverrideKeys,
          if (system.isDesktop) TunOverrideKey.strictRoute,
        },
        dns: state.dns.copyWith(
          enable: true,
          ipv6: false,
          preferH3: false,
          useHosts: true,
          respectRules: false,
          enhancedMode: DnsMode.fakeIp,
          nameserver: _presetDnsResolvers,
          defaultNameserver: _presetBootstrapDns,
          proxyServerNameserver: _presetBootstrapDns,
          directNameserver: _presetDirectDns,
        ),
        dnsOverrideKeys: {...state.dnsOverrideKeys, ..._speedDnsOverrideKeys},
      );
    });
    if (system.isAndroid) {
      ref
          .read(vpnSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              enable: true,
              systemProxy: true,
              ipv6: false,
              dnsHijacking: true,
              allowBypass: false,
            ),
          );
    }
    ref
        .read(networkSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            bypassPrivateRoute: true,
            appendSystemDns: false,
            systemProxy: system.isDesktop ? true : state.systemProxy,
          ),
        );
  }
}

final speedBoostPresetProvider =
    NotifierProvider<SpeedBoostPresetNotifier, bool>(
      SpeedBoostPresetNotifier.new,
    );

class PrivacyScreenShieldNotifier extends _PersistedBoolNotifier {
  @override
  Future<bool> readValue() => preferences.getPrivacyScreenShield();

  @override
  Future<void> writeValue(bool value) =>
      preferences.setPrivacyScreenShield(value);

  @override
  void onHydrated(bool saved) {
    if (system.isAndroid) {
      unawaited(app?.setSecureScreen(saved));
    } else if (system.isWindows) {
      windows?.setSecureScreen(saved);
    }
  }

  @override
  set value(bool next) {
    super.value = next;
    if (system.isAndroid) {
      unawaited(app?.setSecureScreen(next));
    } else if (system.isWindows) {
      windows?.setSecureScreen(next);
    }
  }
}

final privacyScreenShieldProvider =
    NotifierProvider<PrivacyScreenShieldNotifier, bool>(
      PrivacyScreenShieldNotifier.new,
    );
