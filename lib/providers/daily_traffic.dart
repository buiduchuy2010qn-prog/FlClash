import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/daily_traffic_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DailyTrafficEnabledNotifier extends Notifier<bool> {
  var _disposed = false;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(_hydrate());
    return true;
  }

  Future<void> _hydrate() async {
    final saved = await preferences.getDailyTrafficEnabled();
    if (!_disposed) {
      state = saved;
    }
  }

  bool get value => state;

  set value(bool next) {
    if (state == next) return;
    state = next;
    unawaited(preferences.setDailyTrafficEnabled(next));
  }
}

final dailyTrafficEnabledProvider =
    NotifierProvider<DailyTrafficEnabledNotifier, bool>(
      DailyTrafficEnabledNotifier.new,
    );

class DailyTrafficNotifier extends Notifier<DailyTrafficLedger> {
  var _disposed = false;
  var _hydrated = false;
  var _dirty = false;
  int? _lastTotalUp;
  int? _lastTotalDown;
  int _pendingUpDelta = 0;
  int _pendingDownDelta = 0;
  Timer? _saveTimer;

  @override
  DailyTrafficLedger build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _saveTimer?.cancel();
      _saveTimer = null;
      if (_dirty) {
        unawaited(preferences.setDailyTrafficHistory(state.encode()));
      }
    });
    unawaited(_hydrate());
    return const DailyTrafficLedger();
  }

  Future<void> _hydrate() async {
    final raw = await preferences.getDailyTrafficHistory();
    if (_disposed) return;
    var ledger = DailyTrafficLedger.decode(raw);
    if (_pendingUpDelta > 0 || _pendingDownDelta > 0) {
      ledger = ledger.recordDelta(
        upDelta: _pendingUpDelta,
        downDelta: _pendingDownDelta,
      );
      _pendingUpDelta = 0;
      _pendingDownDelta = 0;
      _dirty = true;
    }
    _hydrated = true;
    state = ledger;
    if (_dirty) {
      _scheduleSave();
    }
  }

  void recordTotalSample({required int up, required int down, DateTime? now}) {
    if (!ref.read(dailyTrafficEnabledProvider)) return;
    if (up < 0 || down < 0) return;

    final prevUp = _lastTotalUp;
    final prevDown = _lastTotalDown;
    _lastTotalUp = up;
    _lastTotalDown = down;

    if (prevUp == null || prevDown == null) {
      return;
    }

    final upDelta = up >= prevUp ? up - prevUp : up;
    final downDelta = down >= prevDown ? down - prevDown : down;
    if (upDelta <= 0 && downDelta <= 0) return;

    if (!_hydrated) {
      _pendingUpDelta += upDelta;
      _pendingDownDelta += downDelta;
      return;
    }

    final next = state.recordDelta(
      upDelta: upDelta,
      downDelta: downDelta,
      now: now,
    );
    if (!identical(next, state)) {
      state = next;
      _dirty = true;
      _scheduleSave();
    }
  }

  void resetSessionBaseline() {
    _lastTotalUp = 0;
    _lastTotalDown = 0;
  }

  void clearHistory() {
    _pendingUpDelta = 0;
    _pendingDownDelta = 0;
    state = const DailyTrafficLedger();
    _dirty = false;
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(preferences.setDailyTrafficHistory(null));
  }

  void _scheduleSave() {
    _saveTimer ??= Timer(const Duration(seconds: 5), () {
      _saveTimer = null;
      if (_disposed || !_dirty) return;
      _dirty = false;
      unawaited(preferences.setDailyTrafficHistory(state.encode()));
    });
  }
}

final dailyTrafficProvider =
    NotifierProvider<DailyTrafficNotifier, DailyTrafficLedger>(
      DailyTrafficNotifier.new,
    );
