import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/storage/directory_service.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';
import '../../core/romm/romm_service.dart';
import '../../core/romm/romm_models.dart';
import 'settings_emulators_section.dart';
import 'settings_display_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _baseUrlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _apiKeyController; // Added API Key controller
  bool _isSaving = false;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _apiKeyController = TextEditingController(); // Initialize API Key controller

    // Mark preferences as loaded (they are now awaited by the provider)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final registry = ref.read(strategyRegistryProvider).asData?.value;
      if (registry != null && !_preferencesLoaded) {
        if (mounted) setState(() => _preferencesLoaded = true);
      }
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _apiKeyController.dispose(); // Dispose API Key controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final rommService = ref.watch(rommServiceProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);
    final strategyRegistry = ref.watch(strategyRegistryProvider).asData?.value;
    final emulatorStatusAsync = ref.watch(emulatorStatusProvider);

    // Display section providers
    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final showButtonsOnHover = ref.watch(showButtonsOnHoverProvider);
    final activePreset = ref.watch(activePresetProvider);

    // Mark preferences as loaded (they are awaited by the provider)
    if (strategyRegistry != null && !_preferencesLoaded) {
      if (mounted) setState(() => _preferencesLoaded = true);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: rommConfigAsync.when(
        data: (rommConfig) {
          // Update controllers with loaded config
          _baseUrlController.text = rommConfig.baseUrl;
          _usernameController.text = rommConfig.username;
          _passwordController.text = rommConfig.password;
          _apiKeyController.text = rommConfig.apiKey; // Load API Key into controller

          return directoryServiceAsync.when(
            data: (directoryService) {
              if (directoryService == null) {
                return const Center(child: Text('Storage service not available.'));
              }
              if (rommService == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return ExcludeSemantics(
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    _buildRommServerSection(context, ref, rommService, rommConfig),
                    const SizedBox(height: 24),
                    // Call the extracted display section function
                    buildDisplaySection(
                      context,
                      cardAspectRatio,
                      columnCount,
                      cardSpacing,
                      showTitle,
                      showButtonsOnHover,
                      activePreset,
                      ref, // Pass ref
                    ),
                    const SizedBox(height: 24),
                    _buildStorageSection(directoryService),
                    const SizedBox(height: 24),
                    _buildRetroArchSyncModeSection(context, ref),
                    const SizedBox(height: 24),
                    if (defaultTargetPlatform == TargetPlatform.linux) ...[
                      _buildLinuxSettingsSection(context, ref, directoryService),
                      const SizedBox(height: 24),
                    ],
                    // Call the extracted emulators section function
                    emulatorStatusAsync.when(
                      data: (states) => buildEmulatorsSection(
                        context,
                        directoryService,
                        true,
                        states,
                        setState,
                        ref,
                      ),
                      loading: () => buildEmulatorsSection(
                        context,
                        directoryService,
                        false,
                        {},
                        setState,
                        ref,
                      ),
                      error: (e, s) => Center(child: Text('Error loading emulators: $e')),
                    ),
                    if (strategyRegistry != null) ...[
                      const SizedBox(height: 24),
                      // Call the extracted conflicts section function
                      buildConflictsSection(
                        strategyRegistry,
                        setState, // Pass the setState callback
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildLegalSection(context),
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

  // --- RomM Server Section ---
  Widget _buildRommServerSection(BuildContext context, WidgetRef ref, RommService? rommService, RomMConfig rommConfig) {
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
        const SizedBox(height: 12),
        TextField(
          controller: _apiKeyController,
          decoration: const InputDecoration(
            labelText: 'API Key (RomM 4.8+)',
            hintText: 'rmm_...',
            border: OutlineInputBorder(),
            helperText: 'Recommended. Generate in RomM Settings → Client API Tokens',
            helperMaxLines: 2,
          ),
          keyboardType: TextInputType.text,
          obscureText: true,
        ),
        const SizedBox(height: 16),
        const Divider(), // Add divider
        const SizedBox(height: 8),
        const Text('Legacy Authentication (RomM 4.7 and below)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)), // Add label
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
                  // Test connection by fetching platforms
                  final platforms = await rommService.getPlatforms();
                  String message;
                  if (rommConfig.apiKey.isNotEmpty) {
                    message = 'Connected via API key. ${platforms.length} platforms found.';
                  } else {
                    message = 'Connected via username/password. ${platforms.length} platforms found.';
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message), backgroundColor: Colors.green),
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
                      final apiKey = _apiKeyController.text.trim(); // Get API Key value

                      // Try Bearer token (OAuth2). If the server doesn't support
                      // it over HTTP or at all, fall back to Basic auth silently.
                      try {
                        await RommService.fetchToken(baseUrl, username, password);
                        // If successful, fetch token from preferences and move to secure storage
                        final prefs = await SharedPreferences.getInstance();
                        final token = prefs.getString('rommAuthToken');
                        if (token != null) {
                          await SecureStorageService.write('rommAuthToken', token);
                          await prefs.remove('rommAuthToken');
                        }
                      } catch (e) {
                        // Clear any stale token so Basic auth is used instead.
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('rommAuthToken');
                        await SecureStorageService.delete('rommAuthToken');
                      }

                      // Save credentials regardless of whether token fetch succeeded.
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('rommBaseUrl', baseUrl);
                      await prefs.setString('rommUsername', username);
                      await SecureStorageService.write('rommPassword', password);
                      await SecureStorageService.write('rommApiKey', apiKey);

                      // Invalidate providers to refresh RomM service and config
                      ref.invalidate(rommConfigProvider);
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

  // --- Storage Section ---
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
              // Fix: Replace ref.refresh with ref.invalidate
              ref.invalidate(directoryServiceProvider);
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
              // Fix: Replace ref.refresh with ref.invalidate
              ref.invalidate(directoryServiceProvider);
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

  // --- RetroArch Sync Mode Section ---
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

  // --- Linux Settings Section ---
  Widget _buildLinuxSettingsSection(BuildContext context, WidgetRef ref, DirectoryService directoryService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Linux Integration', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Select sync method for Linux/Steam Deck', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'default', label: Text('Default')),
            ButtonSegment(value: 'emudeck', label: Text('EmuDeck')),
          ],
          selected: {directoryService.linuxSyncPreset},
          onSelectionChanged: (selection) async {
            final value = selection.first;
            await directoryService.setLinuxSyncPreset(value);
            ref.invalidate(directoryServiceProvider);
            if (mounted) setState(() {});
          },
        ),
        if (directoryService.linuxSyncPreset == 'emudeck') ...[
          const SizedBox(height: 16),
          _buildPathRow(
            label: 'EmuDeck Root Path',
            currentPath: directoryService.emudeckRootPath ?? 'Not set',
            onChanged: (newPath) async {
              if (newPath != null) {
                await directoryService.setEmudeckRoot(newPath);
                ref.invalidate(directoryServiceProvider);
                if (mounted) setState(() {});
              }
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'EmuDeck integration will use Emulation/roms and Emulation/tools inside this path.',
            style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  // --- Legal Section ---
  Widget _buildLegalSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Legal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Third-Party Licenses'),
          subtitle: const Text('View licenses for open-source software used in Freegosy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Register 7-Zip license before showing the page
            LicenseRegistry.addLicense(() async* {
              final license = await rootBundle.loadString('thirdparty/7zip_license.txt');
              yield LicenseEntryWithLineBreaks(['7-Zip'], license);
            });

            showLicensePage(
              context: context,
              applicationName: 'Freegosy',
              applicationVersion: '0.3.0',
              applicationLegalese: '© 2026 Freegosy Contributors.\nRedistributes 7-Zip binaries under LGPL.',
            );
          },
        ),
      ],
    );
  }
}