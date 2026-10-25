import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/brand_mark.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../data/models/local_account.dart';
import '../../state/local_account_controller.dart';
import '../../state/ui_state.dart';
import '../../app/nav.dart';

/// Opens the profile switcher. The account list is always remembered; signing
/// out only returns to the picker, it never deletes a ledger.
Future<void> showLocalAccountSwitcher(BuildContext context) {
  return showAppSheet<void>(
    context,
    (sheetContext) => const _LocalAccountSheet(),
    maxWidth: 560,
  );
}

/// Shown at launch and after signing out of the current local profile.
class LocalAccountGate extends ConsumerWidget {
  const LocalAccountGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final local = ref.watch(localAccountProvider);
    if (local == null) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: CanvasWash(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(size: 42, showWordmark: true)),
                  const SizedBox(height: AppSpace.x3),
                  Text(
                    'Choose a ledger',
                    textAlign: TextAlign.center,
                    style: AppText.displayM.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Each local account keeps its own tasks, journal, backups, '
                    'and Google Drive link on this device. Nothing is uploaded '
                    'unless you connect a Drive account inside that profile.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkMuted,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  for (final account in local.accounts)
                    _GateAccountRow(
                      account: account,
                      current: account.id == local.active.id,
                      onOpen: () => _open(context, ref, account.id),
                    ),
                  const SizedBox(height: AppSpace.lg),
                  OutlinedButton.icon(
                    onPressed: () => _create(context, ref),
                    icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                    label: const Text('New local account'),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    'Local accounts are profiles, not a password lock. Use your '
                    'operating system account lock if you need security.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Future<void> _open(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(localAccountProvider.notifier).switchTo(id);
      ref.read(navIndexProvider.notifier).state = NavTarget.today;
    } catch (error) {
      if (context.mounted) showToast(context, '$error');
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _askAccountName(context);
    if (name == null || !context.mounted) return;
    try {
      await ref.read(localAccountProvider.notifier).createAccount(name);
      ref.read(navIndexProvider.notifier).state = NavTarget.today;
    } catch (error) {
      if (context.mounted) showToast(context, '$error');
    }
  }
}

class LocalAccountCard extends ConsumerStatefulWidget {
  const LocalAccountCard({super.key});

  @override
  ConsumerState<LocalAccountCard> createState() => _LocalAccountCardState();
}

class _LocalAccountCardState extends ConsumerState<LocalAccountCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final local = ref.watch(localAccountProvider);
    if (local == null) return const SizedBox.shrink();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(
                  Icons.account_circle_outlined,
                  size: 18,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local account',
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${local.accounts.length} '
                      '${local.accounts.length == 1 ? 'profile' : 'profiles'} '
                      'on this device',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: colors.surfaceSunken.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                _AccountAvatar(account: local.active, active: true),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        local.active.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyMedium.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Active ledger · local only',
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkFaint,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => showLocalAccountSwitcher(context),
                icon: const Icon(Icons.switch_account_rounded, size: 17),
                label: const Text('Switch account'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.person_add_alt_rounded, size: 17),
                label: const Text('Add local account'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _signOut,
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign out'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Google Drive is connected inside each local account, so one '
            'profile never sees another profile’s cloud files.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.3,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final name = await _askAccountName(context);
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(localAccountProvider.notifier).createAccount(name);
      ref.read(navIndexProvider.notifier).state = NavTarget.today;
      if (mounted) showToast(context, 'Local account “$name” created');
    } catch (error) {
      if (mounted) showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out of this local account?',
      message:
          'Your ledger stays on this device and remains in the account picker. '
          'Google Drive links stay with this local account.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    await ref.read(localAccountProvider.notifier).signOut();
  }
}

class _LocalAccountSheet extends ConsumerStatefulWidget {
  const _LocalAccountSheet();

  @override
  ConsumerState<_LocalAccountSheet> createState() => _LocalAccountSheetState();
}

class _LocalAccountSheetState extends ConsumerState<_LocalAccountSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localAccountProvider);
    if (local == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('No local accounts')),
      );
    }
    return AppSheet(
      title: 'Local accounts',
      subtitle:
          'Switch profiles without losing anything. Every ledger and Google '
          'link is remembered locally.',
      icon: Icons.switch_account_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final account in local.accounts)
            _SwitchAccountRow(
              account: account,
              current: account.id == local.active.id,
              busy: _busy,
              onOpen: () => _open(account.id),
            ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.person_add_alt_rounded, size: 18),
            label: const Text('New local account'),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout_rounded, size: 17),
            label: const Text('Sign out to the account picker'),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Each local account opens its own SQLite ledger and its own cloud '
            'folder. Switching closes the previous ledger after in-flight work '
            'settles.',
            style: AppText.bodySmall.copyWith(
              color: context.colors.inkFaint,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(String id) async {
    final local = ref.read(localAccountProvider);
    if (local != null && id == local.active.id && local.signedIn) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(localAccountProvider.notifier).switchTo(id);
      ref.read(navIndexProvider.notifier).state = NavTarget.today;
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = await _askAccountName(context);
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(localAccountProvider.notifier).createAccount(name);
      ref.read(navIndexProvider.notifier).state = NavTarget.today;
      if (mounted) {
        Navigator.of(context).maybePop();
        showToast(context, 'Local account “$name” created');
      }
    } catch (error) {
      if (mounted) showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    Navigator.of(context).maybePop();
    await ref.read(localAccountProvider.notifier).signOut();
  }
}

class _GateAccountRow extends StatelessWidget {
  const _GateAccountRow({
    required this.account,
    required this.current,
    required this.onOpen,
  });

  final LocalAccount account;
  final bool current;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: current
            ? colors.primarySoft.withValues(alpha: 0.45)
            : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: current ? colors.primary.withValues(alpha: 0.35) : colors.line,
        ),
      ),
      child: Row(
        children: [
          _AccountAvatar(account: account, active: current),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyMedium.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  current ? 'Last used ledger' : 'Local ledger',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onOpen,
            child: Text(current ? 'Continue' : 'Open'),
          ),
        ],
      ),
    );
  }
}

class _SwitchAccountRow extends StatelessWidget {
  const _SwitchAccountRow({
    required this.account,
    required this.current,
    required this.busy,
    required this.onOpen,
  });

  final LocalAccount account;
  final bool current;
  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: current
            ? colors.primarySoft.withValues(alpha: 0.5)
            : colors.surfaceSunken.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: current ? colors.primary.withValues(alpha: 0.35) : colors.line,
        ),
      ),
      child: Row(
        children: [
          _AccountAvatar(account: account, active: current),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  current ? 'Active ledger' : 'Remembered on this device',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (current)
            Text(
              'CURRENT',
              style: AppText.label.copyWith(color: colors.primary, fontSize: 8),
            )
          else
            TextButton(
              onPressed: busy ? null : onOpen,
              child: const Text('Open'),
            ),
        ],
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account, required this.active});

  final LocalAccount account;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active ? colors.primary : colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.line),
      ),
      child: Center(
        child: Text(
          account.initial,
          style: AppText.bodyMedium.copyWith(
            color: active ? colors.onPrimary : colors.inkMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

Future<String?> _askAccountName(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('New local account'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Account name',
          hintText: 'Work, Personal, Studio…',
        ),
        onSubmitted: (value) {
          final clean = value.trim();
          if (clean.isNotEmpty) Navigator.of(dialogContext).pop(clean);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final clean = controller.text.trim();
            if (clean.isNotEmpty) Navigator.of(dialogContext).pop(clean);
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
