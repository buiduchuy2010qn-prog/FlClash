import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showPortalConnectSheet(BuildContext context, Profile profile) {
  return showFormSheet<void>(
    context: context,
    builder: (_) => _PlanPortalConnectSheet(profile: profile),
  );
}

class _PlanPortalConnectSheet extends ConsumerStatefulWidget {
  const _PlanPortalConnectSheet({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_PlanPortalConnectSheet> createState() =>
      _PlanPortalConnectSheetState();
}

class _PlanPortalConnectSheetState
    extends ConsumerState<_PlanPortalConnectSheet> {
  late final TextEditingController _originController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _saving = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final binding = ref.read(portalAccountsProvider)[widget.profile.id];
    final deviceMeta = ref.read(
      effectiveProfileDeviceMetaProvider(widget.profile.id),
    );
    final initialOrigin =
        binding?.origin ??
        derivePortalOrigin(deviceMeta?.portalUrl) ??
        derivePortalOrigin(widget.profile.url) ??
        '';
    _originController = TextEditingController(text: initialOrigin);
    _emailController = TextEditingController(text: binding?.email ?? '');
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _originController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validate(AppLocalizations l) {
    final origin = _originController.text.trim();
    if (derivePortalOrigin(origin) == null) {
      return l.portalInvalidUrl;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return l.portalInvalidEmail;
    }
    if (_passwordController.text.isEmpty) {
      return l.emptyTip(l.portalPasswordLabel);
    }
    return null;
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    final l = context.appLocalizations;
    final issue = _validate(l);
    if (issue != null) {
      setState(() => _submitError = issue);
      return;
    }
    setState(() {
      _saving = true;
      _submitError = null;
    });
    try {
      await ref
          .read(profilesActionProvider.notifier)
          .connectPortalAccount(
            profile: widget.profile,
            origin: _originController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;
      dialogs.showBanner(l.portalConnectedTip, level: BannerLevel.success);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submitError = userFacingErrorMessage(error, l);
      });
    }
  }

  Future<void> _handleDisconnect() async {
    if (_saving) return;
    final l = context.appLocalizations;
    ref
        .read(profilesActionProvider.notifier)
        .disconnectPortalAccount(widget.profile.id);
    if (!mounted) return;
    dialogs.showBanner(l.portalDisconnectedTip);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final binding = ref.watch(
      portalAccountsProvider.select((s) => s[widget.profile.id]),
    );
    return FormPage(
      title: l.portalAccountSync,
      onSave: () => unawaited(_handleSave()),
      saving: _saving,
      error: _submitError,
      children: [
        generateSection(
          footer: l.portalSecurityFooter,
          items: [
            FormRow(
              title: l.portalOriginLabel,
              trailing: FormRowTextField(
                controller: _originController,
                hintText: 'https://example.com',
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _submitError = null),
              ),
            ),
            FormRow(
              title: l.portalEmailLabel,
              trailing: FormRowTextField(
                controller: _emailController,
                hintText: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _submitError = null),
              ),
            ),
            FormRow(
              title: l.portalPasswordLabel,
              trailing: FormRowSecretTextField(
                controller: _passwordController,
                hintText: l.required,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _submitError = null),
                onFieldSubmitted: (_) => unawaited(_handleSave()),
              ),
            ),
          ],
        ),
        if (binding != null)
          generateSection(
            items: [
              FormRow(
                title: l.portalDisconnect,
                titleStyle: TextStyle(color: context.colorScheme.error),
                onPressed: _saving
                    ? null
                    : () => unawaited(_handleDisconnect()),
              ),
            ],
          ),
      ],
    );
  }
}
