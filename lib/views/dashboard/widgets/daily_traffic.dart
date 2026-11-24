import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/daily_traffic_store.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

enum _TrafficWindow {
  today(1),
  week(7),
  month(30);

  const _TrafficWindow(this.days);
  final int days;
}

class DailyTrafficCard extends ConsumerStatefulWidget {
  const DailyTrafficCard({super.key});

  @override
  ConsumerState<DailyTrafficCard> createState() => _DailyTrafficCardState();
}

class _DailyTrafficCardState extends ConsumerState<DailyTrafficCard> {
  static const _outer = 18.0;
  var _window = _TrafficWindow.today;

  String _windowLabel(BuildContext context, _TrafficWindow window) {
    final l = context.appLocalizations;
    return switch (window) {
      _TrafficWindow.today => l.dailyTrafficToday,
      _TrafficWindow.week => l.dailyTraffic7Days,
      _TrafficWindow.month => l.dailyTraffic30Days,
    };
  }

  Future<void> _confirmClear() async {
    final l = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      title: l.clearDailyTraffic,
      message: TextSpan(text: l.clearDailyTrafficConfirm),
      confirmText: l.clearDailyTraffic,
      destructive: true,
    );
    if (confirmed == true && mounted) {
      ref.read(dailyTrafficProvider.notifier).clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final ledger = ref.watch(dailyTrafficProvider);
    final colors = DashboardColors.of(context);
    final colorScheme = context.colorScheme;

    final summary = switch (_window) {
      _TrafficWindow.today => ledger.today(),
      _ => null,
    };
    final windowSum = summary != null
        ? (up: summary.up, down: summary.down, total: summary.total)
        : ledger.sumDays(_window.days);
    final chartDays = ledger.recentDays(
      _window == _TrafficWindow.today ? 7 : _window.days,
    );

    return DashboardCard(
      semanticLabel: l.dailyTraffic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: l.dailyTraffic,
            trailing: [
              DashboardIconButton(
                glyph: AppGlyphs.delete,
                tooltip: l.clearDailyTraffic,
                onPressed: _confirmClear,
              ),
            ],
          ),
          const SizedBox(height: 10),
          DashboardConnectedGroup(
            children: [
              for (final (index, item) in _TrafficWindow.values.indexed)
                Expanded(
                  child: DashboardConnectedButton(
                    selected: item == _window,
                    first: index == 0,
                    last: index == _TrafficWindow.values.length - 1,
                    outer: _outer,
                    inner: 8,
                    background: colors.tone,
                    semanticLabel: _windowLabel(context, item),
                    onTap: () => setState(() => _window = item),
                    builder: (foreground) => SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          _windowLabel(context, item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.footnote
                              .of(context, emphasized: true)
                              .copyWith(color: foreground),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DashboardFitText(
            dashboardTraffic(windowSum.total),
            style: DashboardText.figure(context, AppTextStyle.title2),
          ),
          const SizedBox(height: 6),
          Row(
            spacing: 12,
            children: [
              _TrafficDirectionStat(
                glyph: AppGlyphs.arrowUp,
                label: dashboardTraffic(windowSum.up),
              ),
              _TrafficDirectionStat(
                glyph: AppGlyphs.arrowDown,
                label: dashboardTraffic(windowSum.down),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: CustomPaint(
              painter: _DailyTrafficBarPainter(
                days: chartDays,
                highlightLast: _window == _TrafficWindow.today,
                activeColor: colorScheme.primary,
                mutedColor: colors.tone2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficDirectionStat extends StatelessWidget {
  const _TrafficDirectionStat({required this.glyph, required this.label});

  final Glyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        GlyphIcon(glyph, size: 14, color: color),
        Text(
          label,
          maxLines: 1,
          style: AppTextStyle.footnote.of(context).copyWith(color: color),
        ),
      ],
    );
  }
}

class _DailyTrafficBarPainter extends CustomPainter {
  const _DailyTrafficBarPainter({
    required this.days,
    required this.highlightLast,
    required this.activeColor,
    required this.mutedColor,
  });

  final List<DailyTrafficDay> days;
  final bool highlightLast;
  final Color activeColor;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || size.width <= 0 || size.height <= 0) return;
    final count = days.length;
    final maxTotal = days.fold<int>(0, (prev, d) => math.max(prev, d.total));
    final slotWidth = size.width / count;
    final gap = math.min(4.0, slotWidth * 0.25);
    final barWidth = math.max(1.5, slotWidth - gap);
    final activePaint = Paint()..color = activeColor;
    final mutedPaint = Paint()..color = mutedColor;

    for (var i = 0; i < count; i++) {
      final value = days[i].total;
      final ratio = maxTotal > 0 ? value / maxTotal : 0.0;
      final barHeight = value > 0
          ? math.max(3.0, ratio * size.height)
          : 2.0;
      final left = i * slotWidth + (slotWidth - barWidth) / 2;
      final top = size.height - barHeight;
      final isHighlighted = value > 0 && (!highlightLast || i == count - 1);
      canvas.drawRect(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        isHighlighted ? activePaint : mutedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DailyTrafficBarPainter oldDelegate) {
    return oldDelegate.days != days ||
        oldDelegate.highlightLast != highlightLast ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.mutedColor != mutedColor;
  }
}
