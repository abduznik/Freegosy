import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/directory_service.dart';
import '../../core/emulator/emulator_registry_data.dart';
import '../../core/emulator/emulator_download_service.dart';
import '../../providers/romm_provider.dart';
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

  @override
  void initState() {
    super.initState();
    // Initialize controllers here, will be updated when rommConfigProvider loads
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
    // Watch DirectoryService (FutureProvider<DirectoryService?>)
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    // Watch RommService (Provider<RommService?>)
    final rommService = ref.watch(rommServiceProvider);
    // Watch RommConfig (FutureProvider<RomMConfig>) to pre-fill fields
    final rommConfigAsync = ref.watch(rommConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: rommConfigAsync.when(
        data: (rommConfig) {
          // Pre-fill controllers with loaded config values
          _baseUrlController.text = rommConfig.baseUrl;
          _usernameController.text = rommConfig.username;
          _passwordController.text = rommConfig.password;

          return directoryServiceAsync.when(
            data: (directoryService) {
              // Handle the case where DirectoryService is null (e.g., due to an error during initialization)
              if (directoryService == null) {
                return const Center(child: Text('Storage service not available.'));
              }

              // Now check RommService. If it's null, it means it's still loading or encountered an error.
              // This check might be redundant if rommService is already being watched above, but kept for clarity.
              if (rommService == null) {
                return const Center(child: CircularProgressIndicator()); // Show loading if RommService is null
              }

              // Both services are available and not null, render the UI
              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildRommServerSection(context, ref, rommService), // Pass context and ref
                  const SizedBox(height: 24),
                  _buildStorageSection(directoryService),
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

  Widget _buildRommServerSection(BuildContext context, WidgetRef ref, RommService? rommService) {
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
                // Test Connection Logic
                if (rommService == null) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('RomM Service not available.'), backgroundColor: Colors.red),
                  );
                  return;
                }
                try {
                  final platforms = await rommService.getPlatforms();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Connection successful! ${platforms.length} platforms found.'), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Test Connection'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () async {
                // Save Logic
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('rommBaseUrl', _baseUrlController.text);
                await prefs.setString('rommUsername', _usernameController.text);
                await prefs.setString('rommPassword', _passwordController.text);

                // Refresh providers
                // ignore: unused_result
                ref.refresh(rommConfigProvider);
                // ignore: unused_result
                ref.refresh(rommServiceProvider);

                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('RomM Server settings saved.'), backgroundColor: Colors.green),
                );
              },
              child: const Text('Save'),
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
          onChanged: (newPath) async { // Make onChanged async
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
          onChanged: (newPath) async { // Make onChanged async
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
    // Instantiate EmulatorDownloadService here, as it needs Dio and DirectoryService.
    // RommService is no longer passed as an argument.
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
                          ? null // Disabled if installed
                          : () async {
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Starting download for $emulatorName...')),
                              );
                              try {
                                await for (var progress in emulatorDownloadService.downloadEmulator(emulatorId)) {
                                  if (progress.error != null) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error downloading $emulatorName: ${progress.error}')),
                                    );
                                    break;
                                  }
                                  if (progress.isComplete) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$emulatorName downloaded and extracted.')),
                                    );
                                    // Refresh the installation status
                                    // ignore: unused_result
                                    ref.refresh(directoryServiceProvider);
                                    break;
                                  }

                                }
                              } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('An unexpected error occurred: $e')),
                                );
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
