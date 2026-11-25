import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get ua {
    final segments = version.split('+').first.split('-').first.split('.');
    final majorMinor = segments.length >= 2
        ? '${segments[0]}.${segments[1]}'
        : version;
    return [
      '$appName/v$majorMinor',
      'clash-verge',
      'Platform/${Platform.operatingSystem}',
    ].join(' ');
  }
}

int _parseSegment(List<String> parts, int index) {
  if (index >= parts.length) {
    return 0;
  }
  return int.tryParse(parts[index]) ?? 0;
}

int _extractBuildNumber(String version) {
  if (version.contains('+')) {
    final afterPlus = version.split('+')[1];
    final digits = RegExp(r'^\d+').stringMatch(afterPlus);
    return digits == null ? 0 : (int.tryParse(digits) ?? 0);
  }
  final viMatch = RegExp(r'-vi\.(\d+)').firstMatch(version);
  if (viMatch != null) {
    return int.tryParse(viMatch.group(1)!) ?? 0;
  }
  return 0;
}

int compareVersions(String version1, String version2) {
  final List<String> v1 = version1.split('+')[0].split('-')[0].split('.');
  final List<String> v2 = version2.split('+')[0].split('-')[0].split('.');
  final int major1 = _parseSegment(v1, 0);
  final int major2 = _parseSegment(v2, 0);
  if (major1 != major2) {
    return major1.compareTo(major2);
  }
  final int minor1 = _parseSegment(v1, 1);
  final int minor2 = _parseSegment(v2, 1);
  if (minor1 != minor2) {
    return minor1.compareTo(minor2);
  }
  final int patch1 = _parseSegment(v1, 2);
  final int patch2 = _parseSegment(v2, 2);
  if (patch1 != patch2) {
    return patch1.compareTo(patch2);
  }
  final int build1 = _extractBuildNumber(version1);
  final int build2 = _extractBuildNumber(version2);
  return build1.compareTo(build2);
}

const releaseNotesBeginMarker = '<!-- flclash:changelog:begin -->';
const releaseNotesEndMarker = '<!-- flclash:changelog:end -->';

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
