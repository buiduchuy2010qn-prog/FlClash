import 'package:fl_clash/common/daily_traffic_store.dart';
import 'package:test/test.dart';

void main() {
  group('DailyTrafficLedger', () {
    test('accumulates per-day traffic and summarizes 7/30 day windows', () {
      final day1 = DateTime(2026, 11, 1);
      final day5 = DateTime(2026, 11, 5);
      final day10 = DateTime(2026, 11, 10);

      var ledger = const DailyTrafficLedger();
      ledger = ledger.recordDelta(upDelta: 100, downDelta: 400, now: day1);
      ledger = ledger.recordDelta(upDelta: 200, downDelta: 300, now: day5);
      ledger = ledger.recordDelta(upDelta: 50, downDelta: 150, now: day10);
      ledger = ledger.recordDelta(upDelta: 25, downDelta: 75, now: day10);

      final today = ledger.today(now: day10);
      expect(today.up, 75);
      expect(today.down, 225);
      expect(today.total, 300);

      final sevenDay = ledger.sumDays(7, now: day10);
      expect(sevenDay.up, 275);
      expect(sevenDay.down, 525);
      expect(sevenDay.total, 800);

      final thirtyDay = ledger.sumDays(30, now: day10);
      expect(thirtyDay.total, 1300);
      expect(ledger.recentDays(7, now: day10), hasLength(7));
    });

    test('prunes entries older than 400 days', () {
      final today = DateTime(2026, 11, 24);
      final oldestKept = today.subtract(const Duration(days: 399));
      final expired = today.subtract(const Duration(days: 400));

      var ledger = const DailyTrafficLedger();
      ledger = ledger.recordDelta(upDelta: 10, downDelta: 20, now: expired);
      ledger = ledger.recordDelta(upDelta: 30, downDelta: 40, now: oldestKept);
      ledger = ledger.recordDelta(upDelta: 50, downDelta: 60, now: today);

      expect(ledger.days.containsKey(dailyTrafficDayKey(expired)), isFalse);
      expect(ledger.days.containsKey(dailyTrafficDayKey(oldestKept)), isTrue);
      expect(ledger.days.containsKey(dailyTrafficDayKey(today)), isTrue);
    });

    test('encodes and decodes safely and handles corrupted JSON', () {
      final now = DateTime(2026, 11, 24);
      final ledger = const DailyTrafficLedger().recordDelta(
        upDelta: 1024,
        downDelta: 2048,
        now: now,
      );

      final decoded = DailyTrafficLedger.decode(ledger.encode(), now: now);
      expect(decoded.today(now: now).total, 3072);

      expect(DailyTrafficLedger.decode(null, now: now).days, isEmpty);
      expect(DailyTrafficLedger.decode('{not-json', now: now).days, isEmpty);
    });
  });
}
