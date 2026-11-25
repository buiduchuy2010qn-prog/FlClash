import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/daily_traffic.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SubscriptionInsightsNotifier
    extends Notifier<SubscriptionInsightsLedger> {
  var _disposed = false;
  var _hydrated = false;
  final Map<int, SubscriptionDeviceMeta> _pendingWrites = {};
  final Set<int> _pendingRemovals = {};

  @override
  SubscriptionInsightsLedger build() {
    _disposed = false;
    _hydrated = false;
    _pendingWrites.clear();
    _pendingRemovals.clear();
    ref.onDispose(() => _disposed = true);
    unawaited(_hydrate());
    return const SubscriptionInsightsLedger();
  }

  Future<void> _hydrate() async {
    final raw = await preferences.getSubscriptionInsights();
    if (_disposed) return;
    var ledger = SubscriptionInsightsLedger.decode(raw);
    for (final id in _pendingRemovals) {
      ledger = ledger.withoutEntry(id);
    }
    for (final entry in _pendingWrites.entries) {
      ledger = ledger.withEntry(entry.key, entry.value);
    }
    final hadPending = _pendingRemovals.isNotEmpty || _pendingWrites.isNotEmpty;
    _pendingRemovals.clear();
    _pendingWrites.clear();
    _hydrated = true;
    state = ledger;
    if (hadPending) {
      unawaited(preferences.setSubscriptionInsights(ledger.encode()));
    }
  }

  void setMeta(int profileId, SubscriptionDeviceMeta meta) {
    final existing = state[profileId];
    final merged = existing != null && meta.portalUrl == null
        ? meta.withPortalUrl(existing.portalUrl)
        : meta;
    final next = state.withEntry(profileId, merged);
    state = next;
    if (!_hydrated) {
      _pendingRemovals.remove(profileId);
      _pendingWrites[profileId] = merged;
      return;
    }
    unawaited(preferences.setSubscriptionInsights(next.encode()));
  }

  void remove(int profileId) {
    final next = state.withoutEntry(profileId);
    state = next;
    if (!_hydrated) {
      _pendingWrites.remove(profileId);
      _pendingRemovals.add(profileId);
      return;
    }
    unawaited(preferences.setSubscriptionInsights(next.encode()));
  }

  void clearPortalMeta(int profileId) {
    final existing = state[profileId];
    if (existing != null && existing.source == DeviceMetaSource.portal) {
      remove(profileId);
    }
  }
}

final subscriptionInsightsProvider =
    NotifierProvider<SubscriptionInsightsNotifier, SubscriptionInsightsLedger>(
      SubscriptionInsightsNotifier.new,
    );

class PortalAccountsNotifier extends Notifier<PortalAccountsLedger> {
  var _disposed = false;
  var _hydrated = false;
  final Map<int, PortalAccountBinding> _pendingWrites = {};
  final Set<int> _pendingRemovals = {};

  @override
  PortalAccountsLedger build() {
    _disposed = false;
    _hydrated = false;
    _pendingWrites.clear();
    _pendingRemovals.clear();
    ref.onDispose(() => _disposed = true);
    unawaited(_hydrate());
    return const PortalAccountsLedger();
  }

  Future<void> _hydrate() async {
    final raw = await preferences.getPortalAccounts();
    if (_disposed) return;
    var ledger = PortalAccountsLedger.decode(raw);
    for (final id in _pendingRemovals) {
      ledger = ledger.withoutEntry(id);
    }
    for (final entry in _pendingWrites.entries) {
      ledger = ledger.withEntry(entry.key, entry.value);
    }
    final hadPending = _pendingRemovals.isNotEmpty || _pendingWrites.isNotEmpty;
    _pendingRemovals.clear();
    _pendingWrites.clear();
    _hydrated = true;
    state = ledger;
    if (hadPending) {
      unawaited(preferences.setPortalAccounts(ledger.encode()));
    }
  }

  void setBinding(int profileId, PortalAccountBinding binding) {
    final next = state.withEntry(profileId, binding);
    state = next;
    if (!_hydrated) {
      _pendingRemovals.remove(profileId);
      _pendingWrites[profileId] = binding;
      return;
    }
    unawaited(preferences.setPortalAccounts(next.encode()));
  }

  void remove(int profileId) {
    final next = state.withoutEntry(profileId);
    state = next;
    if (!_hydrated) {
      _pendingWrites.remove(profileId);
      _pendingRemovals.add(profileId);
      return;
    }
    unawaited(preferences.setPortalAccounts(next.encode()));
  }
}

final portalAccountsProvider =
    NotifierProvider<PortalAccountsNotifier, PortalAccountsLedger>(
      PortalAccountsNotifier.new,
    );

final effectiveProfileDeviceMetaProvider =
    Provider.family<SubscriptionDeviceMeta?, int>((ref, profileId) {
      final stored = ref.watch(
        subscriptionInsightsProvider.select((s) => s[profileId]),
      );
      if (stored != null && stored.hasCounts) {
        return stored;
      }
      final currentId = ref.watch(currentProfileIdProvider);
      if (currentId != profileId) {
        return stored;
      }
      final groups = ref.watch(groupsProvider);
      if (groups.isEmpty) {
        return stored;
      }
      final names = <String>[
        for (final group in groups)
          for (final proxy in group.all) proxy.name,
      ];
      final fromLive = parseDeviceMetaFromNodeNames(
        names,
        source: DeviceMetaSource.liveGroup,
      );
      if (fromLive == null) {
        return stored;
      }
      return fromLive.withPortalUrl(stored?.portalUrl);
    });

final currentQuotaForecastProvider = Provider<QuotaForecast?>((ref) {
  final info = ref.watch(
    currentProfileProvider.select((profile) => profile?.subscriptionInfo),
  );
  final ledger = ref.watch(dailyTrafficProvider);
  return forecastSubscriptionQuota(info, ledger);
});
