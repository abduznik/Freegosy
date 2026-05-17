import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/storage/directory_service.dart';
import '../../core/storage/system_utils.dart';
import '../../core/emulator/emulator_registry_data.dart';
import '../../core/emulator/strategy_registry.dart';
import '../../core/emulator/firmware_service.dart';
import '../../ui/widgets/emulator_selection_dialog.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';
import '../widgets/focus_effect_wrapper.dart';

Widget _buildActionButton(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
  bool isPrimary = false,
  bool isDestructive = false,
}) {
  final theme = Theme.of(context);
  return FocusEffectWrapper(
    onTap: onTap,
    borderRadius: 12.0,
    scaleFactor: 1.05,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: isPrimary
            ? LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isPrimary
            ? null
            : (isDestructive
                ? Colors.red.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
        border: Border.all(
          color: isPrimary
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : (isDestructive
                  ? Colors.red.withValues(alpha: 0.2)
                  : theme.colorScheme.outline.withValues(alpha: 0.3)),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isPrimary
                ? theme.colorScheme.onPrimary
                : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isPrimary
                  ? theme.colorScheme.onPrimary
                  : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildActionIconButton(
  BuildContext context, {
  required IconData icon,
  required String tooltip,
  required VoidCallback onTap,
  Color? color,
}) {
  final theme = Theme.of(context);
  return FocusEffectWrapper(
    onTap: onTap,
    borderRadius: 10.0,
    scaleFactor: 1.15,
    child: Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: (color ?? theme.colorScheme.primary).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: (color ?? theme.colorScheme.primary).withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
      ),
    ),
  );
}

Widget buildEmulatorsSection(
  BuildContext context,
  DirectoryService directoryService,
  bool emulatorsLoaded,
  Map<String, bool> emulatorInstallStates,
  Function(void Function()) setState,
  WidgetRef ref,
) {
  final theme = Theme.of(context);
  final currentPlatform = defaultTargetPlatform == TargetPlatform.windows 
      ? 'windows' 
      : (defaultTargetPlatform == TargetPlatform.macOS ? 'macos' : 'linux');

  final supportedEmulators = kEmulatorDefinitions.where((def) {
    final supported = def['supported_platforms'] as List<String>? ?? [];
    return supported.contains(currentPlatform);
  }).toList();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Emulators',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Row(
            children: [
              _buildActionIconButton(
                context,
                icon: Icons.refresh,
                tooltip: 'Refresh Status',
                onTap: () {
                  ref.invalidate(emulatorStatusProvider);
                },
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                context,
                icon: Icons.sync,
                label: 'Sync BIOS',
                onTap: () => _syncAllBios(context, ref),
                isPrimary: true,
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (!emulatorsLoaded)
        const Center(child: CircularProgressIndicator())
      else
        ...supportedEmulators.map<Widget>((def) {
          final emulatorId = def['id'] as String;
          final emulatorName = def['name'] as String;
          final isInstalled = emulatorInstallStates[emulatorId] ?? false;
          final overridePath = directoryService.getEmulatorPathOverride(emulatorId);
          final type = def['type'] as String? ?? 'none';
          final canManage = type != 'none';

          return Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isInstalled
                        ? Colors.green.withValues(alpha: 0.12)
                        : theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isInstalled
                          ? Colors.green.withValues(alpha: 0.3)
                          : theme.colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isInstalled ? Icons.check_circle_outline : Icons.cancel_outlined,
                        color: isInstalled ? Colors.green : theme.colorScheme.error,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isInstalled ? 'Installed' : 'Missing',
                        style: TextStyle(
                          color: isInstalled ? Colors.green : theme.colorScheme.error,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emulatorName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (overridePath != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            overridePath,
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (emulatorId == 'rpcs3' && defaultTargetPlatform == TargetPlatform.macOS) ...[
                  const Text('Arch: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Consumer(
                    builder: (context, ref, child) {
                      final arch = ref.watch(rpcs3ArchitectureProvider);
                      return DropdownButton<String>(
                        value: arch,
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'x64', child: Text('x64')),
                          DropdownMenuItem(value: 'arm64', child: Text('ARM64')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(rpcs3ArchitectureProvider.notifier).update(value);
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isInstalled) ...[
                      _buildActionIconButton(
                        context,
                        icon: Icons.play_arrow,
                        tooltip: 'Launch Standalone',
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final strategy = ref
                              .read(strategyRegistryProvider)
                              .asData
                              ?.value
                              ?.getStrategyById(emulatorId);
                          if (strategy != null) {
                            try {
                              await strategy.launchStandalone();
                            } catch (e) {
                              messenger.showSnackBar(
                                  SnackBar(content: Text("Failed to launch: $e")));
                            }
                          }
                        },
                        color: Colors.green,
                      ),
                      const SizedBox(width: 6),
                      _buildActionIconButton(
                        context,
                        icon: Icons.library_books,
                        tooltip: 'Sync BIOS',
                        onTap: () async {
                          _syncBiosForEmulator(context, ref, emulatorId, emulatorName);
                        },
                      ),
                      if (canManage) ...[
                        const SizedBox(width: 6),
                        _buildActionIconButton(
                          context,
                          icon: Icons.update,
                          tooltip: 'Update',
                          onTap: () async {
                            _startDownload(context, ref, emulatorId, emulatorName, emulatorInstallStates, setState);
                          },
                          color: Colors.blue,
                        ),
                      ],
                    ],
                    if (!isInstalled && canManage) ...[
                      _buildActionButton(
                        context,
                        icon: Icons.download,
                        label: 'Download',
                        onTap: () => _startDownload(context, ref, emulatorId, emulatorName, emulatorInstallStates, setState),
                        isPrimary: true,
                      ),
                    ],
                    const SizedBox(width: 6),
                    Theme(
                      data: theme.copyWith(
                        cardColor: theme.colorScheme.surfaceContainer,
                      ),
                      child: PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurfaceVariant),
                        onSelected: (val) async {
                          if (val == 'custom_dir') {
                            String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                            if (selectedDirectory != null) {
                              await directoryService.setEmulatorPathOverride(emulatorId, selectedDirectory);
                              setState(() {});
                            }
                          } else if (val == 'open_folder') {
                            final path = await directoryService.getEmulatorDirectory(emulatorId);
                            await SystemUtils.openDirectory(path);
                          } else if (val == 'url_override') {
                            _showUrlOverrideDialog(context, ref, directoryService, emulatorId, type);
                          } else if (val == 'uninstall') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                title: const Text("Uninstall Emulator"),
                                content: Text("Are you sure you want to delete $emulatorName? This will remove all local files."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                  TextButton(
                                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text("Uninstall"),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await directoryService.deleteEmulator(emulatorId);
                              ref.invalidate(emulatorStatusProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("$emulatorName uninstalled.")),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'custom_dir',
                            child: Row(
                              children: [
                                Icon(Icons.folder_open, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                const Text('Set Custom Directory', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'open_folder',
                            child: Row(
                              children: [
                                Icon(Icons.folder_shared, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                const Text('Open Emulator Folder', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'url_override',
                            child: Row(
                              children: [
                                Icon(Icons.link, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                const Text('Download URL Override', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          if (isInstalled && canManage)
                            PopupMenuItem(
                              value: 'uninstall',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 16, color: theme.colorScheme.error),
                                  const SizedBox(width: 8),
                                  Text('Uninstall', style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
    ],
  );
}

Future<void> _startDownload(
  BuildContext context,
  WidgetRef ref,
  String emulatorId,
  String emulatorName,
  Map<String, bool> emulatorInstallStates,
  Function(void Function()) setState, {
  String? urlOverride,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  String? architecture;
  String? buildType;

  if (urlOverride == null) {
    if (emulatorId == 'rpcs3' && defaultTargetPlatform == TargetPlatform.macOS) {
      architecture = ref.read(rpcs3ArchitectureProvider);
    }

    if (emulatorId == 'eden') {
      if (!context.mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("Select Eden Build"),
          content: const Text("Choose which version of Eden to install:"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'nightly'),
              child: const Text("Nightly (Experimental)"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'stable'),
              child: const Text("Stable (Recommended)"),
            ),
          ],
        ),
      );

      if (choice == null) return;
      buildType = choice;
      ref.read(edenBuildTypeProvider.notifier).update(buildType);
    }
  }

  final String buildLabel = (buildType != null && buildType != 'stable') ? " ($buildType)" : "";
  if (urlOverride == null) {
    messenger.showSnackBar(SnackBar(
      content: Text('Starting download for $emulatorName${architecture != null ? " ($architecture)" : ""}$buildLabel...'),
    ));
  }

  ref.read(downloadProvider.notifier).startEmulatorDownload(
    emulatorId, 
    emulatorName,
    architecture: architecture,
    buildType: buildType,
    urlOverride: urlOverride,
  );

  StreamSubscription? sub;
  sub = ref.read(downloadProvider.notifier).stream.listen((downloads) async {
    final progress = downloads[emulatorId];
    if (progress == null) return;

    if (progress.status == 'selection_required') {
      sub?.cancel();
      
      final service = await ref.read(emulatorDownloadServiceProvider.future);
      if (service == null) return;
      final assets = await service.getLatestAssetsForEmulator(emulatorId);
      
      if (context.mounted) {
        final selected = await showDialog<Map<String, String>>(
          context: context,
          builder: (ctx) => EmulatorSelectionDialog(
            assets: assets,
            onSelect: (url) => Navigator.pop(ctx, assets.firstWhere((a) => a['url'] == url)),
          ),
        );
        
        if (selected != null) {
          if (context.mounted) {
            _startDownload(context, ref, emulatorId, emulatorName, emulatorInstallStates, setState, urlOverride: selected['url']);
          }
        }
      }
      return; 
    }

    if (progress.isComplete || progress.error != null) {
      if (progress.isComplete) {
        if (context.mounted) {
          ref.invalidate(emulatorStatusProvider);
          messenger.showSnackBar(SnackBar(content: Text('$emulatorName downloaded successfully.')));
        }
      } else if (progress.error != null) {
        if (context.mounted) {
          setState(() {});
          messenger.showSnackBar(SnackBar(content: Text('Failed to download $emulatorName: ${progress.error}')));
        }
      }
      sub?.cancel();
    }
  });
}

Widget buildConflictsSection(
  BuildContext context,
  StrategyRegistry registry,
  Function(void Function()) setState,
) {
  final conflicts = registry.detectConflicts();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Emulator Conflicts',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      if (conflicts.isEmpty)
        const Text('No conflicts detected', style: TextStyle(color: Colors.grey))
      else
        ...conflicts.entries.map((entry) {
          final slug = entry.key;
          final strategies = entry.value;
          final currentStrategy = registry.getStrategyForSlug(slug);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(slug, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(strategies.map((s) => s.name).join(' vs '),
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: currentStrategy?.emulatorId,
                  underline: const SizedBox(),
                  items: strategies.map((s) {
                    return DropdownMenuItem(
                      value: s.emulatorId,
                      child: Text(s.name),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value != null) {
                      await registry.setPreference(slug, value);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          );
        }),
      const SizedBox(height: 16),
      Row(
        children: [
          _buildActionButton(
            context,
            icon: Icons.restore_page,
            label: 'Reset Emulator Preferences',
            onTap: () async {
              await registry.clearPreferences();
              setState(() {});
            },
            isDestructive: true,
          ),
        ],
      ),
    ],
  );
}

void _syncAllBios(BuildContext context, WidgetRef ref) async {
  final firmwareService = await ref.read(firmwareServiceProvider.future);
  if (firmwareService == null) return;

  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _FirmwareProgressDialog(
      title: 'Syncing All BIOS',
      onSync: (onProgress) => firmwareService.syncAllFirmware(onProgress: onProgress),
    ),
  );
}

void _syncBiosForEmulator(BuildContext context, WidgetRef ref, String emulatorId, String emulatorName) async {
  final firmwareService = await ref.read(firmwareServiceProvider.future);
  if (firmwareService == null) return;

  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _FirmwareProgressDialog(
      title: 'Syncing BIOS for $emulatorName',
      onSync: (onProgress) => firmwareService.syncFirmwareForEmulator(emulatorId, onProgress: onProgress),
    ),
  );
}

void _showUrlOverrideDialog(BuildContext context, WidgetRef ref, DirectoryService directoryService, String emulatorId, String type) {
  final controller = TextEditingController();
  final theme = Theme.of(context);

  directoryService.getEmulatorUrlOverride(emulatorId).then((stored) {
    controller.text = stored ?? '';
  });

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text("Download URL Override"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Source: $type — paste a direct download URL to override",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: "Override URL",
              hintText: "https://example.com/emulator.zip",
              helperText: "Accepts .zip .7z .dmg .tar.gz .AppImage",
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () async {
            await directoryService.setEmulatorUrlOverride(emulatorId, null);
            controller.text = '';
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text("Reset"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () async {
            final text = controller.text.trim();
            await directoryService.setEmulatorUrlOverride(
              emulatorId,
              text.isEmpty ? null : text,
            );
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text("Confirm"),
        ),
      ],
    ),
  );
}

class _FirmwareProgressDialog extends StatefulWidget {
  final String title;
  final Future<void> Function(FirmwareProgressCallback onProgress) onSync;

  const _FirmwareProgressDialog({
    required this.title,
    required this.onSync,
  });

  @override
  State<_FirmwareProgressDialog> createState() => _FirmwareProgressDialogState();
}

class _FirmwareProgressDialogState extends State<_FirmwareProgressDialog> {
  String _currentFile = 'Initializing...';
  double _progress = 0;
  String _status = '';
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  void _startSync() async {
    await widget.onSync((fileName, received, total) {
      if (mounted) {
        setState(() {
          _currentFile = fileName;
          if (total > 0) {
            _progress = received / total;
            final mbReceived = (received / (1024 * 1024)).toStringAsFixed(1);
            final mbTotal = (total / (1024 * 1024)).toStringAsFixed(1);
            
            if (total > 10 * 1024 * 1024) {
              _status = 'Downloading large file... ($mbReceived / $mbTotal MB)';
            } else {
              _status = '$mbReceived / $mbTotal MB';
            }
          } else {
            _progress = 0;
            _status = 'Fetching...';
          }
        });
      }
    });

    if (mounted) {
      setState(() {
        _isComplete = true;
        _currentFile = 'Complete!';
        _status = 'All BIOS files synced successfully.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_currentFile, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _isComplete ? 1.0 : (_progress > 0 ? _progress : null)),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isComplete ? () => Navigator.pop(context) : null,
          child: Text(_isComplete ? 'Close' : 'Please wait...'),
        ),
      ],
    );
  }
}
