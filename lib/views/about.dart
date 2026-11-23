import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class Contributor {
  final String avatar;
  final String name;

  const Contributor({required this.avatar, required this.name});
}

class AboutView extends ConsumerWidget {
  const AboutView({super.key});

  static const _contributors = [
    Contributor(avatar: 'assets/images/avatar/june2.jpg', name: 'June2'),
    Contributor(avatar: 'assets/images/avatar/arue.jpg', name: 'Arue'),
  ];

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    if (ref.read(loadingProvider(LoadingTag.checkUpdate))) return;
    final commonAction = ref.read(commonActionProvider.notifier);
    final result = await globalState.loadingRun(
      () async => (release: await request.checkForUpdate()),
      title: context.appLocalizations.checkUpdate,
      tag: LoadingTag.checkUpdate,
    );
    if (result == null) return;
    unawaited(
      commonAction.checkUpdateResultHandle(data: result.release, isUser: true),
    );
  }

  Widget _buildLinkItem({
    required Glyph glyph,
    required String title,
    required String url,
    required String label,
  }) {
    return ListItem(
      leading: _LinkBadge(glyph: glyph),
      title: Text(title),
      subtitle: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const GlyphIcon(AppGlyphs.openExternal),
      onTap: () {
        dialogs.openUrl(url);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final isLoading = ref.watch(loadingProvider(LoadingTag.checkUpdate));
    final updateState = ref.watch(updateDownloadStateProvider);
    final commonAction = ref.read(commonActionProvider.notifier);
    return Scaffold(
      isLoading: isLoading,
      title: appLocalizations.about,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 32 + context.bottomInset,
        ),
        children: [
          _AboutHero(
            isCheckingUpdate: isLoading,
            updateState: updateState,
            onCheckUpdate: () {
              _checkUpdate(context, ref);
            },
            onCancelUpdate: commonAction.cancelUpdateDownload,
            onInstallUpdate: () {
              unawaited(commonAction.installUpdate());
            },
            onDiscardUpdate: () {
              unawaited(commonAction.discardUpdate());
            },
            onEnterDeveloperMode: () {
              ref
                  .read(appSettingProvider.notifier)
                  .update((state) => state.copyWith(developerMode: true));
              dialogs.showBanner(
                appLocalizations.developerModeEnableTip,
                level: BannerLevel.success,
              );
            },
          ),
          const SizedBox(height: 8),
          generateSection(
            title: appLocalizations.more,
            items: [
              _buildLinkItem(
                glyph: AppGlyphs.code,
                title: appLocalizations.project,
                url: 'https://github.com/$repository',
                label: 'github.com/$repository',
              ),
              _buildLinkItem(
                glyph: AppGlyphs.cpu,
                title: appLocalizations.core,
                url: 'https://github.com/chen08209/Clash.Meta/tree/FlClash',
                label: 'github.com/chen08209/Clash.Meta',
              ),
              _buildLinkItem(
                glyph: AppGlyphs.send,
                title: 'Telegram',
                url: 'https://t.me/FlClash',
                label: 't.me/FlClash',
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.otherContributors,
            items: [
              for (final contributor in _contributors)
                ListItem(
                  leading: Container(
                    width: 40,
                    height: 40,
                    foregroundDecoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: AssetImage(contributor.avatar),
                        fit: BoxFit.cover,
                      ),
                    ),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.colorScheme.primaryContainer,
                    ),
                  ),
                  title: Text(contributor.name),
                  subtitle: Text(appLocalizations.appIconDesign),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutHero extends StatelessWidget {
  final bool isCheckingUpdate;
  final UpdateDownload? updateState;
  final VoidCallback onCheckUpdate;
  final VoidCallback onCancelUpdate;
  final VoidCallback onInstallUpdate;
  final VoidCallback onDiscardUpdate;
  final VoidCallback onEnterDeveloperMode;

  const _AboutHero({
    required this.isCheckingUpdate,
    required this.updateState,
    required this.onCheckUpdate,
    required this.onCancelUpdate,
    required this.onInstallUpdate,
    required this.onDiscardUpdate,
    required this.onEnterDeveloperMode,
  });

  static const _logoSize = 96.0;
  static const _logoInset = 14.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          _DeveloperModeDetector(
            onEnterDeveloperMode: onEnterDeveloperMode,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                shape: AppShape.all(AppCorner.fit(_logoSize)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_logoInset),
                child: Image.asset(
                  'assets/images/icon.png',
                  width: _logoSize - _logoInset * 2,
                  height: _logoSize - _logoInset * 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            appName,
            style: AppTextStyle.title2.of(context, emphasized: true),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Pill(
                label: 'v${globalState.packageInfo.version}',
                color: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              _Pill(
                label: 'GPL-3.0',
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              appLocalizations.desc,
              textAlign: TextAlign.center,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (updateState) {
              null => TonalButton(
                key: const ValueKey('checkUpdateButton'),
                size: TonalButtonSize.bar,
                glyph: AppGlyphs.sync,
                label: appLocalizations.checkUpdate,
                onPressed: isCheckingUpdate ? null : onCheckUpdate,
              ),
              final state => _UpdateProgressCard(
                key: const ValueKey('updateProgressCard'),
                updateState: state,
                onCancel: onCancelUpdate,
                onInstall: onInstallUpdate,
                onDiscard: onDiscardUpdate,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _UpdateProgressCard extends StatelessWidget {
  final UpdateDownload updateState;
  final VoidCallback onCancel;
  final VoidCallback onInstall;
  final VoidCallback onDiscard;

  const _UpdateProgressCard({
    super.key,
    required this.updateState,
    required this.onCancel,
    required this.onInstall,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final currentVer = globalState.packageInfo.version;
    final targetVer = updateState.tag.replaceFirst(RegExp('^v'), '');
    final isSuccessTone =
        updateState is UpdateReady || updateState is UpdateInstalling;
    final accent = isSuccessTone ? colorScheme.success : colorScheme.primary;
    final trackColor = isSuccessTone
        ? colorScheme.successContainer
        : colorScheme.primaryContainer;
    final iconColor = isSuccessTone
        ? colorScheme.onSuccessContainer
        : colorScheme.onPrimaryContainer;
    final borderColor = isSuccessTone
        ? colorScheme.success.withValues(alpha: 0.35)
        : colorScheme.outlineVariant;

    final title = switch (updateState) {
      UpdateDownloading() => appLocalizations.downloadingUpdate,
      UpdateVerifying() => appLocalizations.updateVerifying,
      UpdateInstalling() => appLocalizations.updateInstalling,
      UpdateReady() => appLocalizations.updateReady,
    };

    final double? progress = switch (updateState) {
      UpdateDownloading(:final received, :final total) when total > 0 =>
        received / total,
      UpdateReady() => 1.0,
      _ => null,
    };

    final badge = SizedBox.square(
      dimension: 36,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: trackColor, shape: AppShape.circle),
        child: Center(
          child: switch (updateState) {
            UpdateDownloading() => GlyphIcon(
              AppGlyphs.cloudDownload,
              size: 18,
              color: iconColor,
            ),
            UpdateVerifying() ||
            UpdateInstalling() => ActivityIndicator(size: 18, color: accent),
            UpdateReady() => GlyphIcon(
              AppGlyphs.checkCircle,
              size: 18,
              fill: 1,
              color: accent,
            ),
          },
        ),
      ),
    );

    const tabular = [FontFeature.tabularFigures()];
    final detailRow = switch (updateState) {
      UpdateDownloading(
        :final received,
        :final total,
        :final speedBytesPerSec,
      ) =>
        Row(
          children: [
            Expanded(
              child: Text(
                [
                  total > 0
                      ? '${received.traffic.show} / ${total.traffic.show}'
                      : received.traffic.show,
                  if (speedBytesPerSec > 0)
                    '${speedBytesPerSec.traffic.show}/s',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFeatures: tabular,
                    ),
              ),
            ),
            if (total > 0)
              Text(
                '${(received * 100 ~/ total).clamp(0, 100)}%',
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(color: accent, fontFeatures: tabular),
              ),
          ],
        ),
      UpdateVerifying() => Text(
        appLocalizations.updateVerifyingDesc,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
      UpdateInstalling() => Text(
        appLocalizations.updateInstallingDesc,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
      UpdateReady() => Text(
        appLocalizations.updateReadyAutoCleanDesc,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    };

    final actions = switch (updateState) {
      UpdateDownloading() => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TonalButton(
            size: TonalButtonSize.compact,
            glyph: AppGlyphs.close,
            label: appLocalizations.cancel,
            onPressed: onCancel,
          ),
        ],
      ),
      UpdateReady() => Row(
        spacing: 8,
        children: [
          Expanded(
            child: FilledButton(
              style: ButtonStyle.from(
                backgroundColor: colorScheme.success,
                foregroundColor: colorScheme.onSuccess,
                minimumSize: const Size.fromHeight(40),
                tapTargetSize: TapTargetSize.shrinkWrap,
                shape: AppShape.full,
              ),
              onPressed: onInstall,
              child: Text(appLocalizations.updateInstallNow),
            ),
          ),
          TonalButton(
            size: TonalButtonSize.compact,
            glyph: AppGlyphs.delete,
            label: appLocalizations.updateDeleteFile,
            onPressed: onDiscard,
          ),
        ],
      ),
      _ => null,
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
          shape: AppShape.all(
            AppCorner.alert,
          ).copyWith(side: BorderSide(color: borderColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 12,
                children: [
                  badge,
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.headline.of(context),
                    ),
                  ),
                  _Pill(
                    label: '$currentVer → $targetVer',
                    color: trackColor,
                    foregroundColor: iconColor,
                  ),
                ],
              ),
              _UpdateProgressBar(
                value: progress,
                trackColor: trackColor,
                fillColor: accent,
              ),
              detailRow,
              ?actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateProgressBar extends StatelessWidget {
  final double? value;
  final Color trackColor;
  final Color fillColor;

  const _UpdateProgressBar({
    required this.value,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(color: trackColor),
          child: switch (value) {
            final v? => TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              tween: Tween<double>(begin: 0, end: v.clamp(0.0, 1.0)),
              builder: (context, progress, _) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: fillColor,
                      shape: AppShape.full,
                    ),
                  ),
                ),
              ),
            ),
            null => _IndeterminateProgressBar(color: fillColor),
          },
        ),
      ),
    );
  }
}

class _IndeterminateProgressBar extends StatefulWidget {
  final Color color;

  const _IndeterminateProgressBar({required this.color});

  @override
  State<_IndeterminateProgressBar> createState() =>
      _IndeterminateProgressBarState();
}

class _IndeterminateProgressBarState extends State<_IndeterminateProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(-0.4 + _controller.value * 1.8, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.38,
              heightFactor: 1,
              child: child,
            ),
          ),
        );
      },
      child: DecoratedBox(
        decoration: ShapeDecoration(color: widget.color, shape: AppShape.full),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color foregroundColor;

  const _Pill({
    required this.label,
    required this.color,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: color, shape: AppShape.full),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          label,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(color: foregroundColor),
        ),
      ),
    );
  }
}

class _LinkBadge extends StatelessWidget {
  final Glyph glyph;

  const _LinkBadge({required this.glyph});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.md,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: GlyphIcon(
            glyph,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DeveloperModeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onEnterDeveloperMode;

  const _DeveloperModeDetector({
    required this.child,
    required this.onEnterDeveloperMode,
  });

  @override
  State<_DeveloperModeDetector> createState() => _DeveloperModeDetectorState();
}

class _DeveloperModeDetectorState extends State<_DeveloperModeDetector> {
  int _counter = 0;
  Timer? _timer;

  void _handleTap() {
    _counter++;
    if (_counter >= 5) {
      widget.onEnterDeveloperMode();
      _resetCounter();
    } else {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), _resetCounter);
    }
  }

  void _resetCounter() {
    _counter = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: _handleTap, child: widget.child);
  }
}
