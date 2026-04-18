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
          'Add your own emulators. Use comma-separated platform names (e.g. ps1,ps2). Custom emulators will appear in "Emulator Conflicts" below if they support the same platforms as built-in ones.',
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
                leading: const Icon(Icons.settings_input_component),
                title: Text(emu.name),
                subtitle: Text('Platforms: ${emu.platforms.join(", ")}\nPath: ${emu.executablePath}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => ref.read(customEmulatorsProvider.notifier).removeEmulator(emu.id),
                ),
                isThreeLine: true,
              ),
            )),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
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
          title: const Row(
            children: [
              Icon(Icons.add_to_queue),
              SizedBox(width: 12),
              Text('Add Custom Emulator'),
            ],
          ),
          content: Container(
            width: 600, // Fixed wider width for desktop/large screens
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('General Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Emulator Name',
                      hintText: 'e.g. PCSX2 Nightly',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: platformsController,
                    decoration: const InputDecoration(
                      labelText: 'Platform Slugs',
                      hintText: 'e.g. ps1,ps2,psx',
                      helperText: 'Comma separated IDs used by RomM',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Executable', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: exeController,
                          decoration: const InputDecoration(
                            labelText: 'Executable Path',
                            border: OutlineInputBorder(),
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Select Executable',
                        onPressed: () async {
                          FilePickerResult? result = await FilePicker.platform.pickFiles();
                          if (result != null) {
                            exeController.text = result.files.single.path ?? '';
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text('Save Synchronization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurpleAccent)),
                  const SizedBox(height: 8),
                  const Text('Configure how Freegosy should backup your saves.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<CustomSaveMethod>(
                    initialValue: saveMethod,
                    items: const [
                      DropdownMenuItem(value: CustomSaveMethod.file, child: Text('File Based (Single save file)')),
                      DropdownMenuItem(value: CustomSaveMethod.folder, child: Text('Folder Based (Syncs entire subfolder)')),
                    ],
                    onChanged: (val) => setDialogState(() => saveMethod = val!),
                    decoration: const InputDecoration(
                      labelText: 'Sync Method',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: savePathController,
                          decoration: const InputDecoration(
                            labelText: 'Save Directory',
                            helperText: 'Path to where the emulator stores saves',
                            border: OutlineInputBorder(),
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Select Directory',
                        onPressed: () async {
                          String? path = await FilePicker.platform.getDirectoryPath();
                          if (path != null) {
                            savePathController.text = path;
                          }
                        },
                      ),
                    ],
                  ),
                  if (saveMethod == CustomSaveMethod.file) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: patternController,
                      decoration: const InputDecoration(
                        labelText: 'Save Pattern',
                        hintText: '*.srm or *.sav',
                        helperText: 'Use * for game name matching (e.g. *.srm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
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
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(100, 45),
              ),
              child: const Text('Add Emulator'),
            ),
          ],
        ),
      ),
    );
  }
}
