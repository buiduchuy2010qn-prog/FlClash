import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionGateOverlay extends ConsumerWidget {
  const VersionGateOverlay({super.key, required this.child});

  final Widget child;

  Future<void> _openDownload(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      final opened = await launchUrl(uri);
      if (opened) return;
    }
    await openReleasePage();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(versionGateProvider);
    if (!gate.blocked) {
      return child;
    }
    final policy = gate.policy;
    final l = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final customMessage = policy?.message ?? '';
    final description = customMessage.isNotEmpty
        ? customMessage
        : l.versionGateDefaultDesc;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ColoredBox(
            color: colorScheme.surface,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: ShapeDecoration(
                        color: colorScheme.surface,
                        shape: AppShape.all(24).copyWith(
                          side: BorderSide(color: colorScheme.outlineVariant),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 16,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: GlyphIcon(
                              AppGlyphs.warning,
                              size: 42,
                              color: colorScheme.error,
                            ),
                          ),
                          Text(
                            l.versionGateTitle,
                            textAlign: TextAlign.center,
                            style: AppTextStyle.title2.of(context),
                          ),
                          Text(
                            description,
                            textAlign: TextAlign.center,
                            style: AppTextStyle.subheadline
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          if (policy != null && policy.latestVersion.isNotEmpty)
                            Text(
                              'v${policy.latestVersion}',
                              textAlign: TextAlign.center,
                              style: AppTextStyle.footnote
                                  .of(context, emphasized: true)
                                  .copyWith(color: colorScheme.primary),
                            ),
                          FilledButton(
                            onPressed: () =>
                                unawaited(_openDownload(policy?.downloadUrl ?? '')),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              spacing: 8,
                              children: [
                                const GlyphIcon(
                                  AppGlyphs.cloudDownload,
                                  fill: 1,
                                ),
                                Text(l.versionGateDownload),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: gate.checking
                                ? null
                                : () => unawaited(
                                    ref
                                        .read(versionGateProvider.notifier)
                                        .checkNow(),
                                  ),
                            child: Text(l.versionGateRetry),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
