import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/mobile_features.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/banner.dart';

class ProfileSecurityNotifier
    extends Notifier<Map<int, ProfileSecurityReport>> {
  var _disposed = false;
  final Set<int> _notifiedDangerIds = {};

  @override
  Map<int, ProfileSecurityReport> build() {
    _disposed = false;
    _notifiedDangerIds.clear();
    ref.onDispose(() => _disposed = true);
    return const {};
  }

  Future<String> _readProfileYaml(Profile profile) async {
    if (profile.type == ProfileType.custom) {
      final (proxies, rules) = await (
        database.customProxiesDao.query().get(),
        database.rulesDao.queryProfileRules(profile.id).get(),
      ).wait;
      return yaml.encode({
        'proxies': [for (final p in proxies) p.definition],
        'rules': [for (final r in rules) r.rawValue],
      });
    }
    final path = await appPath.getProfilePath(profile.id.toString());
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }
    final length = await file.length();
    if (length > 4 * 1024 * 1024) {
      return '';
    }
    final text = await file.readAsString();
    if (profile.ageSecretKey.isNotEmpty &&
        text.startsWith('age-encryption.org/')) {
      try {
        final decoded = await ref
            .read(coreHandlerProvider)
            .readConfig(profile.id);
        return yaml.encode(decoded);
      } catch (_) {
        return '';
      }
    }
    return text;
  }

  Future<ProfileSecurityReport?> scanProfile(
    Profile profile, {
    bool notifyIfDangerous = false,
  }) async {
    try {
      final rawYaml = await _readProfileYaml(profile);
      final report = await compute(auditProfileSecurityTask, (
        rawYaml: rawYaml,
        subscriptionUrl: profile.type == ProfileType.url ? profile.url : null,
      ));
      if (_disposed) return report;
      state = {...state, profile.id: report};
      if (notifyIfDangerous &&
          report.isDangerous &&
          _notifiedDangerIds.add(profile.id)) {
        final l = currentAppLocalizations;
        final title = l.securityAlertTitle(profile.realLabel);
        final body = l.securityAlertBody(report.score, report.criticalCount);
        dialogs.showBanner('$title: $body', level: BannerLevel.warning);
        if (system.isAndroid && ref.read(expiryAlertsEnabledProvider)) {
          unawaited(
            app?.showAlertNotification(
              id: 3000 + (profile.id.abs() % 500),
              title: title,
              body: body,
            ),
          );
        }
      }
      return report;
    } catch (error) {
      commonPrint.log(
        'scanProfile(${profile.id}) failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  void remove(int profileId) {
    _notifiedDangerIds.remove(profileId);
    if (!state.containsKey(profileId)) return;
    final next = Map<int, ProfileSecurityReport>.from(state)..remove(profileId);
    state = Map.unmodifiable(next);
  }
}

final profileSecurityProvider =
    NotifierProvider<ProfileSecurityNotifier, Map<int, ProfileSecurityReport>>(
      ProfileSecurityNotifier.new,
    );
