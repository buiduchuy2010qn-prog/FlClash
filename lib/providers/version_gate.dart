import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/version_gate.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VersionGateNotifier extends Notifier<VersionGateState> {
  static const _evaluator = VersionGateEvaluator();
  var _disposed = false;

  @override
  VersionGateState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(_hydrateAndCheck());
    return const VersionGateState();
  }

  int get _currentVersionCode =>
      int.tryParse(globalState.packageInfo.buildNumber) ?? 0;

  Future<void> _hydrateAndCheck() async {
    final cachedRaw = await preferences.getVersionGateCache();
    if (_disposed) return;
    final cached = VersionGatePolicy.decodeCache(cachedRaw);
    if (cached != null) {
      state = state.copyWith(
        policy: cached,
        blocked: VersionGateEvaluator.isBlocked(
          currentVersionCode: _currentVersionCode,
          policy: cached,
        ),
      );
    }
    if (cached == null || cached.isExpired()) {
      await checkNow();
    }
  }

  Future<void> checkNow() async {
    if (_disposed || state.checking) return;
    state = state.copyWith(checking: true);
    final fresh = await _evaluator.fetchPolicy();
    if (_disposed) return;
    if (fresh != null) {
      unawaited(preferences.setVersionGateCache(fresh.encodeCache()));
      state = VersionGateState(
        policy: fresh,
        blocked: VersionGateEvaluator.isBlocked(
          currentVersionCode: _currentVersionCode,
          policy: fresh,
        ),
        checking: false,
      );
      return;
    }
    state = state.copyWith(checking: false);
  }
}

final versionGateProvider =
    NotifierProvider<VersionGateNotifier, VersionGateState>(
      VersionGateNotifier.new,
    );
