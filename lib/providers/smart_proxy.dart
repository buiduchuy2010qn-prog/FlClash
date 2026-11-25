import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config.dart';
import 'state.dart';

typedef ActiveProxyTarget = ({String proxyName, String testUrl});

class AutoFailoverNotifier extends Notifier<bool> {
  var _disposed = false;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(_hydrate());
    return true;
  }

  Future<void> _hydrate() async {
    final saved = await preferences.getAutoFailover();
    if (!_disposed && state != saved) {
      state = saved;
    }
    unawaited(service?.setAutoFailover(saved));
  }

  void toggle() => setEnabled(!state);

  void setEnabled(bool value) {
    state = value;
    unawaited(preferences.setAutoFailover(value));
    unawaited(service?.setAutoFailover(value));
  }
}

final autoFailoverProvider = NotifierProvider<AutoFailoverNotifier, bool>(
  AutoFailoverNotifier.new,
);

final activeProxyTargetProvider = Provider<ActiveProxyTarget?>((ref) {
  final groups = ref.watch(visibleGroupsStateProvider).value;
  if (groups.isEmpty) return null;
  final allGroups = ref.watch(groupsProvider);
  final selectedMap = ref.watch(selectedMapProvider);
  final defaultTestUrl = ref.watch(
    patchClashConfigProvider.select((state) => state.testUrl),
  );
  final primary =
      groups.firstWhereOrNull((g) => g.type == GroupType.Selector) ??
      groups.first;
  final selected = primary.getCurrentSelectedName(
    selectedMap[primary.name] ?? '',
  );
  if (selected.isEmpty) return null;
  final real = computeRealSelectedProxyState(
    selected,
    groups: allGroups,
    selectedMap: selectedMap,
  );
  if (real.proxyName.isEmpty) return null;
  final testUrl = real.testUrl.takeFirstValid([
    primary.testUrl,
    defaultTestUrl,
  ]);
  return (proxyName: real.proxyName, testUrl: testUrl);
});

String notificationTitleFor({
  required String profileName,
  required String? activeProxyName,
  required int? activeDelay,
}) {
  final base = profileName.isEmpty ? appName : profileName;
  final proxy = activeProxyName?.trim() ?? '';
  if (proxy.isEmpty) {
    return base;
  }
  if (activeDelay != null && activeDelay > 0) {
    return '$proxy · ${activeDelay}ms';
  }
  if (activeDelay != null && activeDelay < 0) {
    return '$proxy · Timeout';
  }
  return '$base · $proxy';
}
