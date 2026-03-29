import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/storage/directory_service.dart';
import '../../core/emulator/emulator_registry_data.dart';
import '../../core/emulator/strategy_registry.dart';
import '../../providers/download_provider.dart';

// Function to build the Emulators section
Widget buildEmulatorsSection(
  BuildContext context,
  DirectoryService directoryService,
  bool emulatorsLoaded,
  Map<String, bool> emulatorInstallStates,
  Function(void Function()) setState,
  WidgetRef ref,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Emulators',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      if (!emulatorsLoaded)
        const Center(child: CircularProgressIndicator())
      else
        ...kEmulatorDefinitions.map<Widget>((def) {
          final emulatorId = def['id'] as String;
          final emulatorName = def['name'] as String;
          final isInstalled = emulatorInstallStates[emulatorId] ?? false;
          final overridePath = directoryService.getEmulatorPathOverride(emulatorId);

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
                ElevatedButton(
                  onPressed: isInstalled
                      ? null
                      : () async {
                          // Capture context safely before any async operations.
                          final messenger = ScaffoldMessenger.of(context);

                          messenger.showSnackBar(SnackBar(
                            content: Text('Starting download for $emulatorName...'),
                          ));

                          ref.read(downloadProvider.notifier).startEmulatorDownload(emulatorId, emulatorName);

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
                        },
                  child: Text(isInstalled ? 'Installed' : 'Download'),
                ),
              ],
            ),
          );
        }),
    ],
  );
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
