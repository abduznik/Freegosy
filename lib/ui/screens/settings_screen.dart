import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/storage/directory_service.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/romm_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../../core/romm/romm_service.dart';
import '../../core/romm/romm_models.dart';
import 'settings_emulators_section.dart';
import 'settings_display_section.dart';
import 'settings_custom_emulators_section.dart';

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
  bool _isLegacyAuth = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _apiKeyController = TextEditingController(); // Initialize API Key controller
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
    final activePreset = ref.watch(activePresetProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'freegosy_logo.png',
              height: 32,
              width: 32,
            ),
            const SizedBox(width: 12),
            const Text('Settings'),
          ],
        ),
      ),
      body: rommConfigAsync.when(
        data: (rommConfig) {
          // Robust initialization: only sync once when data is ready
          if (!_preferencesLoaded) {
            debugPrint('[Settings] Data loaded from provider. Syncing controllers...');
            debugPrint('  - BaseURL: ${rommConfig.baseUrl}');
            debugPrint('  - User: ${rommConfig.username}');
            debugPrint('  - API Key exists: ${rommConfig.apiKey.isNotEmpty}');
            
            _baseUrlController.text = rommConfig.baseUrl;
            _usernameController.text = rommConfig.username;
            _passwordController.text = rommConfig.password;
            _apiKeyController.text = rommConfig.apiKey;
            _isLegacyAuth = rommConfig.apiKey.isEmpty && 
                           (rommConfig.username.isNotEmpty || rommConfig.password.isNotEmpty);
            
            _preferencesLoaded = true;
          }

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
                      activePreset,
                      ref, // Pass ref
                    ),
                    const SizedBox(height: 24),
                    _buildStorageSection(directoryService),
                    const SizedBox(height: 24),
                    _buildRetroArchSettingsSection(context, ref),
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
                    const SizedBox(height: 24),
                    const SettingsCustomEmulatorsSection(),
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
        if (_isLegacyAuth) ...[
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
        ] else
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
        Row(
          children: [
            const Text('Legacy Authentication', style: TextStyle(fontSize: 14)),
            const Spacer(),
            Switch(
              value: _isLegacyAuth,
              onChanged: (val) => setState(() => _isLegacyAuth = val),
            ),
          ],
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
                  // Temporarily update service config for testing
                  final currentConfig = RomMConfig(
                    baseUrl: _baseUrlController.text.trim(),
                    username: _isLegacyAuth ? _usernameController.text.trim() : '',
                    password: _isLegacyAuth ? _passwordController.text : '',
                    apiKey: !_isLegacyAuth ? _apiKeyController.text.trim() : '',
                  );
                  rommService.updateConfig(currentConfig);

                  // Test connection by fetching platforms
                  final platforms = await rommService.getPlatforms();
                  String message;
                  if (currentConfig.apiKey.isNotEmpty) {
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
                      final String username;
                      final String password;
                      final String apiKey;

                      final prefs = ref.read(sharedPreferencesProvider);

                      if (_isLegacyAuth) {
                        username = _usernameController.text.trim();
                        password = _passwordController.text;
                        apiKey = '';
                        
                        // Try Bearer token (OAuth2). If the server doesn't support
                        // it over HTTP or at all, fall back to Basic auth silently.
                        try {
                          final token = await RommService.fetchToken(baseUrl, username, password, prefs);
                          if (token.isNotEmpty) {
                            await SecureStorageService.write('rommAuthToken', token, prefs);
                          }
                        } catch (e) {
                          // Clear any stale token so Basic auth is used instead.
                          await SecureStorageService.delete('rommAuthToken', prefs);
                        }
                      } else {
                        username = '';
                        password = '';
                        apiKey = _apiKeyController.text.trim();
                        // Clear any legacy tokens when switching to API Key
                        await SecureStorageService.delete('rommAuthToken', prefs);
                      }

                      // Save credentials regardless of whether token fetch succeeded.
                      await prefs.setString('rommBaseUrl', baseUrl);
                      await prefs.setString('rommUsername', username);
                      await SecureStorageService.write('rommPassword', password, prefs);
                      await SecureStorageService.write('rommApiKey', apiKey, prefs);

                      // Invalidate providers to refresh RomM service and config
                      ref.invalidate(rommConfigProvider);
                      ref.invalidate(rommServiceProvider);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged in and settings saved.'), backgroundColor: Colors.green),
                        );
                        if (!kIsWeb && io.Platform.isMacOS) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Note: this is an unsigned build — credentials are stored without encryption. For a secure build, compile from source with your own signing certificate.'),
                              duration: Duration(seconds: 5),
                            ),
                          );
                        }
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
        if (directoryService.status.hasError) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Error: ${directoryService.status.message}\nPath: ${directoryService.status.failedPath}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
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
          onReset: () async {
            await directoryService.resetRomsRoot();
            ref.invalidate(directoryServiceProvider);
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
          onReset: () async {
            await directoryService.resetEmulatorsRoot();
            ref.invalidate(directoryServiceProvider);
          },
        ),
      ],
    );
  }

  Widget _buildPathRow({required String label, required String currentPath, required Function(String?) onChanged, VoidCallback? onReset}) {
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
            if (onReset != null)
              IconButton(
                onPressed: onReset,
                icon: const Icon(Icons.restore),
                tooltip: 'Reset to default',
              ),
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

  // --- RetroArch Settings Section ---
  Widget _buildRetroArchSettingsSection(BuildContext context, WidgetRef ref) {
    final syncMode = ref.watch(retroarchSyncModeProvider);
    final ndsCore = ref.watch(retroarchNdsCoreProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RetroArch Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('Save Sync Mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const Text('What to sync with RomM cloud', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'saves', label: Text('Saves only')),
            ButtonSegment(value: 'states', label: Text('States only')),
            ButtonSegment(value: 'both', label: Text('Both')),
          ],
          selected: {syncMode},
          onSelectionChanged: (selection) {
            final value = selection.first;
            ref.read(retroarchSyncModeProvider.notifier).update(value);
          },
        ),
        const SizedBox(height: 20),
        const Text('Nintendo DS Core', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const Text('Preferred core for DS games', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'melonds', label: Text('MelonDS')),
            ButtonSegment(value: 'desmume', label: Text('DeSmuME')),
          ],
          selected: {ndsCore},
          onSelectionChanged: (selection) {
            final value = selection.first;
            ref.read(retroarchNdsCoreProvider.notifier).update(value);
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
            ButtonSegment(value: 'retrodeck', label: Text('RetroDECK')),
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
        if (directoryService.linuxSyncPreset == 'retrodeck') ...[
          const SizedBox(height: 16),
          const Text(
            'RetroDECK integration is active. Games will be launched via flatpak.',
            style: TextStyle(fontSize: 14, color: Colors.deepPurpleAccent),
          ),
          const SizedBox(height: 8),
          const Text(
            'Default paths: ~/retrodeck/roms/ for ROMs and ~/.var/app/net.retrodeck.retrodeck/config/ for saves.',
            style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
        // Detection suggestions
        _buildDetectionSuggestions(directoryService),
      ],
    );
  }

  Widget _buildDetectionSuggestions(DirectoryService directoryService) {
    return FutureBuilder<Map<String, bool>>(
      future: () async {
        if (defaultTargetPlatform != TargetPlatform.linux) return <String, bool>{};
        
        bool retrodeckFound = false;
        try {
          final result = await io.Process.run('flatpak', ['info', 'net.retrodeck.retrodeck']);
          retrodeckFound = result.exitCode == 0;
        } catch (_) {}

        final home = io.Platform.environment['HOME'] ?? '';
        final emudeckFound = io.Directory(p.join(home, 'Emulation', 'roms')).existsSync();
        return <String, bool>{'retrodeck': retrodeckFound, 'emudeck': emudeckFound};
      }(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        
        final found = snapshot.data!;
        if (!found['retrodeck']! && !found['emudeck']!) return const SizedBox.shrink();

        final current = directoryService.linuxSyncPreset;
        String? suggestion;
        String? suggestionId;

        if (found['retrodeck']! && current != 'retrodeck') {
          suggestion = 'RetroDECK';
          suggestionId = 'retrodeck';
        } else if (found['emudeck']! && current == 'default') {
          suggestion = 'EmuDeck';
          suggestionId = 'emudeck';
        }

        if (suggestion == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.deepPurpleAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'We detected $suggestion on your system. Would you like to switch?',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await directoryService.setLinuxSyncPreset(suggestionId!);
                    ref.invalidate(directoryServiceProvider);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Switch'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Legal Section ---
  Widget _buildLegalSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Legal & Support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.favorite, color: Colors.red),
          title: const Text('Support Development'),
          subtitle: const Text('Become a GitHub Sponsor to support Freegosy'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse('https://github.com/sponsors/abduznik'), mode: LaunchMode.externalApplication),
        ),
        const Divider(height: 32),
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
              applicationVersion: AppConstants.version,
              applicationLegalese: '© 2026 Freegosy Contributors.\nRedistributes 7-Zip binaries under LGPL.',
            );
          },
        ),
      ],
    );
  }
}