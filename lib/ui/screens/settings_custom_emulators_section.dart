import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/emulator/custom_emulator_config.dart';
import '../../providers/custom_emulators_provider.dart';
import '../widgets/focus_effect_wrapper.dart';

InputDecoration _buildInputDecoration(BuildContext context, String label, {String? hintText, String? helperText}) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    helperText: helperText,
    labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
    helperStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11),
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
}

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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: isPrimary
                ? theme.colorScheme.onPrimary
                : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
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

class SettingsCustomEmulatorsSection extends ConsumerWidget {
  const SettingsCustomEmulatorsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'EXPERIMENTAL',
                style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Add your own emulators. Use comma-separated platform names (e.g. ps1,ps2). Custom emulators will appear in "Emulator Conflicts" below if they support the same platforms as built-in ones.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (customEmulators.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No custom emulators added yet.', 
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ...customEmulators.map((emu) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.settings_input_component, color: theme.colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          emu.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Platforms: ${emu.platforms.join(", ")}',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          'Path: ${emu.executablePath}',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FocusEffectWrapper(
                    onTap: () => ref.read(customEmulatorsProvider.notifier).removeEmulator(emu.id),
                    borderRadius: 12.0,
                    scaleFactor: 1.15,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.2)),
                      ),
                      child: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 12),
        _buildActionButton(
          context,
          icon: Icons.add,
          label: 'Add Custom Emulator',
          onTap: () => _showAddEmulatorDialog(context, ref),
          isPrimary: true,
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
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.add_to_queue, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Add Custom Emulator'),
            ],
          ),
          content: Container(
            width: 600,
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
                    decoration: _buildInputDecoration(context, 'Emulator Name', hintText: 'e.g. PCSX2 Nightly'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: platformsController,
                    decoration: _buildInputDecoration(
                      context, 
                      'Platform Slugs', 
                      hintText: 'e.g. ps1,ps2,psx',
                      helperText: 'Comma separated IDs used by RomM',
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
                          decoration: _buildInputDecoration(context, 'Executable Path'),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FocusEffectWrapper(
                        onTap: () async {
                          FilePickerResult? result = await FilePicker.platform.pickFiles();
                          if (result != null) {
                            exeController.text = result.files.single.path ?? '';
                          }
                        },
                        borderRadius: 12.0,
                        scaleFactor: 1.1,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Icon(Icons.folder_open, color: theme.colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Save Synchronization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  Text('Configure how Freegosy should backup your saves.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 12)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<CustomSaveMethod>(
                    value: saveMethod,
                    items: const [
                      DropdownMenuItem(value: CustomSaveMethod.file, child: Text('File Based (Single save file)')),
                      DropdownMenuItem(value: CustomSaveMethod.folder, child: Text('Folder Based (Syncs entire subfolder)')),
                    ],
                    onChanged: (val) => setDialogState(() => saveMethod = val!),
                    decoration: _buildInputDecoration(context, 'Sync Method'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: savePathController,
                          decoration: _buildInputDecoration(
                            context, 
                            'Save Directory',
                            helperText: 'Path to where the emulator stores saves',
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FocusEffectWrapper(
                        onTap: () async {
                          String? path = await FilePicker.platform.getDirectoryPath();
                          if (path != null) {
                            savePathController.text = path;
                          }
                        },
                        borderRadius: 12.0,
                        scaleFactor: 1.1,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Icon(Icons.folder_open, color: theme.colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                  if (saveMethod == CustomSaveMethod.file) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: patternController,
                      decoration: _buildInputDecoration(
                        context, 
                        'Save Pattern',
                        hintText: '*.srm or *.sav',
                        helperText: 'Use * for game name matching (e.g. *.srm)',
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
            FocusEffectWrapper(
              onTap: () {
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
              borderRadius: 12.0,
              scaleFactor: 1.05,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                  ),
                ),
                child: Text(
                  'Add Emulator',
                  style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
