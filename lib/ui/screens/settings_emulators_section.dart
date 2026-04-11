import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/storage/directory_service.dart';
import '../../core/emulator/emulator_registry_data.dart';
import '../../core/emulator/strategy_registry.dart';
import '../../core/emulator/firmware_service.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';

// Function to build the Emulators section
Widget buildEmulatorsSection(
  BuildContext context,
  DirectoryService directoryService,
  bool emulatorsLoaded,
  Map<String, bool> emulatorInstallStates,
  Function(void Function()) setState,
  WidgetRef ref,
) {
  final currentPlatform = defaultTargetPlatform == TargetPlatform.windows 
      ? 'windows' 
      : (defaultTargetPlatform == TargetPlatform.macOS ? 'macos' : 'linux');

  // Filter emulators that are supported on the current OS
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
          ElevatedButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Sync BIOS from RomM'),
            onPressed: () async {
              _syncAllBios(context, ref);
            },
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
          final canManage = type != 'none'; // Only github/direct emulators can be updated/uninstalled

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Icon(
                  isInstalled ? Icons.check_circle : Icons.cancel,
                  color: isInstalled ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emulatorName),
                      if (overridePath != null)
                        Text(
                          overridePath,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (emulatorId == 'rpcs3' && defaultTargetPlatform == TargetPlatform.macOS) ...[
                  const Text('Arch: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Consumer(
                    builder: (context, ref, child) {
                      final arch = ref.watch(rpcs3ArchitectureProvider);
                      return DropdownButton<String>(
                        value: arch,
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                        items: const [
                          DropdownMenuItem(value: 'x64', child: Text('x64')),
                          DropdownMenuItem(value: 'arm64', child: Text('ARM64')),
                        ],
                        onChanged: (value) async {
                          if (value != null) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('rpcs3_macos_architecture', value);
                            ref.read(rpcs3ArchitectureProvider.notifier).state = value;
                          }
                        },
                      );
                    },
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 20),
                  tooltip: 'Set custom directory',
                  onPressed: () async {
                    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                    if (selectedDirectory != null) {
                      await directoryService.setEmulatorPathOverride(emulatorId, selectedDirectory);
                      setState(() {}); // Trigger parent state update
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.library_books, size: 20),
                  tooltip: 'Sync BIOS from RomM',
                  onPressed: () async {
                    _syncBiosForEmulator(context, ref, emulatorId, emulatorName);
                  },
                ),
                if (isInstalled) ...[
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.green),
                    tooltip: "Launch Standalone",
                    onPressed: () async {
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
                  ),
                  if (canManage) ...[
                    IconButton(
                      icon: const Icon(Icons.update, color: Colors.blue),
                      tooltip: "Update Emulator",
                      onPressed: () async {
                        _startDownload(context, ref, emulatorId, emulatorName, emulatorInstallStates, setState);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: "Uninstall Emulator",
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("Uninstall Emulator"),
                            content: Text("Are you sure you want to delete $emulatorName? This will remove all local files."),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text("Uninstall"),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await directoryService.deleteEmulator(emulatorId);
                          emulatorInstallStates[emulatorId] = false;
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("$emulatorName uninstalled.")),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ],
                if (!isInstalled && canManage)
                  ElevatedButton(
                    onPressed: () => _startDownload(context, ref, emulatorId, emulatorName, emulatorInstallStates, setState),
                    child: const Text('Download'),
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
  Function(void Function()) setState,
) async {
  final messenger = ScaffoldMessenger.of(context);
  String? architecture;

  if (emulatorId == 'rpcs3' && defaultTargetPlatform == TargetPlatform.macOS) {
    // Check if preference already set
    final prefs = await SharedPreferences.getInstance();
    final hasPreference = prefs.containsKey('rpcs3_macos_architecture');
    
    if (!hasPreference) {
      // Show choice dialog
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Select Architecture"),
          content: const Text("Choose the variant of RPCS3 to download for macOS:"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'arm64'),
              child: const Text("ARM64 (Apple Silicon Native)"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'x64'),
              child: const Text("x64 (Rosetta 2 - Default)"),
            ),
          ],
        ),
      );
      
      if (choice == null) return; // Cancelled
      architecture = choice;
      
      // Save preference
      await prefs.setString('rpcs3_macos_architecture', architecture);
      ref.read(rpcs3ArchitectureProvider.notifier).state = architecture;
    } else {
      architecture = ref.read(rpcs3ArchitectureProvider);
    }
  }

  messenger.showSnackBar(SnackBar(
    content: Text('Starting download for $emulatorName${architecture != null ? " ($architecture)" : ""}...'),
  ));

  ref.read(downloadProvider.notifier).startEmulatorDownload(
    emulatorId, 
    emulatorName,
    architecture: architecture,
  );

  // Listen for download completion and update state
  StreamSubscription? sub;
  sub = ref.read(downloadProvider.notifier).stream.listen((downloads) {
    final progress = downloads[emulatorId];
    if (progress != null && (progress.isComplete || progress.error != null)) {
      if (progress.isComplete) {
        emulatorInstallStates[emulatorId] = true;
        if (context.mounted) setState(() {});
        messenger.showSnackBar(SnackBar(
          content: Text('$emulatorName downloaded successfully.'),
        ));
      } else if (progress.error != null) {
        if (context.mounted) setState(() {});
        messenger.showSnackBar(SnackBar(
          content: Text('Failed to download $emulatorName: ${progress.error}'),
        ));
      }
      sub?.cancel();
    }
  });
}

// Function to build the Emulator Conflicts section
Widget buildConflictsSection(
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
        const Text('No conflicts detected')
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
                      Text(slug, style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(strategies.map((s) => s.name).join(' vs '),
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: currentStrategy?.emulatorId,
                  items: strategies.map((s) {
                    return DropdownMenuItem(
                      value: s.emulatorId,
                      child: Text(s.name),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value != null) {
                      await registry.setPreference(slug, value);
                      setState(() {}); // Trigger parent state update
                    }
                  },
                ),
              ],
            ),
          );
        }),
      const SizedBox(height: 16),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.red,
        ),
        onPressed: () async {
          await registry.clearPreferences();
          setState(() {});
        },
        child: const Text('Reset Emulator Preferences'),
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
