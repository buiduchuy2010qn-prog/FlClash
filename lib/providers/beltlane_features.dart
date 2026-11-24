import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class _PersistedBoolNotifier extends Notifier<bool> {
  var _disposed = false;

  bool get defaultValue => false;
  bool get syncAndroidAutoVpn => false;

  Future<bool> readValue();
  Future<void> writeValue(bool value);

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(_hydrate());
    return defaultValue;
  }

  Future<void> _hydrate() async {
    final saved = await readValue();
    if (_disposed) return;
    state = saved;
    if (syncAndroidAutoVpn) {
      _pushAutoVpnSettings();
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
  @override
  Future<bool> readValue() => preferences.getOptimize4gPreset();

  @override
  Future<void> writeValue(bool value) => preferences.setOptimize4gPreset(value);
}

final optimize4gPresetProvider =
    NotifierProvider<Optimize4gPresetNotifier, bool>(
      Optimize4gPresetNotifier.new,
    );
