import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/emulator/custom_emulator_config.dart';
import '../../providers/custom_emulators_provider.dart';

class SettingsCustomEmulatorsSection extends ConsumerWidget {
  const SettingsCustomEmulatorsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customEmulators = ref.watch(customEmulatorsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Custom Emulators', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: const Text(
                'EXPERIMENTAL',
                style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Add your own emulators. Use comma-separated platform names (e.g. ps1,ps2).',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (customEmulators.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No custom emulators added yet.', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ...customEmulators.map((emu) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(emu.name),
                subtitle: Text('${emu.platforms.join(", ")}\n${emu.executablePath}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => ref.read(customEmulatorsProvider.notifier).removeEmulator(emu.id),
                ),
                isThreeLine: true,
              ),
            )),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showAddEmulatorDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add Custom Emulator'),
          ),
        ),
      ],
    );
  }

  void _showAddEmulatorDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final platformsController = TextEditingController();
    final exeController = TextEditingController();
    final savePathController = TextEditingController();
    final patternController = TextEditingController();
    CustomSaveMethod saveMethod = CustomSaveMethod.file;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Custom Emulator'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Emulator Name (e.g. PCSX2 Nightly)'),
                ),
                TextField(
                  controller: platformsController,
                  decoration: const InputDecoration(labelText: 'Platform Slugs (e.g. ps1,ps2)'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: exeController,
                        decoration: const InputDecoration(labelText: 'Executable Path'),
                        readOnly: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform.pickFiles();
                        if (result != null) {
                          exeController.text = result.files.single.path ?? '';
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const Text('Save Sync Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<CustomSaveMethod>(
                  value: saveMethod,
                  items: const [
                    DropdownMenuItem(value: CustomSaveMethod.file, child: Text('File Based')),
                    DropdownMenuItem(value: CustomSaveMethod.folder, child: Text('Folder Based')),
                  ],
                  onChanged: (val) => setDialogState(() => saveMethod = val!),
                  decoration: const InputDecoration(labelText: 'Save Method'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: savePathController,
                        decoration: const InputDecoration(labelText: 'Save Directory'),
                        readOnly: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
                        String? path = await FilePicker.platform.getDirectoryPath();
                        if (path != null) {
                          savePathController.text = path;
                        }
                      },
                    ),
                  ],
                ),
                if (saveMethod == CustomSaveMethod.file)
                  TextField(
                    controller: patternController,
                    decoration: const InputDecoration(
                      labelText: 'Save Pattern (e.g. *.srm or specific name)',
                      hintText: '*.srm',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isEmpty || exeController.text.isEmpty || platformsController.text.isEmpty) {
                  return;
                }
                final platforms = platformsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                
                final config = CustomEmulatorConfig(
                  id: const Uuid().v4(),
                  name: nameController.text.trim(),
                  platforms: platforms,
                  executablePath: exeController.text.trim(),
                  saveMethod: saveMethod,
                  savePath: savePathController.text.trim(),
                  savePattern: patternController.text.trim().isEmpty ? null : patternController.text.trim(),
                );

                ref.read(customEmulatorsProvider.notifier).addEmulator(config);
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
