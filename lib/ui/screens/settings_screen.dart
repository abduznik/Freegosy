import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/directory_service.dart';
import '../../core/emulator/emulator_registry_data.dart';
import '../../core/emulator/emulator_download_service.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final rommService = ref.watch(rommServiceProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);

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
              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildRommServerSection(context, ref, rommService),
                  const SizedBox(height: 24),
                  _buildCardAspectRatioSection(context, ref),
                  const SizedBox(height: 24),
                  _buildStorageSection(directoryService),
                  const SizedBox(height: 24),
                  _buildRetroArchSyncModeSection(context, ref),
                  const SizedBox(height: 24),
                  _buildEmulatorsSection(directoryService),
                ],
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
                        print('[Settings] fetchToken succeeded');
                      } catch (e) {
                        print('[Settings] fetchToken failed ($e), falling back to Basic auth');
                        // Clear any stale token so Basic auth is used instead.
                        final p = await SharedPreferences.getInstance();
                        await p.remove('rommAuthToken');
                      }

                      // Save credentials regardless of whether token fetch succeeded.
                      print('[Settings] saving baseUrl=$baseUrl user=$username passLen=${password.length}');
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

  Widget _buildCardAspectRatioSection(BuildContext context, WidgetRef ref) {
    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Library Display', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Card Aspect Ratio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 0.72, label: Text('Square')),
            ButtonSegment(value: 0.56, label: Text('Portrait')),
          ],
          selected: {cardAspectRatio},
          onSelectionChanged: (selection) async {
            final value = selection.first;
            ref.read(cardAspectRatioProvider.notifier).state = value;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('card_aspect_ratio', value);
          },
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
    final emulatorDownloadService = EmulatorDownloadService(Dio(), directoryService);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Emulators', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...kEmulatorDefinitions.map<Widget>((def) {
          final emulatorId = def['id'] as String;
          final emulatorName = def['name'] as String;
          final windowsExecutable = def['windows_executable'] as String;

          return FutureBuilder<bool>(
            future: directoryService.isEmulatorInstalled(emulatorId, windowsExecutable),
            builder: (context, snapshot) {
              final isInstalled = snapshot.data ?? false;
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
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Starting download for $emulatorName...')),
                                );
                              }
                              try {
                                await for (var progress in emulatorDownloadService.downloadEmulator(emulatorId)) {
                                  if (progress.error != null) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error downloading $emulatorName: ${progress.error}')),
                                      );
                                    }
                                    break;
                                  }
                                  if (progress.isComplete) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$emulatorName downloaded and extracted.')),
                                      );
                                    }
                                    // ignore: unused_result
                                    ref.refresh(directoryServiceProvider);
                                    break;
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('An unexpected error occurred: $e')),
                                  );
                                }
                              }
                            },
                      child: Text(isInstalled ? 'Installed' : 'Download'),
                    ),
                  ],
                ),
              );
            },
          );
        }),
      ],
    );
  }
}
