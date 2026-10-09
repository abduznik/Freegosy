import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/update/update_models.dart';
import '../../providers/update_provider.dart';
import '../widgets/focus_effect_wrapper.dart';
import 'settings_display_section.dart' show buildCustomDropdown, buildCustomToggleRow;

/// Body of the "Updates" settings card: launch-check / auto-download toggles,
/// release channel, a check button and the current update status.
class SettingsUpdateSection extends ConsumerWidget {
  const SettingsUpdateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final channel = UpdateChannel.parse(ref.watch(updateChannelProvider));
    final manualInstall = ref.watch(updateServiceProvider).installKind == InstallKind.manual;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Installed: v${AppConstants.version}',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        buildCustomToggleRow(
          context,
          title: 'Check for updates on launch',
          subtitle: 'Looks for a newer release each time Freegosy starts.',
          value: ref.watch(updateCheckOnLaunchProvider),
          onChanged: (v) => ref.read(updateCheckOnLaunchProvider.notifier).update(v),
        ),
        const SizedBox(height: 8),
        buildCustomToggleRow(
          context,
          title: 'Download updates automatically',
          subtitle: manualInstall
              ? 'Not available for this install type; updates open the release page.'
              : 'Fetches a new version in the background, then asks you to restart.',
          value: ref.watch(updateAutoDownloadProvider) && !manualInstall,
          onChanged: (v) {
            if (!manualInstall) ref.read(updateAutoDownloadProvider.notifier).update(v);
          },
        ),
        const SizedBox(height: 8),
        buildCustomDropdown<UpdateChannel>(
          context: context,
          label: 'Release channel',
          currentValue: channel,
          currentValueLabel: channel.label,
          items: [for (final c in UpdateChannel.values) {'value': c, 'label': c.label}],
          onChanged: (c) => ref.read(updateChannelProvider.notifier).update(c.name),
        ),
        const SizedBox(height: 16),
        _status(context, ref, state, manualInstall),
        const SizedBox(height: 12),
        _actions(context, state, controller, manualInstall),
      ],
    );
  }

  Widget _status(BuildContext context, WidgetRef ref, UpdateState state, bool manualInstall) {
    final theme = Theme.of(context);
    final info = state.info;
    String text;
    switch (state.status) {
      case UpdateStatus.idle:
        text = 'Not checked yet.';
      case UpdateStatus.checking:
        text = 'Checking for updates…';
      case UpdateStatus.upToDate:
        text = 'You are up to date.';
      case UpdateStatus.available:
        text = 'Version ${info?.version}${info?.isRebuild == true ? ' (updated build)' : ''} is available${manualInstall ? '.' : ' to download.'}';
      case UpdateStatus.downloading:
        text = 'Downloading version ${info?.version}… ${(state.progress * 100).round()}%';
      case UpdateStatus.ready:
        text = 'Version ${info?.version} is ready. Restart to finish updating.';
      case UpdateStatus.applying:
        text = 'Installing update…';
      case UpdateStatus.error:
        text = 'Update failed: ${state.error}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: state.status == UpdateStatus.error ? theme.colorScheme.error : theme.colorScheme.onSurface,
          ),
        ),
        if (state.status == UpdateStatus.downloading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.progress > 0 ? state.progress : null),
        ],
      ],
    );
  }

  Widget _actions(BuildContext context, UpdateState state, UpdateController controller, bool manualInstall) {
    final busy = state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.applying;
    final info = state.info;
    final children = <Widget>[
      _button(context, Icons.refresh, 'Check for updates', busy ? null : () => controller.check(manual: true)),
    ];
    if (state.status == UpdateStatus.ready) {
      children.add(_button(context, Icons.restart_alt, 'Restart to update', controller.restartToUpdate, primary: true));
    } else if (info != null && (state.status == UpdateStatus.available || state.status == UpdateStatus.error)) {
      if (manualInstall || !info.hasAsset) {
        children.add(_button(context, Icons.open_in_new, 'Open release page',
            () => launchUrl(Uri.parse(info.pageUrl), mode: LaunchMode.externalApplication), primary: true));
      } else if (!busy) {
        children.add(_button(context, Icons.download, 'Download v${info.version}', controller.download, primary: true));
      }
    }
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }

  Widget _button(BuildContext context, IconData icon, String label, VoidCallback? onTap, {bool primary = false}) {
    final theme = Theme.of(context);
    final fg = primary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: FocusEffectWrapper(
        onTap: onTap,
        borderRadius: 16.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: primary ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
