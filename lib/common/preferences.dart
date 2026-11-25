import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Preferences {
  static Preferences? _instance;
  var _store = ResolveOnce(_open);

  Future<bool> get isInit async => await _store.value != null;

  Preferences._internal();

  static Future<SharedPreferences?> _open() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  Future<void> rebind() async {
    _store = ResolveOnce(_open);
    await _store.value;
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Future<int> getVersion() async {
    final preferences = await _store.value;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) async {
    final preferences = await _store.value;
    await preferences?.setInt('version', version);
  }

  Future<int> getUpgradeVersion() async {
    final preferences = await _store.value;
    return preferences?.getInt('upgradeVersion') ?? 0;
  }

  Future<void> setUpgradeVersion(int version) async {
    final preferences = await _store.value;
    await preferences?.setInt('upgradeVersion', version);
  }

  static const _autoFailoverKey = 'smart_auto_failover';
  static const _autoVpnOnCellularKey = 'auto_vpn_on_cellular';
  static const _autoVpnOffWifiKey = 'auto_vpn_off_wifi';
  static const _autoStartOnBootKey = 'auto_start_on_boot';
  static const _rootHotspotShareKey = 'root_hotspot_share';
  static const _optimize4gPresetKey = 'optimize_4g_preset';
  static const _optimize4gSnapshotKey = 'optimize_4g_snapshot_v1';
  static const _privacyScreenShieldKey = 'privacy_screen_shield';
  static const _dailyTrafficEnabledKey = 'daily_traffic_enabled';
  static const _dailyTrafficHistoryKey = 'daily_traffic_history_v1';
  static const _versionGateCacheKey = 'version_gate_cache_v1';

  Future<bool> _getBool(String key, bool fallback) async {
    final preferences = await _store.value;
    return preferences?.getBool(key) ?? fallback;
  }

  Future<void> _setBool(String key, bool value) async {
    final preferences = await _store.value;
    await preferences?.setBool(key, value);
  }

  Future<String?> _getString(String key) async {
    final preferences = await _store.value;
    return preferences?.getString(key);
  }

  Future<void> _setString(String key, String? value) async {
    final preferences = await _store.value;
    if (value == null) {
      await preferences?.remove(key);
    } else {
      await preferences?.setString(key, value);
    }
  }

  Future<bool> getAutoFailover() => _getBool(_autoFailoverKey, true);

  Future<void> setAutoFailover(bool value) => _setBool(_autoFailoverKey, value);

  Future<bool> getAutoVpnOnCellular() => _getBool(_autoVpnOnCellularKey, false);

  Future<void> setAutoVpnOnCellular(bool value) =>
      _setBool(_autoVpnOnCellularKey, value);

  Future<bool> getAutoVpnOffWifi() => _getBool(_autoVpnOffWifiKey, false);

  Future<void> setAutoVpnOffWifi(bool value) =>
      _setBool(_autoVpnOffWifiKey, value);

  Future<bool> getAutoStartOnBoot() => _getBool(_autoStartOnBootKey, false);

  Future<void> setAutoStartOnBoot(bool value) =>
      _setBool(_autoStartOnBootKey, value);

  Future<bool> getRootHotspotShare() => _getBool(_rootHotspotShareKey, false);

  Future<void> setRootHotspotShare(bool value) =>
      _setBool(_rootHotspotShareKey, value);

  Future<bool> getOptimize4gPreset() => _getBool(_optimize4gPresetKey, false);

  Future<void> setOptimize4gPreset(bool value) =>
      _setBool(_optimize4gPresetKey, value);

  Future<String?> getOptimize4gSnapshot() => _getString(_optimize4gSnapshotKey);

  Future<void> setOptimize4gSnapshot(String? value) =>
      _setString(_optimize4gSnapshotKey, value);

  Future<bool> getPrivacyScreenShield() =>
      _getBool(_privacyScreenShieldKey, false);

  Future<void> setPrivacyScreenShield(bool value) =>
      _setBool(_privacyScreenShieldKey, value);

  Future<bool> getDailyTrafficEnabled() =>
      _getBool(_dailyTrafficEnabledKey, true);

  Future<void> setDailyTrafficEnabled(bool value) =>
      _setBool(_dailyTrafficEnabledKey, value);

  Future<String?> getDailyTrafficHistory() =>
      _getString(_dailyTrafficHistoryKey);

  Future<void> setDailyTrafficHistory(String? value) =>
      _setString(_dailyTrafficHistoryKey, value);

  Future<String?> getVersionGateCache() => _getString(_versionGateCacheKey);

  Future<void> setVersionGateCache(String? value) =>
      _setString(_versionGateCacheKey, value);

  Future<void> saveShareState(SharedState shareState) async {
    final preferences = await _store.value;
    await preferences?.setString('sharedState', json.encode(shareState));
  }

  /// The md5 of the config.yaml the Core last accepted, which is also what
  /// the Android service applies when it starts without Flutter.
  Future<String?> getAppliedConfigMd5() async {
    final preferences = await _store.value;
    return preferences?.getString(appliedConfigMd5Key);
  }

  Future<void> saveAppliedConfigMd5(String? md5) async {
    final preferences = await _store.value;
    if (md5 == null) {
      await preferences?.remove(appliedConfigMd5Key);
    } else {
      await preferences?.setString(appliedConfigMd5Key, md5);
    }
  }

  Future<Map<String, Object?>?> getConfigMap() async {
    try {
      final preferences = await _store.value;
      final configString = preferences?.getString(configKey);
      if (configString == null) return null;
      final Map<String, Object?>? configMap = json.decode(configString);
      return configMap;
    } catch (e) {
      commonPrint.log(
        'getConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<Map<String, Object?>?> getClashConfigMap() async {
    try {
      final preferences = await _store.value;
      final clashConfigString = preferences?.getString(clashConfigKey);
      if (clashConfigString == null) return null;
      return json.decode(clashConfigString);
    } catch (e) {
      commonPrint.log(
        'getClashConfigMap error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> clearClashConfig() async {
    try {
      final preferences = await _store.value;
      await preferences?.remove(clashConfigKey);
      return;
    } catch (e) {
      commonPrint.log(
        'clearClashConfig error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return;
    }
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) {
      return null;
    }
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    final preferences = await _store.value;
    return preferences?.setString(configKey, json.encode(config)) ?? false;
  }

  Future<SystemDnsRecord?> getSystemDnsRecord() async {
    try {
      final sharedPreferencesIns = await _store.value;
      final raw = sharedPreferencesIns?.getString(systemDnsRecordKey);
      if (raw == null) {
        return null;
      }
      return SystemDnsRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getSystemDnsRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> clearSystemDnsRecord() async {
    final sharedPreferencesIns = await _store.value;
    await sharedPreferencesIns?.remove(systemDnsRecordKey);
  }

  Future<BootRecord?> getBootRecord() async {
    try {
      final sharedPreferencesIns = await _store.value;
      final raw = sharedPreferencesIns?.getString(bootRecordKey);
      if (raw == null) {
        return null;
      }
      return BootRecord.fromJson(json.decode(raw));
    } catch (e) {
      commonPrint.log(
        'getBootRecord error ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveBootRecord(BootRecord record) async {
    final sharedPreferencesIns = await _store.value;
    await sharedPreferencesIns?.setString(bootRecordKey, json.encode(record));
  }

  Future<void> clearPreferences() async {
    final sharedPreferencesIns = await _store.value;
    await sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
