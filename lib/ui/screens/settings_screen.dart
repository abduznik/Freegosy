import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/directory_service.dart';
import '../../core/emulator/emulator_registry_data.dart';
import '../../core/emulator/strategy_registry.dart';
import '../../core/extraction/extraction_service.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/download_provider.dart';
import '../../core/romm/romm_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _baseUrlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isSaving = false;
  Map<String, bool> _emulatorInstallStates = {};
  bool _emulatorsLoaded = false;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final registry = ref.read(strategyRegistryProvider);
      if (registry != null) {
        registry.loadPreferences().then((_) {
          if (mounted) setState(() => _preferencesLoaded = true);
        });
      }
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadEmulatorStates(DirectoryService directoryService) async {
    if (_emulatorsLoaded) return;
    final states = <String, bool>{};
    for (final def in kEmulatorDefinitions) {
      final id = def['id'] as String;
      final exe = def['windows_executable'] as String;
      if (exe.isEmpty) {
        states[id] = true;
        continue;
      }
      states[id] = await directoryService.isEmulatorInstalled(id, exe);
    }
    if (mounted) {
      setState(() {
        _emulatorInstallStates = states;
        _emulatorsLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final rommService = ref.watch(rommServiceProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);
    final strategyRegistry = ref.watch(strategyRegistryProvider);

    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final showButtonsOnHover = ref.watch(showButtonsOnHoverProvider);
    final activePreset = ref.watch(activePresetProvider);

    if (strategyRegistry != null && !_preferencesLoaded) {
      strategyRegistry.loadPreferences().then((_) {
        if (mounted) setState(() => _preferencesLoaded = true);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: rommConfigAsync.when(
        data: (rommConfig) {
          _baseUrlController.text = rommConfig.baseUrl;
          _usernameController.text = rommConfig.username;
          _passwordController.text = rommConfig.password;

          return directoryServiceAsync.when(
            data: (directoryService) {
              if (directoryService == null) {
                return const Center(child: Text('Storage service not available.'));
              }
              if (rommService == null) {
                return const Center(child: CircularProgressIndicator());
              }
              
              _loadEmulatorStates(directoryService);

              return ExcludeSemantics(
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    _buildRommServerSection(context, ref, rommService),
                    const SizedBox(height: 24),
                    _buildDisplaySection(
                      context,
                      cardAspectRatio,
                      columnCount,
                      cardSpacing,
                      showTitle,
                      showButtonsOnHover,
                      activePreset,
                    ),
                    const SizedBox(height: 24),
                    _buildStorageSection(directoryService),
                    const SizedBox(height: 24),
                    _buildRetroArchSyncModeSection(context, ref),
                    const SizedBox(height: 24),
                    _buildEmulatorsSection(directoryService),
                    if (strategyRegistry != null) ...[
                      const SizedBox(height: 24),
                      _buildConflictsSection(strategyRegistry),
                    ],
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error loading storage service: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error loading RomM config: $e')),
      ),
    );
  }

  Widget _buildConflictsSection(StrategyRegistry registry) {
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
                        const Text('Multiple emulators support this platform',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDisplaySection(
    BuildContext context,
    double cardAspectRatio,
    int columnCount,
    double cardSpacing,
    bool showTitle,
    bool showButtonsOnHover,
    String activePreset,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Library Display', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Presets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _presetChip('Windows', 'windows_best', activePreset),
            _presetChip('Steam Deck', 'steamdeck_best', activePreset),
            _presetChip('Cozy', 'cozy', activePreset),
            _presetChip('Compact', 'compact', activePreset),
            _presetChip('Custom', 'custom', activePreset),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Columns per row', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            Text('$columnCount', style: const TextStyle(fontSize: 16, color: Colors.deepPurple)),
          ],
        ),
        Slider(
          value: columnCount.toDouble(),
          min: 2,
          max: 8,
          divisions: 6,
          label: '$columnCount',
          onChanged: (value) async {
            ref.read(activePresetProvider.notifier).state = 'custom';
            ref.read(columnCountProvider.notifier).state = value.toInt();
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('column_count', value.toInt());
            await prefs.setString('active_preset', 'custom');
          },
        ),
        const SizedBox(height: 16),
        const Text('Card Shape', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 1.0, label: Text('Square')),
            ButtonSegment(value: 0.72, label: Text('Portrait')),
            ButtonSegment(value: 0.58, label: Text('Tall')),
          ],
          selected: {
            [1.0, 0.72, 0.58].reduce((a, b) =>
                (a - cardAspectRatio).abs() < (b - cardAspectRatio).abs()
                    ? a
                    : b)
          },
          onSelectionChanged: (selection) async {
            ref.read(activePresetProvider.notifier).state = 'custom';
            ref.read(cardAspectRatioProvider.notifier).state = selection.first;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('card_aspect_ratio', selection.first);
            await prefs.setString('active_preset', 'custom');
          },
        ),
        const SizedBox(height: 16),
        const Text('Card Spacing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 4.0, label: Text('Tight')),
            ButtonSegment(value: 8.0, label: Text('Normal')),
            ButtonSegment(value: 12.0, label: Text('Airy')),
          ],
          selected: {
            [4.0, 8.0, 12.0].reduce((a, b) =>
                (a - cardSpacing).abs() < (b - cardSpacing).abs() ? a : b)
          },
          onSelectionChanged: (selection) async {
            ref.read(activePresetProvider.notifier).state = 'custom';
            ref.read(cardSpacingProvider.notifier).state = selection.first;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('card_spacing', selection.first);
            await prefs.setString('active_preset', 'custom');
          },
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Show game title'),
          subtitle: const Text('Display title text below cover art'),
          value: showTitle,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) async {
            ref.read(activePresetProvider.notifier).state = 'custom';
            ref.read(showTitleProvider.notifier).state = value;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('show_title', value);
            await prefs.setString('active_preset', 'custom');
          },
        ),
        SwitchListTile(
          title: const Text('Show buttons on hover only'),
          subtitle: const Text('Buttons appear when hovering over a card'),
          value: showButtonsOnHover,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) async {
            ref.read(activePresetProvider.notifier).state = 'custom';
            ref.read(showButtonsOnHoverProvider.notifier).state = value;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('show_buttons_on_hover', value);
            await prefs.setString('active_preset', 'custom');
          },
        ),
      ],
    );
  }

  Widget _presetChip(String label, String presetKey, String activePreset) {
    final isSelected = activePreset == presetKey;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) async {
        if (!selected) return;
        ref.read(activePresetProvider.notifier).state = presetKey;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_preset', presetKey);
        if (presetKey == 'custom') return;
        final preset = kDisplayPresets[presetKey];
        if (preset == null) return;
        final cols = preset['columnCount'] as int;
        final ratio = preset['cardAspectRatio'] as double;
        final spacing = preset['cardSpacing'] as double;
        final title = preset['showTitle'] as bool;
        final hover = preset['showButtonsOnHover'] as bool;
        ref.read(columnCountProvider.notifier).state = cols;
        ref.read(cardAspectRatioProvider.notifier).state = ratio;
        ref.read(cardSpacingProvider.notifier).state = spacing;
        ref.read(showTitleProvider.notifier).state = title;
        ref.read(showButtonsOnHoverProvider.notifier).state = hover;
        await prefs.setInt('column_count', cols);
        await prefs.setDouble('card_aspect_ratio', ratio);
        await prefs.setDouble('card_spacing', spacing);
        await prefs.setBool('show_title', title);
        await prefs.setBool('show_buttons_on_hover', hover);
      },
    );
  }

  Widget _buildRetroArchSyncModeSection(BuildContext context, WidgetRef ref) {
    final syncMode = ref.watch(retroarchSyncModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RetroArch Save Sync', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('What to sync with RomM cloud', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'saves', label: Text('Saves only')),
            ButtonSegment(value: 'states', label: Text('States only')),
            ButtonSegment(value: 'both', label: Text('Both')),
          ],
          selected: {syncMode},
          onSelectionChanged: (selection) async {
            final value = selection.first;
            ref.read(retroarchSyncModeProvider.notifier).state = value;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('retroarch_sync_mode', value);
          },
        ),
      ],
    );
  }

  Widget _buildRommServerSection(BuildContext context, WidgetRef ref, rommService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RomM Server', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _baseUrlController,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'http://your-server:3000',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: () async {
                if (rommService == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('RomM Service not available.'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }
                try {
                  final platforms = await rommService.getPlatforms();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Connection successful! ${platforms.length} platforms found.'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Test Connection'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      setState(() => _isSaving = true);
                      final baseUrl = _baseUrlController.text.trim();
                      final username = _usernameController.text.trim();
                      final password = _passwordController.text;

                      // Try Bearer token (OAuth2). If the server doesn't support
                      // it over HTTP or at all, fall back to Basic auth silently.
                      try {
                        await RommService.fetchToken(baseUrl, username, password);
                      } catch (e) {
                        // Clear any stale token so Basic auth is used instead.
                        final p = await SharedPreferences.getInstance();
                        await p.remove('rommAuthToken');
                      }

                      // Save credentials regardless of whether token fetch succeeded.
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('rommBaseUrl', baseUrl);
                      await prefs.setString('rommUsername', username);
                      await prefs.setString('rommPassword', password);

                      // ignore: unused_result
                      ref.invalidate(rommConfigProvider);
                      // ignore: unused_result
                      ref.invalidate(rommServiceProvider);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged in and settings saved.'), backgroundColor: Colors.green),
                        );
                      }
                      setState(() => _isSaving = false);
                    },
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStorageSection(DirectoryService directoryService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Storage', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildPathRow(
          label: 'ROMs Directory',
          currentPath: directoryService.romsRootPath,
          onChanged: (newPath) async {
            if (newPath != null) {
              await directoryService.setRomsRoot(newPath);
              // ignore: unused_result
              ref.refresh(directoryServiceProvider);
            }
          },
        ),
        const SizedBox(height: 12),
        _buildPathRow(
          label: 'Emulators Directory',
          currentPath: directoryService.emulatorsRootPath,
          onChanged: (newPath) async {
            if (newPath != null) {
              await directoryService.setEmulatorsRoot(newPath);
              // ignore: unused_result
              ref.refresh(directoryServiceProvider);
            }
          },
        ),
      ],
    );
  }

  Widget _buildPathRow({required String label, required String currentPath, required Function(String?) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                currentPath,
                style: const TextStyle(color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                onChanged(selectedDirectory);
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmulatorsSection(DirectoryService directoryService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Emulators',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        if (!_emulatorsLoaded)
          const Center(child: CircularProgressIndicator())
        else
          ...kEmulatorDefinitions.map<Widget>((def) {
            final emulatorId = def['id'] as String;
            final emulatorName = def['name'] as String;
            final isInstalled = _emulatorInstallStates[emulatorId] ?? false;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(
                    isInstalled ? Icons.check_circle : Icons.cancel,
                    color: isInstalled ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(emulatorName)),
                  ElevatedButton(
                    onPressed: isInstalled
                        ? null
                        : () async {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('Starting download for $emulatorName...'),
                            ));
                            
                            ref.read(downloadProvider.notifier).startEmulatorDownload(emulatorId, emulatorName);

                            // Watch for completion to update local UI state
                            final subscription = ref.read(downloadProvider.notifier).stream.listen((downloads) {
                              final progress = downloads[emulatorId];
                              if (progress != null && progress.isComplete && mounted) {
                                setState(() {
                                  _emulatorInstallStates[emulatorId] = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('$emulatorName downloaded.'),
                                ));
                              }
                            });
                            
                            // Clean up subscription eventually (simplified for this context)
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
}
