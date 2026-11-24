import 'dart:convert';

import 'package:dio/dio.dart';

const versionGateManifestUrl =
    'https://raw.githubusercontent.com/buiduchuy2010qn-prog/FlClash/main/min_version.json';
const versionGateCacheTtl = Duration(hours: 6);

class VersionGatePolicy {
  const VersionGatePolicy({
    required this.minVersionCode,
    required this.latestVersion,
    required this.downloadUrl,
    required this.message,
    required this.fetchedAt,
  });

  final int minVersionCode;
  final String latestVersion;
  final String downloadUrl;
  final String message;
  final DateTime fetchedAt;

  bool isExpired({DateTime? now}) {
    final current = now ?? DateTime.now();
    return current.difference(fetchedAt) >= versionGateCacheTtl;
  }

  Map<String, Object> toJson() => {
    'minVersionCode': minVersionCode,
    'latestVersion': latestVersion,
    'downloadUrl': downloadUrl,
    'message': message,
    'fetchedAtMs': fetchedAt.millisecondsSinceEpoch,
  };

  static VersionGatePolicy? fromJson(
    Map<dynamic, dynamic>? raw, {
    DateTime? fallbackFetchedAt,
  }) {
    if (raw == null) return null;
    final minCode = (raw['minVersionCode'] as num?)?.toInt();
    if (minCode == null || minCode < 0) return null;
    final fetchedMs = (raw['fetchedAtMs'] as num?)?.toInt();
    final fetchedAt = fetchedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(fetchedMs)
        : (fallbackFetchedAt ?? DateTime.now());
    return VersionGatePolicy(
      minVersionCode: minCode,
      latestVersion: (raw['latestVersion'] as String?)?.trim() ?? '',
      downloadUrl: (raw['downloadUrl'] as String?)?.trim() ?? '',
      message: (raw['message'] as String?)?.trim() ?? '',
      fetchedAt: fetchedAt,
    );
  }

  static VersionGatePolicy? decodeCache(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  String encodeCache() => json.encode(toJson());
}

class VersionGateState {
  const VersionGateState({
    this.policy,
    this.blocked = false,
    this.checking = false,
  });

  final VersionGatePolicy? policy;
  final bool blocked;
  final bool checking;

  VersionGateState copyWith({
    VersionGatePolicy? policy,
    bool? blocked,
    bool? checking,
  }) {
    return VersionGateState(
      policy: policy ?? this.policy,
      blocked: blocked ?? this.blocked,
      checking: checking ?? this.checking,
    );
  }
}

class VersionGateEvaluator {
  const VersionGateEvaluator();

  static bool isBlocked({
    required int currentVersionCode,
    required VersionGatePolicy? policy,
  }) {
    if (policy == null ||
        policy.minVersionCode <= 0 ||
        currentVersionCode <= 0) {
      return false;
    }
    return currentVersionCode < policy.minVersionCode;
  }

  Future<VersionGatePolicy?> fetchPolicy({
    Dio? client,
    String url = versionGateManifestUrl,
    DateTime? now,
  }) async {
    final dio =
        client ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
            responseType: ResponseType.plain,
          ),
        );
    try {
      final response = await dio.get<String>(url);
      final body = response.data;
      if (body == null || body.trim().isEmpty) return null;
      final decoded = json.decode(body);
      if (decoded is! Map) return null;
      return VersionGatePolicy.fromJson(
        decoded,
        fallbackFetchedAt: now ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) {
        dio.close();
      }
    }
  }
}
