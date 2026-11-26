part of '../action.dart';

class _DelayTestTarget {
  const _DelayTestTarget({
    required this.proxyName,
    required this.testUrl,
    required this.key,
  });

  final String proxyName;
  final String testUrl;
  final String key;
}

typedef _DelayTestBatch = ({List<Proxy> proxies, String? testUrl});

class _DelayTestJob {
  _DelayTestJob(Iterable<String> keys, this.timeout) : held = keys.toSet();

  final Set<String> held;
  final Duration timeout;
  final Set<String> startedOnDispatch = {};
  bool cancelled = false;
}

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  static const _builtinNames = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'};
  static const _failoverSlowDelayMs = 1200;
  static const _failoverFastEnoughMs = 650;
  static const _failoverDegradedImproveMs = 300;
  static const _autoFastCandidateDelayMs = 800;
  static const _autoProbeBatchSize = 1;
  static const _foregroundWatchdogInterval = Duration(seconds: 60);
  static const _backgroundWatchdogInterval = Duration(seconds: 180);
  static const _resumeCheckCooldown = Duration(seconds: 30);
  static const _failoverConfirmDelay = Duration(milliseconds: 500);
  static const _autoSwitchHysteresisMs = 100;
  static const _quarantineDuration = Duration(minutes: 3);
  static const _quarantinePenaltyMs = 1500;
  static const _autoSubRefreshCooldown = Duration(minutes: 15);
  static final _infoBannerProxyRegex = RegExp(
    r'(剩余流量|套餐到期|距离下次重置|官网|群组|频道|traffic\s*[:：]|expire\s*[:：]|dung\s*lượng\s*[:：]|hạn\s*dùng\s*[:：])',
    caseSensitive: false,
  );
  CoreController get _core => ref.read(coreHandlerProvider);

  final TaskPool _delayTestPool = TaskPool(
    system.isAndroid ? maxConcurrentMobileDelayTests : maxConcurrentDelayTests,
  );

  final List<_DelayTestJob> _delayTestJobs = [];

  final List<Delay> _bufferedDelays = [];

  final List<String> _bufferedStarts = [];

  final List<String> _bufferedFinishes = [];

  Timer? _delayFlushTimer;

  Timer? _autoPingTimer;

  Timer? _watchdogTimer;

  int _lastAutoPingEpoch = -1;

  DateTime? _lastAutoCheckAt;

  final Map<String, String> _pendingSelectedRollback = {};

  final Map<String, DateTime> _quarantinedUntil = {};

  final Map<int, DateTime> _lastAutoSubRefreshAt = {};

  @override
  void build() {
    ref.onDispose(() {
      _delayFlushTimer?.cancel();
      _autoPingTimer?.cancel();
      _watchdogTimer?.cancel();
    });
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        _autoPingTimer?.cancel();
        _watchdogTimer?.cancel();
        _watchdogTimer = null;
        _lastAutoPingEpoch = -1;
        _lastAutoCheckAt = null;
        cancelDelayTests();
      }
    });
    ref.listen(runTimeProvider, (prev, next) {
      if (next == null) {
        _autoPingTimer?.cancel();
        _watchdogTimer?.cancel();
        _watchdogTimer = null;
        _lastAutoPingEpoch = -1;
        _lastAutoCheckAt = null;
        return;
      }
      if (prev == null) {
        _scheduleAutoPing();
        _startWatchdog();
      }
    });
    ref.listen(appVisibleProvider, (prev, next) {
      if (prev == next || ref.read(runTimeProvider) == null) {
        return;
      }
      _startWatchdog();
      if (next &&
          (_lastAutoCheckAt == null ||
              DateTime.now().difference(_lastAutoCheckAt!) >=
                  _resumeCheckCooldown)) {
        _scheduleAutoPing();
      }
    });
    ref.listen(groupsProvider, (prev, next) {
      if ((prev == null || prev.isEmpty) &&
          next.isNotEmpty &&
          ref.read(runTimeProvider) != null) {
        _scheduleAutoPing();
      }
    });
    ref.listen(routeTrackerProvider.select((state) => state.coreEpoch), (
      prev,
      next,
    ) {
      if (next != prev &&
          next != _lastAutoPingEpoch &&
          ref.read(runTimeProvider) != null) {
        _lastAutoPingEpoch = next;
        _scheduleAutoPing();
      }
    });
    ref.listen(routeTrackerProvider.select((state) => state.routeVersion), (
      prev,
      next,
    ) {
      if (next != prev && ref.read(runTimeProvider) != null) {
        updateGroupsDebounce();
      }
    });
  }

  void _scheduleAutoPing() {
    if (!ref.read(autoFailoverProvider)) {
      return;
    }
    _autoPingTimer?.cancel();
    _autoPingTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_autoTestActiveGroup());
    });
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    final interval = ref.read(appVisibleProvider)
        ? _foregroundWatchdogInterval
        : _backgroundWatchdogInterval;
    _watchdogTimer = Timer.periodic(interval, (_) {
      if (ref.read(runTimeProvider) == null ||
          ref.read(coreStatusProvider) != CoreStatus.connected ||
          !ref.read(autoFailoverProvider) ||
          ref.read(delayTestingGroupsProvider).isNotEmpty) {
        return;
      }
      unawaited(_autoTestActiveGroup());
    });
  }

  static bool isInfoBannerProxyName(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty && _infoBannerProxyRegex.hasMatch(trimmed);
  }

  Group? _resolvePrimaryLeafSelectorGroup() {
    final visible = ref.read(visibleGroupsStateProvider).value;
    if (visible.isEmpty) return null;
    final allGroups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    var current =
        visible.firstWhereOrNull((g) => g.type == GroupType.Selector) ??
        visible.first;
    final visited = <String>{current.name};
    for (var i = 0; i < 8; i++) {
      final pick = current.getCurrentSelectedName(
        selectedMap[current.name] ?? '',
      );
      if (pick.isEmpty || visited.contains(pick)) break;
      final next = allGroups.getGroup(pick);
      if (next == null || next.type != GroupType.Selector) break;
      visited.add(pick);
      current = next;
    }
    return current;
  }

  Future<void> _autoTestActiveGroup() async {
    if (ref.read(runTimeProvider) == null ||
        ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    final primary = _resolvePrimaryLeafSelectorGroup();
    if (primary == null || primary.all.isEmpty) {
      return;
    }
    _lastAutoCheckAt = DateTime.now();
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final selected = selectedMap[primary.name] ?? '';
    final activeName = primary.getCurrentSelectedName(selected);
    final defaultTestUrl = ref.read(realTestUrlProvider(primary.testUrl));
    final real = computeRealSelectedProxyState(
      activeName,
      groups: groups,
      selectedMap: selectedMap,
    );
    final targetName = real.proxyName.isNotEmpty ? real.proxyName : activeName;
    final leafProxy =
        primary.all.firstWhereOrNull((p) => p.name == targetName) ??
        groups
            .expand((g) => g.all)
            .firstWhereOrNull((p) => p.name == targetName);
    if (leafProxy == null || _builtinNames.contains(leafProxy.name)) {
      return;
    }
    await _runDelayTests([
      (proxies: [leafProxy], testUrl: defaultTestUrl),
    ]);
    if (ref.read(runTimeProvider) == null ||
        ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    final currentGroups = ref.read(groupsProvider);
    final currentSelectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final delayMap = ref.read(delayDataSourceProvider);
    final activeDelay = computeProxyDelayState(
      proxyName: leafProxy.name,
      testUrl: defaultTestUrl,
      groups: currentGroups,
      selectedMap: currentSelectedMap,
      delayMap: delayMap,
    ).delay;
    if ((activeDelay <= 0 || activeDelay >= _failoverSlowDelayMs) &&
        primary.type == GroupType.Selector &&
        ref.read(autoFailoverProvider)) {
      await Future<void>.delayed(_failoverConfirmDelay);
      if (ref.read(runTimeProvider) == null ||
          ref.read(coreStatusProvider) != CoreStatus.connected ||
          !ref.read(autoFailoverProvider)) {
        return;
      }
      await _runDelayTests([
        (proxies: [leafProxy], testUrl: defaultTestUrl),
      ]);
      if (ref.read(runTimeProvider) == null ||
          ref.read(coreStatusProvider) != CoreStatus.connected) {
        return;
      }
      final confirmedDelay = computeProxyDelayState(
        proxyName: leafProxy.name,
        testUrl: defaultTestUrl,
        groups: ref.read(groupsProvider),
        selectedMap: ref.read(
          currentProfileProvider.select((state) => state?.selectedMap ?? {}),
        ),
        delayMap: ref.read(delayDataSourceProvider),
      ).delay;
      if (confirmedDelay <= 0 || confirmedDelay >= _failoverSlowDelayMs) {
        if (confirmedDelay <= 0) {
          _quarantinedUntil[leafProxy.name] = DateTime.now().add(
            _quarantineDuration,
          );
        }
        await selectFastestProxy(primary.name, automatic: true);
      }
    }
  }

  bool _isQuarantined(String proxyName, DateTime now) {
    _quarantinedUntil.removeWhere((_, until) => !now.isBefore(until));
    final until = _quarantinedUntil[proxyName];
    return until != null && now.isBefore(until);
  }

  Future<bool> _tryRecoverDeadSubscription() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null ||
        profile.type != ProfileType.url ||
        profile.url.isEmpty) {
      return false;
    }
    final now = DateTime.now();
    final lastRefresh = _lastAutoSubRefreshAt[profile.id];
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _autoSubRefreshCooldown) {
      return false;
    }
    _lastAutoSubRefreshAt[profile.id] = now;
    try {
      await ref.read(profilesActionProvider.notifier).updateProfile(profile);
      if (!ref.mounted) return false;
      await updateGroups();
      return true;
    } catch (e) {
      commonPrint.log(
        'auto subscription recovery failed: $e',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  Future<void> selectFastestActiveGroup({bool automatic = false}) async {
    final primary = _resolvePrimaryLeafSelectorGroup();
    if (primary == null) return;
    await selectFastestProxy(primary.name, automatic: automatic);
  }

  Future<void> selectFastestProxy(
    String groupName, {
    bool automatic = false,
    bool allowSubscriptionRecovery = true,
  }) async {
    final allGroups = ref.read(groupsProvider);
    final group = allGroups.getGroup(groupName);
    if (group == null || group.all.isEmpty) {
      return;
    }
    final testing = ref.read(delayTestingGroupsProvider.notifier);
    if (!testing.start(groupName)) {
      return;
    }
    var recoverNeeded = false;
    try {
      final groupNames = {for (final g in allGroups) g.name};
      final nonBuiltin = [
        for (final proxy in group.all)
          if (!_builtinNames.contains(proxy.name)) proxy,
      ];
      final leafOnly = [
        for (final proxy in nonBuiltin)
          if (!groupNames.contains(proxy.name)) proxy,
      ];
      final nonBannerLeaves = [
        for (final proxy in leafOnly)
          if (!isInfoBannerProxyName(proxy.name)) proxy,
      ];
      final candidates = nonBannerLeaves.isNotEmpty
          ? nonBannerLeaves
          : leafOnly.isNotEmpty
          ? leafOnly
          : (nonBuiltin.isNotEmpty ? nonBuiltin : group.all);
      final probedCandidates = <Proxy>[];
      if (!automatic) {
        await delayTest(candidates, group.testUrl);
        probedCandidates.addAll(candidates);
      } else {
        final initialSelectedMap = ref.read(
          currentProfileProvider.select((state) => state?.selectedMap ?? {}),
        );
        final currentName = group.getCurrentSelectedName(
          initialSelectedMap[groupName] ?? '',
        );
        final currentLeaf = computeRealSelectedProxyState(
          currentName,
          groups: allGroups,
          selectedMap: initialSelectedMap,
        );
        final currentLookupName = currentLeaf.proxyName.isNotEmpty
            ? currentLeaf.proxyName
            : currentName;
        final defaultTestUrl = ref.read(realTestUrlProvider(group.testUrl));
        final probeNow = DateTime.now();
        final otherClean = <Proxy>[];
        final otherQuarantined = <Proxy>[];
        final selfCandidates = <Proxy>[];
        for (final candidate in candidates) {
          if (candidate.name == currentLookupName) {
            selfCandidates.add(candidate);
          } else if (_isQuarantined(candidate.name, probeNow)) {
            otherQuarantined.add(candidate);
          } else {
            otherClean.add(candidate);
          }
        }
        Future<bool> probeBatches(List<Proxy> pool) async {
          var foundAlive = false;
          for (var i = 0; i < pool.length; i += _autoProbeBatchSize) {
            final end = (i + _autoProbeBatchSize > pool.length)
                ? pool.length
                : i + _autoProbeBatchSize;
            final batch = pool.sublist(i, end);
            await delayTest(batch, group.testUrl);
            probedCandidates.addAll(batch);
            final latestGroups = ref.read(groupsProvider);
            final latestSelectedMap = ref.read(
              currentProfileProvider.select(
                (state) => state?.selectedMap ?? {},
              ),
            );
            final latestDelays = ref.read(delayDataSourceProvider);
            var hitFast = false;
            for (final candidate in batch) {
              final delay = computeProxyDelayState(
                proxyName: candidate.name,
                testUrl: defaultTestUrl,
                groups: latestGroups,
                selectedMap: latestSelectedMap,
                delayMap: latestDelays,
              ).delay;
              if (delay > 0) {
                foundAlive = true;
                if (delay < _autoFastCandidateDelayMs) {
                  hitFast = true;
                }
              }
            }
            if (hitFast) {
              break;
            }
          }
          return foundAlive;
        }

        final cleanAlive = await probeBatches(otherClean);
        if (!cleanAlive) {
          final quarantinedAlive = await probeBatches(otherQuarantined);
          if (!quarantinedAlive &&
              otherClean.isEmpty &&
              otherQuarantined.isEmpty) {
            await probeBatches(selfCandidates);
          }
        }
      }

      final groups = ref.read(groupsProvider);
      final selectedMap = ref.read(
        currentProfileProvider.select((state) => state?.selectedMap ?? {}),
      );
      final defaultTestUrl = ref.read(realTestUrlProvider(group.testUrl));
      final delayMap = ref.read(delayDataSourceProvider);
      final now = DateTime.now();

      Proxy? bestProxy;
      var bestScore = 1 << 30;
      var bestDelay = 1 << 30;
      for (final candidate in probedCandidates) {
        final delay = computeProxyDelayState(
          proxyName: candidate.name,
          testUrl: defaultTestUrl,
          groups: groups,
          selectedMap: selectedMap,
          delayMap: delayMap,
        ).delay;
        if (delay <= 0) continue;
        final penalty = automatic && _isQuarantined(candidate.name, now)
            ? _quarantinePenaltyMs
            : 0;
        final score = delay + penalty;
        if (score < bestScore || (score == bestScore && delay < bestDelay)) {
          bestScore = score;
          bestDelay = delay;
          bestProxy = candidate;
        }
      }
      if (bestProxy == null) {
        recoverNeeded =
            allowSubscriptionRecovery && await _tryRecoverDeadSubscription();
        if (!recoverNeeded && !automatic) {
          dialogs.showBanner(
            currentAppLocalizations.noAvailableProxyTip,
            level: BannerLevel.warning,
          );
        }
      } else {
        final selected = selectedMap[groupName] ?? '';
        final currentName = group.getCurrentSelectedName(selected);
        final switched = bestProxy.name != currentName;
        if (automatic && switched) {
          final currentLeaf = computeRealSelectedProxyState(
            currentName,
            groups: groups,
            selectedMap: selectedMap,
          );
          final currentLookupName = currentLeaf.proxyName.isNotEmpty
              ? currentLeaf.proxyName
              : currentName;
          final currentDelay = computeProxyDelayState(
            proxyName: currentLookupName,
            testUrl: defaultTestUrl,
            groups: groups,
            selectedMap: selectedMap,
            delayMap: delayMap,
          ).delay;
          if (currentDelay >= _failoverSlowDelayMs) {
            if (bestDelay >= _failoverFastEnoughMs ||
                bestDelay + _failoverDegradedImproveMs > currentDelay) {
              return;
            }
          } else if (currentDelay > 0 &&
              bestDelay + _autoSwitchHysteresisMs >= currentDelay) {
            return;
          }
        }
        if (switched && group.type == GroupType.Selector) {
          await changeProxy(groupName: groupName, proxyName: bestProxy.name);
          updateGroupsDebounce();
        }
        if (automatic && !switched) {
          return;
        }
        final delayLabel = '${bestDelay}ms';
        final tip = automatic
            ? currentAppLocalizations.autoFailoverSwitchedTip(
                bestProxy.name,
                delayLabel,
              )
            : currentAppLocalizations.fastestProxySelectedTip(
                bestProxy.name,
                delayLabel,
              );
        dialogs.showBanner(tip, level: BannerLevel.success);
      }
    } finally {
      testing.stop(groupName);
    }
    if (recoverNeeded && ref.mounted) {
      await selectFastestProxy(
        groupName,
        automatic: automatic,
        allowSubscriptionRecovery: false,
      );
    }
  }

  void cancelDelayTests() {
    for (final job in _delayTestJobs) {
      job.cancelled = true;
      job.held.clear();
    }
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    _bufferedDelays.clear();
    _bufferedStarts.clear();
    _bufferedFinishes.clear();
    ref.read(pendingDelayTestsProvider.notifier).clear();
  }

  void _scheduleDelayFlush() {
    _delayFlushTimer ??= Timer(renderThrottleDuration, _flushDelayResults);
  }

  void _flushDelayResults() {
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    if (_bufferedDelays.isNotEmpty) {
      final delays = List.of(_bufferedDelays);
      _bufferedDelays.clear();
      ref.read(delayDataSourceProvider.notifier).setDelays(delays);
    }
    if (_bufferedStarts.isNotEmpty || _bufferedFinishes.isNotEmpty) {
      final started = List.of(_bufferedStarts);
      final finished = List.of(_bufferedFinishes);
      _bufferedStarts.clear();
      _bufferedFinishes.clear();
      ref
          .read(pendingDelayTestsProvider.notifier)
          .apply(started: started, finished: finished);
    }
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    _pendingSelectedRollback.putIfAbsent(
      groupName,
      () => _currentSelectedName(groupName),
    );
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(groupName, proxyName);
    debouncer.call((FunctionTag.changeProxy, groupName), (
      String groupName,
      String proxyName,
    ) async {
      await changeProxy(groupName: groupName, proxyName: proxyName);
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  String _currentSelectedName(String groupName) {
    return ref.read(currentProfileProvider)?.selectedMap[groupName] ?? '';
  }

  Future<void> updateGroups() async {
    try {
      final groups = await retry<List<Group>>(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            patchClashConfigProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          try {
            return await _core.getProxiesGroups(
              selectedMap: selectedMap,
              sortType: sortType,
              delayMap: delayMap,
              defaultTestUrl: testUrl,
            );
          } catch (e) {
            commonPrint.log(
              'updateGroups error: $e',
              logLevel: coreFailureLogLevel(e),
            );
            return <Group>[];
          }
        },
        retryIf: (res) => res.isEmpty,
      );
      ref.read(groupsProvider.notifier).value = groups;
      final currentProfile = ref.read(currentProfileProvider);
      if (currentProfile != null && groups.isNotEmpty) {
        final profilesAction = ref.read(profilesActionProvider.notifier);
        for (final group in groups) {
          final corePick = group.now;
          if (group.type == GroupType.Selector &&
              corePick != null &&
              corePick.isNotEmpty &&
              !_pendingSelectedRollback.containsKey(group.name) &&
              currentProfile.selectedMap.containsKey(group.name) &&
              currentProfile.selectedMap[group.name] != corePick) {
            profilesAction.updateCurrentSelectedMap(group.name, corePick);
          }
        }
      }
    } catch (e) {
      // The Core failure path already runs inside the retry task above; a
      // throw here only means ref.read hit a disposed container or the
      // groupsProvider write itself failed.
      commonPrint.log(
        'updateGroups failed: $e',
        logLevel: coreFailureLogLevel(e),
      );
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    _bufferedDelays.add(delay);
    _scheduleDelayFlush();
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    final rollbackName =
        _pendingSelectedRollback.remove(groupName) ??
        _currentSelectedName(groupName);
    profilesAction.updateCurrentSelectedMap(groupName, proxyName);
    final ChangeProxyResult result;
    try {
      result = await _core.changeProxy(
        ChangeProxyParams(groupName: groupName, proxyName: proxyName),
      );
      if (result.message.isNotEmpty) {
        throw MessageException(result.message);
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
      profilesAction.updateCurrentSelectedMap(groupName, rollbackName);
      dialogs.showBanner(
        currentAppLocalizations.changeProxyFailedTip,
        level: BannerLevel.error,
      );
      return;
    }
    if (!result.changed) {
      return;
    }
    try {
      if (ref.read(appSettingProvider).closeConnections) {
        await _core.closeConnections();
      } else {
        await _core.resetConnections();
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) connection reset failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
    // After the reset, which closes the probes out through the tunnel too.
    ref.read(routeTrackerProvider.notifier).markPicked();
  }

  Future<void> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final clashProvidersAction = ref.read(
        clashProvidersActionProvider.notifier,
      );
      final ruleSet = await clashProvidersAction.remoteProviderOf(provider);
      if (ruleSet != null && !await clashProvidersAction.syncRemote(ruleSet)) {
        return;
      }
      await _core.updateExternalProvider(provider.name);
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<void> sideLoadExternalProvider(
    ExternalProvider provider,
    String data, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      await _core.sideLoadExternalProvider(
        providerName: provider.name,
        data: data,
      );
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<void> addToLocalProxies(String proxyName) async {
    final appLocalizations = currentAppLocalizations;
    final definition = await _core.getProxyDefinition(proxyName);
    if (definition == null) {
      throw MessageException(
        appLocalizations.customIssueMissingProxies(proxyName),
      );
    }
    final (proxies, groupNames) = await (
      database.customProxiesDao.query().get(),
      database.proxyGroupsDao.names().get(),
    ).wait;
    final (:name, :added) = importProxy(
      definition,
      existing: [for (final proxy in proxies) proxy.definition],
      groupNames: groupNames.toSet(),
    );
    if (added == null) {
      dialogs.showBanner(appLocalizations.alreadyInLocalProxies(name));
      return;
    }
    final order = indexing.generateKeyBetween(
      proxies.map((proxy) => proxy.order).nonNulls.lastOrNull,
      null,
    );
    await database.customProxies.put(
      CustomProxy.fromDefinition(added).copyWith(order: order).toCompanion(),
    );
    dialogs.showBanner(appLocalizations.addedToLocalProxies(name));
  }

  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) {
    return _runDelayTests([
      (proxies: [proxy], testUrl: testUrl),
    ]);
  }

  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    await _runDelayTests([(proxies: proxies, testUrl: testUrl)]);
    ref.read(sortNumProvider.notifier).add();
  }

  Future<void> delayTestGroups(List<Group> groups) async {
    await _runDelayTests([
      for (final group in groups) (proxies: group.all, testUrl: group.testUrl),
    ]);
    ref.read(sortNumProvider.notifier).add();
  }

  Future<void> delayTestPageGroup(
    String groupName, {
    bool matchSearch = true,
  }) async {
    final group = ref.read(groupsProvider).getGroup(groupName);
    if (group == null) {
      return;
    }
    final testing = ref.read(delayTestingGroupsProvider.notifier);
    if (!testing.start(groupName)) {
      return;
    }
    try {
      final query = SearchQuery(
        matchSearch ? ref.read(queryProvider(QueryTag.proxies)) : '',
      );
      await delayTest(
        group.all.whereMatches(query, (proxy) => proxy.searchFields).toList(),
        group.testUrl,
      );
    } finally {
      testing.stop(groupName);
    }
  }

  List<_DelayTestTarget> _resolveDelayTestTargets(
    List<_DelayTestBatch> batches,
  ) {
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final seen = <String>{};
    final targets = <_DelayTestTarget>[];
    for (final batch in batches) {
      final fallbackTestUrl = ref.read(realTestUrlProvider(batch.testUrl));
      for (final proxy in batch.proxies) {
        final state = computeRealSelectedProxyState(
          proxy.name,
          groups: groups,
          selectedMap: selectedMap,
        );
        if (state.proxyName.isEmpty) {
          continue;
        }
        final currentTestUrl = state.testUrl.takeFirstValid([fallbackTestUrl]);
        final key = delayTestKey(currentTestUrl, state.proxyName);
        if (!seen.add(key)) {
          continue;
        }
        targets.add(
          _DelayTestTarget(
            proxyName: state.proxyName,
            testUrl: currentTestUrl,
            key: key,
          ),
        );
      }
    }
    return targets;
  }

  Future<void> _runDelayTests(List<_DelayTestBatch> batches) async {
    final targets = _resolveDelayTestTargets(batches);
    if (targets.isEmpty) {
      return;
    }
    final pending = ref.read(pendingDelayTestsProvider.notifier);
    final job = _DelayTestJob(
      targets.map((target) => target.key),
      Duration(milliseconds: ref.read(appSettingProvider).delayTestTimeout),
    );
    _delayTestJobs.add(job);
    // TaskPool.run starts a task synchronously while it has an idle slot.
    job.startedOnDispatch.addAll(
      targets.take(_delayTestPool.idleSlots).map((target) => target.key),
    );
    pending.apply(acquired: job.held, started: job.startedOnDispatch);
    try {
      await Future.wait(
        targets.map(
          (target) => _delayTestPool.run(() => _runDelayTest(job, target)),
        ),
      );
    } finally {
      _delayTestJobs.remove(job);
      _flushDelayResults();
      final abandoned = job.held.toList();
      job.held.clear();
      pending.apply(
        finished: abandoned.where(job.startedOnDispatch.contains),
        released: abandoned.where(
          (key) => !job.startedOnDispatch.contains(key),
        ),
      );
    }
  }

  Future<void> _runDelayTest(_DelayTestJob job, _DelayTestTarget target) async {
    if (job.cancelled) {
      return;
    }
    if (!job.startedOnDispatch.contains(target.key)) {
      _bufferedStarts.add(target.key);
      _scheduleDelayFlush();
    }
    try {
      final delay = await _core.testDelay(
        TestDelayParams(
          proxyName: target.proxyName,
          testUrl: target.testUrl,
          timeout: job.timeout.inMilliseconds,
        ),
      );
      if (!job.cancelled) {
        setDelay(delay);
      }
    } catch (error) {
      if (error is CoreMethodException && error.isCoreUnavailable) {
        job.cancelled = true;
      }
      commonPrint.log(
        'Delay test failed for ${target.proxyName}: $error',
        logLevel: coreFailureLogLevel(error),
      );
    } finally {
      if (job.held.remove(target.key)) {
        _bufferedFinishes.add(target.key);
        _scheduleDelayFlush();
      }
    }
  }
}
