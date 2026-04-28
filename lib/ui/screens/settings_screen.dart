import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../core/storage/directory_service.dart';
import '../../core/storage/system_utils.dart';
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
  late TextEditingController _apiKeyController;
  bool _preferencesLoaded = false;
  bool _isLegacyAuth = false;
  bool _isTestingConnection = false;
  String? _connectionError;
  bool _connectionSuccess = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directoryServiceAsync = ref.watch(directoryServiceProvider);
    final rommService = ref.watch(rommServiceProvider);
    final rommConfigAsync = ref.watch(rommConfigProvider);
    final strategyRegistry = ref.watch(strategyRegistryProvider).asData?.value;
    final emulatorStatusAsync = ref.watch(emulatorStatusProvider);

    final cardAspectRatio = ref.watch(cardAspectRatioProvider);
    final columnCount = ref.watch(columnCountProvider);
    final cardSpacing = ref.watch(cardSpacingProvider);
    final showTitle = ref.watch(showTitleProvider);
    final activePreset = ref.watch(activePresetProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('freegosy_logo.png', height: 32, width: 32),
            const SizedBox(width: 12),
            const Text('Settings'),
          ],
        ),
      ),
      body: rommConfigAsync.when(
        data: (rommConfig) {
          if (!_preferencesLoaded) {
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
              if (directoryService == null) return const Center(child: Text('Storage service not available.'));
              if (rommService == null) return const Center(child: CircularProgressIndicator());

              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildRommServerSection(context, ref, rommService, rommConfig),
                  const SizedBox(height: 24),
                  buildDisplaySection(context, cardAspectRatio, columnCount, cardSpacing, showTitle, activePreset, ref),
                  const SizedBox(height: 24),
                  _buildStorageSection(directoryService),
                  const SizedBox(height: 24),
                  _buildRetroArchSettingsSection(context, ref),
                  const SizedBox(height: 24),
                  if (defaultTargetPlatform == TargetPlatform.linux) ...[
                    _buildLinuxSettingsSection(context, ref, directoryService),
                    const SizedBox(height: 24),
                  ],
                  emulatorStatusAsync.when(
                    data: (states) => buildEmulatorsSection(context, directoryService, true, states, setState, ref),
                    loading: () => buildEmulatorsSection(context, directoryService, false, {}, setState, ref),
                    error: (e, s) => Center(child: Text('Error: $e')),
                  ),
                  const SizedBox(height: 24),
                  const SettingsCustomEmulatorsSection(),
                  if (strategyRegistry != null) ...[
                    const SizedBox(height: 24),
                    buildConflictsSection(strategyRegistry, setState),
                  ],
                  const SizedBox(height: 24),
                  _buildLegalSection(context),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  // --- RomM Server Section (Kept as is) ---
  Widget _buildRommServerSection(BuildContext context, WidgetRef ref, RommService? rommService, RomMConfig rommConfig) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('RomM Server', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      TextField(controller: _baseUrlController, decoration: const InputDecoration(labelText: 'Server URL', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      if (_isLegacyAuth) ...[
        TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
      ] else
        TextField(controller: _apiKeyController, decoration: const InputDecoration(labelText: 'API Key (RomM 4.8+)', border: OutlineInputBorder()), obscureText: true),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Legacy Authentication'),
        const Spacer(),
        Switch(value: _isLegacyAuth, onChanged: (val) => setState(() => _isLegacyAuth = val)),
      ]),
      const SizedBox(height: 16),
      const SizedBox(height: 16),
      if (_connectionError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(_connectionError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ),
      if (_connectionSuccess)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Connection successful!', style: TextStyle(color: Colors.green, fontSize: 13)),
        ),
      Row(
        children: [
          ElevatedButton(
            onPressed: _isTestingConnection ? null : () async {
              final baseUrl = _baseUrlController.text.trim();
              if (baseUrl.isEmpty) {
                setState(() => _connectionError = 'Server URL is required');
                return;
              }

              setState(() {
                _isTestingConnection = true;
                _connectionError = null;
                _connectionSuccess = false;
              });

              try {
                // Temporary config for testing
                final testConfig = RomMConfig(
                  baseUrl: baseUrl,
                  username: _usernameController.text.trim(),
                  password: _passwordController.text,
                  apiKey: _apiKeyController.text.trim(),
                );
                
                final testService = RommService(testConfig);
                await testService.getPlatforms(); // Simple connectivity test
                
                if (mounted) {
                  setState(() {
                    _isTestingConnection = false;
                    _connectionSuccess = true;
                  });
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _isTestingConnection = false;
                    _connectionError = 'Connection failed: ${e.toString().split('\n').first}';
                  });
                }
              }
            },
            child: _isTestingConnection 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Test Connection'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final prefs = ref.read(sharedPreferencesProvider);
              await prefs.setString('rommBaseUrl', _baseUrlController.text.trim());
              if (_isLegacyAuth) {
                 await prefs.setString('rommUsername', _usernameController.text.trim());
                 await SecureStorageService.write('rommPassword', _passwordController.text, prefs);
              } else {
                 await SecureStorageService.write('rommApiKey', _apiKeyController.text.trim(), prefs);
              }
              ref.invalidate(rommConfigProvider);
              ref.invalidate(rommServiceProvider);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ]);
  }

  // --- Storage Section ---
  Widget _buildStorageSection(DirectoryService directoryService) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Storage', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      _buildPathRow(
        label: 'ROMs Directory',
        currentPath: directoryService.romsRootPath,
        onChanged: (p) async { if (p != null) { await directoryService.setRomsRoot(p); ref.invalidate(directoryServiceProvider); } },
        onReset: () async { await directoryService.resetRomsRoot(); ref.invalidate(directoryServiceProvider); },
      ),
      const SizedBox(height: 12),
      _buildPathRow(
        label: 'Emulators Directory',
        currentPath: directoryService.emulatorsRootPath,
        onChanged: (p) async { if (p != null) { await directoryService.setEmulatorsRoot(p); ref.invalidate(directoryServiceProvider); } },
        onReset: () async { await directoryService.resetEmulatorsRoot(); ref.invalidate(directoryServiceProvider); },
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => SystemUtils.openDirectory(directoryService.romsRootPath),
        icon: const Icon(Icons.folder_open),
        label: const Text('Open ROMs Directory'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: SystemUtils.openAppDataDirectory,
        icon: const Icon(Icons.folder_open),
        label: const Text('Open App Data Directory'),
      ),
    ]);
  }

  Widget _buildPathRow({required String label, required String currentPath, required Function(String?) onChanged, VoidCallback? onReset}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      Row(children: [
        Expanded(child: Text(currentPath, overflow: TextOverflow.ellipsis)),
        IconButton(onPressed: onReset, icon: const Icon(Icons.restore)),
        ElevatedButton(onPressed: () async => onChanged(await FilePicker.platform.getDirectoryPath()), child: const Text('Change')),
      ]),
    ]);
  }

  // --- Placeholder methods for sections to pass analysis ---
  Widget _buildRetroArchSettingsSection(BuildContext context, WidgetRef ref) => const SizedBox();
  Widget _buildLinuxSettingsSection(BuildContext context, WidgetRef ref, DirectoryService directoryService) => const SizedBox();
  Widget _buildLegalSection(BuildContext context) => const SizedBox();
}
