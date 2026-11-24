import 'dart:convert';
import 'dart:math' as math;

String dailyTrafficDayKey(DateTime date) {
  final local = date.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime? parseDailyTrafficDayKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

class DailyTrafficDay {
  const DailyTrafficDay({
    required this.dayKey,
    required this.up,
    required this.down,
  });

  final String dayKey;
  final int up;
  final int down;

  int get total => up + down;

  DailyTrafficDay add(int upDelta, int downDelta) {
    return DailyTrafficDay(
      dayKey: dayKey,
      up: up + math.max(0, upDelta),
      down: down + math.max(0, downDelta),
    );
  }

  Map<String, Object> toJson() => {'u': up, 'd': down};

  static DailyTrafficDay? fromJson(String key, Object? raw) {
    if (parseDailyTrafficDayKey(key) == null || raw is! Map) return null;
    final up = (raw['u'] as num?)?.toInt();
    final down = (raw['d'] as num?)?.toInt();
    if (up == null || down == null || up < 0 || down < 0) return null;
    return DailyTrafficDay(dayKey: key, up: up, down: down);
  }
}

class DailyTrafficLedger {
  const DailyTrafficLedger({this.days = const {}});

  static const maxRetentionDays = 400;

  final Map<String, DailyTrafficDay> days;

  DailyTrafficLedger recordDelta({
    required int upDelta,
    required int downDelta,
    DateTime? now,
  }) {
    final safeUp = math.max(0, upDelta);
    final safeDown = math.max(0, downDelta);
    if (safeUp == 0 && safeDown == 0) return this;
    final ref = (now ?? DateTime.now()).toLocal();
    final key = dailyTrafficDayKey(ref);
    final existing = days[key] ?? DailyTrafficDay(dayKey: key, up: 0, down: 0);
    final updated = Map<String, DailyTrafficDay>.from(days)
      ..[key] = existing.add(safeUp, safeDown);
    return DailyTrafficLedger(days: _prune(updated, ref));
  }

  DailyTrafficDay today({DateTime? now}) {
    final key = dailyTrafficDayKey((now ?? DateTime.now()).toLocal());
    return days[key] ?? DailyTrafficDay(dayKey: key, up: 0, down: 0);
  }

  ({int up, int down, int total}) sumDays(int dayCount, {DateTime? now}) {
    var up = 0;
    var down = 0;
    for (final day in recentDays(dayCount, now: now)) {
      up += day.up;
      down += day.down;
    }
    return (up: up, down: down, total: up + down);
  }

  List<DailyTrafficDay> recentDays(int dayCount, {DateTime? now}) {
    if (dayCount <= 0) return const [];
    final ref = (now ?? DateTime.now()).toLocal();
    final anchor = DateTime(ref.year, ref.month, ref.day);
    return List.generate(dayCount, (index) {
      final offset = dayCount - 1 - index;
      final date = anchor.subtract(Duration(days: offset));
      final key = dailyTrafficDayKey(date);
      return days[key] ?? DailyTrafficDay(dayKey: key, up: 0, down: 0);
    });
  }

  String encode() {
    return json.encode({
      'v': 1,
      'days': {
        for (final entry in days.entries) entry.key: entry.value.toJson(),
      },
    });
  }

  static DailyTrafficLedger decode(String? raw, {DateTime? now}) {
    if (raw == null || raw.trim().isEmpty) {
      return const DailyTrafficLedger();
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return const DailyTrafficLedger();
      final rawDays = decoded['days'];
      if (rawDays is! Map) return const DailyTrafficLedger();
      final parsed = <String, DailyTrafficDay>{};
      for (final entry in rawDays.entries) {
        final key = entry.key?.toString();
        if (key == null) continue;
        final day = DailyTrafficDay.fromJson(key, entry.value);
        if (day != null) parsed[key] = day;
      }
      final ref = (now ?? DateTime.now()).toLocal();
      return DailyTrafficLedger(days: _prune(parsed, ref));
    } catch (_) {
      return const DailyTrafficLedger();
    }
  }

  static Map<String, DailyTrafficDay> _prune(
    Map<String, DailyTrafficDay> source,
    DateTime reference,
  ) {
    final anchor = DateTime(reference.year, reference.month, reference.day);
    final cutoff = anchor.subtract(const Duration(days: maxRetentionDays - 1));
    final kept = <String, DailyTrafficDay>{};
    for (final entry in source.entries) {
      final parsed = parseDailyTrafficDayKey(entry.key);
      if (parsed == null) continue;
      if (!parsed.isBefore(cutoff)) {
        kept[entry.key] = entry.value;
      }
    }
    return Map.unmodifiable(kept);
  }
}
